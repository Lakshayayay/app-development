# MASTER ENGINEERING PROMPT

## Build a Native macOS Menu-Bar Focus Companion

You are the senior-most macOS engineer, product architect, SwiftUI engineer, persistence engineer, and QA lead responsible for building this application end-to-end.

Do not produce a prototype, mockup, pseudo-implementation, or partially wired demo.

Build a production-quality native macOS application with real persistence, real timers, real notifications, real widgets, real global shortcuts, real analytics, real offline behavior, and real Supabase synchronization.

The product should feel extremely small, native, fast, quiet, and deliberate.

The goal is NOT to build another bloated productivity application.

The goal is:

> A tiny native Mac menu-bar companion that makes starting, maintaining, and understanding focused work almost effortless.

The product combines the strongest ideas from Be Focused and Flowmo while intentionally excluding unnecessary complexity.

---

# 1. PRODUCT DIRECTION

The application lives primarily in the macOS menu bar.

The menu bar should always communicate:

1. What task is being focused on.
2. What the timer is doing.
3. How much time has elapsed/remaining.
4. What the next action is.

The application supports two fundamentally different focus philosophies:

### Flowmodoro

The user starts focusing and works for as long as naturally required.

The application counts UP.

When the user ends the focus session:

`breakDuration = focusDuration / breakRatio`

Default:

`5:1`

Therefore:

* 25 min focus → 5 min break
* 50 min focus → 10 min break
* 120 min focus → 24 min break

The ratio must be configurable.

The application then offers/starts the break timer depending on the user's setting.

### Pomodoro

The user deliberately chooses structured intervals.

Default:

* Work: 25 minutes
* Short break: 5 minutes
* Long break: 15 minutes
* Long break after: 4 work intervals

All values configurable.

The user must be able to use either method without the application trying to force one methodology.

---

# 2. CORE PRODUCT PRINCIPLE

Follow these principles aggressively:

### Local first

The application must function completely without:

* internet
* Supabase
* authentication
* an account
* a server

Starting a timer must never depend on the network.

Recording a session must never depend on the network.

Analytics must never depend on the network.

The network is only for optional synchronization.

### Native first

Prefer Apple's native frameworks.

Do not introduce a third-party dependency when Apple already provides an appropriate stable framework.

### Simple first

Do not add:

* social features
* teams
* accounts as a requirement
* subscriptions
* gamification
* achievements
* streak gimmicks
* unnecessary dashboards
* unnecessary onboarding
* complicated project hierarchies
* artificial productivity scores

### One source of truth

The local persistence layer is the authoritative application state.

Supabase is a synchronization target, not the primary runtime database.

### No fake timer

Never implement the timer by simply incrementing/decrementing an integer every second.

The timer must derive its displayed value from timestamps/state so that it remains correct across:

* application suspension
* system sleep
* wake
* menu-bar popover closing
* temporary CPU pauses
* screen locking
* notification interactions
* app relaunch

---

# 3. PLATFORM / TECHNOLOGY

Build a native macOS application using:

* Swift
* SwiftUI
* AppKit only where macOS-specific behavior genuinely requires it
* SwiftData
* UserNotifications
* WidgetKit
* ServiceManagement / SMAppService
* Keychain Services
* Supabase Swift SDK

Target modern macOS and choose a sensible minimum OS version rather than supporting unnecessarily old versions.

Before implementing any API, verify its current Apple documentation and SDK availability.

Do not invent APIs.

Do not rely on deprecated APIs when a supported replacement exists.

Use Swift's modern concurrency model and strict concurrency checking.

Prefer:

* `async/await`
* `@MainActor`
* actors where isolation is useful
* `Sendable`
* structured concurrency

Avoid:

* callback-heavy architecture
* NotificationCenter-driven hidden state
* global mutable singletons as state containers
* thread-unsafe shared mutable data

---

# 4. RESEARCH REQUIREMENT

Before implementation, inspect and verify the current Apple documentation for:

* MenuBarExtra
* SwiftUI menu-bar applications
* AppKit NSStatusItem where required
* SwiftData
* ModelContainer
* ModelContext
* Swift concurrency
* UserNotifications
* WidgetKit
* ServiceManagement / SMAppService
* Keychain
* relevant global keyboard-event APIs

