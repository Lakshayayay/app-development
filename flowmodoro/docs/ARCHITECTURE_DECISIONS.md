# Architecture decisions

## MenuBarExtra & WindowGroup Pluggability

- Decision: use a hybrid model with SwiftUI `MenuBarExtra` (`.menuBarExtraStyle(.window)`) and `WindowGroup` (`.windowStyle(.hiddenTitleBar)`).
- Reason: allows the main UI components to run as a pure macOS menu-bar item or a standalone desktop/iOS window, heavily decoupling the UI layer from the App lifecycle.
- Alternative: an AppKit `NSStatusItem` and custom `NSPopover`.
- Source consulted: Apple Developer Documentation, `MenuBarExtra` and `MenuBarExtraStyle`, current macOS SDK shipped with Xcode 26.

## SwiftData as local authority

- Decision: use `ModelContainer` and explicit `@Model` types for tasks, sessions, settings, and outbox entries.
- Reason: local-first persistence, schema evolution, and a native model layer are more valuable than introducing a remote-first client database.
- Alternative: Core Data or a third-party SQLite wrapper.
- Source consulted: Apple Developer Documentation, SwiftData `ModelContainer`, `ModelContext`, and `@Model`.

## Timestamp-derived timer

- Decision: keep a Codable recovery snapshot containing dates, pause-adjusted durations, and countdown targets; derive display values from `Date`.
- Reason: sleep/wake, process suspension, and closed popovers must not lose elapsed time.
- Alternative: increment/decrement a counter from a repeating timer.
- Source consulted: Foundation `Date` and Swift concurrency timing APIs; the behavior is covered by `TimerEngine` tests.

## Notifications

- Decision: schedule `UNTimeIntervalNotificationTrigger` notifications at actual target times and keep the local timer authoritative.
- Reason: notification delivery can be delayed or denied without affecting focus data.
- Alternative: sleeping the application task until completion.
- Source consulted: Apple UserNotifications documentation for `UNUserNotificationCenter`, `UNNotificationRequest`, and time-interval triggers.

## Launch at Login

- Decision: query and mutate `SMAppService.mainApp` rather than maintaining a fake boolean.
- Reason: the UI should reflect actual system registration.
- Alternative: deprecated login-item APIs or a UserDefaults flag.
- Source consulted: Apple ServiceManagement documentation for `SMAppService`.

## Calendar attribution

- Decision: group a session by the local calendar day on which it started.
- Reason: it is deterministic for sessions crossing midnight and preserves the complete duration.
- Alternative: split durations across calendar days.
- Source consulted: Foundation `Calendar.dateInterval(of:for:)` and `Calendar.startOfDay(for:)`.

## Interrupted sessions count toward statistics

- Decision: `StatisticsEngine` includes interrupted (skipped) sessions in every total, daily grouping, and per-task breakdown.
- Reason: `TimerEngine.skip()` persists the real elapsed `focusedDuration` up to the point of interruption, and History displays that duration unfiltered. Excluding the same rows from Statistics made two screens disagree about how much focus actually happened on a given day — a silent data discrepancy, not a deliberate product distinction. No metric in the UI currently distinguishes "completed" from "interrupted" session counts, so there was no signal being preserved by the exclusion.
- Alternative: keep excluding interrupted sessions from statistics only, on the theory that an abandoned session "doesn't count." Rejected because the app already treats it as real, recorded focus time everywhere else, and the product principle is that focus data reflects what actually happened, not what the user intended.
- Source consulted: product principle — focus data reflects what actually happened, not what the user intended (see `PRINCIPLES.md`); stop behavior records actual focus duration.

## Email OTP code instead of magic link

- Decision: sign-in uses `Auth.signInWithOTP(email:)` + `Auth.verifyOTP(email:token:type:)` with the user typing a 6-digit code, not `signInWithOTP(email:redirectTo:)` with a clickable magic link.
- Reason: a magic link requires registering a custom URL scheme, handling `onOpenURL`/`NSApplicationDelegate` callbacks, and reasoning about the app's cold-launch-vs-already-running behavior when the link is opened — real added surface area for a menu-bar utility app. A typed code needs only a text field already living inside the existing Settings → Sync section.
- Trade-off accepted: the Supabase project's default "Magic Link" email template sends a clickable link, not a bare code, so the dashboard template must be edited to include `{{ .Token }}` for this flow to produce something the user can type in. This is a one-time manual step documented in `docs/SYNC.md`, not something the app can configure itself (it needs the anon key only; template configuration needs the Management API or dashboard access).
- Source consulted: Supabase Swift API reference (`auth-signinwithotp`, `auth-verifyotp`) and the passwordless-email guide's note that magic links and OTP codes share the same underlying email, distinguished only by the template.

## One shared clock instead of a scheduled wake, instead of a 1-second poll loop

