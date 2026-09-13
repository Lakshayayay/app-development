import AppKit
import Charts
import SwiftUI

struct ContentView: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        FlowmodoraPopover()
            .environment(store)
            .frame(width: 360, height: 560)
    }
}

struct FlowmodoraPopover: View {
    @Environment(AppStore.self) private var store
    @Environment(\.openWindow) private var openWindow
    @State private var showingNewTask = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().padding(.vertical, 14)
            taskSection
            Divider().padding(.vertical, 14)
            timerSection
            Spacer(minLength: 12)
            footer
        }
        .padding(18)
        .glassEffect(.regular, in: .rect(cornerRadius: 16))
        .shadow(color: .black.opacity(0.12), radius: 12, y: 6)
        .alert("Flowmodora", isPresented: Binding(get: { store.alertMessage != nil }, set: { if !$0 { store.alertMessage = nil } })) {
            Button("OK") { store.alertMessage = nil }
        } message: { Text(store.alertMessage ?? "") }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text("FLOWMODORA")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .tracking(1.8)
                Text(store.timer.phase == .idle ? "Ready to focus" : phaseTitle)
                    .font(.title3.weight(.semibold))
            }
            Spacer()
            TimerReadout(store: store, compact: true)
        }
    }

    @ViewBuilder private var taskSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("TASK").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Spacer()
                Button { showingNewTask = true } label: { Image(systemName: "plus") }
                    .buttonStyle(.plain)
                    .help("New task")
            }
            if store.tasks.isEmpty {
                Button("Create your first task") { showingNewTask = true }
                    .buttonStyle(.bordered)
            } else {
                Picker("Task", selection: Binding(get: { store.settings.selectedTaskID }, set: { id in
                    if let id, let task = store.tasks.first(where: { $0.id == id }) { store.selectTask(task) }
                })) {
                    Text("Select a task").tag(UUID?.none)
                    ForEach(store.tasks.filter { !$0.isCompleted }) { task in
                        Text(task.title).tag(Optional(task.id))
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
            }
        }
        if showingNewTask {
            NewTaskInlineView(showingNewTask: $showingNewTask) { title in
                if let task = store.createTask(title: title) {
                    store.selectTask(task)
                }
            }
        }
    }

    private var timerSection: some View {
        VStack(spacing: 14) {
            HStack {
                Text("MODE").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Spacer()
                Picker("Mode", selection: Binding(get: { store.settings.selectedMode }, set: store.setMode)) {
                    ForEach(FocusMode.allCases) { mode in Text(mode.title).tag(mode) }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .disabled(store.timer.isActive)
            }

            FlowmodoraTimerView()
                .frame(maxWidth: .infinity)
                .padding(.top, 10)
        }
    }



    private var footer: some View {
        HStack {
            let today = StatisticsEngine.filteredSessions(store.sessionValues, period: .today)
            Text("Today: \(formatDuration(StatisticsEngine.summary(today).total))")
                .font(.subheadline).foregroundStyle(.secondary)
            Spacer()
            Menu {
                Button("History") { openWindow(id: "history") }
                Button("Statistics") { openWindow(id: "statistics") }
                Divider()
                Button("Settings") { openWindow(id: "settings") }
                Divider()
                Button("Quit Flowmodora") { NSApplication.shared.terminate(nil) }
            } label: { Image(systemName: "ellipsis.circle") }
                .menuStyle(.borderlessButton)
        }
    }

    private var phaseTitle: String {
        switch store.timer.phase {
        case .focus, .pausedFocus: return store.timer.mode == .flowmodoro ? "Focused" : "Focus"
        case .breakTimer, .pausedBreak: return store.timer.snapshot.breakKind == .long ? "Long Break" : "Break"
        case .suggestedBreak: return "Break ready"
        case .idle: return "Ready to focus"
        }
    }
}

struct TimerReadout: View {
    var store: AppStore
    var compact = false

    var body: some View {
        let timerFont: Font = compact ? .headline : .system(size: 42, weight: .medium, design: .rounded)
        TimelineView(.periodic(from: .now, by: 1)) { context in
            VStack(alignment: compact ? .trailing : .center, spacing: compact ? 0 : 4) {
                Text(displayValue(at: context.date))
                    .font(timerFont.monospacedDigit())
                    .contentTransition(.numericText())
                if !compact { Text(subtitle).font(.subheadline).foregroundStyle(.secondary) }
            }
        }
    }

    private func displayValue(at date: Date) -> String {
        switch store.timer.phase {
        case .focus where store.timer.mode == .flowmodoro:
            return formatDuration(store.timer.focusDuration(at: date), style: .timer)
        case .focus, .pausedFocus, .breakTimer, .pausedBreak:
            return formatDuration(store.timer.countdownRemaining(at: date), style: .timer)
        case .suggestedBreak: return "Ready"
        case .idle: return "—"
        }
    }