Also inspect the current Supabase Swift SDK documentation for:

* authentication
* Postgres/Data API
* Row Level Security
* Realtime where useful
* current Swift package APIs

Do not assume an API exists because it existed in an older macOS version.

Record architectural decisions and important API choices in:

`docs/ARCHITECTURE_DECISIONS.md`

Each decision should state:

* decision
* reason
* alternative considered
* source/documentation consulted

---

# 5. APPLICATION ARCHITECTURE

Use a feature-oriented architecture.

Recommended structure:

```text
FocusCompanion/
│
├── App/
│   ├── FocusCompanionApp.swift
│   ├── AppDelegate.swift
│   ├── AppEnvironment.swift
│   └── AppRouter.swift
│
├── Core/
│   ├── Timer/
│   ├── Persistence/
│   ├── Sync/
│   ├── Notifications/
│   ├── Hotkeys/
│   ├── LoginItem/
│   ├── Keychain/
│   ├── Analytics/
│   └── Utilities/
│
├── Features/
│   ├── MenuBar/
│   ├── Focus/
│   ├── Pomodoro/
│   ├── Flowmodoro/
│   ├── Tasks/
│   ├── History/
│   ├── Statistics/
│   └── Settings/
│
├── Widgets/
│
├── Models/
│
├── Services/
│
└── Tests/
```

Do not over-engineer this into a massive enterprise architecture.

The important separation is:

```text
UI
↓
Application state / commands
↓
Domain logic
↓
Persistence / system services / sync
```

The timer engine must not know about SwiftUI views.

The SwiftUI views must not contain timer mathematics.

The analytics engine must not perform network requests.

The Supabase layer must not directly manipulate SwiftUI state.

---

# 6. DOMAIN MODEL

Define explicit domain models.

At minimum:

## Task

```swift
Task
- id: UUID
- title: String
- isCompleted: Bool
- createdAt: Date
- completedAt: Date?
- updatedAt: Date
- deletedAt: Date?
```

Do not add:

* tags
* due dates
* notes
* project hierarchies

unless there is an extremely strong architectural reason.

Keep the first version intentionally small.

---

## FocusSession

```swift
FocusSession
- id: UUID
- taskID: UUID?
- mode: FocusMode
- startedAt: Date
- endedAt: Date?
- focusedDuration: TimeInterval
- plannedDuration: TimeInterval?
- breakDuration: TimeInterval?
- completed: Bool
- interrupted: Bool
- createdAt: Date
- updatedAt: Date
- deletedAt: Date?
```

`FocusMode`:

```swift
enum FocusMode {
    case flowmodoro
    case pomodoro
}
```

The session record represents actual focus work.

Do not count paused time as focused time.

---

## PomodoroConfiguration

```text
workDuration
shortBreakDuration
longBreakDuration
cyclesBeforeLongBreak
autoStartBreak
autoStartFocus
showPauseButton
```

---

## FlowmodoroConfiguration

```text
breakRatio
autoStartBreak
```

Default:

```text
breakRatio = 5
```

Meaning:

```text
break = focusDuration / 5
```

Store the ratio, not merely the resulting break duration.

---

## AppSettings

Store user preferences such as:

```text
selectedMode
selectedTaskID
launchAtLogin
notificationsEnabled
soundEnabled
appearance
globalHotkey
flowmodoroConfiguration
pomodoroConfiguration
showPauseButton
autoStartBreak
```

Do not store secrets here.

---

# 7. TIMER ENGINE

This is one of the most important pieces of the application.

Create a dedicated timer domain engine.

Example conceptual state:

```text
idle
focusRunning
focusPaused
breakRunning
breakPaused
completed
```

Do not allow arbitrary views to mutate timer state.

Expose commands such as:

```text
startFocus()
pause()
resume()
stop()
skip()
startBreak()
completeBreak()
reset()
```

All transitions must go through the timer engine.

---

# 8. TIMER ACCURACY

Never implement:

```text
remaining -= 1
```

as the canonical source of time.

Instead persist/reference actual timestamps.

