# Flowmodora architecture

One consolidated technical reference (merged 2026-09-17 from six previously
separate files — architecture, data model, timer engine, sync, testing, and
performance — to keep documentation to a handful of files worth actually
reading). For product-level status and principles, see `STATUS.md` at the
repo root.

```text
SwiftUI MenuBarExtra / windows
              ↓ commands
AppStore (main-actor application state)
       ↙              ↓               ↘
TimerEngine      SwiftData        system services
 timestamp math  local authority  notifications/login item
              ↓
       StatisticsEngine
       pure local derivation
```

The app uses both a standard `WindowGroup` and a `MenuBarExtra` popover as
primary surfaces. `AppStore` uses the `@Observable` macro to own durable
model access and translate user actions into domain operations. `TimerEngine`
(also `@Observable`) owns all timer transitions and never depends on a view.
`StatisticsEngine` is a pure calculator over copied session values, so
analytics remain available offline and never mutate persistence.

SwiftData models are deliberately small:

- `FocusTask` — lightweight task title and completion state.
- `FocusSessionRecord` — one logical focus session, including actual focused
  duration.
- `AppSettingsRecord` — user preferences and defaults.
- `OutboxEntry` — local synchronization intent, retained independently of UI.

Timer runtime state is a Codable `TimerSnapshot` in `UserDefaults`. This is
not a second database: it is the small durable recovery record needed to
reconstruct an in-progress timer after the process or popover disappears.
Completed sessions remain authoritative in SwiftData.

All application state is main-actor isolated. The timer does not use a
decrementing counter; displayed values are always derived from persisted
timestamps and pause-adjusted values.

The app is marked `LSUIElement` so it behaves as a menu-bar utility instead
of occupying the Dock. Secondary windows are opened from the popover for
history, statistics, and settings.

## Data model

### FocusTask
`id`, `title`, completion timestamps, update timestamp, and optional
soft-delete timestamp. There are intentionally no tags, projects, notes, due
dates, or external IDs in v1.

### FocusSessionRecord
One logical focus interval. Paused time is excluded from `focusedDuration`.
`modeRawValue` stores the stable Codable form of `FocusMode`. The session
UUID is created before local recording so a remote upload can be idempotent.

### AppSettingsRecord
Stores user preferences only; it never contains authentication secrets.
Supabase tokens belong in Keychain when the remote transport is enabled.

### OutboxEntry
An append-only local intent to upsert a task, settings record, or focus
session. It is safe to retry because remote IDs are client-generated UUIDs
and the Supabase contract uses `upsert` on those IDs.

### Migration strategy
Future schema changes should add a new SwiftData model version and
`SchemaMigrationPlan`, preserving existing UUIDs and timestamps. Do not
silently change the meaning of `focusedDuration` or the calendar attribution
rule. New `@Model`/settings properties need an inline default (not just in
`init`) so SwiftData's lightweight migration can fill them in for rows that
already exist on disk.

## Timer engine

### State transitions
```text
idle → focus → pausedFocus → focus
focus → suggestedBreak → breakTimer → idle
focus → breakTimer                 (automatic Flowmodora break)
focus → breakTimer → focus         (Pomodoro auto-start, plan permitting)
focus/pausedFocus → idle           (stop or skip)
```

Flowmodora uses `accumulatedFocus + (now - focusResumedAt)` while running.
Stopping calculates `duration / flowBreakRatio`. Pomodoro uses a target end
date for work and breaks; pausing moves the remaining interval into
`remainingWhenPaused` and resume reconstructs a new target end date. Pressing
Start freezes the current Pomodoro settings into `TimerSnapshot.pomodoroPlan`
(clamped to sane ranges) so a mid-run Settings edit can't change a cycle
already in progress; `roundsCompleted` ends a run after the configured round
count (0 = until stopped) and is cleared whenever a fresh manual Start
begins, but preserved across an auto-continued round.

`TimerEngine` owns one shared 1 Hz clock (`now`, driven by `updateTicking()`,
called from `persist()` and at `init`) that ticks only while
`phase == .focus || .breakTimer` — every ticking display (menu-bar label,
task row, timer ring) reads it instead of running its own loop or
`TimelineView`. `AppStore` doesn't poll separately. On relaunch, or after
sleep/wake, the engine decodes `TimerSnapshot` and the first `refresh()`
immediately catches up any countdown that ended while the app wasn't
visible — including ending a run cleanly (not fabricating a backdated focus
interval) if a break's end is noticed more than `autoContinueGrace` (120s)
late, since that almost certainly means the Mac was asleep. A completed
focus session is written once using its UUID; recording is idempotent if a
completion event is repeated.

