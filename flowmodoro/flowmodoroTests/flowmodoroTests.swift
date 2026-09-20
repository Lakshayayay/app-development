import Foundation
import SwiftData
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

    @Test func formatDurationTimerStyleStaysSubtle() {
        // Menu bar / ring digits: m:ss under an hour, h:mm:ss past it — no
        // leading zeroes standing in for time that hasn't happened yet.
        #expect(formatDuration(59, style: .timer) == "0:59")
        #expect(formatDuration(3_599, style: .timer) == "59:59")
        #expect(formatDuration(3_600, style: .timer) == "1:00:00")
        #expect(formatDuration(0, style: .timer) == "0:00")
    }

    @Test func taskTotalsSplitTodayFromLifetime() {
        let calendar = Calendar(identifier: .gregorian)
        let today = Date(timeIntervalSince1970: 1_700_000_000)
        let yesterday = today.addingTimeInterval(-86_400)
        let taskA = UUID()
        let values = [
            makeSession(duration: 600, startedAt: today, taskID: taskA),
            makeSession(duration: 300, startedAt: yesterday, taskID: taskA),
            makeSession(duration: 120, startedAt: today, taskID: nil), // no task: excluded
        ]

        let totals = StatisticsEngine.taskTotals(values, calendar: calendar, now: today)
        #expect(totals.count == 1)
        #expect(totals[taskA]?.today == 600)
        #expect(totals[taskA]?.total == 900)
    }

    @Test @MainActor func flowmodoroBreakStoresPlannedDurationForRingProgress() {
        // Regression: startBreak() previously left snapshot.plannedDuration
        // at whatever the prior focus interval set it to (nil, for
        // Flowmodoro), so the break ring's progress fraction collapsed to
        // remaining / remaining == 1 — always full for the whole break.
        let suiteName = "flowmodo.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let engine = TimerEngine(defaults: defaults)
        let start = Date(timeIntervalSince1970: 4_000)

        engine.startFocus(taskID: UUID(), mode: .flowmodoro, now: start)
        engine.stop(now: start.addingTimeInterval(300)) // 5m focus -> 1m suggested break (ratio 5)
        #expect(engine.phase == .suggestedBreak)

        engine.startSuggestedBreak(now: start.addingTimeInterval(300))
        #expect(engine.phase == .breakTimer)
        #expect(engine.snapshot.plannedDuration == 60)
        #expect(engine.countdownRemaining(at: start.addingTimeInterval(300)) == 60)
        defaults.removePersistentDomain(forName: suiteName)
    }

    @Test func streakCountsGoalDaysAndTodayInProgressDoesNotBreakIt() {
        let calendar = Calendar(identifier: .gregorian)
        let today = calendar.startOfDay(for: Date(timeIntervalSince1970: 1_700_000_000))
        func day(_ offset: Int) -> Date { calendar.date(byAdding: .day, value: offset, to: today)! }
        let goal: TimeInterval = 30 * 60
        let dailyTotals: [Date: TimeInterval] = [
            today: 10 * 60,     // in progress, under goal — must not break the streak
            day(-1): 40 * 60,
            day(-2): 35 * 60,
            // day(-3) has no entry at all (no session that day) — breaks the run
            day(-4): 60 * 60,
            day(-5): 60 * 60,
            day(-6): 60 * 60,
        ]
        let streak = StatisticsEngine.streak(dailyTotals, goal: goal, calendar: calendar, now: today)
        #expect(streak.current == 2)
        #expect(streak.best == 3)
    }

    @Test func zeroFilledDaysCoverRangeEndingToday() {
        let calendar = Calendar(identifier: .gregorian)
        let today = calendar.startOfDay(for: Date(timeIntervalSince1970: 1_700_000_000))
        let start = calendar.date(byAdding: .day, value: -6, to: today)!
        let days = StatisticsEngine.days(from: start, through: today, calendar: calendar)
        #expect(days.count == 7)
        #expect(days.last == today)

        let filled = StatisticsEngine.zeroFilled([today: 600], days: days)
        #expect(filled.count == 7)
        #expect(filled.filter { $0.duration == 0 }.count == 6)
        #expect(filled.last?.duration == 600)
    }

    @Test @MainActor func tickerRunsOnlyWhileRunning() {
        // The shared clock (TimerEngine.now) must tick only while a timer is
        // actually running — idle/paused/suggested-break must stay silent so
        // the app is App Nap-eligible whenever nothing is counting.
        let suiteName = "flowmodo.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let engine = TimerEngine(defaults: defaults)
        let start = Date(timeIntervalSince1970: 5_000)

        #expect(!engine.isTicking)
        engine.startFocus(taskID: UUID(), mode: .flowmodoro, now: start)
        #expect(engine.isTicking)
        engine.pause(now: start.addingTimeInterval(10))
        #expect(!engine.isTicking)
        engine.resume(now: start.addingTimeInterval(20))
        #expect(engine.isTicking)
        engine.stop(now: start.addingTimeInterval(30))
        #expect(!engine.isTicking)
        defaults.removePersistentDomain(forName: suiteName)
    }

    @Test @MainActor func snapshotSavedBeforeRoundsStillDecodes() throws {
        // Upgrade safety: earlier builds persisted snapshots without the new
        // keys. Were either field non-optional, decoding would throw and
        // TimerEngine.init would silently discard a running timer.
        let legacy = #"{"phase":"focus","mode":"pomodoro","accumulatedFocus":0,"pomodoroCycle":1}"#
        let snapshot = try JSONDecoder().decode(TimerSnapshot.self, from: Data(legacy.utf8))
        #expect(snapshot.phase == .focus)
        #expect(snapshot.pomodoroPlan == nil)
        #expect(snapshot.roundsCompleted == nil)
    }

    @Test @MainActor func startFreezesClampedPlan() {
        let suiteName = "flowmodo.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let engine = TimerEngine(defaults: defaults)
        let start = Date(timeIntervalSince1970: 6_000)

        engine.startFocus(taskID: UUID(), mode: .pomodoro, plan: PomodoroPlan(work: 0, shortBreak: 10 * 60, rounds: 99), now: start)
        #expect(engine.snapshot.pomodoroPlan?.work == 60) // 0 would complete, and record, every tick
        #expect(engine.snapshot.pomodoroPlan?.rounds == 24)
        #expect(engine.countdownRemaining(at: start) == 60)
        defaults.removePersistentDomain(forName: suiteName)
    }

    @Test @MainActor func roundsLimitEndsRunAfterLastBreak() {
        let suiteName = "flowmodo.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let engine = TimerEngine(defaults: defaults)
        let start = Date(timeIntervalSince1970: 7_000)
        let plan = PomodoroPlan(work: 60, shortBreak: 60, longBreak: 60, rounds: 2, autoStartBreak: true, autoStartFocus: true)

        engine.startFocus(taskID: UUID(), mode: .pomodoro, plan: plan, now: start)
        engine.refresh(at: start.addingTimeInterval(60))   // round 1 done → break
        #expect(engine.phase == .breakTimer)
        engine.refresh(at: start.addingTimeInterval(120))  // break ends on time → round 2
        #expect(engine.phase == .focus)
        #expect(engine.snapshot.focusStartedAt == start.addingTimeInterval(120))
        engine.refresh(at: start.addingTimeInterval(180))  // round 2 done → break
        #expect(engine.snapshot.roundsCompleted == 2)
        engine.refresh(at: start.addingTimeInterval(240))  // last break ends → run over
        #expect(engine.phase == .idle)
        #expect(engine.snapshot.roundsCompleted == nil)
        defaults.removePersistentDomain(forName: suiteName)
    }

    @Test @MainActor func autoContinuePersistsRoundsCompleted() throws {
        // Regression: startFocus used to unconditionally clear
        // roundsCompleted and persist() before completeBreak's in-memory
        // restore ran, so a crash/relaunch during round 2+ of an
        // auto-continued run read back roundsCompleted == nil. Assert the
        // *persisted* snapshot (not just the live engine) carries the count.
        let suiteName = "flowmodo.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let engine = TimerEngine(defaults: defaults)
        let start = Date(timeIntervalSince1970: 7_500)
        let plan = PomodoroPlan(work: 60, shortBreak: 60, longBreak: 60, rounds: 3, autoStartBreak: true, autoStartFocus: true)

        engine.startFocus(taskID: UUID(), mode: .pomodoro, plan: plan, now: start)
        engine.refresh(at: start.addingTimeInterval(60))   // round 1 done → break
        engine.refresh(at: start.addingTimeInterval(120))  // break ends on time → round 2 auto-continues
        #expect(engine.phase == .focus)
        #expect(engine.snapshot.roundsCompleted == 1)

        let data = try #require(defaults.data(forKey: TimerEngine.snapshotKey))
        let persisted = try JSONDecoder().decode(TimerSnapshot.self, from: data)
        #expect(persisted.roundsCompleted == 1)
        defaults.removePersistentDomain(forName: suiteName)
    }

    @Test @MainActor func lateBreakEndDoesNotAutoStartFocus() {
        // Regression: after sleeping through a break with auto-continue on, the
        // tick loop chained break → backdated focus → completed focus → …,
        // recording 25-minute sessions nobody worked.
        let suiteName = "flowmodo.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let engine = TimerEngine(defaults: defaults)
        let start = Date(timeIntervalSince1970: 8_000)

        engine.startFocus(taskID: UUID(), mode: .pomodoro, plan: PomodoroPlan(work: 60, shortBreak: 60, autoStartBreak: true, autoStartFocus: true), now: start)
        engine.refresh(at: start.addingTimeInterval(60))               // → break ending at +120
        engine.refresh(at: start.addingTimeInterval(120 + 3 * 3_600))  // Mac woke 3 h later
        #expect(engine.phase == .idle)
        defaults.removePersistentDomain(forName: suiteName)
    }

    @Test @MainActor func bellRingsOnBreakStartAndEndButNotForStaleEnd() {
        let suiteName = "flowmodo.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let engine = TimerEngine(defaults: defaults)
        var rings = 0
        engine.onBell = { rings += 1 }
        let start = Date(timeIntervalSince1970: 9_000)
        let plan = PomodoroPlan(work: 60, shortBreak: 60, autoStartBreak: true)

        engine.startFocus(taskID: UUID(), mode: .pomodoro, plan: plan, now: start)
        #expect(rings == 0)                                            // nothing at focus start
        engine.refresh(at: start.addingTimeInterval(60))               // break starts
        #expect(rings == 1)
        engine.refresh(at: start.addingTimeInterval(120))              // break ends on time
        #expect(rings == 2)

        engine.startFocus(taskID: UUID(), mode: .pomodoro, plan: plan, now: start.addingTimeInterval(200))
        engine.refresh(at: start.addingTimeInterval(260))              // break starts
        engine.refresh(at: start.addingTimeInterval(320 + 3 * 3_600)) // woke 3 h late: silent
        #expect(rings == 3)
        defaults.removePersistentDomain(forName: suiteName)
    }

    @Test @MainActor func freshManualStartClearsStaleRoundsCompleted() {
        // Regression: a break that ends without auto-continuing (grace
        // exceeded here) left roundsCompleted on the idle snapshot. A later
        // *manual* Start must not inherit it — rounds=4 after 2 rounds this
        // morning should give 4 fresh rounds this afternoon, not 2 more.
        let suiteName = "flowmodo.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let engine = TimerEngine(defaults: defaults)
        let start = Date(timeIntervalSince1970: 9_000)
        let taskID = UUID()
        let plan = PomodoroPlan(work: 60, shortBreak: 60, longBreak: 60, rounds: 4, autoStartBreak: true, autoStartFocus: true)

        engine.startFocus(taskID: taskID, mode: .pomodoro, plan: plan, now: start)
        engine.refresh(at: start.addingTimeInterval(60))                    // round 1 done → break
        engine.refresh(at: start.addingTimeInterval(120))                   // break ends on time → round 2 (auto-continue)
        engine.refresh(at: start.addingTimeInterval(180))                   // round 2 done → break
        #expect(engine.snapshot.roundsCompleted == 2)
        engine.refresh(at: start.addingTimeInterval(180 + 60 + 3 * 3_600))  // Mac woke 3 h later: grace exceeded, run not finished (2 < 4)
        #expect(engine.phase == .idle)
        #expect(engine.snapshot.roundsCompleted == 2) // the leak: idle snapshot still carries the stale count

        let afternoon = start.addingTimeInterval(180 + 60 + 4 * 3_600)
        engine.startFocus(taskID: taskID, mode: .pomodoro, plan: plan, now: afternoon)
        #expect(engine.snapshot.roundsCompleted == nil) // fresh manual Start must not inherit it
        defaults.removePersistentDomain(forName: suiteName)
    }

    @Test func heatmapCellIndexIsWeekTimesSevenPlusWeekday() {
        // Hover resolves a cell by index (week * 7 + weekday) instead of scanning;
        // this invariant is what makes that lookup correct.
        let calendar = Calendar(identifier: .gregorian)
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let cells = HeatmapCell.pastYear([:], calendar: calendar, now: now)
        for (index, cell) in cells.enumerated() {
            #expect(index == cell.weekIndex * 7 + cell.weekday)
        }
        #expect(cells.last?.date == calendar.startOfDay(for: now))
    }

    @Test @MainActor func recordSessionMatchesFullReload() throws {
        // Guards AppStore.recordSession's in-memory aggregate update against
        // drifting from the fetch-and-recompute path it replaced.
        let container = try ModelContainer(
            for: FocusTask.self, FocusSessionRecord.self, AppSettingsRecord.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let store = AppStore(modelContainer: container)
        let taskID = UUID()
        let start = Date(timeIntervalSince1970: 8_000)

        store.recordSession(id: UUID(), taskID: taskID, mode: .flowmodoro, startedAt: start, endedAt: start.addingTimeInterval(600), focusedDuration: 600, plannedDuration: nil, completed: true)
        store.recordSession(id: UUID(), taskID: taskID, mode: .flowmodoro, startedAt: start.addingTimeInterval(1_000), endedAt: start.addingTimeInterval(1_300), focusedDuration: 300, plannedDuration: nil, completed: true)

        let incrementalSessionValues = store.sessionValues
        let incrementalTaskTotals = store.taskTotals
        let incrementalTodayTotal = store.todayTotal

        store.reload()

        #expect(store.sessionValues == incrementalSessionValues)
        #expect(store.taskTotals == incrementalTaskTotals)
        #expect(store.todayTotal == incrementalTodayTotal)
    }

    private func makeSession(duration: TimeInterval, startedAt: Date, taskID: UUID? = nil, interrupted: Bool = false) -> FocusSessionValue {
        let record = FocusSessionRecord(taskID: taskID, mode: .flowmodoro, startedAt: startedAt, endedAt: startedAt.addingTimeInterval(duration), focusedDuration: duration, plannedDuration: nil, completed: !interrupted, interrupted: interrupted)
        return FocusSessionValue(record)
    }
}
