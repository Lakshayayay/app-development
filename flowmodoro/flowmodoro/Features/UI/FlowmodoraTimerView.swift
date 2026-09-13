import SwiftUI

struct FlowmodoraTimerView: View {
    @Environment(AppStore.self) private var store
    
    var body: some View {
        VStack(spacing: 32) {
            timerCircle
            controls
        }
        .padding(24)
        .liquidGlassStyle()
    }
    
    private var timerCircle: some View {
        ZStack {
            Circle()
                .stroke(Color.secondary.opacity(0.2), lineWidth: 12)
            
            Circle()
                .trim(from: 0, to: progress)
                .stroke(
                    Color.accentColor,
                    style: StrokeStyle(lineWidth: 12, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(.linear, value: progress)
            
            VStack(spacing: 8) {
                Text(displayValue(at: .now))
                    .font(.system(size: 48, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(.primary)
                    .contentTransition(.numericText())
                
                Text(subtitle)
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 250, height: 250)
    }
    
    @ViewBuilder private var controls: some View {
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
                .liquidGlassStyle()
                .disabled(store.settings.selectedTaskID == nil)
            }
            
        case .focus:
            HStack(spacing: 20) {
                if store.settings.showPauseButton {
                    Button { store.timer.pause() } label: {
                        Image(systemName: "pause.fill")
                            .font(.title2)
                            .frame(width: 50, height: 50)
                    }
                    .springButtonStyle()
                    .liquidGlassStyle()
                }
                
                Button { store.timer.stop() } label: {
                    Image(systemName: "stop.fill")
                        .font(.title2)
                        .frame(width: 50, height: 50)
                }
                .springButtonStyle()
                .liquidGlassStyle()
                
                if store.timer.mode == .pomodoro {
                    Button { store.timer.skip() } label: {
                        Image(systemName: "forward.fill")
                            .font(.title2)
                            .frame(width: 50, height: 50)
                    }
                    .springButtonStyle()
                    .liquidGlassStyle()
                }
            }
            
        case .pausedFocus:
            HStack(spacing: 20) {
                Button { store.timer.resume() } label: {
                    Image(systemName: "play.fill")
                        .font(.title2)
                        .frame(width: 50, height: 50)
                }
                .springButtonStyle()
                .liquidGlassStyle()
                
                Button { store.timer.stop() } label: {
                    Image(systemName: "stop.fill")
                        .font(.title2)
                        .frame(width: 50, height: 50)
                }
                .springButtonStyle()
                .liquidGlassStyle()
            }
            
        case .breakTimer:
            HStack(spacing: 20) {
                Button { store.timer.pause() } label: {
                    Image(systemName: "pause.fill")
                        .font(.title2)
                        .frame(width: 50, height: 50)
                }
                .springButtonStyle()
                .liquidGlassStyle()
                
                Button { store.timer.skip() } label: {
                    Image(systemName: "forward.fill")
                        .font(.title2)
                        .frame(width: 50, height: 50)
                }
                .springButtonStyle()
                .liquidGlassStyle()
            }
            
        case .pausedBreak:
            HStack(spacing: 20) {
                Button { store.timer.resume() } label: {
                    Image(systemName: "play.fill")
                        .font(.title2)
                        .frame(width: 50, height: 50)
                }
                .springButtonStyle()
                .liquidGlassStyle()
                
                Button { store.timer.skip() } label: {
                    Image(systemName: "forward.fill")
                        .font(.title2)
                        .frame(width: 50, height: 50)
                }
                .springButtonStyle()
                .liquidGlassStyle()
            }
            
        case .suggestedBreak:
            HStack(spacing: 20) {
                Button { store.timer.startSuggestedBreak() } label: {
                    Image(systemName: "cup.and.saucer.fill")
                        .font(.title2)
                        .frame(width: 60, height: 60)
                }
                .springButtonStyle()
                .liquidGlassStyle()
                
                Button { store.timer.reset() } label: {
                    Image(systemName: "xmark")
                        .font(.title2)
                        .frame(width: 50, height: 50)
                }
                .springButtonStyle()
                .liquidGlassStyle()
            }
        }
    }
    
    private var progress: Double {
        let _ = store.clockTick
        switch store.timer.phase {
        case .idle, .suggestedBreak:
            return 0
        case .focus, .pausedFocus:
            if store.timer.mode == .flowmodoro {
                return 1.0 // Flowmodoro counts up, no fixed end to show a decreasing circle for
            } else {
                let remaining = store.timer.countdownRemaining()
                let total = store.timer.snapshot.plannedDuration ?? 25 * 60
                return total > 0 ? remaining / total : 0
            }
        case .breakTimer, .pausedBreak:
            let remaining = store.timer.countdownRemaining()
            let total = store.timer.snapshot.breakKind == .long 
                ? (store.settings.pomodoroLongBreakDuration ) 
                : (store.timer.mode == .flowmodoro ? (store.timer.snapshot.suggestedBreak ?? remaining) : store.settings.pomodoroShortBreakDuration )
            return total > 0 ? remaining / total : 0
        }
    }
    
    private func displayValue(at date: Date) -> String {
        let _ = store.clockTick
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