`stop` records a completed local session before changing the visible state.
`skip` records any non-zero abandoned work as interrupted; it's still real
focused time and counts in Statistics identically to a completed session
(see Decisions log). Breaks are ephemeral and are not stored as focus
sessions.

## Sync (optional Supabase transport)

The app is deliberately local-first. SwiftData is authoritative for runtime
behavior, history, and statistics. `OutboxEntry` records local changes
without blocking the user — but only once sync is actually configured
(`LocalSyncEngine.status.isConfigured`, true once a user is signed in).
`AppStore.save()` does not queue entries while signed out.

**Transport:** `Core/Supabase.swift` holds the `SupabaseClient` (project URL
+ anon/publishable key — see the note on that key below) and
`LocalSyncEngine`, which owns auth state and the actual upsert calls.
`AppStore.attemptSync()` is the drain: it reads every pending `OutboxEntry`,
builds the matching row from the in-memory `tasks`/`sessions`/`settings`
already loaded, upserts it, and deletes the outbox entry only on success. A
row that fails (offline, transient error) stays queued — every subsequent
`save()` (coalesced through `AppStore.requestSync()`, which debounces a
burst of rapid writes into one sync pass and never overlaps an in-flight
one), plus a backoff retry (`AppStore.scheduleOutboxRetry`, 30s doubling to
30min while anything is pending), drains it. Upserting by the
client-generated UUID makes retries idempotent.

