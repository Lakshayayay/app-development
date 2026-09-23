import AppKit
import SwiftUI

struct ContentView: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        FlowmodoraPopover()
            .environment(store)
            .frame(width: 396)
            .fixedSize(horizontal: false, vertical: true)
    }
}

struct FlowmodoraPopover: View {
    @Environment(AppStore.self) private var store
    @Environment(\.openWindow) private var openWindow
    @State private var showingNewTask = false
    @State private var completedExpanded = false

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
                Button { withExpandCollapse { showingNewTask = true } } label: {
                    Image(systemName: "plus")
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                }
                .springButtonStyle()
                .help("New task")
            }
            // Only top-level tasks (domains) list directly; subtasks render
            // inside their domain's TaskGroup.
            let activeTasks = store.tasks.filter { !$0.isCompleted && $0.parentID == nil }
            let completedTasks = store.tasks.filter { $0.isCompleted && $0.parentID == nil }
            if activeTasks.isEmpty && completedTasks.isEmpty {
                Button("Create your first task") { withExpandCollapse { showingNewTask = true } }
                    .buttonStyle(.bordered)
            } else {
                ScrollView {
                    VStack(spacing: 2) {
                        ForEach(activeTasks) { task in TaskGroup(task: task) }
                    }
                    .animation(.expandCollapse, value: activeTasks.map(\.id))
                }
                .scrollBounceBehavior(.basedOnSize)
                .frame(minHeight: 106, maxHeight: 250)
                if !completedTasks.isEmpty {
                    // A custom disclosure, not the native DisclosureGroup, so its
                    // open/close matches every other dropdown's curve exactly
                    // (see Animation.expandCollapse).
                    VStack(alignment: .leading, spacing: 4) {
                        Button { withExpandCollapse { completedExpanded.toggle() } } label: {
                            HStack(spacing: 4) {
                                Text("Completed (\(completedTasks.count))")
                                Image(systemName: "chevron.right")
                                    .font(.caption2.weight(.semibold))
                                    .rotationEffect(.degrees(completedExpanded ? 90 : 0))
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)

                        if completedExpanded {
                            VStack(spacing: 2) {
                                ForEach(completedTasks) { task in TaskGroup(task: task) }
                            }
                            .transition(.expandCollapse)
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .dropdownClip()
                }
            }
        }
        if showingNewTask {
            // createTask already selects the new task — see AppStore.createTask.
            VStack(spacing: 0) {
                NewTaskInlineView(showingNewTask: $showingNewTask) { title in
                    store.createTask(title: title)
                }
            }
            .dropdownClip()
            .transition(.expandCollapse)
        }
    }

    private var timerSection: some View {
        FlowmodoraTimerView()
            .frame(maxWidth: .infinity)
            .padding(.top, 14)
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
                .contentShape(Rectangle())
            }
            .springButtonStyle()
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

/// A top-level task (domain) plus its collapsible checklist of subtasks.
/// Subtasks are plain FocusTasks with `parentID` set — see AppStore.subtasks.
struct TaskGroup: View {
    @Environment(AppStore.self) private var store
    let task: FocusTask
    @State private var isExpanded = false
    @State private var addingSubtask = false

    private var children: [FocusTask] { store.subtasks[task.id] ?? [] }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            TaskRow(task: task, isExpanded: $isExpanded, onAddSubtask: {
                withExpandCollapse {
                    addingSubtask = true
                    isExpanded = true
                }
            })
            if isExpanded {
                VStack(spacing: 2) {
                    ForEach(children) { child in
                        TaskRow(task: child, isExpanded: .constant(false), onAddSubtask: nil)
                            .padding(.leading, 30)
                    }
                    if addingSubtask {
                        NewTaskInlineView(showingNewTask: $addingSubtask, prompt: "Add a subtask…", keepsOpen: true) { title in
                            withExpandCollapse { store.createTask(title: title, parentID: task.id) }
                        }
                        .padding(.leading, 30)
                    }
                }
                .transition(.expandCollapse)
            }
        }
        .dropdownClip()
    }
}

