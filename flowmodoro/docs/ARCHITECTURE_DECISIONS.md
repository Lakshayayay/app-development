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

## Optional sync boundary

- Decision: local persistence and the outbox are usable without Supabase; remote sync is a separate transport concern.
- Reason: focus must never block on authentication, connectivity, or RLS.
- Alternative: remote database as source of truth.
- Source consulted: Supabase Postgres/RLS contract in `Supabase/001_initial_schema.sql`; official Supabase Swift SDK should be added only when package configuration is supplied.
