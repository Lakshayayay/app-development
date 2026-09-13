# Flowmodora — UI/UX Testing & Backend Integration Plan

**Status:** Draft v1 · **Authored:** 2026-09-13 · **Repo:** `/Volumes/MAC workspace /flowmo`
**Design reference:** Emil Kowalski `apple-design` + `emil-design-eng` + `write-swift` skills (installed at `~/.claude/skills/`, mirrored in `.agents/skills/`)
**Source specs:** `FLOWMODORA_PLAN.md` (UI blueprint), `PRODUCT PLAN.md` (61-section engineering spec)

---

## Overview

### What this document is

An execution plan to take Flowmodora from its current state to a shippable macOS menu-bar app: correct UI/UX measured against Apple's design principles, a real backend for focus logs and per-task tracking, and a dashboard worth opening. Every finding below was verified against the actual source tree or the macOS 26.5 SDK — none are assumed.

### Verified current state

The headline finding gates everything else:

> **The app does not compile.**
> `flowmodoro/flowmodoro/Features/UI/FlowmodoraTimerView.swift:59` calls `.springButtonStyle()`.
> `Features/UI/SpringButtonStyle.swift` defines the `SpringButtonStyle: ButtonStyle` struct but **never defines the `View` extension** that exposes it. Ten call sites, zero of them resolve.
>
> ```
> error: value of type 'Button<some View>' has no member 'springButtonStyle'
> ** BUILD FAILED **
> ```

Everything the last commit claims (`feat(ui): implement pluggable Liquid Glass UI, History, Settings and App entry`) is unverified, because it has never run.

Beyond that, the audit found four categories of problem:

| Category | Severity | Summary |
| --- | --- | --- |
| Build + correctness | **P0** | Does not compile. Four missing `\` string interpolations silently ship literal placeholder text into the UI. |
| Identity | **P0** | Three different app names coexist. No app icon exists. No accent colour is defined. |
| Missing subsystems | **P0** | Widget is not an Xcode target. Sync is a stub that counts rows. Outbox grows unboundedly and is never drained. |
| Design + performance | **P1** | Glass is hand-rolled and triple-stacked. Two redundant 500 ms poll loops force full-tree re-render of a blurred material stack ~4×/sec. Deployment target already permits *native* Liquid Glass, which is unused. |

### The single highest-leverage discovery

`MACOSX_DEPLOYMENT_TARGET = 26.5`, and the installed SDK is macOS 26.5. I verified by typechecking against the real SDK that these compile cleanly today:

```swift
GlassEffectContainer(spacing: 12) {
    Text("Hi")
        .padding()
        .glassEffect(.regular.tint(.accentColor).interactive(), in: .rect(cornerRadius: 16))
}
```

`.buttonStyle(.glass)`, `.buttonStyle(.glassProminent)`, `backgroundExtensionEffect`, and `scrollEdgeEffectStyle` are all present in the SDK's SwiftUI interface.

`FLOWMODORA_PLAN.md` was written before Liquid Glass shipped, so it instructs the agent to *imitate* glass with `.ultraThinMaterial` plus a hardcoded white stroke. That instruction is now obsolete and actively harmful: the imitation is wrong in light mode, stacks illegally, and clips its own shadow. **Deleting `LiquidGlassModifier.swift` in favour of the native API removes code and fixes three bugs at once.** This is the rare change that is simultaneously less work, less code, and more correct.

### Scope boundaries

**In scope:** compile fix, UI/UX audit + remediation, motion pass, menu-bar hardening, icon + naming, focus-log backend, per-task tracking, dashboard, Supabase sync, test coverage.

**Out of scope** (per `PRODUCT PLAN.md` §48, which this plan does not relitigate): AI features, teams, gamification, streaks, achievements, app blocking, third-party task integrations, subscriptions.

### One conflict to resolve before starting

The brief asks for **"task-factor tracking"**. `PRODUCT PLAN.md` §2 and §48 explicitly forbid *"artificial productivity scores"* and *"unnecessary dashboards"*.

These are reconcilable only under a restrained reading, which this plan adopts:

> **Task factor = factual per-task aggregates. Never a composite invented score.**
> Total focused time, session count, mean and median session length, interruption rate, last-focused date. Each number traceable to real `FocusSessionRecord` rows. No weighting, no 0–100 "focus score", no letter grades.

If a composite score is genuinely wanted, it is a product-direction change and needs an explicit decision — `PRODUCT PLAN.md` §58 states the agent is *not* empowered to change product direction unilaterally.

---

## UI/UX Testing Strategy

Five gates, run in order. Gate 0 is a hard blocker; nothing downstream is meaningful until it passes.

### Gate 0 — Build & launch verification

Non-negotiable prerequisite. No UI claim is valid until the app runs.

```bash
cd "/Volumes/MAC workspace /flowmo/flowmodoro"
xcodebuild -project flowmodoro.xcodeproj -scheme flowmodoro \
           -destination 'platform=macOS' build 2>&1 | grep -E "error:|warning:|BUILD"
