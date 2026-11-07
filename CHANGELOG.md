# Changelog

All notable changes to Flowmodora are documented here.

## [2.0.0] — 2026-11-07

### Added

- Break-over alarm: the native Glass chime repeats for 10 seconds when a
  break ends, until the menu-bar item is clicked (or the timeout passes).
  It respects the Sounds setting.
- Menu bar `BREAK 4:32` state, with `BREAK` while the focus clock is hidden.
- Automatic focus pause on sleep or screen lock (74b3517).
- Reset Today from the footer’s right-click menu (74b3517).
- Grouped History with daily totals, start/end times, and per-session delete
  (74b3517).

### Changed

- Footer Today and overflow controls are 20% larger with larger hit targets.
- Historical screenshots are organized into `docs/journey/v1` and
  `docs/journey/v0-early`.

### Fixed

- Task deletion confirms inline so the popover stays open (74f3b96).
- Inline deletion confirmation text has a larger, more readable treatment
  (4d0013c).

### Removed

- The ambiguous break coffee icon in the menu bar.
- Stale documentation for removed sync code and a stale App Group/file-access
  configuration note.

## [1.0.0] — 2026-10-01

Flowmodoro + Pomodoro modes, Liquid Glass popover, task list with timeable
subtasks, Reset Time, statistics (streak, 52-week heatmap, charts), hideable
menu-bar timer, break-over bell, automatic JSON backups with restore, delete
tasks (kept in history), and local-only operation (sync removed 2026-09-18).
