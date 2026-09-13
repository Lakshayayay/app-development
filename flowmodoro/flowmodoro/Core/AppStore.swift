import AppKit
import Foundation
import Combine
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
    var alertMessage: String?

    private var refreshTask: Task<Void, Never>?
    private var wakeObserver: NSObjectProtocol?

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
        purgeOutboxIfSyncNotConfigured()
        syncEngine.refresh(pendingChanges: pendingOutboxCount())
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

        startTimerRefreshLoop()
        // queue: .main guarantees this runs on the main thread; assumeIsolated
        // asserts that rather than paying for an async hop through Task.
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.timer.refresh() }
        }
    }

    /// Single source of periodic phase-completion checks — replaces the two
    /// duplicate 500ms UI poll loops that previously drove this. Runs regardless
    /// of whether any view (popover, window) is currently visible, so a
    /// completed Pomodoro interval or break is recognized even while the
    /// menu-bar popover is closed.
    private func startTimerRefreshLoop() {
        refreshTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { return }
                self?.timer.refresh()
            }
        }
    }

    func reload() {
        do {
            tasks = try modelContext.fetch(FetchDescriptor<FocusTask>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)]))
                .filter { $0.deletedAt == nil }
            sessions = try modelContext.fetch(FetchDescriptor<FocusSessionRecord>(sortBy: [SortDescriptor(\.startedAt, order: .reverse)]))
                .filter { $0.deletedAt == nil }
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
        task.isCompleted.toggle()
        task.completedAt = task.isCompleted ? .now : nil
        task.updatedAt = .now
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

    var sessionValues: [FocusSessionValue] { sessions.map(FocusSessionValue.init) }

    func taskTitle(for id: UUID?) -> String {
        guard let id, let task = tasks.first(where: { $0.id == id }) else { return "No task selected" }
        return task.title
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