For countdown:

```text
remaining =
targetEndDate - currentTime
```

For count-up:

```text
elapsed =
currentTime - effectiveStartTime
```

with pause intervals accounted for.

The displayed timer may refresh periodically, but the display refresh mechanism must NOT define the actual elapsed time.

The timer must remain correct if:

* the Mac sleeps for 30 minutes
* the application disappears behind other windows
* the popover closes
* the UI isn't refreshed for several seconds

When the application reappears, reconstruct the correct state from persisted timer/session information.

---

# 9. TIMER PERSISTENCE

A timer must survive:

* popover closing
* app relaunch
* accidental process termination where reasonably recoverable
* system sleep/wake

At launch, inspect persisted timer state and determine whether:

1. a session is still active
2. the session completed while the application was not visible
3. a break is currently active
4. the session needs recovery
5. the session must be closed as interrupted

Do not silently fabricate focus time.

---

# 10. MENU-BAR EXPERIENCE

The menu bar is the primary interface.

Use native macOS menu-bar architecture.

Preferred direction:

```text
SwiftUI MenuBarExtra
+
window-style popover
```

Only fall back to an AppKit `NSStatusItem` implementation where the required behavior cannot be implemented reliably using `MenuBarExtra`.

Do not create two independent menu-bar status items.

The menu bar label should dynamically communicate timer state.

Examples:

```text
25:00
```

```text
14:32
Deep Work
```

```text
◉ 42:18
```

Do not make the menu-bar item visually noisy.

The timer is the primary information.

The task is secondary.

---

# 11. MENU-BAR POPOVER

The popover should be compact.

Primary hierarchy:

```text
TASK
Deep Work
--------------------------------
MODE
Flowmodoro

42:18
Focused

[ Pause ] [ Stop ]

--------------------------------
Today: 2h 14m
```

When idle:

```text
Ready to focus

Task
[ Select task ]

Mode
[ Flowmodoro ▾ ]

[ Start ]
```

Do not immediately open a huge application window.

The menu-bar popover should feel closer to a high-quality native control panel than a traditional productivity dashboard.

---

# 12. RIGHT-CLICK / QUICK CONTROL

Provide fast controls from the menu-bar interaction where the chosen implementation supports them cleanly:

* Start
* Pause
* Resume
* Stop
* Skip
* Change task
* Change mode
* Open Statistics
* Open Settings
* Quit

Never require navigating through multiple screens to pause a session.

---

# 13. FLOWMODORO UX

The Flowmodoro experience must be frictionless.

Flow:

```text
Select task
↓
Start
↓
Timer counts UP
↓
User works naturally
↓
User presses Stop
↓
Show calculated break
↓
Start break
↓
Break completes
↓
Ready for next focus
```

Example:

```text
Focused for
52:18

Suggested break
10:28

[ Start Break ]
```

Allow the user to override the break when necessary.

Do not force them into a break if the setting says automatic break is disabled.

---

# 14. POMODORO UX

Example:

```text
25:00
Focus
```

then:

```text
05:00
Short Break
```

then:

```text
25:00
Focus
```

After configured cycles:

```text
15:00
Long Break
```

Clearly distinguish:

* focus
* short break
* long break

Support:

* start
* pause
* resume
* skip
* stop
* auto-start next interval

The application must preserve the current task across Pomodoro intervals unless the user intentionally changes it.

---

# 15. PAUSE BEHAVIOR

Pause must mean:

> Stop accumulating focused time while preserving the current session.

Do not create multiple fake focus sessions merely because the user pauses/resumes.

One logical focus session should remain one logical session unless the user explicitly ends it.

The persisted `focusedDuration` should exclude paused time.

---

# 16. STOP BEHAVIOR

Stopping a focus session should:

1. calculate final actual focus duration
2. persist the FocusSession
3. update task analytics
4. update local statistics immediately
5. enqueue synchronization
6. calculate Flowmodoro break if relevant
7. schedule/start break depending on settings
8. update menu-bar UI
9. issue notification when appropriate

---

# 17. TASKS

Keep task management intentionally lightweight.

User can:

```text
Create task
Select task
Start focus
Complete task
```

