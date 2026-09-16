# Timer engine

## State transitions

```text
idle → focus → pausedFocus → focus
focus → suggestedBreak → breakTimer → idle
focus → breakTimer                 (automatic Flowmodora break)
focus → breakTimer → focus         (Pomodoro auto-start)
focus/pausedFocus → idle           (stop or skip)
```

Flowmodora uses `accumulatedFocus + (now - focusResumedAt)` while running. Stopping calculates `duration / flowBreakRatio`. Pomodoro uses a target end date for work and breaks; pausing moves the remaining interval into `remainingWhenPaused` and resume reconstructs a new target end date.

The UI may refresh every second, but refresh cadence is never the source of truth. `AppStore` doesn't poll: it sleeps a single `Task` until `snapshot.countdownEnd`, re-armed via `TimerEngine.onSnapshotChange` (called from `persist()`) whenever a pause/resume/stop/break/reset could have moved that target — a Flowmodora count-up has no `countdownEnd`, so nothing schedules while one runs. On relaunch, or after sleep/wake, the engine decodes `TimerSnapshot` and the first refresh immediately catches up any countdown that ended while the app was not visible. A completed focus session is written once using its UUID; recording is idempotent if a completion event is repeated.

`stop` records a completed local session before changing the visible state. `skip` records any non-zero abandoned work as interrupted and does not count it in statistics. Breaks are ephemeral and are not stored as focus sessions.
