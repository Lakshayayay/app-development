import Foundation
import SwiftData

enum FocusMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case flowmodoro
    case pomodoro

    var id: String { rawValue }

    var title: String {
        switch self {
        case .flowmodoro: "Flowmodoro"
        case .pomodoro: "Pomodoro"
        }
    }
}

enum TimerPhase: String, Codable, Sendable {
    case idle
    case focus
    case pausedFocus
    case breakTimer
    case pausedBreak
    case suggestedBreak
}

enum BreakKind: String, Codable, Sendable {
    case flowmodoro
    case short
    case long
}

enum AppearancePreference: String, Codable, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }
}

@Model
final class FocusTask {
    @Attribute(.unique) var id: UUID
    var title: String
    var isCompleted: Bool
    var createdAt: Date
    var completedAt: Date?
    var updatedAt: Date
    var deletedAt: Date?

    init(title: String, now: Date = .now) {
        self.id = UUID()
        self.title = title
        self.isCompleted = false
        self.createdAt = now
        self.updatedAt = now
        self.completedAt = nil
        self.deletedAt = nil
    }
}

@Model
final class FocusSessionRecord {
    @Attribute(.unique) var id: UUID
    var taskID: UUID?
    var modeRawValue: String
    var startedAt: Date
    var endedAt: Date?
    var focusedDuration: TimeInterval
    var plannedDuration: TimeInterval?
    var breakDuration: TimeInterval?
    var completed: Bool
    var interrupted: Bool
    var createdAt: Date
    var updatedAt: Date
    var deletedAt: Date?

    init(
        id: UUID = UUID(),
        taskID: UUID?,
        mode: FocusMode,
        startedAt: Date,
        endedAt: Date?,
        focusedDuration: TimeInterval,
        plannedDuration: TimeInterval?,
        breakDuration: TimeInterval? = nil,
        completed: Bool,
        interrupted: Bool = false,
        now: Date = .now
    ) {
        self.id = id
        self.taskID = taskID
        self.modeRawValue = mode.rawValue
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.focusedDuration = max(0, focusedDuration)
        self.plannedDuration = plannedDuration
        self.breakDuration = breakDuration
        self.completed = completed
        self.interrupted = interrupted
        self.createdAt = now
        self.updatedAt = now
        self.deletedAt = nil
    }

    var mode: FocusMode { FocusMode(rawValue: modeRawValue) ?? .flowmodoro }
}

@Model
final class AppSettingsRecord {
    @Attribute(.unique) var id: UUID
    var selectedModeRawValue: String
    var selectedTaskID: UUID?
    var launchAtLogin: Bool
    var notificationsEnabled: Bool
    var soundEnabled: Bool
    var appearanceRawValue: String
    var flowBreakRatio: Double
    var flowAutoStartBreak: Bool
    var pomodoroWorkDuration: TimeInterval
    var pomodoroShortBreakDuration: TimeInterval
    var pomodoroLongBreakDuration: TimeInterval
    var pomodoroCyclesBeforeLongBreak: Int
    var pomodoroAutoStartBreak: Bool
    var pomodoroAutoStartFocus: Bool
    var showPauseButton: Bool
    var updatedAt: Date

    init(now: Date = .now) {
        self.id = UUID()
        self.selectedModeRawValue = FocusMode.flowmodoro.rawValue
        self.selectedTaskID = nil
        self.launchAtLogin = false
        self.notificationsEnabled = true
        self.soundEnabled = true
        self.appearanceRawValue = AppearancePreference.system.rawValue
        self.flowBreakRatio = 5
        self.flowAutoStartBreak = false
        self.pomodoroWorkDuration = 25 * 60
        self.pomodoroShortBreakDuration = 5 * 60
        self.pomodoroLongBreakDuration = 15 * 60
        self.pomodoroCyclesBeforeLongBreak = 4
        self.pomodoroAutoStartBreak = true
        self.pomodoroAutoStartFocus = false
        self.showPauseButton = true
        self.updatedAt = now
    }

    var selectedMode: FocusMode {
        get { FocusMode(rawValue: selectedModeRawValue) ?? .flowmodoro }
        set { selectedModeRawValue = newValue.rawValue; updatedAt = .now }
    }

    var appearance: AppearancePreference {
        get { AppearancePreference(rawValue: appearanceRawValue) ?? .system }
        set { appearanceRawValue = newValue.rawValue; updatedAt = .now }
    }
}

@Model
final class OutboxEntry {
    @Attribute(.unique) var id: UUID
    var entityType: String
    var entityID: UUID
    var operation: String
    var payload: String
    var createdAt: Date
    var attemptCount: Int
    var lastAttemptAt: Date?

    init(entityType: String, entityID: UUID, operation: String, payload: String, now: Date = .now) {
        self.id = UUID()
        self.entityType = entityType
        self.entityID = entityID
        self.operation = operation
        self.payload = payload
        self.createdAt = now
        self.attemptCount = 0
        self.lastAttemptAt = nil
    }
}

struct FocusSessionValue: Identifiable, Hashable, Sendable {
    let id: UUID
    let taskID: UUID?
    let mode: FocusMode
    let startedAt: Date
    let endedAt: Date?
    let focusedDuration: TimeInterval
    let plannedDuration: TimeInterval?
    let completed: Bool
    let interrupted: Bool

    init(_ record: FocusSessionRecord) {
        id = record.id
        taskID = record.taskID
        mode = record.mode
        startedAt = record.startedAt
        endedAt = record.endedAt
        focusedDuration = record.focusedDuration
        plannedDuration = record.plannedDuration
        completed = record.completed
        interrupted = record.interrupted
    }
}

struct TimerSnapshot: Codable, Sendable {
    var phase: TimerPhase = .idle
    var mode: FocusMode = .flowmodoro
    var taskID: UUID?
    var sessionID: UUID?
    var focusStartedAt: Date?
    var focusResumedAt: Date?
    var accumulatedFocus: TimeInterval = 0
    var countdownEnd: Date?
    var remainingWhenPaused: TimeInterval?
    var breakKind: BreakKind?
    var suggestedBreak: TimeInterval?
    var pomodoroCycle: Int = 0
    var plannedDuration: TimeInterval?
}