Only one task is actively focused at any moment.

Task selection should be extremely fast.

Ideal flow:

```text
+ New task
```

Then:

```text
Research paper
```

appears immediately in the list.

Completed tasks may move into a completed section.

Do not build a full project-management application.

---

# 18. HISTORY

Every completed focus session must be stored.

History should support:

* date selection
* task
* mode
* duration
* start time
* end time

Example:

```text
Today

09:12   Deep Work         52m
11:04   Research          38m
14:20   Coding             1h 12m
```

The history screen must remain readable rather than becoming a huge data table.

---

# 19. STATISTICS

All statistics must be calculated locally from persisted focus sessions.

No paid analytics API.

No server-side analytics dependency.

Required periods:

```text
Today
Week
Month
Year
Total
```

Required metrics:

```text
Total focus time
Longest session
Average session
Number of sessions
Focus by task
```

Optional useful visualization:

```text
daily focus distribution
```

The statistics layer should expose reusable calculations such as:

```swift
totalFocusTime(...)
longestSession(...)
averageSession(...)
sessionCount(...)
focusByTask(...)
dailyFocus(...)
weeklyFocus(...)
monthlyFocus(...)
yearlyFocus(...)
```

Do not store derived statistics permanently unless there is a demonstrated performance requirement.

Calculate them from session data so the values cannot become inconsistent.

---

# 20. DATE / CALENDAR LOGIC

Be extremely careful with dates.

Use:

* `Calendar`
* `Date`
* user's current time zone

Statistics must correctly handle:

* local day boundaries
* daylight-saving transitions
* month boundaries
* year boundaries

Do not assume:

```text
1 day = 86,400 seconds
```

for calendar grouping.

Sessions crossing midnight must be handled correctly.

If a session spans multiple calendar periods, decide explicitly whether analytics attribute it to the start date, end date, or split it proportionally.

For this product:

### Use start-date attribution for v1.

Store the complete session duration but associate the session with the calendar day on which it started.

Document this decision.

---

# 21. STATISTICS UI

Do not create a giant dashboard.

Use:

```text
Today
2h 14m

Sessions
4

Longest
1h 12m

Average
33m
```

followed by a clean daily/weekly visualization.

Then:

```text
Focus by task
```

The statistics page should answer:

> How much did I actually focus?

rather than:

> How many meaningless productivity metrics can I display?

---

# 22. SWIFTDATA

Use SwiftData for local persistence.

Create explicit models and relationships.

Suggested model layer:

```text
Task
FocusSession
AppSettings
SyncMetadata / OutboxEntry
```

Do not use SwiftData as an accidental dumping ground for transient timer state.

Separate:

```text
persistent domain data
```

from:

```text
ephemeral runtime state
```

Timer runtime state belongs in the timer engine.

Persistence should exist to reconstruct the application's meaningful state.

Plan for schema migrations from v1 onward.

Do not assume the first schema will never change.

---

# 23. CONCURRENCY

Do not access SwiftData arbitrarily from background threads.

Choose a clear actor/concurrency strategy.

Keep UI-bound model access on the main actor where appropriate.

For heavy analytics calculations, consider fetching the necessary value objects and processing them outside UI rendering.

Do not introduce race conditions between:

* timer completion
* session persistence
* sync
* statistics refresh
* notification scheduling

A timer completion event must be idempotent.

---

# 24. SUPABASE ARCHITECTURE

Supabase is optional.

The application must work without authentication.

When the user signs in, synchronize local data.

Use the official Supabase Swift SDK.

Use Postgres.

Enable RLS on every user-exposed table.

No service-role key is ever embedded in the application.

Never ship a Supabase secret/service-role credential inside the Mac application.

The client may use the appropriate public/publishable key protected by Supabase RLS.

---

# 25. SUPABASE DATA MODEL

Create a schema similar to:

```sql
profiles
tasks
focus_sessions
user_settings
```

Every user-owned row must contain:

```text
id
user_id
created_at
updated_at
deleted_at
```

Use UUIDs generated client-side.

This makes offline creation possible.

---

# 26. SESSION SYNCHRONIZATION

Focus sessions should be treated as largely append-oriented records.

