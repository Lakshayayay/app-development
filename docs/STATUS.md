# Flowmodora — project status

Plain-language snapshot of what's built, what isn't, what's next, and the
product principles that constrain future changes. Update this when something
ships or the plan changes — it's meant to replace re-reading old audit docs
or a scratch working-notes ledger to figure out where things stand.

## What Flowmodora is

A native macOS menu-bar focus timer (Flowmodoro + Pomodoro), local-only. See the repo root's `README.md` for build
instructions and `ARCHITECTURE.md` (this same folder) for how each
subsystem works and why specific technical calls were made.

## Product principles (non-negotiable)

### What it is
A tiny native macOS menu-bar companion that makes starting, maintaining, and
understanding focused work almost effortless. Not another bloated
productivity app — it wins through restraint.

### The two methodologies (both permanent, neither privileged)
- **Flowmodoro** — count up. `breakDuration = focusDuration / breakRatio`
  (default 5:1), configurable.
- **Pomodoro** — fixed work/short-break/long-break intervals, all
  configurable, long break after N cycles, an optional round limit, and a
  B Focused-style pre-start configuration card.

### Must hold
- **Local-first.** Starting a timer, recording a session, and viewing
  analytics must never touch the network or require an account.
- **Native-first.** Reach for an Apple framework before a third-party
  dependency.
- **No fake timer.** Never a counter incremented once a second. Derive
  displayed time from timestamps so it survives sleep/wake, suspension,
  popover close, and relaunch.
- **One source of truth.** SwiftData is the only database. (A
  Supabase sync layer existed and was removed; see ARCHITECTURE.md.)
- **Focus data reflects what actually happened**, not what the user
  intended — an interrupted session still counts for what was actually
  focused, and a slept-through auto-continue must never fabricate a
  session that didn't happen.

### Permanently out of scope
AI assistant/chatbot, teams/social/leaderboards, points/badges/levels,
project management, calendar or third-party task-app integrations, browser
integrations, app/web blocking, complex tags, detailed notes, due dates,
subscriptions, ads, server-dependent analytics, artificial productivity
scores.

A personal streak and daily-goal ring are in scope, narrowly: a day counts
once its focused time meets a user-set daily goal (default 30 min); the
Statistics window shows the current/best streak and a heatmap — all
derived facts from recorded sessions, like everything else in Statistics.
No points, XP, badges, levels, or
social/competitive framing. If this ever grows toward those, that's a new
product decision, not a natural extension of this one.

Architect cleanly enough that some of these *could* be added later — don't
implement them now, and don't add a feature just because a competing app
has it.

**Subtasks are one level deep, on purpose.** A task can have a checklist of
timeable subtasks; a subtask cannot have its own subtasks, notes, or due
dates. Nesting further is project-management scope creep — see above.

### Must-not-change without an explicit product decision
Local-first behavior, native macOS direction, menu-bar-first UX, Flowmodoro,
Pomodoro, tasks, history, statistics, SwiftData persistence,
notifications, global shortcuts, launch-at-login, widgets,
minimalism.

Everything else — class names, file layout, algorithms, dependency choices,
documentation structure — is a free implementation decision.

### The gut check
> Could a student open this app, choose "Deep Work," press Start, forget
> about the app completely, work for 57 minutes, press Stop, take a
> calculated break, and later understand exactly how much focused work they
> completed — without fighting the software?

If the answer isn't obviously yes, simplify.

## Built and working

- Menu-bar app (`MenuBarExtra`), no stray window at launch, subtle live
  clock label (icon-only idle, `m:ss`/`h:mm:ss` while running, dimmed while
  paused).
- Right-click the menu-bar clock for a native context menu: pause/resume,
  stop or skip, complete the running task, quit.
- Flowmodoro (count-up + ratio break) and Pomodoro (fixed intervals, an
  optional round limit, and a B Focused-style pre-start configuration card
  shown only while idle in Pomodoro mode — the task-selection flow itself
  is unchanged), pause/resume/stop/skip.
- Timestamp-derived timer — correct across sleep/wake, popover close,
  relaunch, and a slept-through auto-continue (which now ends the run
  cleanly instead of fabricating a backdated session).
- Inline task list in the popover, in a min/max-height scrolling band (never
  cramped at 1 task, never balloons the popover past ~7): complete/
  uncomplete, completed tasks collapse under a disclosure, each row shows
  a single duration when today's and lifetime focused time are equal or
  both (with a tooltip) when they differ, and every pressable control
  (checkbox, row, new-task button, footer) gives spring-press feedback.
