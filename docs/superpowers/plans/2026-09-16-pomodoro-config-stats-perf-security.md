# Flowmodora — Pomodoro Config, Statistics Refresh, Performance & Security Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let users set up a Pomodoro before starting it, the way B Focused does. Give Statistics a cleaner, more colorful ("poppy") look. Make the UI measurably smoother and more responsive, and close a live data exposure. Keep the current select-task → Start flow and the current look.

**Architecture:** The Pomodoro settings already exist on `AppSettingsRecord`. This plan adds one field, `pomodoroRounds`, and shows the settings as a collapsible card in the popover, only while the timer is idle. Pressing Start copies the settings into `TimerSnapshot` as a `PomodoroPlan`, so a running cycle keeps its values even if Settings change. The Statistics parent view computes all history-based data once and passes plain values to child sections, which own their own hover state. Performance work starts and ends with recorded measurements.

**Tech Stack:** Swift 5 language mode (default `MainActor` isolation), SwiftUI with Liquid Glass, macOS 26.5, SwiftData, Swift Charts, Swift Testing, supabase-swift. No new dependencies.

**Spec:** the 2026-09-16 request: B Focused-style pre-start configuration (work/break intervals, cycle count, auto-break, auto-continue), a poppy statistics graph with the last columns removed, performance, security, and the current theme kept. Product constraints come from `STATUS.md`'s Product Principles section (was `PRINCIPLES.md` until the 2026-09-17 doc consolidation — see that note under Task 3.4).

---

## Findings this plan is built on (verified 2026-09-16)

| # | Finding | Evidence | Task |
|---|---|---|---|
| F1 | **Live data leak.** `public.daily_focus_logs` is a `SECURITY DEFINER` view over `focus_sessions`, and `anon` has SELECT on it. Anyone with the anon key embedded in the app can read every user's `user_id` and daily focus totals. `docs/SYNC.md` wrongly calls this view unrelated. | `get_advisors(security)` ERROR; `pg_get_viewdef`; `has_table_privilege('anon', …)` = true | 4.1 |
| F2 | `public.movies` has RLS disabled, and `anon` can SELECT, INSERT and DELETE on it. The table isn't Flowmodora's (it came from the pgvector/Gemini migrations), but it lives in the same project behind the same key. | advisors ERROR; privilege query | 4.1 (owner decision) |
| F3 | `Supabase/002_rls_perf_and_index.sql` was never applied. | advisors still report `auth_rls_initplan` ×4 and unindexed `tasks.user_id` | 4.1 |
| F4 | The app is sandboxed but has no `network.client` entitlement, so the sandbox blocks all outgoing network: Supabase sign-in and sync can't connect. The app also carries an unused `files.user-selected.read-write` entitlement and has no hardened runtime. | `codesign -d --entitlements -` on the Release build; `project.pbxproj` | 4.2 |
| F5 | **Auto-continue records sessions that never happened.** After the Mac sleeps through a break, each tick of `refresh` runs one more transition: break ends, then a focus interval starts backdated to the break's end, then that interval completes. This repeats, recording 25-minute sessions nobody worked. | `TimerEngine.refresh` / `completeBreak` | 1.1 |
| F6 | After switching the picker to Pomodoro, the idle ring shows `0:00`. The idle branch reads the stale snapshot mode (`timer.mode`) instead of `settings.selectedMode`. | `FlowmodoraTimerView.displayValue` | 1.2 |
| F7 | Hovering Statistics recomputes history on every pointer event. The heatmap rebuilds its 364 `cells` (Calendar calls) on each `onContinuousHover`, and `ProgressSection` evaluates `daily` 3 times per selection change. | `StatisticsView.swift` computed properties | 2.1 |
| F8 | `FlowmodoraTimerView.body` reads `timer.now`, so the glass control buttons re-render every second. | `timerCircle` | 3.1 |
| F9 | The Flowmodoro ring sweeps backwards once an hour: progress drops from 0.999 to 0 under a 1 s linear animation. | `progress(at:)` + `.animation(.linear(duration: 1))` | 3.1 |
| F10 | The task row, checkbox, `+` and footer buttons give no feedback when pressed. The control morph animation runs 350 ms, above the repo's own guide of < 300 ms (`.agents/skills/emil-design-eng`). | `ContentView.swift` | 3.2 |
| F11 | Every `save()` starts its own `attemptSync()`. A burst of saves (for example, holding a stepper) runs several syncs at once, and they upload the same queued entries repeatedly. | `AppStore.save` | 3.3 |

## Assumption to confirm

"Remove the completely last columns" is read here as: remove the **Longest** and **Average** tiles, which are the last two columns of the four-tile row under the period picker. **Focus time** and **Sessions** stay. `StatisticsEngine.summary` still computes all four values, so no engine tests change. If you meant other columns, only Task 2.2 Step 2 changes.

## Global Constraints

- Do not change the header mode picker, task-list selection, the ring and controls, the right-click menu, or the ⌘⌥S/P/X hotkeys. The config card appears **only** when `timer.phase == .idle` and the selected mode is Pomodoro.
- Theme: `Color.accentColor` (violet). Use `.glassEffect` only on floating or interactive elements, never as a second glass pane inside the popover. Tiles are `.quaternary.opacity(0.5)` in a `RoundedRectangle(cornerRadius: 10)`. Pressable elements use `.springButtonStyle()`. Every animation honors `accessibilityReduceMotion`.
- UI animations take ≤ 300 ms. The only exception is the ring's 1 s linear tick.
- New `@Model` properties need an inline default so SwiftData's lightweight migration can fill them. New `TimerSnapshot` fields must be **Optional**: the synthesized `Decodable` throws on a missing non-optional key, which would silently discard a running timer on upgrade.
- Local-first: no network calls on the timer or statistics paths. Never backdate focus time.
- New `.swift` files under `flowmodoro/flowmodoro/` join the target automatically (the project uses file-system-synchronized groups).
- Changes to the live Supabase project (Task 4.1) need the owner's explicit go-ahead before they are applied.
- Test command (15 tests today):
  `xcodebuild test -project flowmodoro/flowmodoro.xcodeproj -scheme flowmodoro -destination 'platform=macOS' -only-testing:flowmodoroTests`

## Execution order

Do **4.1 now**: it is an ops change, independent of the code, and fixes a live leak. Then run 0.1 → 1.1 → 1.2 → 2.1 → 2.2 → 3.1 → 3.2 → 4.2 → 4.3 → 3.3 → 3.4. Task 3.3's manual check needs working sync, so it comes after 4.2.

---

## Section 0 — Baseline

### Task 0.1: Demo-data launch flag + before-benchmarks

**Description:** "Snappier" can't be proven without numbers, and the Statistics jank only shows up with years of history. This task adds a Debug-only `-demoData` launch flag that runs the app on an in-memory store. Real data is never touched, and sync is off. Then it records the baseline measurements.

**Files:**
- Create: `flowmodoro/flowmodoro/Core/DemoData.swift`
- Modify: `flowmodoro/flowmodoro/flowmodoroApp.swift:9-19`
- Modify: `flowmodoro/flowmodoro/Core/AppStore.swift:97-98` (`attemptSync`)
- Create: `flowmodoro/docs/PERFORMANCE.md`