```

**Exit criteria:**
- `** BUILD SUCCEEDED **`, zero errors.
- Warning count recorded as a baseline and monotonically decreasing thereafter.
- App launches, menu-bar item appears, **no window opens uninvited** (see Gate 3).

Use `XcodeBuildMCP` for the build/launch/screenshot loop — it is installed and connected at user scope. `AGENTS.md` requires loading the XcodeBuildMCP skill before calling its tools.

### Gate 1 — Static correctness audit

Automated sweeps that catch the bug classes already found. Run these as a pre-commit hook or CI step so they never regress.

**1a. Unescaped string interpolation.** This class of bug compiles cleanly and ships placeholder text to users. Four instances exist today.

```bash
# Finds "(identifier)" inside a string literal where "\(identifier)" was meant
rg -n '"[^"]*\([a-zA-Z_][a-zA-Z0-9_.]*(\(\))?[^"]*"' --glob '*.swift' \
   | rg -v '\\\('
```

Known hits to fix:

| File:line | Current (literal) | Intended |
| --- | --- | --- |
| `Core/StatisticsEngine.swift:89` | `"(hours)h (minutes)m"` | `"\(hours)h \(minutes)m"` |
| `Core/StatisticsEngine.swift:90` | `"(minutes)m"` | `"\(minutes)m"` |
| `Core/StatisticsEngine.swift:91` | `"(remainingSeconds)s"` | `"\(remainingSeconds)s"` |
| `Core/StatisticsEngine.swift:93` | `"(max(1, Int(...)))m"` | `"\(max(1, Int(...)))m"` |
| `Core/Services.swift:26` | `"flowmodo.interval.(UUID().uuidString)"` | `"flowmodo.interval.\(UUID().uuidString)"` |
| `Core/Services.swift:137` | `"(pendingChanges) changes queued"` | `"\(pendingChanges) changes queued"` |

The `StatisticsEngine` hits are the worst: `.compact` is the **default** `DurationStyle`, so the popover footer, every History row, all four Statistics metric cards, focus-by-day and focus-by-task all currently render literal `(minutes)m`.

**1b. Dead and unreferenced code.**

```bash
# Files on disk but absent from the Xcode project
grep -c "patch_contentview\|test.swift\|WidgetExtension" flowmodoro.xcodeproj/project.pbxproj
# → currently 0
```

Confirmed dead: `flowmodoro/test.swift` (contains a second `@main struct TestApp` — a latent duplicate-entry-point hazard if ever added to a target), `flowmodoro/patch_contentview.swift` (a one-off codemod script), `flowmodoro/WidgetExtension/` (no target exists).

**1c. Unwired settings.** Every persisted preference must have both a UI control and a read site.

| Setting | UI control | Actually applied | Verdict |
| --- | --- | --- | --- |
| `appearance` | ✅ `SettingsView` picker | ❌ no `.preferredColorScheme` anywhere | **Dead — does nothing** |
| `pomodoroAutoStartFocus` | ❌ none | ✅ `TimerEngine.completeBreak` | **Unreachable** |
| global hotkey | ❌ none | ✅ hardcoded ⌘⌥S/P/X | **Unconfigurable** (spec §39 requires a Shortcuts section) |
| `showPauseButton` | ✅ | ✅ | OK |
| `flowBreakRatio` | ✅ | ✅ | OK |

### Gate 2 — Apple design-principle audit

Score each surface against the eight principles from `apple-design` §16. Any score below 3/5 becomes a tracked remediation item.

| Surface | Purpose | Agency | Familiarity | Simplicity | Craft |
| --- | --- | --- | --- | --- | --- |
| Menu-bar label | | | | | |
| Popover — idle | | | | | |
| Popover — focus running | | | | | |
| Popover — suggested break | | | | | |
| History | | | | | |
| Statistics | | | | | |
| Settings | | | | | |

Alongside the scoring, verify the **wayfinding** questions (`apple-design` §16) on every screen: *Where am I? Where can I go? What's there? How do I get out?* The current in-popover pages fail the last one — a lone chevron with no title context.

### Gate 3 — Interaction, motion & performance

**3a. Menu-bar-only lifecycle.** `Info.plist` correctly sets `LSUIElement = true`, but `flowmodoroApp.swift:22` declares `WindowGroup(id: "mainWindow")` as the **first scene**. SwiftUI will materialise that window at launch. Verify explicitly:

- Launch cold → menu-bar item present, **no window**, no Dock icon.
- Quit and relaunch → same.
- Launch via login item → same.

**3b. Render cost.** Instrument with the Time Profiler and the SwiftUI instrument, popover open, timer running, 60 seconds.

Two independent 500 ms loops currently exist — `MenuBarLabel.task` (`flowmodoroApp.swift:60-65`) and `FlowmodoPopover.task` (`ContentView.swift:60-65`) — both calling `store.refreshTimer()`, which increments the `@Observable` `clockTick`. `clockTick` is read at the top of `TimerReadout.body`, `FlowmodoraTimerView.progress`, `FlowmodoraTimerView.displayValue`, and `MenuBarLabel.body`. Each increment invalidates the whole tree, **including three nested `.ultraThinMaterial` layers plus stroke plus shadow**.

**Target:** popover body re-render count drops from ~4/sec to 0/sec for static chrome, with only the digit text updating. Measure `View.body` evaluations before and after.

**3c. Motion review** (`emil-design-eng` §"Debugging Animations"). Record the screen, play at 0.25×, check:

- Phase transitions (`idle → focus → suggestedBreak → break`) — currently an instant `switch` swap with no transition at all.
- Progress-ring stepping. `.animation(.linear, value: progress)` at `FlowmodoraTimerView.swift:27` is driven by a 500 ms-quantised value, so the ring advances in visible jumps.
- Button press feedback (blocked by the Gate 0 build failure — `SpringButtonStyle`'s parameters are correct but unreachable).

**3d. Accessibility.**

- `accessibilityReduceMotion` — currently unhandled anywhere in the codebase.
- `accessibilityReduceTransparency` — critical given the glass-heavy design; `apple-design` §14 requires frostier/solid surfaces under this setting.
- Full VoiceOver pass over the popover.
- Increase Contrast on: verify the hardcoded `.white.opacity(0.2)` stroke does not vanish or invert.

### Gate 4 — Behavioural & failure-path testing

The current test suite has 4 real unit tests (`flowmodoroTests.swift` — Flowmodoro ratios, pause/resume accumulation, Pomodoro countdown recovery, statistics grouping). They are well written and worth keeping. The UI test target is **pure Xcode boilerplate** — `testExample()` launches the app and asserts nothing.

`PRODUCT PLAN.md` §44–45 requires substantially more. Priority additions, in order:

1. **Sleep/wake reconstruction** — advance a controlled clock past `countdownEnd` while no view is polling; assert the phase transitions correctly on the next refresh.
2. **Stop / skip / session completion** — including the interrupted-session path.
3. **Pomodoro cycle progression** — short break → work → long break after N cycles, auto-transitions on and off.
4. **Calendar boundaries** — midnight crossover, DST transition, timezone change, year boundary. Spec §20 mandates start-date attribution; `StatisticsEngine.dailyFocus` implements it but no test pins it.
5. **Empty data** — every statistics period with zero sessions.
6. **Persistence** — relaunch with a live snapshot; corrupted store handling.
7. **Sync** — offline, reconnect, duplicate upload idempotency, conflict, soft delete, auth failure.

Then the three UI flows from spec §44, as real XCUITest automation:

```
Launch → select task → Start → Pause → Resume → Stop
Launch → Flowmodoro → Focus → Stop → Break
Launch → Pomodoro → Work → Break → Work
```

---

## UI/UX Improvement Recommendations

### Priority table (Emil review format)

| Before | After | Why |
| --- | --- | --- |
| `SpringButtonStyle.swift` defines only the struct | Add `extension View { func springButtonStyle() -> some View { buttonStyle(SpringButtonStyle()) } }` | **Build is broken.** 10 unresolved call sites. |
| `"(minutes)m"` in `StatisticsEngine.swift:89-93` | `"\(minutes)m"` | Literal placeholder text is currently rendered in History, Statistics and the footer. |
| Hand-rolled `LiquidGlassModifier` (`.ultraThinMaterial` + `.white.opacity(0.2)` stroke) | `.glassEffect(.regular.interactive(), in: .rect(cornerRadius: 16))` | Native API verified available on the 26.5 SDK. Deletes ~20 lines and fixes light-mode, stacking and shadow bugs together. |
| `.shadow(...)` then `.clipShape(...)` (`LiquidGlassModifier.swift:11-12`) | Shadow must come **after** the clip | `clipShape` clips the shadow it was meant to cast. The lift effect currently does not render. |
| `.liquidGlassStyle()` on popover **and** timer card **and** every button | One glass container; children are plain | `apple-design` §12: *"Never stack a light translucent surface on another — legibility collapses."* Currently 3 deep. |
| `.white.opacity(0.2)` stroke | Semantic `.separator`, or let the native API own the edge | Hardcoded white is wrong in light mode. `PRODUCT PLAN.md` §36: *"Do not hard-code colors everywhere."* |
| `store.clockTick` read in 4 view bodies | `TimelineView(.periodic(from: .now, by: 1))` scoped to the readout only | Confines invalidation to the digits. Removes ~4 full-tree re-renders/sec of a blurred material stack. |
| Two 500 ms `.task` poll loops | One `TimelineView` + one `NSWorkspace.didWakeNotification` observer | Redundant work; neither is the actual source of truth (timestamps are). |
| `.animation(.linear, value: progress)` on 500 ms-quantised input | `TimelineView(.animation)` computing progress continuously | Ring currently advances in visible 500 ms steps. |
| `progress` returns `1.0` for Flowmodoro (`FlowmodoraTimerView.swift:180`) | Render a distinct count-up affordance, not a full static ring | A permanently-full ring reads as "complete" and conveys nothing. |
| Phase changes swap instantly via `switch` | `.transition(.opacity)` at ~180 ms ease-out on the controls group | `emil-design-eng`: *"elements appearing or disappearing without transition feel broken."* |
| `.frame(width: 360, height: 560)` popover hosting `StatisticsView` with `.frame(minWidth: 620)` | Separate compact popover views from full window views | A 620 pt minimum inside a 360 pt popover is an unsatisfiable constraint. Layout breaks today. |
| `WindowGroup` first in scene order, `LSUIElement = true` | `MenuBarExtra` first; windows opened only on demand | An uninvited window at launch violates the menu-bar-only requirement. |
| `appearance` setting stored but never read | Apply `.preferredColorScheme(...)` at the scene root | The Appearance picker currently does nothing. |
| No `accessibilityReduceMotion` / `ReduceTransparency` handling | Gate motion and glass on both | `apple-design` §14. Mandatory for a glass-forward design. |
| Hand-rolled `GeometryReader` bar chart (`ContentView.swift:279-283`) | Swift Charts | Native, ships with the SDK, handles light/dark, axes and VoiceOver for free. Less code. |
| Hotkey registration failure `return`s silently (`Services.swift:94-96`) | Surface via `store.alertMessage` | Spec §42 requires *"Global shortcut could not be registered."* |
| `startFocus` silently no-ops when `taskID == nil` (`TimerEngine.swift:50`) | Surface feedback on the hotkey path | The button is disabled so the UI path is safe, but ⌘⌥S fails invisibly. |

### Structural: resolve the duplicate navigation

There are currently **two** unconnected ways to reach History, Statistics and Settings:

1. Separate `Window(...)` scenes — `flowmodoroApp.swift:34-47`.
2. In-popover pages via `PopoverPage` — `ContentView.swift:18`.

`@Environment(\.openWindow)` is captured at `ContentView.swift:16` and **never called**. Pick one model:

- **Recommended:** popover stays compact (timer + task + today's total only). History / Statistics / Settings open as real windows via `openWindow`. This matches `PRODUCT PLAN.md` §11 (*"closer to a high-quality native control panel than a traditional productivity dashboard"*) and removes the unsatisfiable-constraint bug for free.
- Alternative: everything in-popover, and the `Window` scenes get deleted.

Do not ship both.

### Structural: reconsider interrupted-session exclusion

`StatisticsEngine.filteredSessions` filters out `interrupted` sessions from **every** period, including `.total`. Meanwhile `TimerEngine.skip()` marks a stopped focus session `interrupted: true`, and `HistoryView` displays it.

Net effect: a 50-minute session the user skipped out of appears in History but contributes **zero** to every statistic. That is a silent data discrepancy between two screens showing the same underlying rows. Decide explicitly, document in `docs/ARCHITECTURE_DECISIONS.md`, and make both screens agree.

---

## Backend Integration Steps

Current backend reality, verified:

- `Supabase/001_initial_schema.sql` is genuinely good — four tables, RLS enabled on all of them, correct per-user policies, a sensible index. It has never been applied or exercised.
- `LocalSyncEngine` (`Services.swift:130-139`) is a placeholder that only counts rows.
- **No Supabase SDK dependency exists** anywhere in the project.
- `OutboxEntry.payload` is the literal string `"local-change"` (`AppStore.swift:166`).
- **The outbox is never drained.** `AppStore.save()` inserts a row on every write and nothing ever deletes one. `pendingOutboxCount()` grows monotonically forever.

`PRODUCT PLAN.md` §60 is unambiguous: *"Do not replace synchronization with a placeholder service."*

### Step 1 — Focus logs (local, authoritative)

The local layer is closest to correct and should be finished first. Local-first means this must work perfectly with Wi-Fi off (spec §43).

1. Fix the outbox leak. Give `LocalSyncEngine` a real drain: read pending entries → attempt transport → delete only on success → increment `attemptCount` with backoff on failure. Until a transport exists, either stop writing outbox rows or cap the table.
2. Replace `payload: "local-change"` with the actual serialised entity, so a drain has something to send.
3. Add the `NSWorkspace.didWakeNotification` observer. The timer *mathematics* are already timestamp-based and correct (`TimerEngine.focusDuration` / `countdownRemaining`) — the gap is that phase **transitions** only fire from the UI poll loop. If both views are gone, a completed interval sits unrecognised.
4. Make `TimerEngine.refresh()` provably idempotent. Spec §23: *"A timer completion event must be idempotent."*
5. Document the UserDefaults-vs-SwiftData split in `docs/ARCHITECTURE_DECISIONS.md`. Storing the ephemeral `TimerSnapshot` in UserDefaults while durable data lives in SwiftData is *correct* per spec §22, but it is currently undocumented and reads as an inconsistency.

### Step 2 — Task factor tracking

Per the conflict resolution in the Overview: factual aggregates only.

Extend `StatisticsEngine` (which is already pure, `Sendable`, and testable — keep it that way; it must never perform network requests, per spec §5):

```swift
struct TaskFactor: Sendable, Equatable {
    let taskID: UUID?
    let totalFocused: TimeInterval
    let sessionCount: Int
    let meanSession: TimeInterval
    let medianSession: TimeInterval
    let interruptedCount: Int
    let lastFocusedAt: Date?
}
```

`focusByTask` (`StatisticsEngine.swift:73`) is the seed — it already groups correctly. Every field must be derivable from `FocusSessionRecord` rows with no stored aggregate, so values cannot drift (spec §19: *"Do not store derived statistics permanently."*).

### Step 3 — Dashboard

Keep it inside the restraint spec §21 demands — *"How much did I actually focus?"*, not a metric wall.

1. Period selector: Today / Week / Month / Year / Total (already present and working).
2. Four headline metrics (already present — they will start rendering real numbers once the `formatDuration` interpolation bug is fixed).
3. Daily distribution — replace the hand-rolled `GeometryReader` bars with **Swift Charts**. Also fix the sparse-data issue: `dailyFocus` returns only days that *have* sessions, so a chart silently omits empty days and misrepresents consistency.
4. Task-factor table from Step 2.

### Step 4 — Supabase sync

Only after Steps 1–3 are solid and tested offline.

1. Add the Supabase Swift SDK via SPM. Verify current API against official docs before writing against it (spec §61).
2. Apply `001_initial_schema.sql`. **Test RLS as an unauthenticated and as a wrong-user client** — spec §46: *"Do not rely on client-side filtering as a security boundary."*
3. Optional email auth. Tokens in **Keychain only** — spec §29 forbids UserDefaults and SwiftData for secrets.
4. Publishable key via build configuration. Never a service-role key in the bundle (spec §24).
5. Transport wired to the outbox drain from Step 1: upsert by client-generated UUID (idempotent), last-write-wins on `updated_at` for tasks/settings, soft-delete via `deleted_at`, remove the outbox row only on a successful response.
6. Prove the failure modes: airplane mode, reconnect, duplicate upload, conflict, auth failure. The local timer must never block on any of them.

`docs/SYNC.md` already specifies this design correctly — it just describes what *"a future transport should"* do. This step is that transport.

### Step 5 — Widget

Currently `WidgetExtension/FlowmodoWidget.swift` is not in any target and returns hardcoded strings (`"Ready to focus"`, `"—"`, `"Today 0m"`).

1. Create a real Widget Extension target.
2. Add an App Group entitlement — **no entitlements file exists today**, which also means no App Sandbox configuration at all.
3. Share a minimal snapshot (current task title, timer text, today's total) through the App Group. Spec §35: *"Do not create a second persistence system."*
4. Verify light mode, dark mode, both supported families.

---

## Menu-Bar Implementation Details

### Naming — the explicit constraint

The brief states: **the app's name is Flowmodora.** Four different names currently coexist:

| Location | Current value | Required |
| --- | --- | --- |
| `PRODUCT_NAME` (`project.pbxproj`) | `$(TARGET_NAME)` → **`flowmodoro`** | `Flowmodora` |
| `CFBundleDisplayName` (`Info.plist:8`) | `Flowmodora` | ✅ correct |
| `PRODUCT_BUNDLE_IDENTIFIER` | `lakshayorg.flowmodoro` | decide + freeze before any release |
| Widget display name | `Flowmodo` | `Flowmodora` |
| App entry struct | `FlowmodoApp` | `FlowmodoraApp` |
| Types | `FlowmodoModels`, `FlowmodoPopover`, `FlowmodoWidget` | `Flowmodora*` |
| Menu-bar idle label | `Flowmodora` | ✅ correct |
| Xcode scheme / directory | `flowmodoro` | cosmetic, low priority |

`PRODUCT_NAME` is the one that matters most — it drives the bundle name, the About box, and the Finder name.

**Caution:** changing `PRODUCT_BUNDLE_IDENTIFIER` orphans the existing SwiftData store, the `SMAppService` login-item registration, and any UserDefaults snapshot. Decide it **once**, before distributing anything.

### Icon

`Assets.xcassets/AppIcon.appiconset/` contains `Contents.json` declaring ten macOS slots and **zero image files**. `AccentColor.colorset` declares a universal entry with **no colour value** — so `Color.accentColor`, used for the progress ring at `FlowmodoraTimerView.swift:23`, is falling back to system blue.

1. Design the app icon on the macOS rounded-rect grid at 1024×1024, export all ten slots. The concept should read at 16 pt — a timer/flow mark, not detailed illustration.
2. Define a real accent colour with explicit light and dark variants.
3. Design the **menu-bar template icon** separately. It is not the app icon: monochrome, template-rendered so macOS handles light/dark and the menu-bar tint automatically. Currently `MenuBarLabel` uses raw SF Symbols (`circle.fill` / `cup.and.saucer`) with no template treatment.

### Menu-bar label behaviour

`PRODUCT PLAN.md` §10: *"Do not make the menu-bar item visually noisy. The timer is the primary information."*

Current behaviour (`flowmodoroApp.swift:68-77`):

| Phase | Renders | Assessment |
| --- | --- | --- |
| `.idle` | `Flowmodora` | **Too wide.** A full word permanently occupying menu-bar space while doing nothing. Prefer the template icon alone. |
| `.focus` (Flowmodoro) | `HH:MM:SS` count-up | `HH:` is wasted width for most sessions — consider adaptive formatting. |
| `.focus` (Pomodoro) | `HH:MM:SS` countdown | Same. |
| `.suggestedBreak` | `Break` | OK |

`.monospacedDigit()` is correctly applied — that is the right call and prevents width jitter.

### Placement & lifecycle

1. **Scene order.** Make `MenuBarExtra` the first scene. With `LSUIElement = true` and `WindowGroup` currently first (`flowmodoroApp.swift:22`), an uninvited window at launch is the expected SwiftUI behaviour. Must be verified empirically.
2. **`.menuBarExtraStyle(.window)`** is already correct — it is what allows full SwiftUI in the dropdown.
3. **Single status item.** Spec §10: *"Do not create two independent menu-bar status items."* Currently satisfied; guard it in review.
4. **Clean the Info.plist.** It still carries Xcode template junk — `CFBundleDocumentTypes` declaring `com.example.plain-text` and a `UTImportedTypeDeclarations` entry for *"Example Text"*. A focus timer currently advertises itself as an editor of a fictional document type.
5. **Add an entitlements file** — App Sandbox, plus the App Group the widget needs.

---

## Timeline & Milestones

Estimates assume one focused engineer. Anchored to a 2026-09-15 start. **M1 is a hard gate** — nothing after it is verifiable until it passes.

| # | Milestone | Days | Target | Exit criteria |
| --- | --- | --- | --- | --- |
| **M1** | **Build green** | 0.5 | Sep 15 | `BUILD SUCCEEDED`. `springButtonStyle` extension added. All 6 interpolation bugs fixed. Dead files removed. App launches, menu-bar only, no stray window. |
| **M2** | Identity & shell | 1.5 | Sep 16–17 | `PRODUCT_NAME = Flowmodora`. Bundle ID frozen. App icon + accent colour shipped. Menu-bar template icon. Info.plist cleaned. Entitlements added. |
| **M3** | Render architecture | 2 | Sep 18–19 | `clockTick` deleted. Single `TimelineView`. Wake observer added. Profiler shows static chrome no longer re-rendering. |
| **M4** | Native Liquid Glass | 2 | Sep 22–23 | `LiquidGlassModifier.swift` deleted. `.glassEffect` / `.buttonStyle(.glass)` adopted. Glass stacking resolved to one layer. Reduce-transparency + reduce-motion handled. |
| **M5** | Navigation & layout | 1.5 | Sep 24–25 | One navigation model. Unsatisfiable frame constraints gone. Appearance setting actually applied. |
| **M6** | Motion pass | 1 | Sep 26 | Phase transitions animated ≤200 ms ease-out. Ring advances continuously. Slow-motion review passed. |
| **M7** | Focus logs + task factor | 2.5 | Sep 29–Oct 1 | Outbox drains. Real payloads. `TaskFactor` implemented + tested. Interrupted-session policy decided and documented. |
| **M8** | Dashboard | 2 | Oct 2–3 | Swift Charts. Sparse-day gap fixed. All five periods correct. |
| **M9** | Test hardening | 3 | Oct 6–8 | Spec §44 timer/analytics/persistence coverage. Three UI flows automated. Calendar-boundary tests green. |
| **M10** | Supabase sync | 4 | Oct 9–14 | SDK integrated. Schema applied. RLS tested as wrong user. Keychain tokens. Offline/reconnect/duplicate/conflict all proven. |
| **M11** | Widget | 2 | Oct 15–16 | Real target. App Group. Live data. Light + dark verified. |
| **M12** | Release hardening | 2 | Oct 19–20 | Accessibility pass. Spec §56 Definition of Done walked item by item. Docs updated. |

**Critical path:** M1 → M3 → M4 → M6 (UI quality). M7 → M8 → M10 (backend) can run in parallel after M3.
**Total:** ~24 working days, roughly 5 calendar weeks.

### Suggested commit sequencing

M1 should be **one small commit** touching only the build blocker and the interpolation bugs. It is the highest-value, lowest-risk change in the entire plan and should not be bundled with anything else.

---

## Risk Assessment & Mitigation

| # | Risk | Likelihood | Impact | Mitigation |
| --- | --- | --- | --- | --- |
| R1 | **Further build errors hide behind the first one.** `xcodebuild` stops early; there may be more unresolved symbols. | High | Medium | Fix M1, rebuild immediately, iterate to zero before estimating anything downstream. Treat all estimates after M1 as provisional until the build is green. |
| R2 | **`MACOSX_DEPLOYMENT_TARGET = 26.5` eliminates almost the entire installed base.** Only users on the newest macOS can run it. | Certain | High | Make this an explicit, recorded decision. It is what unlocks native Liquid Glass, so it may well be correct — but it must be a *choice*, not an accident. The `if #available(macOS 13.0, *)` guards in `Services.swift` are already dead code under it. |
| R3 | **Bundle-ID change orphans user data.** Alters the SwiftData store path, login-item registration and UserDefaults suite. | Medium | High | Decide in M2, before any distribution. If the app has already run on a real machine, write a migration or accept the reset knowingly. |
| R4 | **Native Liquid Glass rendering differs from the hand-rolled version.** Visual regression in a look the user has already seen. | Medium | Medium | Screenshot before/after in both appearances. API availability is verified; only aesthetics are uncertain. |
| R5 | **Removing `clockTick` breaks an unnoticed dependency.** Four view bodies read it. | Medium | Medium | Migrate one view at a time; confirm each still ticks before moving on. |
| R6 | **Supabase integration bloats scope.** M10 is the largest block and touches auth, Keychain, RLS and conflict handling. | High | Medium | Ship M1–M9 as a fully usable local-first app first. Spec §2 requires it to work with no network, no account and no server — so sync can slip without blocking release. |
| R7 | **RLS not genuinely tested.** Policies exist in SQL but have never been exercised. | High | **Critical** | Test as an unauthenticated client *and* as a different authenticated user. Spec §46. Never treat client-side filtering as the boundary. |
| R8 | **Outbox table has grown unboundedly in any existing install.** Never drained since inception. | High | Medium | Fix the drain and add a one-time cleanup in M7. |
| R9 | **`FLOWMODORA_PLAN.md` actively contradicts this plan.** It mandates `.ultraThinMaterial` and forbids the approach now recommended. | Certain | Medium | Update that document as part of M4 so the next agent isn't handed obsolete instructions. Note its warning against manual `NSVisualEffectView` remains sound. |
| R10 | **"Task factor" scope creep into a productivity score.** Directly forbidden by spec §48. | Medium | Medium | The Overview's restrained definition is the contract. Anything beyond factual aggregates requires an explicit product decision. |
| R11 | **Swift 5.0 language mode** while spec §3 demands strict concurrency. | Certain | Low | Enable Approachable Concurrency and `MainActor` default isolation, then migrate to Swift 6 mode. Follow `write-swift` §16: app layer first, fix warnings cheapest-first, never combine with a refactor. Schedule after M9. |
| R12 | **Widget is a from-scratch build, not a fix.** No target, no entitlement, no shared state. | Certain | Low | Treated as greenfield in M11. Kept last because it is the least load-bearing feature. |