    private var subtitle: String {
        switch store.timer.phase {
        case .focus, .pausedFocus: return store.taskTitle(for: store.timer.snapshot.taskID)
        case .breakTimer, .pausedBreak: return store.timer.snapshot.breakKind == .long ? "Long break" : "Break"
        case .suggestedBreak: return "Take a breath"
        case .idle: return "Start when you’re ready"
        }
    }
}

struct NewTaskView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    let onSave: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("New task").font(.title2.weight(.semibold))
            TextField("What are you focusing on?", text: $title).textFieldStyle(.roundedBorder).onSubmit(save)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Create") { save() }.buttonStyle(.borderedProminent).disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24).frame(width: 320)
    }

    private func save() {
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        onSave(title)
        dismiss()
    }
}

struct HistoryView: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        List {
            ForEach(store.sessions) { session in
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(store.taskTitle(for: session.taskID)).font(.body.weight(.medium))
                        Text(session.startedAt.formatted(date: .omitted, time: .shortened)).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 3) {
                        Text(formatDuration(session.focusedDuration)).font(.body.monospacedDigit())
                        Text(session.mode.title).font(.caption).foregroundStyle(.secondary)
                    }
                }.padding(.vertical, 4)
            }
        }
        .overlay { if store.sessions.isEmpty { ContentUnavailableView("No sessions yet", systemImage: "clock", description: Text("Completed focus sessions will appear here.")) } }
        .navigationTitle("History").frame(minWidth: 420, minHeight: 420)
    }
}

struct StatisticsView: View {
    @Environment(AppStore.self) private var store
    @State private var period: StatisticsPeriod = .today

    private var values: [FocusSessionValue] { StatisticsEngine.filteredSessions(store.sessionValues, period: period) }
    private var summary: FocusSummary { StatisticsEngine.summary(values) }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Picker("Period", selection: $period) { ForEach(StatisticsPeriod.allCases) { Text($0.rawValue).tag($0) } }.pickerStyle(.segmented)
            HStack(spacing: 12) {
                MetricCard(title: "Focus time", value: formatDuration(summary.total))
                MetricCard(title: "Sessions", value: "\(summary.sessions)")
                MetricCard(title: "Longest", value: formatDuration(summary.longest))
                MetricCard(title: "Average", value: formatDuration(summary.average))
            }
            VStack(alignment: .leading, spacing: 10) {
                Text("Focus by day").font(.headline)
                let daily = StatisticsEngine.dailyFocus(store.sessionValues, period: period)
                if daily.allSatisfy({ $0.duration == 0 }) {
                    Text("Start a session to see your focus pattern.").foregroundStyle(.secondary)
                } else {
                    Chart(daily) { day in
                        BarMark(
                            x: .value("Day", day.date, unit: .day),
                            y: .value("Minutes", day.duration / 60)
                        )
                        .foregroundStyle(Color.accentColor.gradient)
                    }
                    .frame(height: 140)
                }
            }
            VStack(alignment: .leading, spacing: 8) {
                Text("Focus by task").font(.headline)
                ForEach(StatisticsEngine.taskFactors(values)) { factor in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(store.taskTitle(for: factor.taskID))
                            Text("\(factor.sessionCount) session\(factor.sessionCount == 1 ? "" : "s") · avg \(formatDuration(factor.meanSession))")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(formatDuration(factor.totalFocused)).foregroundStyle(.secondary)
                    }
                }
            }
            Spacer()
        }
        .padding(24).navigationTitle("Statistics").frame(minWidth: 620, minHeight: 480)
    }
}

struct MetricCard: View {
    let title: String
    let value: String
    var body: some View {
        VStack(alignment: .leading, spacing: 6) { Text(title).font(.caption).foregroundStyle(.secondary); Text(value).font(.title3.monospacedDigit().weight(.medium)) }
            .frame(maxWidth: .infinity, alignment: .leading).padding(12)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
    }
}

struct SettingsView: View {
    @Environment(AppStore.self) private var store
    @State private var email = ""
    @State private var otpCode = ""
    @State private var awaitingCode = false
    @State private var syncErrorMessage: String?
    @State private var isWorking = false