A session created locally should receive its UUID immediately.

Example:

```text
Local session created
↓
Stored in SwiftData
↓
Outbox entry created
↓
UI immediately updated
↓
Sync engine later uploads to Supabase
```

Never block the user on synchronization.

---

# 27. OFFLINE SYNC

Implement a simple synchronization engine.

Conceptually:

```text
Local Database
      ↓
Sync Outbox
      ↓
Supabase
      ↓
Remote Changes
      ↓
Local Database
```

The user should never see:

```text
Saving...
```

for a simple timer session.

The app should simply work.

---

# 28. CONFLICT RESOLUTION

Use explicit conflict rules.

For mutable entities such as tasks:

```text
updatedAt
```

is the basis for last-write-wins conflict resolution.

For focus sessions:

* session IDs are unique
* duplicate uploads must be idempotent
* completed sessions should not be duplicated
* deleted records use soft deletion/tombstones so deletion can synchronize

Do not implement complicated CRDT infrastructure for v1.

Use deterministic simple synchronization.

Document the exact conflict rules.

---

# 29. AUTHENTICATION

Authentication must be optional.

The user can use the application entirely locally without an account.

For v1 synchronization, prefer a simple native-friendly email authentication flow supported by Supabase.

Do not make experimental authentication technologies a dependency for the first release.

Persist authentication/session secrets securely using Keychain mechanisms.

Never store authentication tokens in UserDefaults or SwiftData.

---

# 30. NOTIFICATIONS

Use Apple's UserNotifications framework.

Request notification authorization at the appropriate moment, not immediately on first launch without context.

Notifications should be useful and limited.

Examples:

```text
Focus complete
52 minutes focused on Research Paper.
```

```text
Break complete
Ready to focus again?
```

For Pomodoro:

```text
Focus interval complete
Start your break.
```

Do not spam notifications.

---

# 31. NOTIFICATION RELIABILITY

Notifications must be scheduled based on actual target dates.

Do not rely solely on:

```text
sleep(for: 1500)
```

because the application may be suspended.

Timer completion must remain correct even if the app is not active.

---

# 32. LAUNCH AT LOGIN

Use Apple's modern Service Management APIs.

Provide:

```text
Launch at Login
[ ON / OFF ]
```

The setting must reflect the actual system registration state.

Do not maintain a fake application-only boolean.

---

# 33. GLOBAL HOTKEYS

Implement real system-wide global shortcuts.

Required actions:

```text
Start / Resume
Pause
Stop
```

Optional:

```text
Skip
```

The shortcut manager must be its own service.

Example conceptual API:

```swift
protocol GlobalHotkeyService {
    func register(...)
    func unregister(...)
}
```

Do not scatter Carbon/AppKit event handling throughout the application.

Important:

Do NOT use `NSEvent.addGlobalMonitorForEvents` as though it registers a global shortcut.

Apple documents it as a monitoring mechanism.

Use an appropriate system-wide hotkey registration implementation and isolate all platform-specific details behind the service.

The shortcut should continue functioning while another application is focused.

Handle registration failure gracefully.

---

# 34. ACCESSIBILITY / PERMISSIONS

Do not request Accessibility permission unless the chosen hotkey implementation genuinely requires it.

Do not request unrelated system permissions.

Explain permissions only when needed.

The application should behave gracefully when a permission is unavailable.

---

# 35. WIDGETS

Use WidgetKit.

Provide a small native Mac widget.

The widget should prioritize:

```text
current focus state
timer
current task
today's focus
```

Do not attempt to reproduce the entire application in the widget.

The widget should remain glanceable.

Possible widget:

```text
Deep Work
42:18

Today
2h 14m
```

The widget must tolerate:

* light mode
* dark mode
* different widget sizes
* system rendering constraints

Prefer App Groups/shared lightweight state only where appropriate and necessary.

Do not create a second persistence system.

---

# 36. DARK / LIGHT MODE

Respect the user's system appearance by default.

Allow a preference:

```text
System
Light
Dark
```

Do not hard-code colors everywhere.

Use semantic SwiftUI colors.

The interface must look native in both appearances.

---

# 37. DESIGN SYSTEM