### Standing constraints (do not violate)

- App stays menu-bar resident. `LSUIElement` remains `true`.
- Name is **Flowmodora**, everywhere.
- Both Flowmodoro (count-up, ratio-derived break) and Pomodoro (fixed intervals) are preserved. Neither methodology is privileged.
- Local-first. Starting a timer, recording a session and viewing analytics must never touch the network.
- No performance change may alter timer mathematics. The timestamp-derived engine is correct today — render optimisations must not regress it.

---

## Appendix — Verified findings ledger

Every item below was confirmed against the source tree or the macOS 26.5 SDK on 2026-09-13.

### P0 — blocks everything

| # | File:line | Finding |
| --- | --- | --- |
| 1 | `Features/UI/FlowmodoraTimerView.swift:59` | `.springButtonStyle()` undefined — **BUILD FAILED**. 10 call sites. |
| 2 | `Core/StatisticsEngine.swift:89-93` | 4 unescaped interpolations. `.compact` is the default style → literal text in History, Statistics, footer. |
| 3 | `Core/Services.swift:26` | Notification identifier not interpolated → constant ID; each schedule replaces the last. |
| 4 | `Core/Services.swift:137` | Sync status string not interpolated. |
| 5 | `Assets.xcassets/AppIcon.appiconset/` | Contents.json declares 10 slots, contains 0 images. |
| 6 | `Assets.xcassets/AccentColor.colorset/` | No colour value defined. |
| 7 | `project.pbxproj` | `PRODUCT_NAME = $(TARGET_NAME)` → ships as `flowmodoro`. |
| 8 | `project.pbxproj` | No widget target. `WidgetExtension/` unreferenced (`grep -c` → 0). |
| 9 | `Core/AppStore.swift:162-173` | Outbox written on every save, **never drained**. Unbounded growth. |
| 10 | `Core/Services.swift:130-139` | `LocalSyncEngine` is a row counter. No Supabase SDK in the project. |