- [ ] **Step 1: Seeder**

```swift
#if DEBUG
import Foundation
import SwiftData

/// `-demoData` launch argument (Debug only): an in-memory store seeded with
/// three years of sessions, so Statistics can be profiled at a realistic
/// history size without touching the real database. Sync is off for the run.
enum DemoData {
    static let isActive = CommandLine.arguments.contains("-demoData")

    static func container() throws -> ModelContainer {
        let container = try ModelContainer(
            for: FocusTask.self, FocusSessionRecord.self, AppSettingsRecord.self, OutboxEntry.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)
        let tasks = ["Thesis", "Reading", "Code review", "Email", "Design"].map { FocusTask(title: $0) }
        tasks.forEach(context.insert)
        let today = Calendar.current.startOfDay(for: .now)
        // Deterministic, so before/after benchmarks run on identical data.
        for dayOffset in 0..<1_095 {
            guard let day = Calendar.current.date(byAdding: .day, value: -dayOffset, to: today) else { continue }
            for slot in 0..<(dayOffset % 7) {
                let start = day.addingTimeInterval(TimeInterval((8 + slot) * 3_600))
                let duration = TimeInterval(((dayOffset * 7 + slot * 13) % 51 + 10) * 60)
                context.insert(FocusSessionRecord(
                    taskID: tasks[(dayOffset + slot) % tasks.count].id, mode: .pomodoro,
                    startedAt: start, endedAt: start.addingTimeInterval(duration),
                    focusedDuration: duration, plannedDuration: 25 * 60, completed: true
                ))
            }
        }
        try context.save()
        return container
    }
}
#endif
```

- [ ] **Step 2: Route container creation through it** (`flowmodoroApp.swift`)

Replace the `do { container = try ModelContainer(for: …) }` line with `container = try Self.makeContainer()` and add:

```swift
private static func makeContainer() throws -> ModelContainer {
    #if DEBUG
    if DemoData.isActive { return try DemoData.container() }
    #endif
    return try ModelContainer(for: FocusTask.self, FocusSessionRecord.self, AppSettingsRecord.self, OutboxEntry.self)
}
```

- [ ] **Step 3: Never upload demo data** (first lines of `AppStore.attemptSync()`)

```swift
#if DEBUG
guard !DemoData.isActive else { return }
#endif
```

- [ ] **Step 4: Record the baselines**

```bash
xcodebuild -project flowmodoro/flowmodoro.xcodeproj -scheme flowmodoro -configuration Debug -derivedDataPath flowmodoro/build build
osascript -e 'quit app "Flowmodora"'   # run one instance only: hotkeys and the status item would collide
open -n flowmodoro/build/Build/Products/Debug/Flowmodora.app --args -demoData
PID=$(pgrep -n Flowmodora)
# 60 s average of CPU and idle wakeups (run once per scenario S1–S3)
top -l 61 -s 1 -stats pid,cpu,idlew -pid $PID | awk -v p=$PID '$1==p {c+=$2; w+=$3; n++} END {printf "cpu %.1f%%  idle wakeups/s %.1f\n", c/n, w/n}'
# S4: list templates first, since names vary by Xcode version
xcrun xctrace list templates
xcrun xctrace record --template 'SwiftUI' --attach $PID --time-limit 15s --output flowmodoro/build/stats-before.trace
```

Scenarios: **S1** idle, popover closed. **S2** Pomodoro running, popover closed. **S3** Pomodoro running, popover open. **S4** Statistics window open with the period set to All; during the 15 s trace, sweep the pointer across the heatmap and the bar chart. In the trace, note the body-update counts for `HeatmapSection` and `ProgressSection`, and the number of hitches. **Stop the timer before quitting a demo run**: the timer snapshot lives in `UserDefaults`, not in the store.

Write `flowmodoro/docs/PERFORMANCE.md` with this table and fill in the Before column (build config: Debug, `-demoData`):

| Scenario | Metric | Before | After |
|---|---|---|---|
| S1 idle, closed | CPU % / idle wakeups/s | | |
| S2 running, closed | CPU % / idle wakeups/s | | |
| S3 running, open | CPU % / idle wakeups/s | | |
| S4 stats hover sweep | body updates (Heatmap / Progress) / hitches | | |

- [ ] **Step 5: Run tests, then commit**

Run the test command. Expected: 15 pass.

```bash
git add flowmodoro/flowmodoro/Core/DemoData.swift flowmodoro/flowmodoro/flowmodoroApp.swift flowmodoro/flowmodoro/Core/AppStore.swift flowmodoro/docs/PERFORMANCE.md
git commit -m "chore(perf): -demoData launch flag and baseline measurements"
```

---

## Section 1 — Pomodoro configuration (B Focused flow)

**What the user sees:** They select a task (unchanged). Under the ring, a card reads "25m focus · 5m break · ∞ rounds". Clicking it expands the card to show Focus, Short break, Long break, Long break every, Rounds, Auto-start breaks and Auto-continue. Then they press Start. While the timer runs, the ring subtitle reads "Round 2 of 4". Settings → Focus shows the same controls, bound to the same values.

### Task 1.1: Freeze the plan at Start, add rounds, and stop auto-continue from recording fake sessions

**Files:**
- Modify: `flowmodoro/flowmodoro/Core/FlowmodoModels.swift` (`AppSettingsRecord`, `TimerSnapshot`, new `PomodoroPlan`)
- Modify: `flowmodoro/flowmodoro/Core/TimerEngine.swift` (`refresh`, `startFocus`, `completePomodoroFocus`, `completeBreak`)
- Test: `flowmodoro/flowmodoroTests/flowmodoroTests.swift`

**Interfaces — Produces:**
- `struct PomodoroPlan: Codable, Sendable, Equatable` with `work`, `shortBreak`, `longBreak: TimeInterval`; `cyclesBeforeLongBreak`, `rounds: Int` (0 = until stopped); `autoStartBreak`, `autoStartFocus: Bool`; `init(settings: AppSettingsRecord?)`; `func clamped() -> PomodoroPlan`
- `AppSettingsRecord.pomodoroRounds: Int`
- `TimerSnapshot.pomodoroPlan: PomodoroPlan?`, `TimerSnapshot.roundsCompleted: Int?`
- `TimerEngine.startFocus(taskID: UUID?, mode: FocusMode, plan: PomodoroPlan? = nil, now: Date = .now)`
- `TimerEngine.autoContinueGrace: TimeInterval` (120)

- [ ] **Step 1: Write the failing tests** (add inside `FlowmodoTests`)

```swift
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
```

- [ ] **Step 2: Run the tests and confirm they fail**

Run the test command. Expected: a build failure with "cannot find 'PomodoroPlan' in scope".

- [ ] **Step 3: Models** (`FlowmodoModels.swift`)

In `AppSettingsRecord`, after `dailyFocusGoal`, add the property, and add `self.pomodoroRounds = 0` in `init`:

```swift
/// Focus rounds per Pomodoro run; 0 = until stopped (the pre-rounds behavior).
var pomodoroRounds: Int = 0
```

Append to `TimerSnapshot`:

```swift
// Optional so snapshots persisted by earlier builds still decode.
var pomodoroPlan: PomodoroPlan?
var roundsCompleted: Int?
```

Add after `TimerSnapshot`:

