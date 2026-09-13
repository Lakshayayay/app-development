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

    @Test func taskFactorsComputeFactualAggregates() {
        // No weighting, no composite score — every field here must be a
        // plain sum/count/average traceable to the underlying sessions.
        let taskA = UUID()
        let taskB = UUID()
        let day = Date(timeIntervalSince1970: 1_700_000_000)
        let values = [
            makeSession(duration: 60, startedAt: day, taskID: taskA),
            makeSession(duration: 120, startedAt: day.addingTimeInterval(60), taskID: taskA),
            makeSession(duration: 30, startedAt: day.addingTimeInterval(120), taskID: taskA, interrupted: true),
            makeSession(duration: 300, startedAt: day.addingTimeInterval(180), taskID: taskB),
        ]

        let factors = StatisticsEngine.taskFactors(values)
        #expect(factors.count == 2)

        let factorA = factors.first { $0.taskID == taskA }
        #expect(factorA?.totalFocused == 210)
        #expect(factorA?.sessionCount == 3)
        #expect(factorA?.meanSession == 70)
        #expect(factorA?.medianSession == 60)
        #expect(factorA?.interruptedCount == 1)
        #expect(factorA?.lastFocusedAt == day.addingTimeInterval(120))

        let factorB = factors.first { $0.taskID == taskB }
        #expect(factorB?.totalFocused == 300)
        #expect(factorB?.sessionCount == 1)
        #expect(factorB?.interruptedCount == 0)

        // Sorted by total focused time, descending.
        #expect(factors.first?.taskID == taskB)
    }

    @Test func dailyFocusZeroFillsQuietDays() {
        // A week with one focused day must still report every day in range
        // (including days with no sessions) so a chart doesn't silently
        // omit — and thereby misrepresent — the quiet days.
        let calendar = Calendar(identifier: .gregorian)
        let now = Date(timeIntervalSince1970: 1_700_000_000) // a Tuesday
        let values = [makeSession(duration: 600, startedAt: now)]

        let daily = StatisticsEngine.dailyFocus(values, period: .week, calendar: calendar, now: now)
        #expect(daily.contains { $0.duration == 0 })
        #expect(daily.contains { calendar.isDate($0.date, inSameDayAs: now) && $0.duration == 600 })
    }

    @Test @MainActor func pomodoroRefreshDetectsCompletionAfterSimulatedSleep() {
        // The timer must reconstruct correct state from timestamps even if
        // refresh() wasn't called while the Mac was asleep — it must not
        // matter that no poll happened between countdownEnd and now.
        let suiteName = "flowmodo.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let engine = TimerEngine(defaults: defaults)
        let start = Date(timeIntervalSince1970: 3_000)

        engine.startFocus(taskID: UUID(), mode: .pomodoro, now: start)
        #expect(engine.phase == .focus)

        // Simulate the Mac sleeping through the entire interval and beyond —
        // refresh() is called once, long after countdownEnd, exactly as
        // AppStore's wake observer or refresh loop would after a long sleep.
        let wakeTime = start.addingTimeInterval(25 * 60 + 90)
        engine.refresh(at: wakeTime)
        #expect(engine.phase == .suggestedBreak || engine.phase == .breakTimer)
        defaults.removePersistentDomain(forName: suiteName)
    }

    private func makeSession(duration: TimeInterval, startedAt: Date, taskID: UUID? = nil, interrupted: Bool = false) -> FocusSessionValue {
        let record = FocusSessionRecord(taskID: taskID, mode: .flowmodoro, startedAt: startedAt, endedAt: startedAt.addingTimeInterval(duration), focusedDuration: duration, plannedDuration: nil, completed: !interrupted, interrupted: interrupted)
        return FocusSessionValue(record)
    }
}