### P1 — quality and performance

| # | File:line | Finding |
| --- | --- | --- |
| 11 | `flowmodoroApp.swift:60` + `ContentView.swift:60` | Two redundant 500 ms poll loops both incrementing `clockTick`. |
| 12 | `ContentView.swift:174`, `FlowmodoraTimerView.swift:174,196` | `clockTick` read in 4 bodies → full-tree invalidation ~4×/sec over stacked materials. |
| 13 | `Features/UI/LiquidGlassModifier.swift:11-12` | `.shadow()` before `.clipShape()` — shadow is clipped away. |
| 14 | `ContentView.swift:59`, `FlowmodoraTimerView.swift:12,60` | `.liquidGlassStyle()` stacked 3 deep. Violates `apple-design` §12. |
| 15 | `Features/UI/LiquidGlassModifier.swift:9` | Hardcoded `.white.opacity(0.2)` stroke — wrong in light mode. |
| 16 | SDK verified | `GlassEffectContainer`, `.glassEffect(...)`, `.buttonStyle(.glass/.glassProminent)` all typecheck on macOS 26.5. |
| 17 | `ContentView.swift:10` vs `:250,296,341` | Popover fixed at 360×560 hosts views declaring `minWidth: 620`. Unsatisfiable. |
| 18 | `flowmodoroApp.swift:22` | `WindowGroup` is the first scene in an `LSUIElement` app. |
| 19 | `flowmodoroApp.swift:34-47` vs `ContentView.swift:18` | Duplicate navigation; `openWindow` captured at `:16`, never called. |
| 20 | `FlowmodoraTimerView.swift:27` | `.animation(.linear, value: progress)` on 500 ms-quantised input → stepping ring. |
| 21 | `FlowmodoraTimerView.swift:180` | Flowmodoro `progress` hardcoded to `1.0` — permanently full ring. |
| 22 | `ContentView.swift:317` | `appearance` picker exists; no `.preferredColorScheme` anywhere. Dead setting. |
| 23 | codebase-wide | No `accessibilityReduceMotion` / `ReduceTransparency` handling. |
| 24 | `Core/Services.swift:94-96` | Hotkey registration failure returns silently. Spec §42 violation. |
| 25 | `ContentView.swift` | `pomodoroAutoStartFocus` used by the engine, has no UI control. |
| 26 | `ContentView.swift` | Global hotkeys hardcoded ⌘⌥S/P/X; spec §39 requires a Shortcuts section. |