- Decision (supersedes the "scheduled wake" design below, which itself replaced an always-on 1s loop): `TimerEngine` owns one `Task` (`updateTicking()`, called from `persist()` and at `init`) that ticks once a second — setting `now` and calling `refresh(at:)` — only while `phase == .focus || .breakTimer`. Every ticking display (`MenuBarLabel`, `TaskRow`, the timer ring) reads `TimerEngine.now` instead of running its own `Task.sleep` loop or `TimelineView`.
- Reason: the scheduled-wake design correctly stopped polling once idle, but every *running* countdown still needed a `wakeTask` (fires once, at completion) alongside three independent per-second UI loops plus a `TimelineView` that kept ticking through idle/paused states whenever the popover was open (a straight regression introduced while iterating on the ring's visuals). Consolidating to one engine-owned clock fixes that regression and removes the duplication: one wake source of truth instead of four.
- Alternative: keep the separate `wakeTask` (fires once, at completion) and only fix the `TimelineView` regression in place. Rejected: doesn't address the three duplicate per-second UI loops, which is the bigger source of redundant wakeups while a timer is actually running.
- Source consulted: `TimerEngine` sleep/wake test coverage (`pomodoroRefreshDetectsCompletionAfterSimulatedSleep`, `tickerRunsOnlyWhileRunning`), which establishes that `refresh()` reconstructs correct state from timestamps regardless of poll cadence, and that ticking starts/stops exactly with `phase`.

## Fixed notification identifier instead of a fresh UUID per schedule

- Decision: `NotificationService` schedules every interval-completion notification under one fixed identifier (`"flowmodo.interval"`) instead of a fresh `UUID()` per call, and cancellation is a plain synchronous `removePendingNotificationRequests(withIdentifiers:)` instead of an async fetch-then-filter-then-remove. `TimerEngine.persist()` cancels whenever `countdownEnd` becomes nil — one point every transition (pause/stop/reset/completion) passes through.
- Reason: a fresh UUID per schedule meant pausing or stopping a Pomodoro left its already-scheduled notification pending (nothing had that old UUID to cancel), and resuming scheduled a *second* one — both banners eventually fired. The async cancel path could also race a fresh `add` scheduled moments later.
- Alternative: keep per-call UUIDs and track the "current" identifier in `TimerSnapshot` to cancel by. Rejected: needs a new persisted field for what a fixed, well-known identifier already gives for free — `UNUserNotificationCenter` already replaces-in-place on a repeated identifier.
- Source consulted: Apple UserNotifications documentation for `removePendingNotificationRequests(withIdentifiers:)` and `UNNotificationRequest(identifier:content:trigger:)` replace-on-reuse behavior.

## Right-click menu via a local NSEvent monitor

- Decision: `StatusItemContextMenu` installs `NSEvent.addLocalMonitorForEvents(matching: .rightMouseDown)`, checks `event.window?.level == .statusBar`, and pops a plain `NSMenu` (`NSMenu.popUpContextMenu`) built fresh from current `AppStore`/`TimerEngine` state at click time.
- Reason: `MenuBarExtra` has no secondary-click API. This keeps the existing SwiftUI `MenuBarExtra`/`.menuBarExtraStyle(.window)` popover (see "MenuBarExtra & WindowGroup Pluggability" above) instead of replacing it with a manually managed `NSStatusItem` + `NSPopover`, which would also have to reproduce `openWindow` for History/Statistics/Settings outside SwiftUI.
- Trade-off accepted: `NSMenuItem`'s target/action needs an `NSObject`-derived target, so the menu-building code lives in an `NSObject` subclass (`StatusItemContextMenu`) with a small `CocoaAction` closure-to-selector bridge, rather than plain Swift closures throughout.
- Alternative: replace `MenuBarExtra` with `NSStatusItem` (`button.sendAction(on: [.leftMouseUp, .rightMouseUp])`) via `@NSApplicationDelegateAdaptor`. Not taken — larger surface change for a small feature; revisit only if the local event monitor proves unreliable in practice.
- Source consulted: AppKit `NSEvent`, `NSMenu`, `NSWindow.Level` documentation.

## Streak, heatmap, and milestones derived from cached daily totals

- Decision: `AppStore.reload()` computes `sessionValues`, `taskTitles`, `dailyTotals`, `taskTotals`, and `streak` once per write and caches them as stored properties; every stats view (StatisticsView's hero row, heatmap, progress charts, milestone chart) reads only these cached values, never re-filtering/re-mapping `sessions` itself. A day "counts" toward the streak once its total meets `AppSettingsRecord.dailyFocusGoal` (default 30 min); the current streak counts consecutive counting days ending today, and a day still in progress that hasn't met goal yet doesn't break it — see `StatisticsEngine.streak`.
- Reason: `StatisticsView` previously re-derived `summary`/`dailyFocus`/`taskFactors` from the full session history on every render (about 6 full passes), which scales with lifetime history instead of staying flat. Deriving once in `reload()` — the same point every mutation already funnels through — keeps every stats screen O(1) to render.
- Alternative: keep deriving inline per-view but memoize with `@State`. Rejected: `reload()` already exists as the one place that must run after every mutation; adding a second, view-local invalidation path would just be two sources of truth for state that's already computed store-side.
- Source consulted: product decision on streaks/goals (`PRINCIPLES.md`, 2026-09-15); `StatisticsEngine` streak/heatmap/milestone test coverage.

## Optional sync boundary

- Decision: local persistence and the outbox are usable without Supabase; remote sync is a separate transport concern.
- Reason: focus must never block on authentication, connectivity, or RLS.
- Alternative: remote database as source of truth.
- Source consulted: Supabase Postgres/RLS contract in `Supabase/001_initial_schema.sql`; official Supabase Swift SDK should be added only when package configuration is supplied.

## Pomodoro plan frozen at Start; no auto-continue after a late break

- Decision: pressing Start copies the Pomodoro settings into `TimerSnapshot.pomodoroPlan` (clamped to the Settings stepper ranges). Auto-continued rounds reuse it, and `roundsCompleted` ends a run after `rounds` focus intervals (0 = until stopped). A break end noticed more than `TimerEngine.autoContinueGrace` (120 s) late never auto-starts focus, and an auto-started focus begins when it is noticed, never backdated.
- Reason: reading Settings live let a mid-run edit change a cycle already running. Worse, after sleep the tick loop chained break → backdated focus → completion and recorded focus that never happened (violates "focus data reflects what actually happened").
- Alternative: keep reading Settings live and only add the grace check. Rejected: a running round could still change underneath the user, and the engine stayed untestable without a full AppStore.
