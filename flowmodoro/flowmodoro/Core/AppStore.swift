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
    private(set) var clockTick = 0
    var alertMessage: String?

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
        hotkeyService.registerDefaultShortcuts(
            onStart: { [weak self] in
                guard let self else { return }
                if self.timer.phase == .pausedFocus || self.timer.phase == .pausedBreak { self.timer.resume() }
                else if self.timer.phase == .idle { self.timer.startFocus(taskID: self.settings.selectedTaskID, mode: self.settings.selectedMode) }
            },
            onPause: { [weak self] in self?.timer.pause() },
            onStop: { [weak self] in self?.timer.stop() }
        )
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

    func refreshTimer() {
        timer.refresh()
        clockTick += 1
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
            if let taskID {
                modelContext.insert(OutboxEntry(entityType: entityType, entityID: taskID, operation: operation, payload: "local-change"))
                try modelContext.save()
            }
            syncEngine.refresh(pendingChanges: pendingOutboxCount())
        } catch {
            alertMessage = AppError.couldNotSave.localizedDescription
        }
    }
}
