# Performance baseline

Measurements taken against a Debug build (`xcodebuild … -configuration Debug`)
launched with `-demoData` (see `Core/DemoData.swift`): an in-memory store
seeded with 3 years of Pomodoro sessions across 5 tasks, so Statistics has a
realistic history size without touching the real database.

Method: `open -n Flowmodora.app --args -demoData`, then
`top -l 61 -s 1 -stats pid,cpu,idlew -pid $PID`, averaged over 60 samples
(1/s). Only one instance of the app was run at a time — hotkeys and the
status item collide otherwise — and the previously-running production
instance was quit first (`osascript -e 'quit app "Flowmodora"'`).

| Scenario | Metric | Before | After |
|---|---|---|---|
| S1 idle, closed | CPU % / idle wakeups/s | 0.1% / 0.0 | |
| S2 running, closed | CPU % / idle wakeups/s | not measured (see below) | |
| S3 running, open | CPU % / idle wakeups/s | not measured (see below) | |
| S4 stats hover sweep | body updates (Heatmap / Progress) / hitches | not measured (see below) | |

## Why S2–S4 are unmeasured

S2 and S3 need the Pomodoro timer actually running, and S4 needs the
Statistics window open with the pointer swept across the heatmap and bar
chart for 15 s while an `xctrace` recording is attached. All three require
driving the menu-bar popover: clicking the status item, then a "Start"
button inside it, then (for S4) opening a separate window from a context
menu.

This is a `MenuBarExtra` popover, not a normal window, and isn't reliably
reachable through AppleScript/System Events in this environment — a status
item click was scriptable, but the popover it opens does not expose an AX
window (`windows` returns 0 even right after the click), so there's no
element to click "Start" on. Pushing further would mean blind coordinate
clicks against a screenshot of the whole display, which risks capturing
whatever else is on screen (other apps, other windows) — not an acceptable
tradeoff for a baseline number. Per the task's guidance, this was left as a
best-effort partial result rather than fought further.

`xcrun xctrace list templates` confirms the `SwiftUI` template referenced in
the task brief is available on this machine, for whoever records S4 later
(manually, driving the popover by hand):

```
Activity Monitor, Allocations, Animation Hitches, App Launch, Audio System
Trace, CPU Counters, CPU Profiler, Core ML, Data Persistence, File Activity,
Game Memory, Game Performance, Game Performance Overview, Leaks, Logging,
Metal System Trace, Network, Power Profiler, Processor Trace, RealityKit
Trace, Swift Concurrency, SwiftUI, System Trace, Tailspin, Time Profiler
```

S2/S3/S4 "After" numbers should be gathered manually the same way once the
corresponding perf work lands, by clicking through the popover by hand
instead of scripting it.