    var body: some View {
        Form {
            Section("General") {
                Toggle("Launch at Login", isOn: Binding(get: { store.loginItemService.isEnabled }, set: store.setLaunchAtLogin))
                Picker("Appearance", selection: Binding(get: { store.settings.appearance }, set: { store.settings.appearance = $0; store.updateSettings() })) {
                    ForEach(AppearancePreference.allCases) { Text($0.rawValue.capitalized).tag($0) }
                }
                Toggle("Notifications", isOn: Binding(get: { store.settings.notificationsEnabled }, set: { store.settings.notificationsEnabled = $0; store.updateSettings() }))
                Toggle("Sounds", isOn: Binding(get: { store.settings.soundEnabled }, set: { store.settings.soundEnabled = $0; store.updateSettings() }))
            }
            Section("Focus") {
                Picker("Default mode", selection: Binding(get: { store.settings.selectedMode }, set: store.setMode)) {
                    ForEach(FocusMode.allCases) { Text($0.title).tag($0) }
                }
                HStack { Text("Flowmodoro break ratio"); Spacer(); Stepper(value: Binding(get: { store.settings.flowBreakRatio }, set: { store.settings.flowBreakRatio = max(1, $0); store.updateSettings() }), in: 1...20, step: 1) { Text("1:\(Int(store.settings.flowBreakRatio))") } }
                Toggle("Auto-start Flowmodoro break", isOn: Binding(get: { store.settings.flowAutoStartBreak }, set: { store.settings.flowAutoStartBreak = $0; store.updateSettings() }))
                HStack { Text("Pomodoro work"); Spacer(); DurationStepper(value: Binding(get: { store.settings.pomodoroWorkDuration }, set: { store.settings.pomodoroWorkDuration = $0; store.updateSettings() })) }
                HStack { Text("Short break"); Spacer(); DurationStepper(value: Binding(get: { store.settings.pomodoroShortBreakDuration }, set: { store.settings.pomodoroShortBreakDuration = $0; store.updateSettings() })) }
                HStack { Text("Long break"); Spacer(); DurationStepper(value: Binding(get: { store.settings.pomodoroLongBreakDuration }, set: { store.settings.pomodoroLongBreakDuration = $0; store.updateSettings() })) }
                Stepper("Long break after \(store.settings.pomodoroCyclesBeforeLongBreak) cycles", value: Binding(get: { store.settings.pomodoroCyclesBeforeLongBreak }, set: { store.settings.pomodoroCyclesBeforeLongBreak = max(1, $0); store.updateSettings() }), in: 1...12)
                Toggle("Auto-start next break", isOn: Binding(get: { store.settings.pomodoroAutoStartBreak }, set: { store.settings.pomodoroAutoStartBreak = $0; store.updateSettings() }))
                Toggle("Auto-start next focus", isOn: Binding(get: { store.settings.pomodoroAutoStartFocus }, set: { store.settings.pomodoroAutoStartFocus = $0; store.updateSettings() }))
                Toggle("Show Pause button", isOn: Binding(get: { store.settings.showPauseButton }, set: { store.settings.showPauseButton = $0; store.updateSettings() }))
            }
            Section("Sync") {
                Label(store.syncEngine.status.message, systemImage: "externaldrive")
                if let signedInEmail = store.syncEngine.currentEmail {
                    Text("Signed in as \(signedInEmail)").font(.caption).foregroundStyle(.secondary)
                    Button("Sign Out") {
                        isWorking = true
                        Task {
                            defer { isWorking = false }
                            do { try await store.syncEngine.signOut() }
                            catch { syncErrorMessage = "Sign out failed. Try again." }
                        }
                    }
                    .disabled(isWorking)
                } else if awaitingCode {
                    TextField("6-digit code", text: $otpCode)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit(verifyCode)
                    HStack {
                        Button("Verify") { verifyCode() }
                            .disabled(isWorking || otpCode.trimmingCharacters(in: .whitespaces).isEmpty)
                        Button("Cancel") { awaitingCode = false; otpCode = ""; syncErrorMessage = nil }
                            .buttonStyle(.plain)
                    }
                } else {
                    TextField("Email", text: $email)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit(sendCode)
                    Button("Send Code") { sendCode() }
                        .disabled(isWorking || email.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                if let syncErrorMessage {
                    Text(syncErrorMessage).font(.caption).foregroundStyle(.red)
                }
                Text("Flowmodora is local-first. Optional Supabase sync can be configured without affecting timers or analytics.").font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped).padding().navigationTitle("Settings").frame(width: 520, height: 620)
    }

    private func sendCode() {
        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        isWorking = true
        syncErrorMessage = nil
        Task {
            defer { isWorking = false }
            do {
                try await store.syncEngine.requestSignIn(email: trimmed)
                awaitingCode = true
            } catch {
                syncErrorMessage = "Couldn't send a code. Check the address and try again."
            }
        }
    }

    private func verifyCode() {
        let code = otpCode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !code.isEmpty else { return }
        isWorking = true
        syncErrorMessage = nil
        Task {
            defer { isWorking = false }
            do {
                try await store.syncEngine.verifySignIn(email: email.trimmingCharacters(in: .whitespacesAndNewlines), code: code)
                awaitingCode = false
                otpCode = ""
            } catch {
                syncErrorMessage = "That code didn't work. Try again."
            }
        }
    }
}

struct DurationStepper: View {
    @Binding var value: TimeInterval
    var body: some View { Stepper(value: $value, in: 60...7200, step: 60) { Text(formatDuration(value)) } }
}

struct NewTaskInlineView: View {
    @Binding var showingNewTask: Bool
    let onSave: (String) -> Void
    @State private var title = ""

    var body: some View {
        HStack {
            TextField("What are you focusing on?", text: $title)
                .textFieldStyle(.roundedBorder)
                .onSubmit(save)
            Button("Cancel") { showingNewTask = false }.buttonStyle(.plain).font(.caption)
            Button("Create") { save() }
                .buttonStyle(.borderedProminent)
                .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(.top, 8)
    }

    private func save() {
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        onSave(title)
        showingNewTask = false
    }
}