Visual direction:

* minimal
* quiet
* compact
* highly legible
* native macOS
* low visual noise
* subtle hierarchy
* restrained animation

Avoid:

* gradients everywhere
* huge hero cards
* excessive rounded containers
* excessive shadows
* gamification
* colorful charts
* giant numbers everywhere
* unnecessary decorative illustrations

The timer should visually dominate.

The task should be immediately understandable.

Buttons should be obvious.

---

# 38. UX PRIORITY

The interaction hierarchy is:

```text
1. Start focusing
2. See timer
3. Control timer
4. Change task
5. Understand focus history
6. Configure behavior
```

Not:

```text
1. Configure everything
2. Navigate dashboard
3. Create project
4. Create category
5. Configure productivity score
6. Finally start timer
```

A first-time user should be able to start their first session within seconds.

---

# 39. SETTINGS

Settings should be divided into a small number of sections:

### General

* Launch at Login
* Appearance
* Notifications
* Sounds

### Focus

* Default mode
* Pomodoro durations
* Flowmodoro ratio
* Auto-start break
* Auto-start next session
* Show pause button

### Shortcuts

* Global shortcut configuration

### Sync

* Sign in
* Sync status
* Sign out

Do not create dozens of preferences.

---

# 40. APP LIFECYCLE

The app is fundamentally a menu-bar application.

It should not unnecessarily occupy the Dock.

Handle:

* launch
* quit
* relaunch
* sleep
* wake
* login item launch
* popover dismissal
* system appearance changes
* screen lock/unlock

correctly.

---

# 41. STATE RESTORATION

At launch reconstruct:

```text
current timer state
current task
current mode
current session
remaining/elapsed time
break status
```

from durable information where appropriate.

Do not persist every UI property.

Persist only meaningful application state.

---

# 42. ERROR HANDLING

Never silently swallow errors.

All service failures should be converted into meaningful domain/application errors.

Examples:

```text
Unable to save session locally.
```

```text
Sync temporarily unavailable.
Your focus data is safe on this Mac.
```

```text
Global shortcut could not be registered.
```

The local timer/session must continue working even if Supabase fails.

---

# 43. ANALYTICS MUST NOT DEPEND ON SUPABASE

This is a hard requirement.

These must work with Wi-Fi disabled:

```text
Today
Week
Month
Year
Total
Longest
Average
Focus by task
History
```

Test this explicitly.

---

# 44. TESTING

Create real tests.

Minimum test categories:

### Timer

Test:

* start
* pause
* resume
* stop
* skip
* focus duration
* countdown
* sleep/wake reconstruction
* multiple pauses
* session completion
* break calculation

### Flowmodoro

Test:

```text
25m / 5 = 5m
50m / 5 = 10m
120m / 5 = 24m
```

and configurable ratios:

```text
50m / 4 = 12m30s
50m / 5 = 10m
50m / 6 = 8m20s
```

### Pomodoro

Test:

* work interval
* short break
* long break
* cycle count
* automatic transitions
* manual skip

### Analytics

Test:

* today
* week
* month
* year
* time-zone boundaries
* midnight crossover
* empty data
* multiple tasks

### Persistence

Test:

* app relaunch
* migration
* deletion
* corrupted/unavailable store handling

### Sync

Test:

* no internet
* reconnect
* duplicate upload
* conflict
* deleted task/session
* authentication failure

### UI

Test the critical flows:

```text
Launch → select task → Start → Pause → Resume → Stop
```

and:

```text
Launch → Flowmodoro → Focus → Stop → Break
```

and:

```text
Launch → Pomodoro → Work → Break → Work
```

---

# 45. FAILURE-ORIENTED TESTING

Do not only test the happy path.

Simulate:

* Mac sleeping during focus
* internet disappearing
* Supabase unavailable
* notification permission denied
* login-at-startup registration failing
* shortcut registration failing
* app being killed during an active session
* app reopening after a completed interval
* system clock/time-zone changes
* SwiftData write failure
* duplicate sync operation

The app must fail safely.

Focus data is more important than temporary UI state.

---

# 46. SECURITY

Never put:

* Supabase service-role keys
* private API secrets
* authentication secrets

