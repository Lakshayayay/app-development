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
    // Inline defaults so lightweight migration fills existing rows.
    /// Set = this task is a subtask of that task. One level only — a subtask
    /// with its own parentID set would be project-management scope creep
    /// (see docs/STATUS.md's "permanently out of scope").
    var parentID: UUID? = nil
    /// The row's today/total time only counts sessions started at or after
    /// this date. Sessions themselves are never touched — see "Reset Time"
    /// in docs/ARCHITECTURE.md's Decisions log.
    var timeResetAt: Date? = nil

    init(title: String, parentID: UUID? = nil, now: Date = .now) {
        self.id = UUID()
        self.title = title
        self.isCompleted = false
        self.createdAt = now
        self.updatedAt = now
        self.completedAt = nil
        self.deletedAt = nil
        self.parentID = parentID
        self.timeResetAt = nil
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
    // Inline default (not just in init) so SwiftData's lightweight migration
    // can fill this in for AppSettingsRecord rows that already exist on disk.
    var dailyFocusGoal: TimeInterval = 30 * 60
    /// Focus rounds per Pomodoro run; 0 = until stopped (the pre-rounds behavior).
    var pomodoroRounds: Int = 0
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
        self.dailyFocusGoal = 30 * 60
        self.pomodoroRounds = 0
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
    // Optional so snapshots persisted by earlier builds still decode.
    var pomodoroPlan: PomodoroPlan?
    var roundsCompleted: Int?
}

/// The Pomodoro configuration committed when Start is pressed. Frozen into
/// TimerSnapshot so editing Settings mid-run can't change a cycle already in
/// progress, and a relaunch resumes the same plan.
// New fields here must be Optional too — see TimerSnapshot's decoding-safety
// comment above `pomodoroPlan`; PomodoroPlan is embedded inside it, so a
// non-optional addition would throw decoding every snapshot persisted today
// and TimerEngine.init's `try?` would silently discard a running timer.
struct PomodoroPlan: Codable, Sendable, Equatable {
    var work: TimeInterval = 25 * 60
    var shortBreak: TimeInterval = 5 * 60
    var longBreak: TimeInterval = 15 * 60
    var cyclesBeforeLongBreak = 4
    /// Focus rounds in this run; 0 = until stopped.
    var rounds = 0
    var autoStartBreak = true
    var autoStartFocus = false

    /// Settings are a trust boundary: a zero-length interval with
    /// auto-continue on would complete, and record a session, every tick.
    /// Ranges match the Settings steppers.
    func clamped() -> PomodoroPlan {
        var plan = self
        plan.work = min(max(work, 60), 7_200)
        plan.shortBreak = min(max(shortBreak, 60), 7_200)
        plan.longBreak = min(max(longBreak, 60), 7_200)
        plan.cyclesBeforeLongBreak = min(max(cyclesBeforeLongBreak, 1), 12)
        plan.rounds = min(max(rounds, 0), 24)
        return plan
    }
}

extension PomodoroPlan {
    // In an extension so the synthesized memberwise initializer survives.
    init(settings: AppSettingsRecord?) {
        guard let settings else { self.init(); return }
        self.init(
            work: settings.pomodoroWorkDuration,
            shortBreak: settings.pomodoroShortBreakDuration,
            longBreak: settings.pomodoroLongBreakDuration,
            cyclesBeforeLongBreak: settings.pomodoroCyclesBeforeLongBreak,
            rounds: settings.pomodoroRounds,
            autoStartBreak: settings.pomodoroAutoStartBreak,
            autoStartFocus: settings.pomodoroAutoStartFocus
        )
    }
}