```swift
/// The Pomodoro configuration committed when Start is pressed. Frozen into
/// TimerSnapshot so editing Settings mid-run can't change a cycle already in
/// progress, and a relaunch resumes the same plan.
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
```

- [ ] **Step 4: Engine** (`TimerEngine.swift`). Replace these four methods in full:

```swift
func refresh(at now: Date = .now) {
    if snapshot.phase == .focus, snapshot.mode == .pomodoro, let end = snapshot.countdownEnd, now >= end {
        completePomodoroFocus(at: end)
        return
    }
    guard snapshot.phase == .breakTimer, let end = snapshot.countdownEnd, now >= end else { return }
    completeBreak(at: end, observedAt: now)
}

/// How late a break's end may be noticed and still auto-continue into focus.
/// Any later and the Mac was almost certainly asleep: starting a focus
/// interval then would record focus that never happened.
static let autoContinueGrace: TimeInterval = 120

func startFocus(taskID: UUID?, mode: FocusMode, plan: PomodoroPlan? = nil, now: Date = .now) {
    guard let taskID else { return }
    if snapshot.phase == .suggestedBreak { snapshot = TimerSnapshot() }
    guard snapshot.phase == .idle else { return }
    snapshot.mode = mode
    snapshot.taskID = taskID
    snapshot.sessionID = UUID()
    snapshot.focusStartedAt = now
    snapshot.focusResumedAt = now
    snapshot.accumulatedFocus = 0
    if mode == .pomodoro {
        // Start commits the popover's configuration; an auto-continued round
        // (completeBreak) passes its frozen plan instead.
        let committed = (plan ?? PomodoroPlan(settings: store?.settings)).clamped()
        snapshot.pomodoroPlan = committed
        snapshot.plannedDuration = committed.work
        snapshot.countdownEnd = now.addingTimeInterval(committed.work)
    } else {
        snapshot.plannedDuration = nil
        snapshot.pomodoroCycle = 0
    }
    snapshot.phase = .focus
    persist()
    scheduleNotificationIfNeeded()
}

private func completePomodoroFocus(at date: Date) {
    let duration = focusDuration(at: date)
    guard duration > 0 else { reset(); return }
    // Snapshots restored from before plans existed fall back to Settings.
    let plan = snapshot.pomodoroPlan ?? PomodoroPlan(settings: store?.settings).clamped()
    let cycle = snapshot.pomodoroCycle + 1
    let isLongBreak = cycle >= plan.cyclesBeforeLongBreak
    let breakDuration = isLongBreak ? plan.longBreak : plan.shortBreak
    store?.recordSession(
        id: snapshot.sessionID ?? UUID(), taskID: snapshot.taskID, mode: .pomodoro,
        startedAt: snapshot.focusStartedAt ?? date, endedAt: date, focusedDuration: duration,
        plannedDuration: snapshot.plannedDuration, breakDuration: breakDuration, completed: true
    )
    snapshot.pomodoroPlan = plan
    snapshot.roundsCompleted = (snapshot.roundsCompleted ?? 0) + 1

    let nextCycle = isLongBreak ? 0 : cycle
    if plan.autoStartBreak {
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

private func completeBreak(at end: Date, observedAt now: Date) {
    let plan = snapshot.pomodoroPlan
    let rounds = plan?.rounds ?? 0
    let runFinished = rounds > 0 && (snapshot.roundsCompleted ?? 0) >= rounds
    let shouldStartFocus = snapshot.mode == .pomodoro
        && (plan?.autoStartFocus ?? store?.settings.pomodoroAutoStartFocus ?? false)
        && !runFinished
        && now.timeIntervalSince(end) <= Self.autoContinueGrace
    let mode = snapshot.mode
    let taskID = snapshot.taskID
    snapshot = runFinished
        ? TimerSnapshot(mode: mode, taskID: taskID)
        : TimerSnapshot(mode: mode, taskID: taskID, pomodoroCycle: snapshot.pomodoroCycle, roundsCompleted: snapshot.roundsCompleted)
    persist()
    // Starts at `now`, never backdated to `end`.
    if shouldStartFocus { startFocus(taskID: taskID, mode: mode, plan: plan, now: now) }
}
```

- [ ] **Step 5: Run the tests and confirm they pass**

Run the test command. Expected: 19 pass. The existing Pomodoro tests still pass because a `nil` store falls back to the default plan.

- [ ] **Step 6: Record the decision.** Append to `flowmodoro/docs/ARCHITECTURE_DECISIONS.md`:

```markdown
## Pomodoro plan frozen at Start; no auto-continue after a late break

- Decision: pressing Start copies the Pomodoro settings into `TimerSnapshot.pomodoroPlan` (clamped to the Settings stepper ranges). Auto-continued rounds reuse it, and `roundsCompleted` ends a run after `rounds` focus intervals (0 = until stopped). A break end noticed more than `TimerEngine.autoContinueGrace` (120 s) late never auto-starts focus, and an auto-started focus begins when it is noticed, never backdated.
- Reason: reading Settings live let a mid-run edit change a cycle already running. Worse, after sleep the tick loop chained break → backdated focus → completion and recorded focus that never happened (violates "focus data reflects what actually happened").
- Alternative: keep reading Settings live and only add the grace check. Rejected: a running round could still change underneath the user, and the engine stayed untestable without a full AppStore.
```

- [ ] **Step 7: Commit**

```bash
git add flowmodoro/flowmodoro/Core/FlowmodoModels.swift flowmodoro/flowmodoro/Core/TimerEngine.swift flowmodoro/flowmodoroTests/flowmodoroTests.swift flowmodoro/docs/ARCHITECTURE_DECISIONS.md
git commit -m "feat(timer): Pomodoro plan frozen at start, rounds, no fabricated auto-continue after sleep"
```

### Task 1.2: Pre-start config card + shared fields

**Files:**
- Create: `flowmodoro/flowmodoro/Features/UI/PomodoroConfigView.swift`
- Modify: `flowmodoro/flowmodoro/Features/UI/FlowmodoraTimerView.swift` (`body`, `displayValue` idle case, `subtitle`)
- Modify: `flowmodoro/flowmodoro/ContentView.swift:248-253` (Settings → Focus Pomodoro rows)

**Interfaces — Consumes:** `AppSettingsRecord.pomodoroRounds`, `TimerSnapshot.pomodoroPlan`, `TimerSnapshot.roundsCompleted` (Task 1.1); `DurationStepper`, `formatDuration`, `.springButtonStyle()` (existing).

- [ ] **Step 1: Create `PomodoroConfigView.swift`**

