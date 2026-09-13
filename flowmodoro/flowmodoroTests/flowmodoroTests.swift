import Foundation
import Testing
@testable import Flowmodora

struct FlowmodoTests {
    @Test func flowmodoroBreakUsesConfiguredRatio() {
        #expect(FlowmodoroMath.breakDuration(for: 25 * 60, ratio: 5) == 5 * 60)
        #expect(FlowmodoroMath.breakDuration(for: 50 * 60, ratio: 5) == 10 * 60)
        #expect(FlowmodoroMath.breakDuration(for: 120 * 60, ratio: 5) == 24 * 60)
        #expect(abs(FlowmodoroMath.breakDuration(for: 50 * 60, ratio: 4) - 12.5 * 60) < 0.001)
        #expect(abs(FlowmodoroMath.breakDuration(for: 50 * 60, ratio: 6) - (50.0 / 6.0) * 60) < 0.001)
    }

    @Test @MainActor func flowmodoroTimerAccumulatesOnlyFocusedTime() {
        let suiteName = "flowmodo.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let engine = TimerEngine(defaults: defaults)
        let taskID = UUID()
        let start = Date(timeIntervalSince1970: 1_000)

        engine.startFocus(taskID: taskID, mode: .flowmodoro, now: start)
        #expect(engine.focusDuration(at: start.addingTimeInterval(25)) == 25)
        engine.pause(now: start.addingTimeInterval(25))
        #expect(engine.focusDuration(at: start.addingTimeInterval(300)) == 25)
        engine.resume(now: start.addingTimeInterval(300))
        #expect(engine.focusDuration(at: start.addingTimeInterval(330)) == 55)
        defaults.removePersistentDomain(forName: suiteName)
    }

    @Test @MainActor func pomodoroCountdownUsesTargetDateAndPauseRecovery() {
        let suiteName = "flowmodo.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let engine = TimerEngine(defaults: defaults)
        let start = Date(timeIntervalSince1970: 2_000)

        engine.startFocus(taskID: UUID(), mode: .pomodoro, now: start)
        #expect(engine.countdownRemaining(at: start.addingTimeInterval(60)) == 24 * 60)
        engine.pause(now: start.addingTimeInterval(60))
        #expect(engine.countdownRemaining(at: start.addingTimeInterval(3_600)) == 24 * 60)
        engine.resume(now: start.addingTimeInterval(3_600))
        #expect(engine.countdownRemaining(at: start.addingTimeInterval(3_660)) == 23 * 60)
        defaults.removePersistentDomain(forName: suiteName)
    }

    @Test func statisticsSummaryAndCalendarGrouping() {
        // Interrupted sessions still represent real focused time (the user
        // worked 30 minutes before skipping) and are shown with that duration
        // in History, so StatisticsEngine must include them too — otherwise
        // the same session tells two different stories on two screens.
        let calendar = Calendar(identifier: .gregorian)
        let day = Date(timeIntervalSince1970: 1_700_000_000)
        let values = [
            makeSession(duration: 60, startedAt: day),
            makeSession(duration: 120, startedAt: day.addingTimeInterval(3_600)),
            makeSession(duration: 30, startedAt: day.addingTimeInterval(86_400), interrupted: true)
        ]

        let filtered = StatisticsEngine.filteredSessions(values, period: .total, calendar: calendar)
        let summary = StatisticsEngine.summary(filtered)
        #expect(summary.total == 210)
        #expect(summary.longest == 120)
        #expect(summary.average == 70)
        #expect(summary.sessions == 3)
        #expect(StatisticsEngine.dailyFocus(values, period: .total, calendar: calendar).count == 2)
    }

    private func makeSession(duration: TimeInterval, startedAt: Date, interrupted: Bool = false) -> FocusSessionValue {
        let record = FocusSessionRecord(taskID: nil, mode: .flowmodoro, startedAt: startedAt, endedAt: startedAt.addingTimeInterval(duration), focusedDuration: duration, plannedDuration: nil, completed: !interrupted, interrupted: interrupted)
        return FocusSessionValue(record)
    }
}