/// Selectable, completable row shown in the popover's inline task list —
/// checkbox to complete, title, and today/total focused time (adding the
/// running task's or subtask's live elapsed time on top of AppStore's cached
/// totals). Used for both top-level tasks (domains) and subtasks.
struct TaskRow: View {
    @Environment(AppStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let task: FocusTask
    /// Only meaningful (and shown) for a top-level task with subtasks.
    @Binding var isExpanded: Bool
    /// Set only for a top-level task's own row — nil for a subtask row.
    var onAddSubtask: (() -> Void)?

    private var isSelected: Bool { store.settings.selectedTaskID == task.id }
    private var isTiming: Bool { store.isTiming(task) }
    private var liveElapsed: TimeInterval {
        guard isTiming else { return 0 }
        return store.timer.focusDuration(at: store.timer.now)
    }
    private var subtaskCount: Int { store.subtasks[task.id]?.count ?? 0 }
    private var isDomain: Bool { task.parentID == nil }

    var body: some View {
        HStack(spacing: 8) {
            Button { store.toggleTask(task) } label: {
                Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(task.isCompleted ? Color.accentColor : Color.secondary)
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .springButtonStyle()
            .accessibilityLabel(task.isCompleted ? "Mark \(task.title) incomplete" : "Complete \(task.title)")

            Button { store.selectTask(task) } label: {
                HStack(spacing: 8) {
                    Text(task.title)
                        .font(.subheadline)
                        .strikethrough(task.isCompleted)
                        .foregroundStyle(task.isCompleted ? .secondary : .primary)
                        .lineLimit(1)
                    if isDomain && subtaskCount > 0 {
                        Text("\(completedSubtaskCount)/\(subtaskCount)")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 8)
                    Text(timeLabel)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .help("\(formattedToday) today · \(formattedTotal) total")
                }
                .contentShape(Rectangle())
            }
            .springButtonStyle()
            // Same rule the old tap-gesture guard enforced.
            .disabled(task.isCompleted || (store.timer.isActive && !isSelected))

            // Reserved slot on every row so the time column stays aligned;
            // only a domain with subtasks gets a visible, hit-testable chevron.
            Button { withExpandCollapse { isExpanded.toggle() } } label: {
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    .frame(width: 16, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .opacity(isDomain && subtaskCount > 0 ? 1 : 0)
            .disabled(!(isDomain && subtaskCount > 0))
            .accessibilityHidden(!(isDomain && subtaskCount > 0))
        }
        .padding(.vertical, 2) // was 5: the 22 pt checkbox target keeps the row height the same
        .padding(.horizontal, 3)
        .background(isSelected ? Color.secondary.opacity(0.12) : Color.clear, in: RoundedRectangle(cornerRadius: 6))
        .animation(reduceMotion ? nil : .snappy(duration: 0.2), value: isSelected)
        .contextMenu {
            if let onAddSubtask {
                Button("Add Subtask") { onAddSubtask() }
            }
            Button("Reset Time") { store.resetTime(task) }
                .disabled(isTiming || (store.taskTotals[task.id]?.total ?? 0) <= 0)
        }
    }

    private var completedSubtaskCount: Int {
        (store.subtasks[task.id] ?? []).filter(\.isCompleted).count
    }

    private var formattedToday: String {
        let totals = store.taskTotals[task.id]
        return formatDuration((totals?.today ?? 0) + liveElapsed)
    }

    private var formattedTotal: String {
        let totals = store.taskTotals[task.id]
        return formatDuration((totals?.total ?? 0) + liveElapsed)
    }

    private var timeLabel: String {
        formattedToday == formattedTotal ? formattedToday : "\(formattedToday) · \(formattedTotal)"
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
        .formStyle(.grouped).padding().navigationTitle("Settings").frame(width: 520, height: 620)
    }

struct DurationStepper: View {
    @Binding var value: TimeInterval
    var range: ClosedRange<TimeInterval> = 60...7200
    var step: TimeInterval = 60
    var body: some View { Stepper(value: $value, in: range, step: step) { Text(formatDuration(value)) } }
}

struct NewTaskInlineView: View {
    @Binding var showingNewTask: Bool
    var prompt = "What are you focusing on?"
    /// Subtasks only: Enter adds and clears the field instead of closing it,
    /// so a whole checklist can be typed in one go. Esc still closes it.
    var keepsOpen = false
    let onSave: (String) -> Void
    @State private var title = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack {
            TextField(prompt, text: $title)
                .textFieldStyle(.roundedBorder)
                .focused($isFocused)
                .onSubmit(save)
            Button("Cancel") { withExpandCollapse { showingNewTask = false } }.buttonStyle(.plain).font(.caption)
            Button("Create") { save() }
                .buttonStyle(.borderedProminent)
                .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(.top, 8)
        .onExitCommand { withExpandCollapse { showingNewTask = false } }
        .task { isFocused = true }
    }

    private func save() {
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        onSave(title)
        if keepsOpen {
            title = ""
            isFocused = true
        } else {
            withExpandCollapse { showingNewTask = false }
        }
    }
}