```swift
import SwiftUI

/// Pomodoro interval and round controls bound directly to AppSettingsRecord.
/// Shared by the popover's pre-start card and Settings → Focus, so the two can
/// never disagree. TimerEngine.startFocus freezes these values when Start is pressed.
struct PomodoroConfigFields: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        LabeledContent("Focus") { DurationStepper(value: setting(\.pomodoroWorkDuration)) }
        LabeledContent("Short break") { DurationStepper(value: setting(\.pomodoroShortBreakDuration)) }
        LabeledContent("Long break") { DurationStepper(value: setting(\.pomodoroLongBreakDuration)) }
        LabeledContent("Long break every") {
            Stepper(value: setting(\.pomodoroCyclesBeforeLongBreak), in: 1...12) {
                Text("\(store.settings.pomodoroCyclesBeforeLongBreak) rounds").monospacedDigit()
            }
        }
        LabeledContent("Rounds") {
            Stepper(value: setting(\.pomodoroRounds), in: 0...24) {
                Text(store.settings.pomodoroRounds == 0 ? "Until stopped" : "\(store.settings.pomodoroRounds)").monospacedDigit()
            }
        }
        LabeledContent("Auto-start breaks") { toggle(\.pomodoroAutoStartBreak) }
        LabeledContent("Auto-continue") { toggle(\.pomodoroAutoStartFocus) }
    }

    private func toggle(_ keyPath: ReferenceWritableKeyPath<AppSettingsRecord, Bool>) -> some View {
        Toggle("", isOn: setting(keyPath)).labelsHidden().toggleStyle(.switch).controlSize(.mini)
    }

    private func setting<T>(_ keyPath: ReferenceWritableKeyPath<AppSettingsRecord, T>) -> Binding<T> {
        Binding(get: { store.settings[keyPath: keyPath] },
                set: { store.settings[keyPath: keyPath] = $0; store.updateSettings() })
    }
}

/// B Focused-style pre-start step: a one-line summary of the plan that expands
/// to edit it. Shown only while idle in Pomodoro mode, so the running flow is
/// unchanged. A plain tile rather than glass: the popover is already the one
/// glass pane (see FlowmodoraTimerView).
struct PomodoroConfigCard: View {
    @Environment(AppStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isExpanded = false

    var body: some View {
        VStack(spacing: 8) {
            Button { isExpanded.toggle() } label: {
                HStack {
                    Text(summary)
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .contentTransition(.numericText())
                    Spacer()
                    Image(systemName: "chevron.down")
                        .rotationEffect(.degrees(isExpanded ? 180 : 0))
                        .foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
            }
            .springButtonStyle()
            .accessibilityLabel("Pomodoro plan: \(summary)")
            .accessibilityHint(isExpanded ? "Collapse" : "Expand to edit")

            if isExpanded {
                VStack(spacing: 6) { PomodoroConfigFields() }
                    .font(.subheadline)
                    .labeledContentStyle(RowLabeledContentStyle())
                    .transition(.opacity.combined(with: .scale(0.95, anchor: .top)))
            }
        }
        .padding(10)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
        .animation(reduceMotion ? nil : .snappy(duration: 0.2), value: isExpanded)
        .sensoryFeedback(.levelChange, trigger: summary)
    }

    private var summary: String {
        let s = store.settings
        let rounds = s.pomodoroRounds == 0 ? "∞" : "\(s.pomodoroRounds)"
        return "\(formatDuration(s.pomodoroWorkDuration)) focus · \(formatDuration(s.pomodoroShortBreakDuration)) break · \(rounds) rounds"
    }
}

/// Label on the leading edge, control on the trailing edge, as a grouped Form row lays them out, for use outside a Form.
private struct RowLabeledContentStyle: LabeledContentStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack { configuration.label; Spacer(); configuration.content }
    }
}
```

- [ ] **Step 2: Insert the card between the ring and the controls** (`FlowmodoraTimerView.body`)

```swift
VStack(spacing: 20) {
    timerCircle
    if showsConfig {
        PomodoroConfigCard()
            .transition(.opacity.combined(with: .scale(0.95, anchor: .top)))
    }
    controls
}
.animation(reduceMotion ? nil : .snappy(duration: 0.25), value: showsConfig)
```

```swift
private var showsConfig: Bool {
    store.timer.phase == .idle && store.settings.selectedMode == .pomodoro
}
```

- [ ] **Step 3: Fix F6 and show round progress** (same file)

In `displayValue(at:)`, replace the `.idle` case:

```swift
case .idle:
    // settings.selectedMode, not timer.mode: the snapshot's mode only
    // refreshes on reset(), so it's stale right after switching the picker.
    let upcoming = store.settings.selectedMode == .flowmodoro ? 0 : store.settings.pomodoroWorkDuration
    return formatDuration(upcoming, style: .timer)
```

In `subtitle`, replace `case .focus, .pausedFocus: return ""`:

```swift
case .focus, .pausedFocus:
    guard store.timer.mode == .pomodoro, let rounds = store.timer.snapshot.pomodoroPlan?.rounds, rounds > 0 else { return "" }
    return "Round \((store.timer.snapshot.roundsCompleted ?? 0) + 1) of \(rounds)"
```

- [ ] **Step 4: Settings reuses the same fields** (`ContentView.swift`)

Replace the six rows from `HStack { Text("Pomodoro work") …` through `Toggle("Auto-start next focus", …)` (lines 248–253) with:

```swift
PomodoroConfigFields()
```

Leave "Show Pause button" and "Daily goal" untouched.

- [ ] **Step 5: Verify**

Run the test command. Expected: 19 pass. Then build, run, and check each item:
- While idle, switch the picker from Flowmodoro to Pomodoro: the ring shows `25:00` immediately and the card appears.
- Select a task and expand the card. Set Focus 1m, Short break 1m, Rounds 2, both toggles on, then Start. Expect: `1:00`, subtitle "Round 1 of 2" → break starts automatically → round 2 starts automatically → after the second break the app is idle, shows "Ready", and the card is back.
- While a round runs, change Focus to 50m in the Settings window. The running countdown doesn't change; the next Start uses 50m.
- The Settings window and the card show the same values live.
- Holding a stepper repeats smoothly, with a trackpad haptic per change (Force Touch trackpad).
- With Reduce Motion on, the card appears and disappears without scaling.
- Quit mid-round and relaunch: the countdown and "Round x of y" are restored.
- The popover resizes on Start without clipping (regression check for commit 1e7beb1).

- [ ] **Step 6: Commit**

```bash
git add flowmodoro/flowmodoro/Features/UI/PomodoroConfigView.swift flowmodoro/flowmodoro/Features/UI/FlowmodoraTimerView.swift flowmodoro/flowmodoro/ContentView.swift
git commit -m "feat(ui): B Focused-style pre-start Pomodoro config card; fix stale idle ring mode"
```

---

## Section 2 — Statistics

### Task 2.1: Compute once, hover cheaply (no visual change)

**Description:** A prerequisite for richer hover callouts. The parent view computes every history-based value once per store write or period change and passes it down. Hover lookups become O(1) and re-render only when the pointer crosses into a new cell or day.

**Files:**
- Modify: `flowmodoro/flowmodoro/Features/UI/StatisticsView.swift`
- Test: `flowmodoro/flowmodoroTests/flowmodoroTests.swift`

**Interfaces — Produces:** `struct HeatmapCell: Identifiable, Equatable` (internal) with `static func pastYear(_ dailyTotals: [Date: TimeInterval], calendar: Calendar = .current, now: Date = .now) -> [HeatmapCell]`; `HeatmapSection(cells:goal:)`; `ProgressSection(daily:summary:goal:)`; `MilestoneSection(series:)`; `TaskBreakdownSection(bars:)`; `struct TaskBar: Identifiable, Equatable { name, duration }`.

- [ ] **Step 1: Write the failing test**

```swift
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
```

