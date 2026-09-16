import AppKit
import Charts
import SwiftUI

struct ContentView: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        FlowmodoraPopover()
            .environment(store)
            .frame(width: 360)
            .fixedSize(horizontal: false, vertical: true)
    }
}

struct FlowmodoraPopover: View {
    @Environment(AppStore.self) private var store
    @Environment(\.openWindow) private var openWindow
    @State private var showingNewTask = false

    /// openWindow(id:) alone shows the window but never brings it forward:
    /// Flowmodora is LSUIElement (no Dock icon), and an accessory app isn't
    /// auto-activated the way a regular app is when a new window appears —
    /// the window opens behind whatever currently has focus. Every window
    /// this popover opens routes through here so the fix lives in one place.
    private func open(_ id: String) {
        openWindow(id: id)
        // Plain NSApp.activate() (macOS 14's less-forceful replacement for
        // ignoringOtherApps:) did not reliably bring the window forward for
        // this accessory app. Dispatched async so it runs after openWindow's
        // own (also async) window creation, not racing it.
        DispatchQueue.main.async {
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().padding(.vertical, 10)
            taskSection
            Divider().padding(.vertical, 10)
            timerSection
            Spacer(minLength: 12)
            footer
        }
        .padding(18)
        .alert("Flowmodora", isPresented: Binding(get: { store.alertMessage != nil }, set: { if !$0 { store.alertMessage = nil } })) {
            Button("OK") { store.alertMessage = nil }
        } message: { Text(store.alertMessage ?? "") }
    }

    private var header: some View {
        HStack {
            Text(store.timer.phase == .idle ? "Ready to focus" : phaseTitle)
                .font(.title3.weight(.semibold))
            Spacer()
            Picker("Mode", selection: Binding(get: { store.settings.selectedMode }, set: store.setMode)) {
                ForEach(FocusMode.allCases) { mode in Text(mode.title).tag(mode) }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .fixedSize()
            .disabled(store.timer.isActive)
        }
    }

    @ViewBuilder private var taskSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("TASKS").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Spacer()
                Button { showingNewTask = true } label: { Image(systemName: "plus") }
                    .buttonStyle(.plain)
                    .help("New task")
            }
            let activeTasks = store.tasks.filter { !$0.isCompleted }
            let completedTasks = store.tasks.filter(\.isCompleted)
            if activeTasks.isEmpty && completedTasks.isEmpty {
                Button("Create your first task") { showingNewTask = true }
                    .buttonStyle(.bordered)
            } else {
                VStack(spacing: 2) {
                    ForEach(activeTasks) { task in TaskRow(task: task) }
                }
                .animation(.smooth(duration: 0.25), value: activeTasks.map(\.id))
                if !completedTasks.isEmpty {
                    DisclosureGroup("Completed (\(completedTasks.count))") {
                        VStack(spacing: 2) {
                            ForEach(completedTasks) { task in TaskRow(task: task) }
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
        }
        if showingNewTask {
            // createTask already selects the new task — see AppStore.createTask.
            NewTaskInlineView(showingNewTask: $showingNewTask) { title in
                store.createTask(title: title)
            }
        }
    }

    private var timerSection: some View {
        FlowmodoraTimerView()
            .frame(maxWidth: .infinity)
            .padding(.top, 4)
    }

    private var footer: some View {
        HStack {
            Button { open("statistics") } label: {
                HStack(spacing: 4) {
                    Text("Today \(formatDuration(store.todayTotal))")
                    if store.streak.current > 0 {
                        Text("· 🔥 \(store.streak.current)")
                    }
                }
                .font(.subheadline).foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            Spacer()
            Menu {
                Button("History") { open("history") }
                Button("Statistics") { open("statistics") }
                Divider()
                Button("Settings") { open("settings") }
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

/// Selectable, completable row shown in the popover's inline task list —
/// checkbox to complete, title, and today/total focused time (adding the
/// running task's live elapsed time on top of AppStore's cached totals).
struct TaskRow: View {
    @Environment(AppStore.self) private var store
    let task: FocusTask

    private var isSelected: Bool { store.settings.selectedTaskID == task.id }
    private var liveElapsed: TimeInterval {
        guard isSelected, store.timer.phase == .focus || store.timer.phase == .pausedFocus else { return 0 }
        return store.timer.focusDuration(at: store.timer.now)
    }

    var body: some View {
        HStack(spacing: 8) {
            Button { store.toggleTask(task) } label: {
                Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(task.isCompleted ? Color.accentColor : Color.secondary)
            }
            .buttonStyle(.plain)

            Text(task.title)
                .font(.subheadline)
                .strikethrough(task.isCompleted)
                .foregroundStyle(task.isCompleted ? .secondary : .primary)
                .lineLimit(1)

            Spacer(minLength: 8)

            Text(timeLabel)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 5)
        .padding(.horizontal, 6)
        .background(isSelected ? Color.secondary.opacity(0.12) : Color.clear, in: RoundedRectangle(cornerRadius: 6))
        .contentShape(Rectangle())
        .onTapGesture {
            guard !task.isCompleted, isSelected || !store.timer.isActive else { return }
            store.selectTask(task)
        }
    }

    private var timeLabel: String {
        let totals = store.taskTotals[task.id]
        let today = (totals?.today ?? 0) + liveElapsed
        let total = (totals?.total ?? 0) + liveElapsed
        return "\(formatDuration(today)) · \(formatDuration(total))"
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

// StatisticsView lives in Features/UI/StatisticsView.swift.

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
                PomodoroConfigFields()
                Toggle("Show Pause button", isOn: Binding(get: { store.settings.showPauseButton }, set: { store.settings.showPauseButton = $0; store.updateSettings() }))
                HStack {
                    Text("Daily goal"); Spacer()
                    DurationStepper(
                        value: Binding(get: { store.settings.dailyFocusGoal }, set: { store.settings.dailyFocusGoal = $0; store.updateSettings() }),
                        range: 5 * 60...8 * 60 * 60, step: 5 * 60
                    )
                }
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
    var range: ClosedRange<TimeInterval> = 60...7200
    var step: TimeInterval = 60
    var body: some View { Stepper(value: $value, in: range, step: step) { Text(formatDuration(value)) } }
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