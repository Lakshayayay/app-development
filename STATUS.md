# Flowmodora — project status

Plain-language snapshot of what's built, what isn't, and what's next. Update
this when something ships or the plan changes — it's meant to replace
re-reading old audit docs to figure out where things stand.

## What Flowmodora is

A native macOS menu-bar focus timer (Flowmodoro + Pomodoro), local-first,
with optional Supabase sync. See `PRINCIPLES.md` for the non-negotiables and
`flowmodoro/README.md` for build instructions.

## Built and working

- Menu-bar app (`MenuBarExtra`), no stray window at launch, subtle live
  clock label (icon-only idle, `m:ss`/`h:mm:ss` while running, dimmed while
  paused — no digits or icon stacked on top of each other).
- Right-click the menu-bar clock for a native context menu: pause/resume,
  stop or skip, complete the running task, quit — built fresh from state at
  click time, no polling (`StatusItemContextMenu`).
- Flowmodoro (count-up + ratio break) and Pomodoro (fixed intervals),
  pause/resume/stop/skip.
- Timestamp-derived timer — correct across sleep/wake, popover close, relaunch.
- Inline task list in the popover: complete/uncomplete with a checkbox,
  completed tasks collapse under a disclosure, and each row shows today's
  and lifetime focused time for that task (live while it's the running one).
- 1 Hz ring animation with a critically-damped glass morph between control
  states, honors Reduce Motion, and the break ring actually drains now
  (previously always read as full — see ARCHITECTURE_DECISIONS.md).
- SwiftData persistence for tasks, sessions, settings; local outbox that
  actually drains (no more unbounded growth) and retries on a backoff
  instead of polling every second.
- No always-on 1s poll loop: `AppStore` sleeps until the timer's next
  countdown completion and is re-armed only when that target moves.
- History and Today/Week/Month/Year/Total statistics.
- Redesigned Statistics window (`Features/UI/StatisticsView.swift`): a daily
  goal (Settings), a current/best streak, a today-vs-goal ring, a 52-week
  heatmap, period bar charts with a goal line, a cumulative-hours chart with
  hour milestones (10h/25h/50h/…), and a by-task breakdown — all derived
  facts from recorded sessions, no points/badges/levels (see PRINCIPLES.md's
  2026-09-15 decision). The popover footer is a button ("Today 1h 20m · 🔥
  5") that opens it.
- Native Liquid Glass UI (`.glassEffect`, `.buttonStyle(.glass)`) — the old
  hand-rolled `.ultraThinMaterial` approach was fully replaced.
- Real Supabase sync: SDK integrated, schema + RLS applied, email OTP auth,
  offline-safe outbox transport.
- App identity: name, icon, accent color, cleaned `Info.plist`.
- Notifications (fixed: pause/stop now actually cancel the pending
  completion banner instead of leaving it scheduled), launch-at-login,
  light/dark/system appearance.
- One shared 1 Hz clock (`TimerEngine.now`) drives every ticking display
  (menu-bar label, task row, timer ring) instead of four separate
  loops/TimelineViews — ticks only while a timer is actually running.
- Derived stats (`sessionValues`, `taskTitles`, `dailyTotals`, `taskTotals`,
  `streak`) are cached once per `AppStore.reload()` instead of recomputed on
  every render.
- Sleep/wake, settings, streak, and ticker-lifecycle test coverage in
  `flowmodoroTests` (15 tests).

## Not built yet

- **Widget.** `WidgetExtension/` exists but isn't wired into an Xcode target;
  no App Group entitlement, so it can't share live data with the app yet.
- **Sandbox/entitlements.** No `.entitlements` file at all yet — needed for
  the widget and for eventual Mac App Store distribution.
- **Accessibility pass.** No `accessibilityReduceMotion` /
  `accessibilityReduceTransparency` handling yet; no VoiceOver pass done.
- **Swift 6 strict concurrency.** Project still builds under `SWIFT_VERSION
  5.0`; migration not started.
- **UI test automation.** `flowmodoroUITests` is still Xcode boilerplate —
  the three core flows (Flowmodoro, Pomodoro, task switch) aren't automated.

## Suggested next step

Widget (App Group + real target) is the most user-visible remaining gap, but
it depends on adding an entitlements file first — do that either as its own
small step or as part of wiring the widget target.

Not done from the 2026-09-15 resource-optimization pass: a profiling
harness (`scripts/measure.sh`, a `-demoData` launch flag, Instruments
baselines) and lazy-loading the Supabase SDK for local-only use — both were
scoped as "do only if a measurement justifies it," and no measurement was
taken. Worth revisiting if idle CPU/wakeups or launch time ever become a
felt problem rather than a theoretical one.

## Where the deeper detail lives

- `flowmodoro/docs/ARCHITECTURE.md`, `TIMER_ENGINE.md`, `DATA_MODEL.md`,
  `SYNC.md`, `TESTING.md` — how each subsystem works.
- `flowmodoro/docs/ARCHITECTURE_DECISIONS.md` — why specific technical calls
  were made (append a new entry here whenever you make a non-obvious one).
- `FLOWMODORA_UIUX_BACKEND_PLAN.md` — the original audit + milestone plan
  this status is tracked against (M1–M10 done, M11–M12 open above).