- [ ] **Step 2: Run the test and confirm it fails**

Run the test command. Expected: a build failure, since `HeatmapCell` is private and `pastYear` doesn't exist.

- [ ] **Step 3: Restructure `StatisticsView.swift`**

Parent:

```swift
struct StatisticsView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var period: StatisticsPeriod = .week

    private static let periods: [StatisticsPeriod] = [.week, .month, .year, .total]

    var body: some View {
        // Everything that scales with history is derived here, once per store
        // write or period change, and passed down as plain values. The sections
        // own their hover/selection state, so a pointer move re-runs only them.
        let values = StatisticsEngine.filteredSessions(store.sessionValues, period: period)
        let goal = store.settings.dailyFocusGoal
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HeroRow()
                HeatmapSection(cells: HeatmapCell.pastYear(store.dailyTotals), goal: goal)
                VStack(alignment: .leading, spacing: 10) {
                    Picker("Period", selection: $period) {
                        ForEach(Self.periods) { Text($0 == .total ? "All" : $0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    ProgressSection(
                        daily: StatisticsEngine.dailyFocus(store.sessionValues, period: period),
                        summary: StatisticsEngine.summary(values),
                        goal: goal
                    )
                    .animation(reduceMotion ? nil : .smooth(duration: 0.25), value: period)
                }
                MilestoneSection(series: cumulativeSeries)
                TaskBreakdownSection(bars: taskBars(values))
            }
            .padding(24)
        }
        .navigationTitle("Statistics")
        .frame(minWidth: 680, minHeight: 720)
    }

    private var cumulativeSeries: [DailyFocus] {
        guard let earliest = store.dailyTotals.keys.min() else { return [] }
        let days = StatisticsEngine.days(from: earliest, through: .now)
        return StatisticsEngine.cumulative(StatisticsEngine.zeroFilled(store.dailyTotals, days: days))
    }

    private func taskBars(_ values: [FocusSessionValue]) -> [TaskBar] {
        let factors = StatisticsEngine.taskFactors(values)
        var bars = factors.prefix(5).map { TaskBar(name: store.taskTitle(for: $0.taskID), duration: $0.totalFocused) }
        let other = factors.dropFirst(5).reduce(0) { $0 + $1.totalFocused }
        if other > 0 { bars.append(TaskBar(name: "Other", duration: other)) }
        return bars
    }
}

private struct TaskBar: Identifiable, Equatable {
    let name: String
    let duration: TimeInterval
    var id: String { name }
}
```

Heatmap. Drop `private` from `HeatmapCell` and move the `cells` code into it:

```swift
struct HeatmapCell: Identifiable, Equatable {
    let date: Date
    let weekIndex: Int
    let weekday: Int
    let duration: TimeInterval
    var id: Date { date }

    /// 52 trailing weeks from a week start through today, in day order, so a
    /// cell's index is always `weekIndex * 7 + weekday`.
    static func pastYear(_ dailyTotals: [Date: TimeInterval], calendar: Calendar = .current, now: Date = .now) -> [HeatmapCell] {
        let today = calendar.startOfDay(for: now)
        guard let start = calendar.date(byAdding: .day, value: -363, to: today) else { return [] }
        let weekStart = calendar.dateInterval(of: .weekOfYear, for: start)?.start ?? start
        return StatisticsEngine.days(from: weekStart, through: today, calendar: calendar).map { day in
            let offset = calendar.dateComponents([.day], from: weekStart, to: day).day ?? 0
            return HeatmapCell(date: day, weekIndex: offset / 7, weekday: offset % 7, duration: dailyTotals[day] ?? 0)
        }
    }
}
```

In `HeatmapSection`: remove `@Environment(AppStore.self)` and the `cells` computed property, and add `let cells: [HeatmapCell]` and `let goal: TimeInterval`. In `level(_:)`, use `goal` instead of `store.settings.dailyFocusGoal`. Replace the `.onContinuousHover` closure with:

```swift
.onContinuousHover { phase in
    guard let plotFrame = proxy.plotFrame else { return }
    var cell: HeatmapCell?
    if case .active(let location) = phase {
        let origin = geo[plotFrame].origin
        if let (week, row) = proxy.value(at: CGPoint(x: location.x - origin.x, y: location.y - origin.y), as: (Int, Int).self),
           (0...6).contains(row) {
            let index = week * 7 + (6 - row)
            cell = cells.indices.contains(index) ? cells[index] : nil
        }
    }
    // Dozens of pointer events land inside one cell; only a new cell re-renders.
    if cell != hovered { hovered = cell }
}
```

In `ProgressSection`: remove the store and the computed `values`/`summary`/`daily`, and add `let daily: [DailyFocus]`, `let summary: FocusSummary`, `let goal: TimeInterval`. Replace `store.settings.dailyFocusGoal` with `goal`. **Delete the existing computed `private var selectedDay: DailyFocus? { … }` property entirely** — its lookup logic becomes the new `match` property below. Then rename `@State private var selectedDate: Date?` to `@State private var selectedDay: Date?` (now a plain day-snapped `Date?`, reusing the freed name) and snap it to the day:

```swift
.chartXSelection(value: Binding(
    get: { selectedDay },
    // Snapped to the day: re-renders once per bar crossed, not per pointer event.
    set: { date in
        let day = date.map { Calendar.current.startOfDay(for: $0) }
        if day != selectedDay { selectedDay = day }
    }
))
```

```swift
private var match: DailyFocus? {
    selectedDay.flatMap { day in daily.first { $0.date == day } }
}
```

Use `match` wherever the view used `selectedDay` (the caption `if let`).

In `MilestoneSection`: remove the store and the computed `series`, and add `let series: [DailyFocus]`. `total` and `milestone` stay computed from `series`.

In `TaskBreakdownSection`: remove the store, `period` and the computed `bars`, add `let bars: [TaskBar]`, and change the chart to `Chart(bars) { bar in … }`.

- [ ] **Step 4: Run the tests and confirm they pass**

Run the test command. Expected: 20 pass.

- [ ] **Step 5: Confirm the re-render reduction**

Temporarily add `let _ = Self._printChanges()` as the first line of `HeatmapSection.body` and `ProgressSection.body`. Run with `-demoData` and sweep the pointer across both charts. Expected: a log line only when the pointer enters a new cell or day, instead of one per pointer event. Then remove both lines. The screen should look identical to before.

- [ ] **Step 6: Commit**

```bash
git add flowmodoro/flowmodoro/Features/UI/StatisticsView.swift flowmodoro/flowmodoroTests/flowmodoroTests.swift
git commit -m "perf(stats): derive once in parent, O(1) day-snapped hover lookups"
```

### Task 2.2: Remove the last two tiles + "poppy" charts in the current theme

**Description:** The charts stay in the single accent hue, lifted into a gradient. Bars get rounded tops and rise from the baseline when the window opens. Hover readouts become Liquid Glass capsules, matching the popover's controls. The cumulative line gets a soft gradient fill and a labelled end point. Label text always uses primary/secondary colors, never the series color.

**Files:**
- Modify: `flowmodoro/flowmodoro/Features/UI/StatisticsView.swift`

- [ ] **Step 1: Shared fill and callout** (add to the file)

