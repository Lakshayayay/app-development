# Flowmodorara architecture

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

The app utilizes both a standard `WindowGroup` and a `MenuBarExtra` popover as primary surfaces. `AppStore` uses the `@Observable` macro to own durable model access and translate user actions into domain operations. `TimerEngine` (also `@Observable`) owns all timer transitions and never depends on a view. `StatisticsEngine` is a pure calculator over copied session values, so analytics remain available offline and do not mutate persistence.

SwiftData models are deliberately small:

- `FocusTask` — lightweight task title and completion state.
- `FocusSessionRecord` — one logical focus session, including actual focused duration.
- `AppSettingsRecord` — user preferences and defaults.
- `OutboxEntry` — local synchronization intent, retained independently of UI.

Timer runtime state is a Codable `TimerSnapshot` in `UserDefaults`. This is not a second database: it is the small durable recovery record needed to reconstruct an in-progress timer after the process or popover disappears. Completed sessions remain authoritative in SwiftData.

All application state is main-actor isolated. The timer does not use a decrementing counter. The UI is refreshed periodically, while displayed values are always derived from persisted timestamps and pause-adjusted values.

The app is marked `LSUIElement` so it behaves as a menu-bar utility instead of occupying the Dock. Secondary windows are opened from the popover for history, statistics, and settings.
