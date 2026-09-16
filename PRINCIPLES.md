# Flowmodora — product principles

Condensed from the original 61-section engineering spec (`PRODUCT PLAN.md`,
now retired — the app matches it closely enough that the spec's job is done;
this file keeps only the parts that should still constrain future changes).
For what's built vs. not, see `STATUS.md`. For why specific technical calls
were made, see `flowmodoro/docs/ARCHITECTURE_DECISIONS.md`.

## What it is

A tiny native macOS menu-bar companion that makes starting, maintaining, and
understanding focused work almost effortless. Not another bloated
productivity app — it wins through restraint.

## The two methodologies (both permanent, neither privileged)

- **Flowmodoro** — count up. `breakDuration = focusDuration / breakRatio`
  (default 5:1), configurable.
- **Pomodoro** — fixed work/short-break/long-break intervals, all
  configurable, long break after N cycles.

## Non-negotiables

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
  focused.

## Permanently out of scope

AI assistant/chatbot, teams/social/leaderboards, points/badges/levels,
project management, calendar or third-party task-app integrations, browser
integrations, app/web blocking, complex tags, detailed notes, due dates,
subscriptions, ads, server-dependent analytics, artificial productivity
scores.

**2026-09-15 decision:** a personal streak and daily-goal ring are in scope,
narrowly. A day counts once its focused time meets a user-set daily goal
(Settings, default 30 min); the Statistics window shows the current/best
streak, a heatmap, and total-hours milestones (10h, 25h, 50h, …) — all
derived facts from recorded sessions, like everything else in Statistics.
No points, XP, badges, levels, or social/competitive framing. If this ever
grows toward those, that's a new decision, not a natural extension of this
one.

Architect cleanly enough that some of these *could* be added later — don't
implement them now, and don't add a feature just because a competing app has it.

## Must-not-change without an explicit product decision

Local-first behavior, native macOS direction, menu-bar-first UX, Flowmodoro,
Pomodoro, tasks, history, statistics, SwiftData persistence, optional
Supabase sync, notifications, global shortcuts, launch-at-login, widgets,
minimalism.

Everything else — class names, file layout, algorithms, dependency choices —
is a free implementation decision.

## The gut check

> Could a student open this app, choose "Deep Work," press Start, forget
> about the app completely, work for 57 minutes, press Stop, take a
> calculated break, and later understand exactly how much focused work they
> completed — without fighting the software?

If the answer isn't obviously yes, simplify.
