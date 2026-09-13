import SwiftUI

struct FlowmodoraTimerView: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        // No outer glass surface here: this view is only ever nested inside
        // FlowmodoraPopover, which is already the one structural glass pane.
        // Stacking a second translucent surface on top of it collapses
        // legibility (apple-design §12). Only the buttons below get their own
        // glass — lighter material drawing attention to what's interactive.
        VStack(spacing: 32) {
            timerCircle
            controls
        }
        .padding(24)
    }

    private var timerCircle: some View {
        // .animation schedule ticks continuously while running so the ring moves
        // smoothly from real timestamps, and pauses entirely (no wasted frames
        // on a stacked-glass tree) whenever nothing is visually changing.
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !isTicking)) { context in
            ZStack {
                Circle()
                    .stroke(Color.secondary.opacity(0.2), lineWidth: 12)

                if isCountingUp {
                    // Flowmodoro counts up with no fixed end, so a full/empty
                    // fraction can't represent it. A short arc sweeping
                    // continuously reads as "still active" instead of looking
                    // like a completed countdown.
                    Circle()
                        .trim(from: 0, to: 0.16)
                        .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 12, lineCap: .round))
                        .rotationEffect(.degrees(sweepAngle(at: context.date)))
                } else {
                    Circle()
                        .trim(from: 0, to: progress(at: context.date))
                        .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 12, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                }

                VStack(spacing: 8) {
                    Text(displayValue(at: context.date))
                        .font(.system(size: 48, weight: .bold, design: .rounded).monospacedDigit())
                        .foregroundStyle(.primary)
                        .contentTransition(.numericText())

                    Text(subtitle)
                        .font(.headline)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(width: 250, height: 250)
    }

    @ViewBuilder private var controls: some View {
        Group {
            switch store.timer.phase {
            case .idle:
                VStack(spacing: 8) {
                    if store.settings.selectedTaskID == nil {
                        Text("Select a task to begin")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Button {
                        store.timer.startFocus(taskID: store.settings.selectedTaskID, mode: store.settings.selectedMode)
                    } label: {
                        Image(systemName: "play.fill")
                            .font(.title2)
                            .frame(width: 60, height: 60)
                    }
                    .springButtonStyle()
                    .glassEffect(.regular.interactive(), in: .circle)
                    .disabled(store.settings.selectedTaskID == nil)
                }

            case .focus:
                GlassEffectContainer(spacing: 20) {
                    HStack(spacing: 20) {
                        if store.settings.showPauseButton {
                            Button { store.timer.pause() } label: {
                                Image(systemName: "pause.fill")
                                    .font(.title2)
                                    .frame(width: 50, height: 50)
                            }
                            .springButtonStyle()
                            .glassEffect(.regular.interactive(), in: .circle)
                        }

                        Button { store.timer.stop() } label: {
                            Image(systemName: "stop.fill")
                                .font(.title2)
                                .frame(width: 50, height: 50)
                        }
                        .springButtonStyle()
                        .glassEffect(.regular.interactive(), in: .circle)

                        if store.timer.mode == .pomodoro {
                            Button { store.timer.skip() } label: {
                                Image(systemName: "forward.fill")
                                    .font(.title2)
                                    .frame(width: 50, height: 50)
                            }
                            .springButtonStyle()
                            .glassEffect(.regular.interactive(), in: .circle)
                        }
                    }
                }

            case .pausedFocus:
                GlassEffectContainer(spacing: 20) {
                    HStack(spacing: 20) {
                        Button { store.timer.resume() } label: {
                            Image(systemName: "play.fill")
                                .font(.title2)
                                .frame(width: 50, height: 50)
                        }
                        .springButtonStyle()
                        .glassEffect(.regular.interactive(), in: .circle)

                        Button { store.timer.stop() } label: {
                            Image(systemName: "stop.fill")
                                .font(.title2)
                                .frame(width: 50, height: 50)
                        }
                        .springButtonStyle()
                        .glassEffect(.regular.interactive(), in: .circle)
                    }
                }

            case .breakTimer:
                GlassEffectContainer(spacing: 20) {
                    HStack(spacing: 20) {
                        Button { store.timer.pause() } label: {
                            Image(systemName: "pause.fill")
                                .font(.title2)
                                .frame(width: 50, height: 50)
                        }
                        .springButtonStyle()
                        .glassEffect(.regular.interactive(), in: .circle)

                        Button { store.timer.skip() } label: {
                            Image(systemName: "forward.fill")
                                .font(.title2)
                                .frame(width: 50, height: 50)
                        }
                        .springButtonStyle()
                        .glassEffect(.regular.interactive(), in: .circle)
                    }
                }

            case .pausedBreak:
                GlassEffectContainer(spacing: 20) {
                    HStack(spacing: 20) {
                        Button { store.timer.resume() } label: {
                            Image(systemName: "play.fill")
                                .font(.title2)
                                .frame(width: 50, height: 50)
                        }
                        .springButtonStyle()
                        .glassEffect(.regular.interactive(), in: .circle)

                        Button { store.timer.skip() } label: {
                            Image(systemName: "forward.fill")
                                .font(.title2)
                                .frame(width: 50, height: 50)
                        }
                        .springButtonStyle()
                        .glassEffect(.regular.interactive(), in: .circle)
                    }
                }

            case .suggestedBreak:
                GlassEffectContainer(spacing: 20) {
                    HStack(spacing: 20) {
                        Button { store.timer.startSuggestedBreak() } label: {
                            Image(systemName: "cup.and.saucer.fill")
                                .font(.title2)
                                .frame(width: 60, height: 60)
                        }
                        .springButtonStyle()
                        .glassEffect(.regular.interactive(), in: .circle)

                        Button { store.timer.reset() } label: {
                            Image(systemName: "xmark")
                                .font(.title2)
                                .frame(width: 50, height: 50)
                        }
                        .springButtonStyle()
                        .glassEffect(.regular.interactive(), in: .circle)
                    }
                }
            }
        }
        .transition(.opacity)
        .animation(.easeOut(duration: 0.18), value: store.timer.phase)
    }

    private var isTicking: Bool {
        store.timer.phase == .focus || store.timer.phase == .breakTimer
    }

    private var isCountingUp: Bool {
        store.timer.phase == .focus && store.timer.mode == .flowmodoro
    }

    private func sweepAngle(at date: Date) -> Double {
        // One full sweep every 2 seconds — a continuous "still going" cue.
        (date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 2) / 2) * 360
    }

    private func progress(at date: Date) -> Double {
        switch store.timer.phase {
        case .idle, .suggestedBreak:
            return 0
        case .focus, .pausedFocus:
            if store.timer.mode == .flowmodoro {
                return 0 // rendered via the rotating sweep in timerCircle instead
            } else {
                let remaining = store.timer.countdownRemaining(at: date)
                let total = store.timer.snapshot.plannedDuration ?? 25 * 60
                return total > 0 ? remaining / total : 0
            }
        case .breakTimer, .pausedBreak:
            let remaining = store.timer.countdownRemaining(at: date)
            let total = store.timer.snapshot.breakKind == .long
                ? (store.settings.pomodoroLongBreakDuration )
                : (store.timer.mode == .flowmodoro ? (store.timer.snapshot.suggestedBreak ?? remaining) : store.settings.pomodoroShortBreakDuration )
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
            return "00:00"
        }
    }

    private var subtitle: String {
        switch store.timer.phase {
        case .focus, .pausedFocus: return store.taskTitle(for: store.timer.snapshot.taskID)
        case .breakTimer, .pausedBreak: return store.timer.snapshot.breakKind == .long ? "Long break" : "Break"
        case .suggestedBreak: return "Suggested break"
        case .idle: return "Ready"
        }
    }
}
