import AppKit
import Foundation
import SwiftData
import Observation

@MainActor
@Observable
final class AppStore {
    let modelContext: ModelContext
    let timer: TimerEngine
    let notificationService: NotificationService
    let loginItemService: LoginItemService
    let hotkeyService: GlobalHotkeyService

    private(set) var settings: AppSettingsRecord
    private(set) var tasks: [FocusTask] = []
    private(set) var sessions: [FocusSessionRecord] = []
    /// Cached once per reload() instead of remapped on every render — see
    /// StatisticsEngine. The task list and streak/heatmap all read from these.
    private(set) var sessionValues: [FocusSessionValue] = []
    private(set) var taskTitles: [UUID: String] = [:]
    /// subtaskID -> its top-level task. One level only.
    private(set) var parentOf: [UUID: UUID] = [:]
    /// Ready-made subtask lists (oldest first), keyed by parent id, so rows
    /// don't each filter the full task list on every redraw.
    private(set) var subtasks: [UUID: [FocusTask]] = [:]
    private(set) var dailyTotals: [Date: TimeInterval] = [:]
    private(set) var taskTotals: [UUID: TaskTotal] = [:]
    private(set) var streak: Streak = Streak(current: 0, best: 0)
    var todayTotal: TimeInterval { dailyTotals[Calendar.current.startOfDay(for: .now)] ?? 0 }
    var alertMessage: String?

