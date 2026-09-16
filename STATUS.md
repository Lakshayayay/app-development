# Flowmodora — project status

Plain-language snapshot of what's built, what isn't, what's next, and the
product principles that constrain future changes. Update this when something
ships or the plan changes — it's meant to replace re-reading old audit docs
or a scratch working-notes ledger to figure out where things stand.

## What Flowmodora is

A native macOS menu-bar focus timer (Flowmodoro + Pomodoro), local-first,
with optional Supabase sync. See `flowmodoro/README.md` for build
instructions and `flowmodoro/docs/ARCHITECTURE.md` for how each subsystem
works and why specific technical calls were made.

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
- **One source of truth.** SwiftData is authoritative; Supabase is an
  optional sync target, never the primary database.
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
Statistics window shows the current/best streak, a heatmap, and
total-hours milestones — all derived facts from recorded sessions, like
everything else in Statistics. No points, XP, badges, levels, or
social/competitive framing. If this ever grows toward those, that's a new
product decision, not a natural extension of this one.

Architect cleanly enough that some of these *could* be added later — don't
implement them now, and don't add a feature just because a competing app
has it.

### Must-not-change without an explicit product decision
Local-first behavior, native macOS direction, menu-bar-first UX, Flowmodoro,
Pomodoro, tasks, history, statistics, SwiftData persistence, optional
Supabase sync, notifications, global shortcuts, launch-at-login, widgets,
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
- Inline task list in the popover: complete/uncomplete, completed tasks
  collapse under a disclosure, each row shows today's/lifetime focused time,
  and every pressable control (checkbox, row, new-task button, footer)
  gives spring-press feedback.
- A single shared 1 Hz clock drives every ticking display; only the timer
  ring's own view re-renders on each tick, not the surrounding controls.
- SwiftData persistence for tasks, sessions, settings; a local outbox that
  drains without unbounded growth, retries on a backoff, and coalesces a
  burst of rapid writes into one sync pass instead of overlapping calls.
- History and Today/Week/Month/Year/Total statistics: a daily goal, a
  current/best streak, a today-vs-goal ring, a 52-week heatmap, accent-
  gradient period bar charts with a goal line and rising-bar entrance,
  a cumulative-hours area chart with milestones, and a by-task breakdown —
  all derived facts from recorded sessions, no points/badges/levels.
- Native Liquid Glass UI (`.glassEffect`, `.buttonStyle(.glass)`) throughout.
- Real Supabase sync: SDK integrated, schema + RLS applied, email OTP auth,
  offline-safe outbox transport, and (as of this branch) an actual network-
  client sandbox entitlement so sync can reach the network at all.
- App identity: name, icon, accent color, cleaned `Info.plist`.
- Notifications, launch-at-login, light/dark/system appearance.
- Sleep/wake, settings, streak, ticker-lifecycle, and Pomodoro-plan/rounds
  test coverage in `flowmodoroTests` (21 tests as of this branch).

## Not built yet

- **Widget.** `WidgetExtension/` exists but isn't wired into an Xcode
  target; no App Group entitlement, so it can't share live data with the
  app yet.
- **Accessibility pass.** No VoiceOver pass done beyond the labels added
  incidentally with recent UI work.
- **Swift 6 strict concurrency.** Project still builds under `SWIFT_VERSION
  5.0`; migration not started.
- **UI test automation.** `flowmodoroUITests` is still Xcode boilerplate —
  the core flows aren't automated, and no GUI-automation path exists yet
  for driving the `MenuBarExtra` popover from a script (confirmed
  repeatedly: a status-item click is scriptable via AppleScript/System
  Events, but the popover it opens exposes no AX window to click inside).

## In progress: feature/pomodoro-config-stats-perf-security

Branch for: Pomodoro pre-start configuration (B Focused-style), a
"poppier" Statistics restyle, performance/smoothness work, and a security
pass. Full task-by-task plan and exact code:
`docs/superpowers/plans/2026-09-16-pomodoro-config-stats-perf-security.md`.

**Done (10 of 12 tasks, all reviewed clean and merged to this branch):**
- [x] Task 0.1 — `-demoData` Debug launch flag + baseline perf numbers (S1
      only; S2–S4 need a manual click-through, see
      `flowmodoro/docs/ARCHITECTURE.md`'s Performance section)
- [x] Task 1.1 — Pomodoro plan frozen at Start, round limit, fixed a real
      bug where sleeping through a break could fabricate recorded sessions
- [x] Task 1.2 — the B Focused-style pre-start configuration card
- [x] Task 2.1 — Statistics performance (derive once, O(1) hover)
- [x] Task 2.2 — Statistics restyle (gradient charts, dropped the
      Longest/Average tiles)
- [x] Task 3.1 — isolated the ticking ring from the control buttons, fixed
      an hourly backwards-sweep animation bug
- [x] Task 3.2 — press feedback on every popover button, faster control
      morph animation
- [x] Task 4.1 — security migration **written**
      (`flowmodoro/Supabase/003_close_public_exposure.sql`, closes an
      anon-readable data leak) — **not yet applied to the live Supabase
      project**, pending an explicit go-ahead
- [x] Task 4.2 — network-client sandbox entitlement (sync was previously
      silently blocked), dropped an unused file-access entitlement,
      hardened runtime — verified against the actual signed binary
- [x] Task 4.3 — sign-in field sanitization + AutoFill hints

**Remaining (2 of 12 tasks + final review):**
- [ ] Task 3.3 — coalesce sync bursts (`AppStore.requestSync()`) — code
      is written and committed (`3a369ed`), tests pass, but its own review
      hadn't been dispatched yet when this branch was paused
- [ ] Task 3.4 — after-benchmarks: repeat Task 0.1's measurement against
      this branch's HEAD and fill in the "After" column of
      `flowmodoro/docs/ARCHITECTURE.md`'s Performance table
- [ ] Final whole-branch review, then `finishing-a-development-branch`
      (decide PR vs. direct merge)

**Standing decisions made while executing this plan** (carried forward so
resuming doesn't need to re-derive them):
- Worked directly on this feature branch, not a separate git worktree —
  single-session, single-writer, no concurrency risk.
- Task 4.1's live-database apply is deliberately held back — implementing
  the migration file is in scope for automated execution, applying it to
  the real Supabase project is not, without one more explicit
  confirmation. The RLS cross-user isolation test is likewise still
  outstanding for the same reason.
- Task 1.1's `roundsCompleted` leak (found in review) was fixed inline
  within Task 1.1 rather than deferred, since Task 1.2 — the very next
  task — was about to make it immediately reachable through the UI.

**Deferred, non-blocking observations from review** (safe to leave for the
final whole-branch review to triage):
- `REGISTER_APP_GROUPS = YES` is dead build config on the app target — no
  app-group ID configured anywhere, no widget/extension target exists yet.
  Same category of unused-capability cruft Task 4.2 already cleaned up,
  just outside that task's diff.
- Task 4.3's implementer report asserted its test result in prose without
  pasting the raw command/output — the underlying claim was independently
  reconfirmed true, this is a documentation-quality nit only.

## Where the deeper detail lives

- `flowmodoro/docs/ARCHITECTURE.md` — how every subsystem works, why
  specific technical calls were made (append a new decision entry there
  whenever you make a non-obvious one), current performance baseline.
- `docs/superpowers/plans/2026-09-16-pomodoro-config-stats-perf-security.md`
  — the exact task-by-task plan (code included) for finishing the in-
  progress branch above.