```swift
extension LinearGradient {
    /// The accent, lifted toward white at the top: more "pop" than a flat
    /// fill while staying the app's single accent hue in light and dark.
    static var barFill: LinearGradient {
        LinearGradient(colors: [Color.accentColor.mix(with: .white, by: 0.3), .accentColor], startPoint: .top, endPoint: .bottom)
    }
}

/// Readout for a selected mark: a Liquid Glass capsule floating over the
/// chart, like the popover's controls. Text stays in primary and secondary
/// colors, never the series color.
private struct ChartCallout: View {
    let title: String
    let detail: String

    var body: some View {
        VStack(spacing: 1) {
            Text(title).font(.callout.weight(.semibold).monospacedDigit())
            Text(detail).font(.caption2).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .glassEffect(.regular, in: .capsule)
    }
}
```

- [ ] **Step 2: `ProgressSection` — two tiles, rising bars, glass callout**

Add `@Environment(\.accessibilityReduceMotion) private var reduceMotion` and `@State private var hasAppeared = false`. Delete the `Longest` and `Average` `StatTile`s. Replace the `Chart { … }` block and the `if let match { Text(…) }` caption below it with:

```swift
Chart {
    ForEach(daily) { day in
        BarMark(x: .value("Day", day.date, unit: .day),
                y: .value("Minutes", hasAppeared ? day.duration / 60 : 0))
            .foregroundStyle(LinearGradient.barFill.opacity(barOpacity(day)))
            .cornerRadius(4)
    }
    RuleMark(y: .value("Goal", goal / 60))
        .foregroundStyle(.secondary)
        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
    if let match {
        RuleMark(x: .value("Day", match.date, unit: .day))
            .foregroundStyle(Color.secondary.opacity(0.25))
            .annotation(position: .top, spacing: 4, overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                ChartCallout(title: formatDuration(match.duration),
                             detail: match.date.formatted(.dateTime.month(.abbreviated).day()))
            }
    }
}
.frame(height: 160)
.chartXSelection(value: Binding(
    get: { selectedDay },
    set: { date in
        let day = date.map { Calendar.current.startOfDay(for: $0) }
        if day != selectedDay { selectedDay = day }
    }
))
.onAppear {
    // Bars rise from the baseline once per window open.
    withAnimation(reduceMotion ? nil : .spring(duration: 0.5, bounce: 0.2)) { hasAppeared = true }
}
```

```swift
private func barOpacity(_ day: DailyFocus) -> Double {
    let base = day.duration >= goal ? 1 : 0.45
    guard let match else { return base }
    return match.date == day.date ? 1 : base * 0.5
}
```

- [ ] **Step 3: `MilestoneSection` — gradient area, rounded line, labelled end point**

```swift
Chart {
    ForEach(series) { day in
        AreaMark(x: .value("Date", day.date), y: .value("Hours", day.duration / 3600))
            .foregroundStyle(LinearGradient(colors: [Color.accentColor.opacity(0.4), Color.accentColor.opacity(0.02)],
                                            startPoint: .top, endPoint: .bottom))
            .interpolationMethod(.monotone)
        LineMark(x: .value("Date", day.date), y: .value("Hours", day.duration / 3600))
            .foregroundStyle(Color.accentColor)
            .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
            // .monotone, not .catmullRom: a running total never decreases, and
            // catmull-rom overshoot would draw dips that never happened.
            .interpolationMethod(.monotone)
    }
    if let last = series.last {
        PointMark(x: .value("Date", last.date), y: .value("Hours", last.duration / 3600))
            .symbolSize(80)
            .foregroundStyle(Color.accentColor)
            .annotation(position: .top, alignment: .trailing) {
                ChartCallout(title: formatDuration(last.duration), detail: "so far")
            }
    }
    if let milestone {
        RuleMark(y: .value("Milestone", milestone / 3600))
            .foregroundStyle(.secondary)
            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
    }
}
.frame(height: 160)
```

- [ ] **Step 4: `TaskBreakdownSection` — rounded bars with direct labels**

```swift
Chart(bars) { bar in
    BarMark(x: .value("Minutes", bar.duration / 60), y: .value("Task", bar.name))
        .foregroundStyle(Color.accentColor.gradient)
        .cornerRadius(6)
        .annotation(position: .trailing) {
            Text(formatDuration(bar.duration)).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
        }
}
.chartXAxis(.hidden) // every bar is labelled directly
.frame(height: CGFloat(bars.count) * 32 + 12)
```

Heatmap: change `.cornerRadius(2)` to `.cornerRadius(3)`. No other change.

- [ ] **Step 5: Verify**

Run the test command. Expected: 20 pass. Then run the app with `-demoData` and check, in both light and dark mode:
- Bars rise on open and don't rise with Reduce Motion on.
- Switching the period animates smoothly.
- The callout never clips at the chart's left or right edge.
- Empty states still show their text.
- Hero row, heatmap, milestones and by-task sections still show all of their data.

Take before/after screenshots in light and dark mode for the PR.

- [ ] **Step 6: Commit**

```bash
git add flowmodoro/flowmodoro/Features/UI/StatisticsView.swift
git commit -m "feat(stats): drop Longest/Average tiles; accent-gradient charts with glass callouts"
```

---

## Section 3 — Performance, smoothness, snappy buttons

### Task 3.1: Isolate the 1 Hz ring; fix the hourly backwards sweep

**Files:**
- Modify: `flowmodoro/flowmodoro/Features/UI/FlowmodoraTimerView.swift`

- [ ] **Step 1: Before measurement.** Temporarily put `let _ = Self._printChanges()` at the top of `FlowmodoraTimerView.body` and run a Flowmodoro session with the popover open. Expected: one log line per second (F8).

- [ ] **Step 2: Extract `TimerRing`.** Move `timerCircle`, `isPaused`, `progress(at:)`, `displayValue(at:)` and `subtitle` into a new private struct. `FlowmodoraTimerView.body` then uses `TimerRing()` in place of `timerCircle`:

```swift
/// The only part of the timer UI that reads the 1 Hz clock. With it split out,
/// a tick re-renders just this view; FlowmodoraTimerView.body and its glass
/// controls no longer depend on `timer.now`.
private struct TimerRing: View {
    @Environment(AppStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let now = store.timer.now
        let progress = progress(at: now)
        ZStack {
            Circle().stroke(Color.secondary.opacity(0.2), lineWidth: 12)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 12, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .opacity(isPaused ? 0.5 : 1)
                .animation(reduceMotion ? nil : .linear(duration: 1), value: progress)
                // Each Flowmodoro hour is a new view, so the ring restarts from
                // empty instead of animating backwards around the whole lap.
                .id(lap(at: now))
            VStack(spacing: 8) {
                Text(displayValue(at: now))
                    .font(.system(size: 44, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(.primary)
                    .contentTransition(.numericText())
                    .animation(reduceMotion ? nil : .snappy(duration: 0.25), value: store.timer.phase)
                Text(subtitle).font(.headline).foregroundStyle(.secondary)
            }
        }
        .frame(width: 250, height: 250)
    }

    private func lap(at date: Date) -> Int {
        guard store.timer.mode == .flowmodoro else { return 0 }
        return Int(store.timer.focusDuration(at: date) / 3600)
    }

    // isPaused, progress(at:), displayValue(at:), subtitle: moved here unchanged
    // (including the Task 1.2 edits).
}
```