    init(modelContainer: ModelContainer) {
        modelContext = ModelContext(modelContainer)
        notificationService = NotificationService()
        loginItemService = LoginItemService()
        hotkeyService = GlobalHotkeyService()

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
        timer.onBell = SoundService.playBell
        reload()
        contextMenu = StatusItemContextMenu(store: self)
        let hotkeysRegistered = hotkeyService.registerDefaultShortcuts(
            onStart: { [weak self] in
                guard let self else { return }
                if self.timer.phase == .pausedFocus || self.timer.phase == .pausedBreak { self.timer.resume() }
                else if self.timer.phase == .idle { self.timer.startFocus(taskID: self.settings.selectedTaskID, mode: self.settings.selectedMode) }
            },
            onPause: { [weak self] in self?.timer.pause() },
            onStop: { [weak self] in self?.timer.stop() },
            onToggleTimer: {
                // Same key the right-click menu's Hide/Show Timer writes.
                let d = UserDefaults.standard
                d.set(!d.bool(forKey: "hideMenuBarTimer"), forKey: "hideMenuBarTimer")
            }
        )
        if !hotkeysRegistered {
            alertMessage = "Global shortcuts could not be registered."
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

    func reload() {
        reloadTasks()
        reloadSessions()
    }

    private func reloadTasks() {
        do {
            tasks = try modelContext.fetch(FetchDescriptor<FocusTask>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)]))
                .filter { $0.deletedAt == nil }
            parentOf = Dictionary(uniqueKeysWithValues: tasks.compactMap { task in task.parentID.map { (task.id, $0) } })
            subtasks = Dictionary(grouping: tasks.filter { $0.parentID != nil }, by: { $0.parentID! })
                .mapValues { $0.sorted { $0.createdAt < $1.createdAt } }
            let titleByID = Dictionary(uniqueKeysWithValues: tasks.map { ($0.id, $0.title) })
            taskTitles = Dictionary(uniqueKeysWithValues: tasks.map { task -> (UUID, String) in
                guard let parentID = task.parentID, let parentTitle = titleByID[parentID] else { return (task.id, task.title) }
                return (task.id, "\(parentTitle) › \(task.title)")
            })
        } catch {
            alertMessage = "Unable to read local focus data."
        }
    }

    private func reloadSessions() {
        do {
            sessions = try modelContext.fetch(FetchDescriptor<FocusSessionRecord>(sortBy: [SortDescriptor(\.startedAt, order: .reverse)]))
                .filter { $0.deletedAt == nil }
            sessionValues = sessions.map(FocusSessionValue.init)
            recomputeAggregates()
        } catch {
            alertMessage = "Unable to read local focus data."
        }
    }

    private func recomputeAggregates() {
        let resetAt = Dictionary(uniqueKeysWithValues: tasks.compactMap { task in task.timeResetAt.map { (task.id, $0) } })
        dailyTotals = StatisticsEngine.dailyTotals(sessionValues)
        taskTotals = StatisticsEngine.taskTotals(sessionValues, resetAt: resetAt, parentOf: parentOf)
        streak = StatisticsEngine.streak(dailyTotals, goal: settings.dailyFocusGoal)
    }

    @discardableResult
    func createTask(title: String, parentID: UUID? = nil) -> FocusTask? {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let task = FocusTask(title: trimmed, parentID: parentID)
        modelContext.insert(task)
        // Don't steal the selection out from under a running timer.
        if !timer.isActive {
            settings.selectedTaskID = task.id
            settings.updatedAt = .now
        }
        save()
        reloadTasks()
        return task
    }

    /// True while the running (or paused) timer belongs to this task or one
    /// of its subtasks — used to keep a row's live time, the stop-on-complete
    /// rule, and Reset Time in sync with what's actually being timed.
    func isTiming(_ task: FocusTask) -> Bool {
        guard timer.phase == .focus || timer.phase == .pausedFocus, let runningID = timer.snapshot.taskID else { return false }
        return runningID == task.id || parentOf[runningID] == task.id
    }

    func resetTime(_ task: FocusTask) {
        task.timeResetAt = .now
        task.updatedAt = .now
        save()
        recomputeAggregates()
    }

    func selectTask(_ task: FocusTask) {
        settings.selectedTaskID = task.id
        settings.updatedAt = .now
        save()
    }

    func toggleTask(_ task: FocusTask) {
        let completing = !task.isCompleted
        // Completing the task (or its running subtask's domain) first, so
        // the focused time is actually recorded rather than discarded.
        if completing, isTiming(task) {
            timer.stop()
        }
        task.isCompleted.toggle()
        task.completedAt = task.isCompleted ? .now : nil
        task.updatedAt = .now
        if completing, settings.selectedTaskID == task.id {
            // Falls back to the parent domain (nil for a top-level task), so
            // completing a subtask leaves its domain selected and ready to go.
            settings.selectedTaskID = task.parentID
            settings.updatedAt = .now
        }
        save()
        reloadTasks()
    }

    func setMode(_ mode: FocusMode) {
        settings.selectedMode = mode
        save()
    }

    func updateSettings() {
        settings.updatedAt = .now
        save()
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
        let record: FocusSessionRecord
        if let index = sessions.firstIndex(where: { $0.id == id }) {
            let existing = sessions[index]
            existing.endedAt = endedAt
            existing.focusedDuration = focusedDuration
            existing.completed = completed
            existing.interrupted = interrupted
            existing.updatedAt = .now
            record = existing
            sessions[index] = existing
            sessionValues[index] = FocusSessionValue(record)
        } else {
            record = FocusSessionRecord(
                id: id, taskID: taskID, mode: mode, startedAt: startedAt, endedAt: endedAt,
                focusedDuration: focusedDuration, plannedDuration: plannedDuration,
                breakDuration: breakDuration, completed: completed, interrupted: interrupted
            )
            modelContext.insert(record)
            sessions.insert(record, at: 0)
            sessionValues.insert(FocusSessionValue(record), at: 0)
        }
        recomputeAggregates()
        save()
        if completed, settings.notificationsEnabled {
            notificationService.requestAuthorizationIfNeeded()
        }
    }

    func taskTitle(for id: UUID?) -> String {
        guard let id, let title = taskTitles[id] else { return "No task selected" }
        return title
    }

    private func save() {
        do {
            try modelContext.save()
        } catch {
            alertMessage = AppError.couldNotSave.localizedDescription
        }
    }
}
