import Foundation
import Observation

enum FlowmodoroMath {
    static func breakDuration(for focusDuration: TimeInterval, ratio: Double) -> TimeInterval {
        guard focusDuration > 0 else { return 0 }
        return focusDuration / max(1, ratio)
    }
}

@MainActor
@Observable
final class TimerEngine {
    var store: AppStore?
    private(set) var snapshot: TimerSnapshot
    /// The clock driving every ticking display (menu-bar label, task row,
    /// timer ring) — updated once a second only while a timer is actually
    /// running. See `updateTicking()`.
    private(set) var now = Date.now

    private let defaults: UserDefaults
    private var tickTask: Task<Void, Never>?

    init(store: AppStore? = nil, defaults: UserDefaults = .standard) {
        self.store = store
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.snapshotKey),
           let restored = try? JSONDecoder().decode(TimerSnapshot.self, from: data) {
            snapshot = restored
        } else {
            snapshot = TimerSnapshot()
        }
        // Covers a restored running snapshot (relaunch mid-session), which
        // never goes through persist(). `store` is assigned synchronously
        // right after this initializer returns, before this Task's first
        // iteration can run.
        updateTicking()
    }

    static let snapshotKey = "flowmodo.timer.snapshot"

    var phase: TimerPhase { snapshot.phase }
    var mode: FocusMode { snapshot.mode }
    var isActive: Bool { [.focus, .pausedFocus, .breakTimer, .pausedBreak, .suggestedBreak].contains(phase) }
    var isFocusRunning: Bool { phase == .focus }
    var isBreakRunning: Bool { phase == .breakTimer || phase == .pausedBreak }
    var isTicking: Bool { tickTask != nil }

    func refresh(at now: Date = .now) {
        if snapshot.phase == .focus, snapshot.mode == .pomodoro, let end = snapshot.countdownEnd, now >= end {
            completePomodoroFocus(at: end)
            return
        }
        guard snapshot.phase == .breakTimer, let end = snapshot.countdownEnd, now >= end else { return }
        completeBreak(at: end)
    }

    func startFocus(taskID: UUID?, mode: FocusMode, now: Date = .now) {
        guard let taskID else { return }
        if snapshot.phase == .suggestedBreak { snapshot = TimerSnapshot() }
        guard snapshot.phase == .idle else { return }
        snapshot.mode = mode
        snapshot.taskID = taskID
        snapshot.sessionID = UUID()
        snapshot.focusStartedAt = now
        snapshot.focusResumedAt = now
        snapshot.accumulatedFocus = 0
        snapshot.plannedDuration = mode == .pomodoro ? store?.settings.pomodoroWorkDuration : nil
        snapshot.pomodoroCycle = snapshot.mode == .pomodoro ? snapshot.pomodoroCycle : 0
        snapshot.phase = .focus
        if mode == .pomodoro { snapshot.countdownEnd = now.addingTimeInterval(snapshot.plannedDuration ?? 25 * 60) }
        persist()
        scheduleNotificationIfNeeded()
    }

    func pause(now: Date = .now) {
        switch snapshot.phase {
        case .focus:
            snapshot.accumulatedFocus += max(0, now.timeIntervalSince(snapshot.focusResumedAt ?? now))
            snapshot.focusResumedAt = nil
            if snapshot.mode == .pomodoro {
                snapshot.remainingWhenPaused = max(0, (snapshot.countdownEnd ?? now).timeIntervalSince(now))
                snapshot.countdownEnd = nil
            }
            snapshot.phase = .pausedFocus
            persist()
        case .breakTimer:
            snapshot.remainingWhenPaused = max(0, (snapshot.countdownEnd ?? now).timeIntervalSince(now))
            snapshot.countdownEnd = nil
            snapshot.phase = .pausedBreak
            persist()
        default: break
        }
    }

    func resume(now: Date = .now) {
        switch snapshot.phase {
        case .pausedFocus:
            snapshot.focusResumedAt = now
            if snapshot.mode == .pomodoro {
                snapshot.countdownEnd = now.addingTimeInterval(snapshot.remainingWhenPaused ?? 0)
                snapshot.remainingWhenPaused = nil
            }
            snapshot.phase = .focus
            persist()
            scheduleNotificationIfNeeded()
        case .pausedBreak:
            snapshot.countdownEnd = now.addingTimeInterval(snapshot.remainingWhenPaused ?? 0)
            snapshot.remainingWhenPaused = nil
            snapshot.phase = .breakTimer
            persist()
        default: break
        }
    }

    func stop(now: Date = .now) {
        guard snapshot.phase == .focus || snapshot.phase == .pausedFocus else { return }
        let duration = focusDuration(at: now)
        guard duration > 0 else { reset(); return }
        let breakDuration: TimeInterval?
        if snapshot.mode == .flowmodoro {
            breakDuration = FlowmodoroMath.breakDuration(for: duration, ratio: store?.settings.flowBreakRatio ?? 5)
        } else {
            breakDuration = nil
        }
        store?.recordSession(
            id: snapshot.sessionID ?? UUID(), taskID: snapshot.taskID, mode: snapshot.mode,
            startedAt: snapshot.focusStartedAt ?? now, endedAt: now, focusedDuration: duration,
            plannedDuration: snapshot.plannedDuration, breakDuration: breakDuration, completed: snapshot.mode == .flowmodoro || isPomodoroIntervalComplete(at: now)
        )
        if snapshot.mode == .flowmodoro, let breakDuration, breakDuration > 0, store?.settings.flowAutoStartBreak == true {
            startBreak(duration: breakDuration, kind: .flowmodoro, now: now)
        } else {
            let suggested = snapshot.mode == .flowmodoro ? breakDuration : nil
            snapshot = TimerSnapshot(phase: suggested == nil ? .idle : .suggestedBreak, mode: snapshot.mode, suggestedBreak: suggested)
            persist()
        }
    }

    func skip(now: Date = .now) {
        switch snapshot.phase {
        case .focus, .pausedFocus:
            let duration = focusDuration(at: now)
            if duration > 0 {
                store?.recordSession(id: snapshot.sessionID ?? UUID(), taskID: snapshot.taskID, mode: snapshot.mode, startedAt: snapshot.focusStartedAt ?? now, endedAt: now, focusedDuration: duration, plannedDuration: snapshot.plannedDuration, completed: false, interrupted: true)
            }
            reset()
        case .breakTimer, .pausedBreak, .suggestedBreak:
            reset()
        case .idle:
            break
        }
    }

    func startSuggestedBreak(now: Date = .now) {
        guard snapshot.phase == .suggestedBreak, let duration = snapshot.suggestedBreak else { return }
        startBreak(duration: duration, kind: snapshot.breakKind ?? .flowmodoro, now: now)
    }

    func reset() {
        snapshot = TimerSnapshot(mode: store?.settings.selectedMode ?? .flowmodoro)
        persist()
    }

    func focusDuration(at now: Date = .now) -> TimeInterval {
        guard snapshot.phase == .focus || snapshot.phase == .pausedFocus else { return 0 }
        let live = snapshot.phase == .focus ? max(0, now.timeIntervalSince(snapshot.focusResumedAt ?? now)) : 0
        return snapshot.accumulatedFocus + live
    }

    func countdownRemaining(at now: Date = .now) -> TimeInterval {
        switch snapshot.phase {
        case .focus where snapshot.mode == .pomodoro:
            return max(0, (snapshot.countdownEnd ?? now).timeIntervalSince(now))
        case .breakTimer:
            return max(0, (snapshot.countdownEnd ?? now).timeIntervalSince(now))
        case .pausedFocus, .pausedBreak:
            return max(0, snapshot.remainingWhenPaused ?? 0)
        default:
            return 0
        }
    }

    private func startBreak(duration: TimeInterval, kind: BreakKind, now: Date) {
        snapshot.phase = .breakTimer
        snapshot.breakKind = kind
        snapshot.countdownEnd = now.addingTimeInterval(duration)
        // Reuses plannedDuration (otherwise only meaningful during Pomodoro
        // focus) as the break's total, so the ring can compute a progress
        // fraction without re-deriving short/long/flow durations itself —
        // it previously fell back to `remaining`, making the ring always
        // read as full for the whole break.
        snapshot.plannedDuration = duration
        snapshot.remainingWhenPaused = nil
        snapshot.suggestedBreak = nil
        persist()
        scheduleNotificationIfNeeded()
    }

    private func completePomodoroFocus(at date: Date) {
        let duration = focusDuration(at: date)
        guard duration > 0 else { reset(); return }
        let cycle = snapshot.pomodoroCycle + 1
        let cyclesBeforeLong = max(1, store?.settings.pomodoroCyclesBeforeLongBreak ?? 4)
        let isLongBreak = cycle >= cyclesBeforeLong
        let breakDuration = isLongBreak ? (store?.settings.pomodoroLongBreakDuration ?? 15 * 60) : (store?.settings.pomodoroShortBreakDuration ?? 5 * 60)
        store?.recordSession(
            id: snapshot.sessionID ?? UUID(), taskID: snapshot.taskID, mode: .pomodoro,
            startedAt: snapshot.focusStartedAt ?? date, endedAt: date, focusedDuration: duration,
            plannedDuration: snapshot.plannedDuration, breakDuration: breakDuration, completed: true
        )

        let nextCycle = isLongBreak ? 0 : cycle
        if store?.settings.pomodoroAutoStartBreak == true {
            snapshot.pomodoroCycle = nextCycle
            startBreak(duration: breakDuration, kind: isLongBreak ? .long : .short, now: date)
        } else {
            snapshot.phase = .suggestedBreak
            snapshot.breakKind = isLongBreak ? .long : .short
            snapshot.suggestedBreak = breakDuration
            snapshot.countdownEnd = nil
            snapshot.focusResumedAt = nil
            snapshot.remainingWhenPaused = nil
            snapshot.pomodoroCycle = nextCycle
            persist()
        }
    }

    private func completeBreak(at date: Date) {
        let shouldStartFocus = snapshot.mode == .pomodoro && (store?.settings.pomodoroAutoStartFocus ?? false)
        let mode = snapshot.mode
        let taskID = snapshot.taskID
        let nextCycle = snapshot.pomodoroCycle
        snapshot = TimerSnapshot(mode: mode, taskID: taskID, pomodoroCycle: nextCycle)
        persist()
        if shouldStartFocus { startFocus(taskID: taskID, mode: mode, now: date) }
    }

    private func isPomodoroIntervalComplete(at now: Date) -> Bool {
        guard snapshot.mode == .pomodoro else { return true }
        return countdownRemaining(at: now) <= 0
    }

    private func scheduleNotificationIfNeeded() {
        guard store?.settings.notificationsEnabled == true else { return }
        let remaining = countdownRemaining()
        guard remaining > 0 else { return }
        store?.notificationService.requestAuthorizationIfNeeded()
        let title = snapshot.phase == .breakTimer ? "Break complete" : "Focus interval complete"
        let body = snapshot.phase == .breakTimer ? "Ready to focus again?" : "Start your break."
        store?.notificationService.scheduleIntervalCompletion(at: Date().addingTimeInterval(remaining), title: title, body: body, sound: store?.settings.soundEnabled ?? true)
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults.set(data, forKey: Self.snapshotKey)
        // Single point every transition passes through: no pending completion
        // is left dangling on pause/stop/reset/completion, and a fresh
        // schedule (above) always replaces rather than stacks on it.
        if snapshot.countdownEnd == nil { store?.notificationService.cancelIntervalNotifications() }
        updateTicking()
    }

    /// One shared 1 Hz clock while a timer is actually running — replaces
    /// three separate per-second loops that used to live in AppStore,
    /// MenuBarLabel, and TaskRow. Idles (no scheduled task) the instant
    /// nothing is ticking, so the app stays App Nap-eligible.
    private func updateTicking() {
        let shouldTick = snapshot.phase == .focus || snapshot.phase == .breakTimer
        guard shouldTick != (tickTask != nil) else { return }
        tickTask?.cancel()
        guard shouldTick else { tickTask = nil; return }
        tickTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                self.now = .now
                self.refresh(at: self.now)
                try? await Task.sleep(for: .seconds(1), tolerance: .milliseconds(100))
            }
        }
    }
}
