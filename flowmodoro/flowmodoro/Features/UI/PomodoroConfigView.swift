import SwiftUI

/// Pomodoro interval and round controls bound directly to AppSettingsRecord.
/// Shared by the popover's pre-start card and Settings → Focus, so the two can
/// never disagree. TimerEngine.startFocus freezes these values when Start is pressed.
struct PomodoroConfigFields: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        LabeledContent("Focus") { DurationStepper(value: setting(\.pomodoroWorkDuration)) }
        LabeledContent("Short break") { DurationStepper(value: setting(\.pomodoroShortBreakDuration)) }
        LabeledContent("Long break") { DurationStepper(value: setting(\.pomodoroLongBreakDuration)) }
        LabeledContent("Long break every") {
            Stepper(value: setting(\.pomodoroCyclesBeforeLongBreak), in: 1...12) {
                Text("\(store.settings.pomodoroCyclesBeforeLongBreak) rounds").monospacedDigit()
            }
        }
        LabeledContent("Rounds") {
            Stepper(value: setting(\.pomodoroRounds), in: 0...24) {
                Text(store.settings.pomodoroRounds == 0 ? "Until stopped" : "\(store.settings.pomodoroRounds)").monospacedDigit()
            }
        }
        LabeledContent("Auto-start breaks") { toggle(\.pomodoroAutoStartBreak) }
        LabeledContent("Auto-continue") { toggle(\.pomodoroAutoStartFocus) }
    }

    private func toggle(_ keyPath: ReferenceWritableKeyPath<AppSettingsRecord, Bool>) -> some View {
        Toggle("", isOn: setting(keyPath)).labelsHidden().toggleStyle(.switch).controlSize(.mini)
    }

    private func setting<T>(_ keyPath: ReferenceWritableKeyPath<AppSettingsRecord, T>) -> Binding<T> {
        Binding(get: { store.settings[keyPath: keyPath] },
                set: { store.settings[keyPath: keyPath] = $0; store.updateSettings() })
    }
}

/// B Focused-style pre-start step: a one-line summary of the plan that expands
/// to edit it. Shown only while idle in Pomodoro mode, so the running flow is
/// unchanged. A plain tile rather than glass: the popover is already the one
/// glass pane (see FlowmodoraTimerView).
struct PomodoroConfigCard: View {
    @Environment(AppStore.self) private var store
    @State private var isExpanded = false

    var body: some View {
        VStack(spacing: 8) {
            Button { withExpandCollapse { isExpanded.toggle() } } label: {
                HStack {
                    Text(summary)
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .contentTransition(.numericText())
                    Spacer()
                    Image(systemName: "chevron.down")
                        .rotationEffect(.degrees(isExpanded ? 180 : 0))
                        .foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
            }
            .springButtonStyle()
            .accessibilityLabel("Pomodoro plan: \(summary)")
            .accessibilityHint(isExpanded ? "Collapse" : "Expand to edit")

            if isExpanded {
                VStack(spacing: 6) { PomodoroConfigFields() }
                    .font(.subheadline)
                    .labeledContentStyle(RowLabeledContentStyle())
                    .transition(.expandCollapse)
            }
        }
        .padding(10)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .sensoryFeedback(.levelChange, trigger: summary)
    }

    private var summary: String {
        let s = store.settings
        let rounds = s.pomodoroRounds == 0 ? "∞" : "\(s.pomodoroRounds)"
        return "\(formatDuration(s.pomodoroWorkDuration)) focus · \(formatDuration(s.pomodoroShortBreakDuration)) break · \(rounds) rounds"
    }
}

/// Label on the leading edge, control on the trailing edge, as a grouped Form row lays them out, for use outside a Form.
private struct RowLabeledContentStyle: LabeledContentStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack { configuration.label; Spacer(); configuration.content }
    }
}
