import AppKit
import Foundation
import SwiftData
import Observation
import SwiftUI

@MainActor
@Observable
final class AppStore {
    let modelContext: ModelContext
    let timer: TimerEngine
    let notificationService: NotificationService
    let loginItemService: LoginItemService
    let hotkeyService: GlobalHotkeyService
    let syncEngine: LocalSyncEngine

    private(set) var settings: AppSettingsRecord
    private(set) var tasks: [FocusTask] = []
    private(set) var sessions: [FocusSessionRecord] = []
    /// Cached once per reload() instead of remapped on every render — see
    /// StatisticsEngine. The task list and streak/heatmap all read from these.
    private(set) var sessionValues: [FocusSessionValue] = []
    private(set) var taskTitles: [UUID: String] = [:]
    private(set) var dailyTotals: [Date: TimeInterval] = [:]
    private(set) var taskTotals: [UUID: TaskTotal] = [:]
    private(set) var streak: Streak = Streak(current: 0, best: 0)
    var todayTotal: TimeInterval { dailyTotals[Calendar.current.startOfDay(for: .now)] ?? 0 }
    var alertMessage: String?

    private var contextMenu: StatusItemContextMenu?
    private var outboxRetryTask: Task<Void, Never>?
    private var wakeObserver: NSObjectProtocol?
    private var dayChangeObserver: NSObjectProtocol?

