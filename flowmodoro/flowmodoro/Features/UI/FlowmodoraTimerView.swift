import SwiftUI

struct FlowmodoraTimerView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var glassNamespace

    var body: some View {
        // No outer glass surface here: this view is only ever nested inside
        // FlowmodoraPopover, which is already the one structural glass pane.
        // Stacking a second translucent surface on top of it collapses
        // legibility (apple-design §12). Only the buttons below get their own
        // glass — lighter material drawing attention to what's interactive.
        VStack(spacing: 14) {
            TimerRing()
            if showsConfig {
                PomodoroConfigCard()
                    .transition(.expandCollapse)
            }
            controls
        }
        .animation(reduceMotion ? nil : .expandCollapse, value: showsConfig)
    }

    private var showsConfig: Bool {
        store.timer.phase == .idle && store.settings.selectedMode == .pomodoro
    }

    private var shouldShowHint: Bool {
        store.timer.phase == .idle && store.settings.selectedTaskID == nil
    }

    /// The only part of the timer UI that reads the 1 Hz clock. With it split
    /// out, a tick re-renders just this view; FlowmodoraTimerView.body and its
    /// glass controls no longer depend on `timer.now`.
    private struct TimerRing: View {
        @Environment(AppStore.self) private var store
        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        @AppStorage("hideMenuBarTimer") private var hideTimer = false

        var body: some View {
            // Driven by TimerEngine.now — its shared 1 Hz clock, ticking only
            // while a timer is actually running — instead of a TimelineView
            // rebuilding this subtree on its own schedule (previously ticked
            // even while idle/paused). The ring still animates the gap between
            // ticks itself, so 1 Hz reads as continuous.
            let now = store.timer.now
            let progress = progress(at: now)
            return Button {
                hideTimer.toggle()
            } label: {
                ZStack {
                    Circle()
                        .stroke(Color.secondary.opacity(0.2), lineWidth: 12)

                    Circle()
                        .trim(from: 0, to: progress)
                        .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 12, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .opacity(isPaused ? 0.5 : 1)
                        .animation(reduceMotion ? nil : .linear(duration: 1), value: progress)
                        // Each Flowmodoro hour is a new view, so the ring restarts
                        // from empty instead of animating backwards around the
                        // whole lap.
                        .id(lap(at: now))

                    VStack(spacing: 8) {
                        Text(displayValue(at: now))
                            .font(.system(size: 40, weight: .bold, design: .rounded).monospacedDigit())
                            .foregroundStyle(.primary)
                            .contentTransition(.numericText())
                            // Keyed on phase, not on the ticking value itself, so
                            // this only rolls on a real discontinuity (start,
                            // stop, skip) — a normal per-second tick hard-swaps,
                            // the way a real clock does.
                            .animation(reduceMotion ? nil : .smooth(duration: 0.3), value: store.timer.phase)

                        Text(subtitle)
                            .font(.headline)
                            .foregroundStyle(.secondary)

                        // Always present (opacity-gated, not conditionally
                        // inserted) so this never changes the ring's height —
                        // see 877978a on popover resize from conditional views.
                        Image(systemName: "cup.and.heat.waves")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .opacity(hideTimer ? 1 : 0)
                    }
                }
                .frame(width: 220, height: 220)
                .scaleEffect(1.02) // visual-only, keeps layout (and popover size) unchanged
                .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .help(hideTimer ? "Show timer in menu bar" : "Hide timer from menu bar")
            .accessibilityLabel(hideTimer ? "Show timer in menu bar" : "Hide timer from menu bar")
            .accessibilityValue(displayValue(at: now))
        }

        private func lap(at date: Date) -> Int {
            guard store.timer.mode == .flowmodoro else { return 0 }
            return Int(store.timer.focusDuration(at: date) / 3600)
        }

        private var isPaused: Bool {
            store.timer.phase == .pausedFocus || store.timer.phase == .pausedBreak
        }

        private func progress(at date: Date) -> Double {
            switch store.timer.phase {
            case .idle, .suggestedBreak:
                return 0
            case .focus, .pausedFocus:
                if store.timer.mode == .flowmodoro {
                    // No fixed end to show a fraction of, so the ring reads like
                    // a minute hand instead: one full lap per hour of focus.
                    let elapsed = store.timer.focusDuration(at: date)
                    return elapsed.truncatingRemainder(dividingBy: 3600) / 3600
                } else {
                    let remaining = store.timer.countdownRemaining(at: date)
                    let total = store.timer.snapshot.plannedDuration ?? 25 * 60
                    return total > 0 ? remaining / total : 0
                }
            case .breakTimer, .pausedBreak:
                let remaining = store.timer.countdownRemaining(at: date)
                let total = store.timer.snapshot.plannedDuration ?? remaining
                return total > 0 ? remaining / total : 0
            }
        }

        private func displayValue(at date: Date) -> String {
            switch store.timer.phase {
            case .focus where store.timer.mode == .flowmodoro:
                return formatDuration(store.timer.focusDuration(at: date), style: .timer)
            case .focus, .pausedFocus, .breakTimer, .pausedBreak:
                return formatDuration(store.timer.countdownRemaining(at: date), style: .timer)
            case .suggestedBreak:
                return formatDuration(store.timer.snapshot.suggestedBreak ?? 0, style: .timer)
            case .idle:
                // settings.selectedMode, not timer.mode: the snapshot's mode only
                // refreshes on reset(), so it's stale right after switching the picker.
                let upcoming = store.settings.selectedMode == .flowmodoro ? 0 : store.settings.pomodoroWorkDuration
                return formatDuration(upcoming, style: .timer)
            }
        }

        private var subtitle: String {
            switch store.timer.phase {
            case .focus, .pausedFocus:
                guard store.timer.mode == .pomodoro, let rounds = store.timer.snapshot.pomodoroPlan?.rounds, rounds > 0 else { return "" }
                return "Round \((store.timer.snapshot.roundsCompleted ?? 0) + 1) of \(rounds)"
            case .breakTimer, .pausedBreak: return store.timer.snapshot.breakKind == .long ? "Long break" : "Break"
            case .suggestedBreak: return "Suggested break"
            case .idle: return "Ready"
            }
        }
    }

    private struct ControlButton: Identifiable {
        let id: String
        let symbol: String
        var isDisabled = false
        let action: () -> Void
    }

    @ViewBuilder private var controls: some View {
        VStack(spacing: 4) {
            Text("Select a task to begin")
                .font(.caption)
                .foregroundStyle(.secondary)
                .opacity(shouldShowHint ? 1 : 0)
            GlassEffectContainer(spacing: 20) {
                HStack(spacing: 20) {
                    ForEach(activeButtons) { button in
                        Button(action: button.action) {
                            Image(systemName: button.symbol)
                                .font(.title2)
                                .frame(width: 52, height: 52)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .glassEffect(.regular.interactive(), in: .circle)
                        .glassEffectID(button.id, in: glassNamespace)
                        .disabled(button.isDisabled)
                    }
                }
            }
        }
        .animation(reduceMotion ? .easeInOut(duration: 0.2) : .snappy(duration: 0.25), value: store.timer.phase)
    }

    /// One stable identity per role (primary/stop/skip/dismiss) across every
    /// phase, so GlassEffectContainer morphs a button into its next state
    /// instead of cross-fading a removed view and a new one.
    private var activeButtons: [ControlButton] {
        switch store.timer.phase {
        case .idle:
            return [ControlButton(id: "primary", symbol: "play.fill", isDisabled: store.settings.selectedTaskID == nil) {
                store.timer.startFocus(taskID: store.settings.selectedTaskID, mode: store.settings.selectedMode)
            }]
        case .focus:
            var buttons: [ControlButton] = []
            if store.settings.showPauseButton {
                buttons.append(ControlButton(id: "primary", symbol: "pause.fill") { store.timer.pause() })
            }
            buttons.append(ControlButton(id: "stop", symbol: "stop.fill") { store.timer.stop() })
            if store.timer.mode == .pomodoro {
                buttons.append(ControlButton(id: "skip", symbol: "forward.fill") { store.timer.skip() })
            }
            return buttons
        case .pausedFocus:
            return [
                ControlButton(id: "primary", symbol: "play.fill") { store.timer.resume() },
                ControlButton(id: "stop", symbol: "stop.fill") { store.timer.stop() },
            ]
        case .breakTimer:
            return [
                ControlButton(id: "primary", symbol: "pause.fill") { store.timer.pause() },
                ControlButton(id: "skip", symbol: "forward.fill") { store.timer.skip() },
            ]
        case .pausedBreak:
            return [
                ControlButton(id: "primary", symbol: "play.fill") { store.timer.resume() },
                ControlButton(id: "skip", symbol: "forward.fill") { store.timer.skip() },
            ]
        case .suggestedBreak:
            return [
                ControlButton(id: "primary", symbol: "cup.and.saucer.fill") { store.timer.startSuggestedBreak() },
                ControlButton(id: "skip", symbol: "xmark") { store.timer.reset() },
            ]
        }
    }
}