inside source code.

Use environment/configuration handling for development.

Use Keychain for user secrets at runtime.

Use Supabase RLS for remote authorization.

Every remote row must be scoped to the authenticated user.

Test RLS.

Do not rely on client-side filtering as a security boundary.

---

# 47. PRIVACY

The application should be local-first and privacy-conscious.

Do not collect:

* keystrokes
* screen recordings
* application activity
* browser history
* unnecessary telemetry

Do not implement surveillance-like productivity tracking.

A focus timer should know:

```text
what task
when focus started
when focus ended
how long focus lasted
```

Nothing more is required for the core product.

---

# 48. DO NOT IMPLEMENT IN V1

Explicitly do NOT add:

* AI assistant
* chatbot
* team collaboration
* social profiles
* leaderboards
* streak gamification
* achievements
* project management
* calendar integration
* Todoist integration
* TickTick integration
* Microsoft To Do integration
* Google Tasks integration
* Focus Matrix integration
* browser integrations
* app/web blocking
* complex tags
* detailed notes
* due dates
* subscriptions
* advertising
* server-dependent analytics

Be Focused contains many of these ideas, but the purpose of this product is to be smaller.

Architect cleanly enough that some could be added later, but do not implement them now.

---

# 49. OPTIONAL FUTURE EXTENSIONS

Leave clean seams for:

```text
App blocking
External task integrations
Advanced reporting
Shortcuts integration
More widget types
Cloud sync improvements
iOS companion
watchOS companion
```

Do not let future extensibility damage the simplicity of v1.

---

# 50. PRODUCT INFORMATION ARCHITECTURE

The application should effectively have only:

```text
Menu Bar
│
├── Current Focus
├── Tasks
├── History
├── Statistics
└── Settings
```

There should not be ten layers of navigation.

---

# 51. IDEAL USER JOURNEY

### First launch

```text
App appears in menu bar
↓
User clicks it
↓
Creates/selects task
↓
Chooses Flowmodoro or Pomodoro
↓
Presses Start
↓
Timer immediately begins
```

No mandatory account creation.

No mandatory tutorial.

No mandatory sync.

No complex setup wizard.

---

# 52. CORE MVP DEFINITION

The build is NOT considered complete until all of these work:

### Menu bar

* native menu-bar presence
* live timer
* current task
* start
* pause
* resume
* stop
* skip

### Flowmodoro

* count-up focus
* configurable ratio
* automatic break calculation
* break countdown
* optional automatic break

### Pomodoro

* configurable work duration
* short break
* long break
* interval count
* auto transitions

### Tasks

* create
* select
* complete

### History

* every session stored
* task association
* dates
* durations

### Statistics

* today
* week
* month
* year
* total
* longest
* average
* by task

### Persistence

* SwiftData
* launch restoration
* schema migration strategy

### Sync

* Supabase
* authentication
* offline queue
* deterministic conflict handling
* RLS

### System

* notifications
* launch at login
* global shortcut
* dark/light mode
* Mac widgets

---

# 53. SOURCE OF TRUTH MATRIX

Implement the following ownership model:

```text
Timer Engine
→ owns timer behavior

SwiftData
→ owns durable local application data

Statistics Engine
→ derives analytics from local session records

Notification Service
→ owns notification scheduling

Hotkey Service
→ owns global shortcut registration

Login Item Service
→ owns launch-at-login integration

Sync Engine
→ owns local ↔ Supabase synchronization

SwiftUI
→ renders state and sends user commands
```

No subsystem should secretly become the owner of another subsystem's state.

---

# 54. ARCHITECTURE RULE

When there is a choice between:

A complicated generic abstraction

and

a small explicit implementation

choose the small explicit implementation.

This application does not need an enterprise framework.

The best codebase is the smallest codebase that remains:

* correct
* testable
* maintainable
* extensible
* native

---

# 55. DEVELOPMENT ORDER

Implement in this exact order.

## Phase 1 — Foundation

* Xcode project
* SwiftUI app lifecycle
* MenuBarExtra
* basic dependency structure
* SwiftData
* models
* settings

## Phase 2 — Timer Engine

