# Flowmodora

Flowmodora is a small native macOS menu-bar focus companion. It is
local-first: starting a timer, recording a session, and viewing statistics
never requires an account or a network connection.

## What works in this target

- Native `MenuBarExtra` with a compact popover and live menu-bar timer.
- Flowmodoro count-up sessions with configurable break ratio and optional
  automatic break.
- Pomodoro countdowns with configurable work, short break, long break, cycle
  count, and skip/pause/resume controls.
- SwiftData persistence for tasks, sessions, settings, and an offline outbox.
- Timestamp-derived timer state saved across popover dismissal and relaunch.
- Local history and calendar-aware Today/Week/Month/Year/Total statistics.
- UserNotifications completion scheduling, launch-at-login registration,
  light/dark/system appearance preference, and menu-bar-only app lifecycle.

## Build

Open `flowmodoro/flowmodoro.xcodeproj` in Xcode 26 or later and run the
`flowmodoro` scheme on macOS. The project currently targets macOS 26.5,
matching the generated workspace SDK.

Run tests with Xcode's `flowmodoroTests` target. The test suite is
deliberately independent of a network, Supabase account, or notification
permission.

## Product boundaries

Supabase is an optional synchronization target, never the runtime database.
The local outbox and SQL/RLS contract are documented in
[`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md)'s Sync section and
`flowmodoro/Supabase/001_initial_schema.sql`; the app remains fully useful
without those credentials. Widget extension source is in
`flowmodoro/WidgetExtension/` and is intentionally kept outside the app
target until an App Group/widget target is added in Xcode.

## Docs

- [`docs/STATUS.md`](docs/STATUS.md) — product principles, what's built,
  what isn't, and current progress. Start here to understand where the
  project stands.
- [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) — how each subsystem works
  and why specific technical calls were made, plus the performance baseline.