- [ ] **Step 3: After measurement.** With the same `_printChanges` line, `FlowmodoraTimerView` should log nothing during ticks; it logs only on phase changes. Remove the line.

- [ ] **Step 4: Check the hour wrap.** Temporarily change `3600` to `60` in `lap(at:)` and in `progress(at:)`. Run Flowmodoro for 2 minutes: at each minute boundary the ring restarts empty instead of sweeping back. Revert both changes.

- [ ] **Step 5: Run the tests (20 pass), then commit**

```bash
git add flowmodoro/flowmodoro/Features/UI/FlowmodoraTimerView.swift
git commit -m "perf(timer): isolate 1 Hz ring from glass controls; fix hourly backwards sweep"
```

### Task 3.2: Press feedback everywhere; faster morphs

**Files:**
- Modify: `flowmodoro/flowmodoro/ContentView.swift` (`TaskRow.body`, `taskSection` `+` button, `footer` button)
- Modify: `flowmodoro/flowmodoro/Features/UI/FlowmodoraTimerView.swift` (`controls` animation)

- [ ] **Step 1: `TaskRow.body`.** Split the tap gesture into two real buttons: the checkbox and the row. Each gets the existing spring press, larger hit targets and VoiceOver labels.

```swift
var body: some View {
    HStack(spacing: 8) {
        Button { store.toggleTask(task) } label: {
            Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(task.isCompleted ? Color.accentColor : Color.secondary)
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .springButtonStyle()
        .accessibilityLabel(task.isCompleted ? "Mark \(task.title) incomplete" : "Complete \(task.title)")

        Button { store.selectTask(task) } label: {
            HStack(spacing: 8) {
                Text(task.title)
                    .font(.subheadline)
                    .strikethrough(task.isCompleted)
                    .foregroundStyle(task.isCompleted ? .secondary : .primary)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Text(timeLabel)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
        }
        .springButtonStyle()
        // Same rule the old tap-gesture guard enforced.
        .disabled(task.isCompleted || (store.timer.isActive && !isSelected))
    }
    .padding(.vertical, 2) // was 5: the 22 pt checkbox target keeps the row height the same
    .padding(.horizontal, 6)
    .background(isSelected ? Color.secondary.opacity(0.12) : Color.clear, in: RoundedRectangle(cornerRadius: 6))
    .animation(.snappy(duration: 0.2), value: isSelected)
}
```

- [ ] **Step 2: The `+` and footer buttons.** Change `.buttonStyle(.plain)` to `.springButtonStyle()` on the "New task" `+` button and on the footer "Today …" button. Give the `+` image `.frame(width: 22, height: 22).contentShape(Rectangle())`.

- [ ] **Step 3: Faster morph.** In `controls`, replace `.animation(reduceMotion ? .easeInOut(duration: 0.2) : .smooth(duration: 0.35), value: store.timer.phase)` with `.animation(reduceMotion ? .easeInOut(duration: 0.2) : .snappy(duration: 0.25), value: store.timer.phase)`.

- [ ] **Step 4: Verify**

Run the test command. Expected: 20 pass. Then click and hold each of these and confirm the 0.97 press: task row, checkbox, `+`, footer, config card header. Also check:
- While a timer runs, clicking other rows does nothing, as before. If disabled rows now render dimmed, keep it: it accurately shows they can't be selected.
- Row height is unchanged.
- VoiceOver announces "Complete ‹title›, button".
- Play → Pause/Stop morph feels quicker, and still has no scale motion with Reduce Motion on.

- [ ] **Step 5: Commit**

```bash
git add flowmodoro/flowmodoro/ContentView.swift flowmodoro/flowmodoro/Features/UI/FlowmodoraTimerView.swift
git commit -m "feat(ui): press feedback on every popover control; 250ms control morph"
```

### Task 3.3: Merge bursts of saves into one sync (do after 4.2)

**Files:**
- Modify: `flowmodoro/flowmodoro/Core/AppStore.swift` (new `syncTask` property and `requestSync()`; `save()` calls it)

- [ ] **Step 1: Implement**

```swift
private var syncTask: Task<Void, Never>?

/// Merges a burst of writes (holding a stepper saves once per step) into a
/// single sync, and waits for any sync already running rather than
/// overlapping it: overlapping syncs fetched the same queued entries and
/// uploaded each one more than once.
private func requestSync() {
    syncTask?.cancel()
    syncTask = Task { [weak self, previous = syncTask] in
        await previous?.value
        try? await Task.sleep(for: .milliseconds(400))
        guard !Task.isCancelled else { return }
        await self?.attemptSync()
    }
}
```

In `save()`, replace `Task { await attemptSync() }` with `requestSync()`. Leave `scheduleOutboxRetry` unchanged.

- [ ] **Step 2: Verify**

Run the test command. Expected: 20 pass. Then, signed in (this needs Task 4.2): hold the popover's Focus stepper for about 3 s. In Supabase Dashboard → Logs → API, filter on `/rest/v1/user_settings`. Expected: 1–2 `POST` requests, down from at least one per step. Settings shows "Synced" afterwards, and the row in `user_settings.payload` has the final value.

- [ ] **Step 3: Commit**

```bash
git add flowmodoro/flowmodoro/Core/AppStore.swift
git commit -m "perf(sync): coalesce outbox drains, never overlap"
```

### Task 3.4: After-benchmarks

> **2026-09-17 note:** `flowmodoro/docs/PERFORMANCE.md`, `SYNC.md`, `TESTING.md`, `TIMER_ENGINE.md`, `DATA_MODEL.md`, and `ARCHITECTURE_DECISIONS.md` were consolidated into one `flowmodoro/docs/ARCHITECTURE.md` (see its "Performance" section for the existing Before column and table shape, and its "Decisions log" section for where a new decision entry goes). `PRINCIPLES.md` was folded into `STATUS.md`. Below, read every `flowmodoro/docs/PERFORMANCE.md` as `flowmodoro/docs/ARCHITECTURE.md`'s Performance section instead.

- [ ] **Step 1:** Repeat Task 0.1 Step 4 exactly (Debug, `-demoData`, same scenarios) and fill in the After column of `flowmodoro/docs/ARCHITECTURE.md`'s Performance table.
- [ ] **Step 2: Acceptance.**
  - S4 body updates per sweep drop by at least 10×.
  - S2 and S3 CPU are no higher than before.
  - S1 stays near zero idle wakeups.
  - If S4 still shows hitches, the next step (not done pre-emptively) is to move the heatmap's hover state into an `@Observable` holder read only by the caption, so the chart body never re-runs on hover.
- [ ] **Step 3:** Update `STATUS.md`: move this branch's "In progress" checklist into "Built and working" now that everything's done, and fold Task 3.4's own row from that checklist away.
- [ ] **Step 4: Commit**

```bash
git add flowmodoro/docs/ARCHITECTURE.md STATUS.md
git commit -m "docs(perf): before/after measurements; status update"
```

---

## Section 4 — Security

### Task 4.1: Close the public data exposure (live database — owner approval required)

**Files:**
- Create: `flowmodoro/Supabase/003_close_public_exposure.sql`
- Modify: `flowmodoro/docs/SYNC.md` (the "Unrelated finding on the same project" bullet)