- Right-click a task for a checklist of timeable subtasks (one level, see
  Product principles) — a subtask can be selected, timed, and completed
  exactly like a task, and its focused time rolls up into its domain's
  total and into Statistics' by-task breakdown. Right-click also offers
  Reset Time, which zeroes a row's displayed total without touching the
  underlying sessions (they stay in History/Statistics/the streak).
- Every dropdown in the popover (subtask checklists, the Completed
  section, both new-task fields, the Pomodoro plan card) opens and closes
  through the same `withExpandCollapse` call, so the dropdown, the rows
  below it, and the popover's own height all move together instead of
  the content fading while its neighbors jump to their new position.
- Every timer control button fires on the first click (full 52pt glass
  circle is hit-testable, not just the glyph) with no perceptible delay
  between press and state change — the popover no longer resizes on
  Start/Stop, and `Stop`/complete-task update in-memory aggregates
  instead of re-fetching full history on the click path.
- A single shared 1 Hz clock drives every ticking display; only the timer
  ring's own view re-renders on each tick, not the surrounding controls.
- SwiftData persistence for tasks, sessions, settings; all local.
- History and Today/Week/Month/Year/Total statistics: a daily goal, a
  current/best streak, a today-vs-goal ring, a 52-week heatmap, accent-
  gradient period bar charts with a goal line and rising-bar entrance,
  and a by-task breakdown (up to 8 named tasks plus "Other") — all
  derived facts from recorded sessions, no points/badges/levels.
- Native Liquid Glass UI (`.glassEffect`, `.buttonStyle(.glass)`) throughout.
- App identity: name, icon, accent color, cleaned `Info.plist`.
- Notifications, launch-at-login, light/dark/system appearance.
- Sleep/wake, settings, streak, ticker-lifecycle, and Pomodoro-plan/rounds
  test coverage in `flowmodoroTests`.

## Not built yet

- **Widget.** Not started — a home-screen widget would need its own
  extension target and an App Group entitlement to share live data with
  the app.
- **Accessibility pass.** No VoiceOver pass done beyond the labels added
  incidentally with recent UI work.
- **Swift 6 strict concurrency.** Project still builds under `SWIFT_VERSION
  5.0`; migration not started.
- **UI test automation.** The core flows aren't automated, and no
  GUI-automation path exists yet for driving the `MenuBarExtra` popover
  from a script (confirmed repeatedly: a status-item click is scriptable
  via AppleScript/System Events, but the popover it opens exposes no AX
  window to click inside). The empty `flowmodoroUITests` target was
  removed rather than left as unused boilerplate; a real UI-test target
  can be added back once that automation path exists.

## Outstanding work

The Pomodoro-config/stats-restyle/performance/security pass (Pomodoro
pre-start configuration, "poppier" Statistics, ring/click-path performance,
and a security pass) is done and merged to `master` as ordinary commits —
see git log for the task-by-task history. Two items from that work still
need a human, not more code:

- **S2–S4 perf click-through.** S1 (idle, closed) was re-measured at 0.1%
  CPU / 0.0 wakeups, unchanged from before. S2–S4 (timer running, popover
  open) still need a manual click-through with `top -l 61 -s 1 -stats
  pid,cpu,idlew -pid $PID` — no scriptable path exists yet: a status-item
  click is AppleScript/System-Events-reachable, but the popover it opens
  exposes no AX window to drive from a script.

Known non-blocking cruft: `REGISTER_APP_GROUPS = YES` is dead build config
on the app target — no app-group ID configured anywhere, no widget
extension target exists yet.

A follow-up round fixed the remaining "press it once or twice" feel
(missing hit target on the 52pt timer buttons, duplicate press-feedback
systems fighting each other, the popover resizing on every Start/Stop) and
rebalanced the popover (smaller ring, scrolling task list, collapsed
duplicate time label) and Statistics ("By task" grown into the space freed
by dropping the milestone chart). Typechecked against the real macOS SDK
(Xcode's own build/test tooling isn't available in every environment this
project is worked in) but not yet run through Xcode's `xcodebuild test` or
a manual click-through on a real build — do that before calling it done.

## Where the deeper detail lives

`ARCHITECTURE.md` (this same folder) — how every subsystem works, why
specific technical calls were made (append a new decision entry there
whenever you make a non-obvious one), current performance baseline.