    init(modelContainer: ModelContainer) {
        modelContext = ModelContext(modelContainer)
        notificationService = NotificationService()
        loginItemService = LoginItemService()
        hotkeyService = GlobalHotkeyService()
        syncEngine = LocalSyncEngine()

        if let existing = try? modelContext.fetch(FetchDescriptor<AppSettingsRecord>()).first {
            settings = existing
        } else {
            let fresh = AppSettingsRecord()
            settings = fresh
            modelContext.insert(fresh)
            try? modelContext.save()
        }

        timer = TimerEngine()
        timer.store = self
        reload()
        syncEngine.refresh(pendingChanges: pendingOutboxCount())
        contextMenu = StatusItemContextMenu(store: self)
        let hotkeysRegistered = hotkeyService.registerDefaultShortcuts(
            onStart: { [weak self] in
                guard let self else { return }
                if self.timer.phase == .pausedFocus || self.timer.phase == .pausedBreak { self.timer.resume() }
                else if self.timer.phase == .idle { self.timer.startFocus(taskID: self.settings.selectedTaskID, mode: self.settings.selectedMode) }
            },
            onPause: { [weak self] in self?.timer.pause() },
            onStop: { [weak self] in self?.timer.stop() }
        )
        if !hotkeysRegistered {
            alertMessage = "Global shortcuts could not be registered."
        }

        // A beat after startup so LocalSyncEngine's auth state has had a
        // chance to resolve (a restored session isn't known synchronously at
        // init) — deciding "not configured" too early would wrongly purge a
        // signed-in user's still-queued entries.
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            self?.purgeOutboxIfSyncNotConfigured()
        }
        // queue: .main guarantees this runs on the main thread; assumeIsolated
        // asserts that rather than paying for an async hop through Task.
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.timer.refresh() }
        }
        // "Today" and the streak are date-relative; without this they'd stay
        // stale past midnight until the next unrelated write triggered reload().
        dayChangeObserver = NotificationCenter.default.addObserver(
            forName: .NSCalendarDayChanged, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.reload() }
        }
    }

    /// Uploads every queued OutboxEntry to Supabase and removes it on success.
    /// A row that fails (offline, transient error) is left queued — the next
    /// tick or the next save() retries it. Idempotent: upsert-by-id means a
    /// retried row never creates a duplicate.
    func attemptSync() async {
        guard syncEngine.status.isConfigured, let userID = syncEngine.currentUserID else { return }
        guard let entries = try? modelContext.fetch(FetchDescriptor<OutboxEntry>()), !entries.isEmpty else { return }

        for entry in entries {
            do {
                switch entry.entityType {
                case "task":
                    guard let task = tasks.first(where: { $0.id == entry.entityID }) else {
                        modelContext.delete(entry)
                        continue
                    }
                    try await syncEngine.upsertTask(SupabaseTaskRow(
                        id: task.id, user_id: userID, title: task.title, is_completed: task.isCompleted,
                        completed_at: task.completedAt, created_at: task.createdAt,
                        updated_at: task.updatedAt, deleted_at: task.deletedAt
                    ))
                case "focus_session":
                    guard let session = sessions.first(where: { $0.id == entry.entityID }) else {
                        modelContext.delete(entry)
                        continue
                    }
                    try await syncEngine.upsertFocusSession(SupabaseFocusSessionRow(
                        id: session.id, user_id: userID, task_id: session.taskID, mode: session.modeRawValue,
                        started_at: session.startedAt, ended_at: session.endedAt,
                        focused_duration: session.focusedDuration, planned_duration: session.plannedDuration,
                        break_duration: session.breakDuration, completed: session.completed,
                        interrupted: session.interrupted, created_at: session.createdAt,
                        updated_at: session.updatedAt, deleted_at: session.deletedAt
                    ))
                case "settings":
                    try await syncEngine.upsertSettings(SupabaseSettingsRow(
                        id: settings.id, user_id: userID,
                        payload: SupabaseSettingsPayload(
                            selectedMode: settings.selectedModeRawValue, flowBreakRatio: settings.flowBreakRatio,
                            pomodoroWorkDuration: settings.pomodoroWorkDuration,
                            pomodoroShortBreakDuration: settings.pomodoroShortBreakDuration,
                            pomodoroLongBreakDuration: settings.pomodoroLongBreakDuration,
                            pomodoroCyclesBeforeLongBreak: settings.pomodoroCyclesBeforeLongBreak,
                            dailyFocusGoal: settings.dailyFocusGoal
                        ),
                        updated_at: settings.updatedAt
                    ))
                default:
                    break
                }
                modelContext.delete(entry)
            } catch {
                continue // leave queued; retried on the next tick or save()
            }
        }
        try? modelContext.save()
        syncEngine.refresh(pendingChanges: pendingOutboxCount())
        scheduleOutboxRetry()
    }

    /// Retries a non-empty outbox on a backoff instead of polling every
    /// second — each write already attempts a drain immediately via save(),
    /// so this only covers the offline/transient-failure case, and idles
    /// (no scheduled task at all) once the outbox is empty.
    private func scheduleOutboxRetry(after seconds: Double = 30) {
        outboxRetryTask?.cancel()
        guard syncEngine.status.isConfigured, syncEngine.status.pendingChanges > 0 else { return }
        outboxRetryTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled, let self else { return }
            await self.attemptSync()
            self.scheduleOutboxRetry(after: min(seconds * 2, 1800))
        }
    }

    func reload() {
        do {
            tasks = try modelContext.fetch(FetchDescriptor<FocusTask>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)]))
                .filter { $0.deletedAt == nil }
            sessions = try modelContext.fetch(FetchDescriptor<FocusSessionRecord>(sortBy: [SortDescriptor(\.startedAt, order: .reverse)]))
                .filter { $0.deletedAt == nil }
            sessionValues = sessions.map(FocusSessionValue.init)
            taskTitles = Dictionary(uniqueKeysWithValues: tasks.map { ($0.id, $0.title) })
            dailyTotals = StatisticsEngine.dailyTotals(sessionValues)
            taskTotals = StatisticsEngine.taskTotals(sessionValues)
            streak = StatisticsEngine.streak(dailyTotals, goal: settings.dailyFocusGoal)
            syncEngine.refresh(pendingChanges: pendingOutboxCount())
        } catch {
            alertMessage = "Unable to read local focus data."
        }
    }

    @discardableResult
    func createTask(title: String) -> FocusTask? {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let task = FocusTask(title: trimmed)
        modelContext.insert(task)
        settings.selectedTaskID = task.id
        settings.updatedAt = .now
        save(taskID: task.id, entityType: "task", operation: "upsert")
        reload()
        return task
    }

    func selectTask(_ task: FocusTask) {
        settings.selectedTaskID = task.id
        settings.updatedAt = .now
        save(taskID: task.id, entityType: "settings", operation: "upsert")
    }

    func toggleTask(_ task: FocusTask) {
        let completing = !task.isCompleted
        // Completing the running task's own session first, so its focused
        // time is actually recorded rather than discarded.
        if completing, timer.snapshot.taskID == task.id, timer.phase == .focus || timer.phase == .pausedFocus {
            timer.stop()
        }
        task.isCompleted.toggle()
        task.completedAt = task.isCompleted ? .now : nil
        task.updatedAt = .now
        if completing, settings.selectedTaskID == task.id {
            settings.selectedTaskID = nil
            settings.updatedAt = .now
        }
        save(taskID: task.id, entityType: "task", operation: "upsert")
        reload()
    }

    func setMode(_ mode: FocusMode) {
        settings.selectedMode = mode
        save(taskID: settings.selectedTaskID, entityType: "settings", operation: "upsert")
    }

    func updateSettings() {
        settings.updatedAt = .now
        save(taskID: settings.selectedTaskID, entityType: "settings", operation: "upsert")
        // Keeps the streak in sync the instant the daily goal changes,
        // instead of waiting for the next unrelated write to call reload().
        streak = StatisticsEngine.streak(dailyTotals, goal: settings.dailyFocusGoal)
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            try loginItemService.setEnabled(enabled)
            settings.launchAtLogin = loginItemService.isEnabled
            updateSettings()
        } catch {
            alertMessage = "Launch at Login could not be changed."
        }
    }

    func recordSession(
        id: UUID,
        taskID: UUID?,
        mode: FocusMode,
        startedAt: Date,
        endedAt: Date,
        focusedDuration: TimeInterval,
        plannedDuration: TimeInterval?,
        breakDuration: TimeInterval? = nil,
        completed: Bool,
        interrupted: Bool = false
    ) {
        guard focusedDuration > 0 else { return }
        if let existing = sessions.first(where: { $0.id == id }) {
            existing.endedAt = endedAt
            existing.focusedDuration = focusedDuration
            existing.completed = completed
            existing.interrupted = interrupted
            existing.updatedAt = .now
        } else {
            modelContext.insert(FocusSessionRecord(
                id: id, taskID: taskID, mode: mode, startedAt: startedAt, endedAt: endedAt,
                focusedDuration: focusedDuration, plannedDuration: plannedDuration,
                breakDuration: breakDuration, completed: completed, interrupted: interrupted
            ))
        }
        save(taskID: id, entityType: "focus_session", operation: "upsert")
        reload()
        if completed, settings.notificationsEnabled {
            notificationService.requestAuthorizationIfNeeded()
        }
    }

    func taskTitle(for id: UUID?) -> String {
        guard let id, let title = taskTitles[id] else { return "No task selected" }
        return title
    }

    func pendingOutboxCount() -> Int {
        (try? modelContext.fetchCount(FetchDescriptor<OutboxEntry>())) ?? 0
    }

    private func save(taskID: UUID?, entityType: String, operation: String) {
        do {
            try modelContext.save()
            // Only queue a sync outbox entry when sync is actually configured.
            // No transport exists to drain the outbox yet (Supabase sync is
            // still a placeholder), so queuing unconditionally — as this used
            // to — meant every local write grew this table forever with rows
            // nothing would ever consume.
            if let taskID, syncEngine.status.isConfigured {
                modelContext.insert(OutboxEntry(
                    entityType: entityType, entityID: taskID, operation: operation,
                    payload: outboxPayload(entityType: entityType, entityID: taskID, operation: operation)
                ))
                try modelContext.save()
                Task { await attemptSync() }
            }
            syncEngine.refresh(pendingChanges: pendingOutboxCount())
        } catch {
            alertMessage = AppError.couldNotSave.localizedDescription
        }
    }

    private func outboxPayload(entityType: String, entityID: UUID, operation: String) -> String {
        let fields: [String: String] = [
            "entityType": entityType,
            "entityID": entityID.uuidString,
            "operation": operation,
            "queuedAt": ISO8601DateFormatter().string(from: .now),
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: fields),
              let json = String(data: data, encoding: .utf8) else { return "{}" }
        return json
    }

    /// One-time cleanup: sync has never been configurable in any shipped
    /// version of this app, so any OutboxEntry rows already on disk are
    /// orphaned placeholder junk from before this fix, not real queued work.
    private func purgeOutboxIfSyncNotConfigured() {
        guard !syncEngine.status.isConfigured else { return }
        guard let stale = try? modelContext.fetch(FetchDescriptor<OutboxEntry>()), !stale.isEmpty else { return }
        stale.forEach { modelContext.delete($0) }
        try? modelContext.save()
    }
}