- [ ] **Step 1: Write the migration**

```sql
-- daily_focus_logs is a SECURITY DEFINER view over focus_sessions that anon
-- could SELECT: it bypassed RLS and exposed every user's user_id and daily
-- focus totals to anyone holding the app's embedded anon key. Nothing in the
-- app reads it. security_invoker makes it obey the caller's RLS; the revoke
-- removes anon access outright. (Dropping the view is equally fine.)
alter view public.daily_focus_logs set (security_invoker = true);
revoke all on public.daily_focus_logs from anon;

-- public.movies: RLS is off and anon can SELECT/INSERT/DELETE. It isn't
-- Flowmodora's (it came from the pgvector/Gemini migrations) but shares this
-- project and key. Uncomment ONLY after confirming what uses it: RLS with no
-- policies blocks anon/authenticated; service-role access is unaffected.
-- alter table public.movies enable row level security;
```

- [ ] **Step 2: Apply.** After the owner approves, apply `002_rls_perf_and_index.sql` and then `003_close_public_exposure.sql`, either through the Supabase Dashboard SQL editor or the MCP `apply_migration`.

- [ ] **Step 3: Verify**

```sql
select has_table_privilege('anon', 'public.daily_focus_logs', 'select');  -- expect false

-- Cross-user isolation (the RLS test docs/SYNC.md lists as not done).
-- Needs at least two signed-up users with sessions; with none it passes vacuously.
begin;
select set_config('request.jwt.claims',
  json_build_object('sub', (select id from auth.users order by created_at limit 1), 'role', 'authenticated')::text, true);
set local role authenticated;
select count(*) as other_users_sessions from public.focus_sessions where user_id <> (select auth.uid());  -- expect 0
select count(*) as other_users_daily    from public.daily_focus_logs where user_id <> (select auth.uid()); -- expect 0
rollback;
```

Re-run `get_advisors` for security and performance. Expected: `security_definer_view`, `auth_rls_initplan` and `unindexed_foreign_keys` are gone. The `movies`, `match_movies` and `vector`-extension findings remain until the owner decides.

- [ ] **Step 4: Correct `docs/SYNC.md`.** Replace the "Unrelated finding" bullet with: "`public.daily_focus_logs` was a SECURITY DEFINER view over **this app's** `focus_sessions`, readable by `anon`. Fixed by `003_close_public_exposure.sql`. `public.movies` (not this app's) still needs its owner to enable RLS." Also mark the RLS cross-user test as done, with its date.

- [ ] **Step 5: Commit**

```bash
git add flowmodoro/Supabase/003_close_public_exposure.sql flowmodoro/docs/SYNC.md
git commit -m "fix(security): close anon read of daily_focus_logs; record cross-user RLS check"
```

### Task 4.2: Entitlements — network client, least privilege, hardened runtime

**Files:**
- Modify: `flowmodoro/flowmodoro.xcodeproj/project.pbxproj`, app target Debug (≈ line 305) and Release (≈ line 337)

- [ ] **Step 1: Change the settings.** Prefer Xcode → target Flowmodora → Signing & Capabilities over hand-editing the pbxproj. Under App Sandbox, check **Outgoing Connections (Client)** and set **User Selected File** to None (grep shows no file panels anywhere). Add the **Hardened Runtime** capability with no exceptions. The resulting pbxproj diff in both configurations:

```
-				ENABLE_USER_SELECTED_FILES = readwrite;
+				ENABLE_HARDENED_RUNTIME = YES;
+				ENABLE_OUTGOING_NETWORK_CONNECTIONS = YES;
```

- [ ] **Step 2: Verify the signed product**

```bash
xcodebuild -project flowmodoro/flowmodoro.xcodeproj -scheme flowmodoro -configuration Release -derivedDataPath flowmodoro/build build
codesign -d --entitlements - flowmodoro/build/Build/Products/Release/Flowmodora.app 2>/dev/null | grep -E "network.client|user-selected"
# expect: com.apple.security.network.client only
codesign -dv flowmodoro/build/Build/Products/Release/Flowmodora.app 2>&1 | grep flags
# expect "runtime" among the flags
```

`get-task-allow` in local builds is expected. A Developer ID archive with notarization removes it.

- [ ] **Step 3: Test by hand**
  - Settings → Sync: Send Code, then Verify.
  - Record a 1-minute session. Settings shows "Synced" and the row appears in `focus_sessions`.
  - Global hotkeys, notifications and Launch at Login still work under the hardened runtime.

- [ ] **Step 4: Commit**

```bash
git add flowmodoro/flowmodoro.xcodeproj/project.pbxproj
git commit -m "fix(security): network client entitlement (sync was sandbox-blocked), drop file access, hardened runtime"
```

### Task 4.3: Sign-in fields — clean input and AutoFill

**Files:**
- Modify: `flowmodoro/flowmodoro/ContentView.swift` (`SettingsView` Sync section)

- [ ] **Step 1: Implement.** On `TextField("Email", …)` add `.textContentType(.emailAddress)`. On `TextField("6-digit code", …)` add:

```swift
.textContentType(.oneTimeCode) // offers the code from Mail via AutoFill
.onChange(of: otpCode) { _, code in
    // ASCII digits only: pasted codes often carry spaces or dashes.
    let digits = String(code.filter { $0.isASCII && $0.isNumber }.prefix(10))
    if digits != code { otpCode = digits }
}
```

Rate limiting and code expiry are enforced server-side by Supabase Auth, so no client-side cooldown is added.

- [ ] **Step 2: Verify.** Pasting `123 456` gives `123456`. The existing generic error messages still don't reveal whether an email has an account.

- [ ] **Step 3: Commit**

```bash
git add flowmodoro/flowmodoro/ContentView.swift
git commit -m "fix(security): sanitize OTP input, enable one-time-code AutoFill"
```

---

## Coverage check against the request

| Request item | Task |
|---|---|
| Config screen: work/break intervals, cycle count | 1.2 (card and shared fields), 1.1 (`rounds`) |
| Auto-break / auto-continue implemented and tested | 1.1 (4 tests, including the sleep regression) |
| Configure before start; selection flow unchanged | 1.2 (idle-only card; picker and task list untouched) |
| Last columns removed; new graph style | 2.2 |
| All essential stats retained | 2.2 Step 5 |
| Benchmarks before and after | 0.1, 3.4 |
| Smoothness, snappy buttons, responsiveness | 2.1, 3.1, 3.2, 3.3 |
| Security | 4.1, 4.2, 4.3; input clamping in 1.1 |
| Current theme kept | Global Constraints; accent/glass/tile reuse throughout |
| Documented | this plan; `ARCHITECTURE_DECISIONS.md`, `PERFORMANCE.md`, `SYNC.md`, `STATUS.md` updates |

## Deliberately left out

- **Flowmodoro pre-start card** (break ratio, auto-break): the same component would fit, but it wasn't requested.
- **Syncing `pomodoroRounds` to Supabase:** the payload already omits the auto-start flags. Add all of them when a multi-device pull path exists.
- **Return key to start:** a default-button key equivalent would steal Return from the new-task field. ⌘⌥S already starts the timer.
- **Lazy Supabase client:** only if Task 0.1 shows a measurable launch cost.
