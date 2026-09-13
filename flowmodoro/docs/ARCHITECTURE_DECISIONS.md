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
- Source consulted: `PRODUCT PLAN.md` §45 ("Focus data is more important than temporary UI state") and §16 (stop behavior records actual focus duration).

## Email OTP code instead of magic link

- Decision: sign-in uses `Auth.signInWithOTP(email:)` + `Auth.verifyOTP(email:token:type:)` with the user typing a 6-digit code, not `signInWithOTP(email:redirectTo:)` with a clickable magic link.
- Reason: a magic link requires registering a custom URL scheme, handling `onOpenURL`/`NSApplicationDelegate` callbacks, and reasoning about the app's cold-launch-vs-already-running behavior when the link is opened — real added surface area for a menu-bar utility app. A typed code needs only a text field already living inside the existing Settings → Sync section.
- Trade-off accepted: the Supabase project's default "Magic Link" email template sends a clickable link, not a bare code, so the dashboard template must be edited to include `{{ .Token }}` for this flow to produce something the user can type in. This is a one-time manual step documented in `docs/SYNC.md`, not something the app can configure itself (it needs the anon key only; template configuration needs the Management API or dashboard access).
- Source consulted: Supabase Swift API reference (`auth-signinwithotp`, `auth-verifyotp`) and the passwordless-email guide's note that magic links and OTP codes share the same underlying email, distinguished only by the template.

## Optional sync boundary

- Decision: local persistence and the outbox are usable without Supabase; remote sync is a separate transport concern.
- Reason: focus must never block on authentication, connectivity, or RLS.
- Alternative: remote database as source of truth.
- Source consulted: Supabase Postgres/RLS contract in `Supabase/001_initial_schema.sql`; official Supabase Swift SDK should be added only when package configuration is supplied.