- Focus sessions are append-oriented and idempotent by `id`.
- Mutable tasks use last-write-wins by `updated_at` (re-upserting the full
  row each time; the server doesn't currently reject a stale write).
- The app keeps showing local data if every remote request fails — nothing
  in `attemptSync()` blocks the timer, task, or statistics code paths.

**Authentication:** email one-time-code sign-in
(`LocalSyncEngine.requestSignIn(email:)` → `Auth.signInWithOTP(email:)`, then
`verifySignIn(email:code:)` → `Auth.verifyOTP(email:token:type:.email)`),
exposed in Settings → Sync. The Supabase SDK persists the session in the
Keychain itself. **Dashboard step required for OTP codes (not magic
links):** Supabase's default "Magic Link" email template only includes
`{{ .ConfirmationURL }}` — since this app has the user type a code rather
than open a link, the project's email template must be edited to include
`{{ .Token }}` (Supabase Dashboard → Authentication → Email Templates →
Magic Link), or `requestSignIn` will succeed but the email won't contain a
typeable code.

**Not yet implemented:**
- **Conflict resolution**: `attemptSync()` always pushes local state; it
  doesn't pull remote rows or compare `updated_at` before overwriting.
  Harmless for a single-device user; a pull path is needed before
  multi-device last-write-wins is safe.
- **Soft-delete propagation**: local `deletedAt` isn't wired to a remote
  delete/tombstone yet — no delete UI exists in the app currently.
- **RLS verification**: RLS is enabled on all four tables
  (`profiles`/`tasks`/`focus_sessions`/`user_settings`). An actual
  cross-user access test (two real signed-in users, confirm A can't read/write
  B's rows) hasn't been run yet — needs two real accounts.
- **`public.daily_focus_logs`** was a `SECURITY DEFINER`-style view over
  this app's own `focus_sessions`, readable by `anon` — a live, quiet
  exposure of every user's focus data via the app's own embedded key. Fixed
  by `Supabase/003_close_public_exposure.sql` (written, not yet applied to
  the live project — pending owner go-ahead). `public.movies` (RLS
  disabled, exposed to anon) is genuinely unrelated to this app's schema —
  it came from separate migrations in the same Supabase project — and needs
  its own owner decision.

The anon/publishable key is meant to be embedded in a client app — Row
Level Security is the actual authorization boundary, not the key's secrecy.
It lives in `Core/Supabase.swift` (`SupabaseConfig.anonKey`). A service-role
key must never be shipped in the macOS bundle or committed anywhere in this
repo.

## Testing

Unit tests cover timer mathematics and statistics without a network or a
real clock dependency — the production timer accepts explicit `Date` values
on its transition methods, making sleep/wake reconstruction testable. UI
tests should exercise: launch → create/select task → start → pause →
resume → stop; Flowmodora stop → calculated break → start break; Pomodoro
work → break → next work (including a rounds-limited run ending cleanly);
history/statistics windows from the popover.

Failure-oriented manual checks should include denied notification
permission, failed login-item registration, unavailable network, process
relaunch with a running snapshot, and a countdown target that passed while
the popover was closed or the Mac was asleep.

Run: `xcodebuild test -project flowmodoro/flowmodoro.xcodeproj -scheme
flowmodoro -destination 'platform=macOS' -only-testing:flowmodoroTests`

## Performance

A Debug-only `-demoData` launch flag (`Core/DemoData.swift`) runs the app on
an in-memory store seeded with 3 years of Pomodoro sessions across 5 tasks,
for measuring Statistics-screen cost at a realistic history size without
touching the real database or ever syncing.

Method: `open -n Flowmodora.app --args -demoData`, then `top -l 61 -s 1
-stats pid,cpu,idlew -pid $PID`, averaged over 60 samples (1/s). Only one
instance of the app runs at a time — hotkeys and the status item collide
otherwise.

| Scenario | Metric | Before | After |
|---|---|---|---|
| S1 idle, closed | CPU % / idle wakeups/s | 0.1% / 0.0 | *pending Task 3.4* |
| S2 running, closed | CPU % / idle wakeups/s | not measured¹ | *pending Task 3.4* |
| S3 running, open | CPU % / idle wakeups/s | not measured¹ | *pending Task 3.4* |
| S4 stats hover sweep | body updates (Heatmap/Progress) / hitches | not measured¹ | *pending Task 3.4* |

¹ S2–S4 need a real click through the menu-bar popover (Start a timer, open
Statistics, sweep the pointer over a chart) — this is a `MenuBarExtra`
popover, not a normal window, and isn't reliably reachable through
AppleScript/System Events (a status-item click is scriptable, but the
popover it opens exposes no AX window — `windows` returns 0 right after the
click). These numbers should be gathered by hand once Task 3.4 runs.
`xcrun xctrace list templates` confirms the `SwiftUI` template is available
on this machine for that pass.

## Decisions log

Append a new entry here whenever a non-obvious technical call is made.

### MenuBarExtra & WindowGroup pluggability
- Decision: hybrid `MenuBarExtra` (`.menuBarExtraStyle(.window)`) +
  `WindowGroup` (`.windowStyle(.hiddenTitleBar)`).
- Reason: lets the UI run as a pure menu-bar item or a standalone window,
  decoupling the UI layer from app lifecycle.
- Alternative: a manual AppKit `NSStatusItem` + `NSPopover`.
- Source: Apple `MenuBarExtra`/`MenuBarExtraStyle` docs, Xcode 26 SDK.

### SwiftData as local authority
- Decision: `ModelContainer` + explicit `@Model` types for tasks, sessions,
  settings, outbox entries.
- Reason: local-first persistence and schema evolution beat a remote-first
  client database.
- Alternative: Core Data or a third-party SQLite wrapper.

### Timestamp-derived timer
- Decision: a Codable recovery snapshot of dates/pause-adjusted
  durations/countdown targets; derive display values from `Date`.
- Reason: sleep/wake, process suspension, and closed popovers must not lose
  elapsed time.
- Alternative: increment/decrement a counter from a repeating timer.

### Notifications
- Decision: `UNTimeIntervalNotificationTrigger` at actual target times; the
  local timer stays authoritative regardless of delivery.
- Reason: notification delivery can be delayed or denied without affecting
  focus data.

### Launch at Login
- Decision: query/mutate `SMAppService.mainApp` rather than a fake boolean.
- Reason: the UI should reflect actual system registration.

### Calendar attribution
- Decision: group a session by the local calendar day it started on.
- Reason: deterministic across midnight, preserves the complete duration.

### Interrupted sessions count toward statistics
- Decision: `StatisticsEngine` includes interrupted (skipped) sessions in
  every total, daily grouping, and per-task breakdown.
- Reason: `TimerEngine.skip()` persists the real elapsed `focusedDuration`,
  and History already shows it unfiltered — excluding the same rows from
  Statistics made two screens disagree about how much focus actually
  happened. The product principle (see `STATUS.md`) is that focus data
  reflects what actually happened, not what the user intended.

### Email OTP code instead of magic link
- Decision: `signInWithOTP(email:)` + `verifyOTP(email:token:type:)` with a
  typed 6-digit code, not a clickable magic link.
- Reason: a magic link needs a custom URL scheme and cold-launch/already-
  running reasoning — real surface area for a menu-bar utility. A typed
  code needs only a text field.
- Trade-off: the Supabase project's default email template sends a link,
  not a bare code — the dashboard template needs `{{ .Token }}` added
  manually (see Sync section above).

### One shared clock instead of per-view polling
- Decision: `TimerEngine` owns one `Task` (`updateTicking()`) ticking once a
  second only while `phase == .focus || .breakTimer`; every ticking display
  reads `TimerEngine.now` instead of its own loop/`TimelineView`.
- Reason: replaced three duplicate per-second UI loops plus a `TimelineView`
  that kept ticking through idle/paused states — a straight regression from
  earlier visual iteration. One wake source of truth instead of four.

### Fixed notification identifier instead of a fresh UUID per schedule
- Decision: one fixed identifier (`"flowmodo.interval"`) for every
  interval-completion notification; cancellation is a plain synchronous
  `removePendingNotificationRequests`. `persist()` cancels whenever
  `countdownEnd` becomes nil.
- Reason: a fresh UUID per schedule left pause/stop unable to cancel their
  own pending notification, and resuming scheduled a second one — both
  eventually fired.

### Right-click menu via a local NSEvent monitor
- Decision: `StatusItemContextMenu` installs
  `NSEvent.addLocalMonitorForEvents(matching: .rightMouseDown)` and pops a
  plain `NSMenu` built fresh from current state at click time.
- Reason: `MenuBarExtra` has no secondary-click API; this keeps the
  existing SwiftUI popover instead of a manually managed
  `NSStatusItem`/`NSPopover` that would also have to reproduce `openWindow`.
- Trade-off: `NSMenuItem` target/action needs an `NSObject` target, so the
  menu-building code lives in a small `NSObject` subclass with a
  closure-to-selector bridge (`CocoaAction`).

### Streak, heatmap, and milestones derived from cached daily totals
- Decision: `AppStore.reload()` computes `sessionValues`, `taskTitles`,
  `dailyTotals`, `taskTotals`, `streak` once per write and caches them;
  every stats view reads only the cached values, never re-filtering
  `sessions` itself. A day "counts" toward the streak once its total meets
  `dailyFocusGoal` (default 30 min); the current streak counts consecutive
  counting days ending today, and today's in-progress total doesn't break it.
- Reason: `StatisticsView` previously re-derived everything from full
  history on every render (~6 full passes) — deriving once in `reload()`
  keeps every stats screen O(1) to render.

### Optional sync boundary
- Decision: local persistence and the outbox are usable without Supabase;
  remote sync is a separate transport concern.
- Reason: focus must never block on authentication, connectivity, or RLS.

### Pomodoro plan frozen at Start; no auto-continue after a late break
- Decision: pressing Start copies the Pomodoro settings into
  `TimerSnapshot.pomodoroPlan` (clamped to sane ranges). Auto-continued
  rounds reuse it; `roundsCompleted` ends a run after the configured round
  count (0 = until stopped). A break end noticed more than
  `autoContinueGrace` (120s) late never auto-starts focus, and an
  auto-started focus begins when it's noticed, never backdated.
- Reason: reading Settings live let a mid-run edit change a cycle already
  running. Worse, after sleep the tick loop chained break → backdated focus
  → completion and recorded focus that never happened.

### Coalesced outbox drains
- Decision: `AppStore.requestSync()` cancels any in-flight debounce chain,
  awaits the previous chain's completion, waits 400ms, then drains once —
  so a burst of rapid saves (e.g. holding a settings stepper) triggers one
  sync pass, never overlapping calls that could each re-upload the same
  queued rows.
- Reason: every `save()` previously spawned its own independent
  `attemptSync()` task.

### Network client entitlement, dropped file access, hardened runtime
- Decision: the sandboxed app gained `com.apple.security.network.client`
  (Supabase sync was previously silently sandbox-blocked with no way to
  reach the network at all), dropped an unused
  `com.apple.security.files.user-selected.read-write` (no file
  picker/importer/exporter exists anywhere in the app), and enabled
  Hardened Runtime.
- Reason: least-privilege entitlements, and sync literally could not have
  worked before this without the network entitlement.