### P2 — correctness, hygiene, coverage

| # | File:line | Finding |
| --- | --- | --- |
| 27 | `Core/TimerEngine.swift:40-47` | Completion fires only from the UI poll loop. No `NSWorkspace.didWakeNotification` observer. |
| 28 | `Core/StatisticsEngine.swift:33,47` | `interrupted` sessions excluded from all stats but shown in History — silent discrepancy. |
| 29 | `Core/StatisticsEngine.swift:60-71` | `dailyFocus` omits zero-session days → sparse chart misreads. |
| 30 | `Core/TimerEngine.swift:50` | `startFocus` silently no-ops with no task; hotkey path gives no feedback. |
| 31 | `ContentView.swift:279-283` | Hand-rolled `GeometryReader` bars where Swift Charts is native and shorter. |
| 32 | `project.pbxproj` | `SWIFT_VERSION = 5.0`; spec §3 requires strict concurrency. |
| 33 | `project.pbxproj` | No `CODE_SIGN_ENTITLEMENTS` — no sandbox, no App Group. |
| 34 | `Info.plist:9-41` | Xcode template junk: `com.example.plain-text` document type, "Example Text" UTI. |
| 35 | `flowmodoro/test.swift` | Dead file containing a second `@main struct TestApp`. |
| 36 | `flowmodoro/patch_contentview.swift` | Dead one-off codemod script. |
| 37 | `flowmodoroUITests/flowmodoroUITests.swift` | Pure boilerplate; `testExample()` asserts nothing. |
| 38 | `flowmodoroTests/flowmodoroTests.swift` | 4 genuine tests — keep. Spec §44 requires substantially more. |
| 39 | `docs/ARCHITECTURE_DECISIONS.md` | Missing ADRs for: deployment target 26.5, UserDefaults-vs-SwiftData split, start-date attribution, interrupted-session policy. |