* state machine
* persistence/recovery
* count-up
* countdown
* pause/resume
* stop
* skip

## Phase 3 — Core UX

* menu-bar popover
* task selection
* Flowmodoro
* Pomodoro

## Phase 4 — History + Analytics

* sessions
* history
* statistics engine
* statistics UI

## Phase 5 — macOS Integrations

* notifications
* login item
* global shortcut
* appearance

## Phase 6 — Widgets

* WidgetKit extension
* shared state
* compact timer/today widget

## Phase 7 — Supabase

* auth
* schema
* RLS
* sync engine
* offline queue
* conflict handling

## Phase 8 — Hardening

* unit tests
* integration tests
* sleep/wake tests
* persistence recovery
* sync failure testing
* performance
* memory
* accessibility
* packaging

---

# 56. DEFINITION OF DONE

The application is complete only when:

1. It builds cleanly.
2. It launches as a true native Mac menu-bar application.
3. A user can start a focus session within seconds.
4. The timer remains accurate across sleep/wake and app lifecycle events.
5. Sessions survive application relaunch.
6. Analytics work completely offline.
7. Supabase synchronization does not block local usage.
8. Duplicate sessions cannot be created by retrying sync.
9. Global shortcuts work while other applications are focused.
10. Notifications are scheduled reliably.
11. Launch-at-login reflects the actual system state.
12. Widgets show meaningful current information.
13. Dark and light appearance both look native.
14. Tests cover all critical timer and analytics behavior.
15. No major feature depends on an invented or deprecated API.
16. The app feels small.

---

# 57. FINAL DESIGN TEST

After implementation, ask:

> Could a student open this app, choose “Deep Work”, press Start, forget about the application completely, work for 57 minutes, press Stop, take a calculated break, and later understand exactly how much focused work they completed — without fighting the software?

If the answer is not obviously yes, simplify the implementation.

---

# 58. IMPORTANT ENGINEERING BEHAVIOR

You are empowered to make implementation decisions, but you are NOT empowered to change the product direction.

You may change:

* internal class names
* file organization
* implementation details
* algorithms
* APIs
* dependency choices

when technically justified.

You must not change:

* local-first behavior
* native macOS direction
* menu-bar-first UX
* Flowmodoro
* Pomodoro
* tasks
* history
* statistics
* SwiftData persistence
* optional Supabase sync
* notifications
* global shortcuts
* launch at login
* widgets
* minimalism

Do not add features merely because competing productivity apps contain them.

The product wins through restraint.

---

# 59. DOCUMENTATION REQUIREMENT

Create:

```text
README.md
docs/ARCHITECTURE.md
docs/ARCHITECTURE_DECISIONS.md
docs/DATA_MODEL.md
docs/SYNC.md
docs/TIMER_ENGINE.md
docs/TESTING.md
```

Document:

* architecture
* state transitions
* persistence
* Supabase schema
* RLS
* conflict resolution
* timer mathematics
* recovery behavior
* permission requirements
* build/run instructions

---

# 60. FINAL DELIVERABLE

Deliver:

1. complete Xcode project
2. all Swift source
3. SwiftData models
4. timer engine
5. SwiftUI interface
6. widgets
7. global shortcut system
8. notifications
9. login-at-startup
10. Supabase integration
11. SQL migrations
12. RLS policies
13. tests
14. architecture documentation
15. setup instructions

Do not return a collection of snippets.

Build the actual application.

Do not stop after creating the UI.

Do not stop after creating the timer.

Do not mock Supabase.

Do not replace persistence with in-memory arrays.

Do not replace the global shortcut with a local keyboard handler.

Do not replace widgets with screenshots.

Do not replace analytics with hard-coded values.

Do not replace synchronization with a placeholder service.

---

# 61. MOST IMPORTANT RULE

Before writing code, make the architecture explicit.

Before choosing a non-obvious API, verify Apple documentation.

Before choosing a Supabase implementation, verify the current official Supabase Swift documentation.

Before adding a dependency, justify why a native framework cannot do the job.

When uncertain, research rather than hallucinate.

The result should look and behave like a small, polished Mac utility that could actually ship on the Mac App Store.
