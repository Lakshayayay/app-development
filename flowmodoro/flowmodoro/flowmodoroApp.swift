import SwiftData
import SwiftUI

@main
struct FlowmodoraApp: App {
    private let modelContainer: ModelContainer
    @State private var store: AppStore

    init() {
        let container: ModelContainer
        do {
            container = try Self.makeContainer()
        } catch {
            fatalError("Flowmodora could not create its local database: \(error)")
        }
        let applicationStore = AppStore(modelContainer: container)
        modelContainer = container
        _store = State(wrappedValue: applicationStore)
    }

    private static func makeContainer() throws -> ModelContainer {
        #if DEBUG
        if DemoData.isActive { return try DemoData.container() }
        #endif
        return try ModelContainer(for: FocusTask.self, FocusSessionRecord.self, AppSettingsRecord.self, OutboxEntry.self)
    }

    var body: some Scene {
        // MenuBarExtra must be the first scene: with LSUIElement = true, SwiftUI
        // materializes whichever scene is declared first at launch. A WindowGroup
        // declared first opens an uninvited window on an app that must stay
        // menu-bar-only.
        MenuBarExtra {
            ContentView().environment(store)
                .preferredColorScheme(preferredColorScheme)
        } label: {
            MenuBarLabel().environment(store)
        }
        .menuBarExtraStyle(.window)

        Window("History", id: "history") {
            HistoryView().environment(store)
                .preferredColorScheme(preferredColorScheme)
        }
        .defaultSize(width: 460, height: 520)

        Window("Statistics", id: "statistics") {
            StatisticsView().environment(store)
                .preferredColorScheme(preferredColorScheme)
        }
        .defaultSize(width: 720, height: 780)

        Window("Settings", id: "settings") {
            SettingsView().environment(store)
                .preferredColorScheme(preferredColorScheme)
        }
        .defaultSize(width: 540, height: 660)
    }

    private var preferredColorScheme: ColorScheme? {
        switch store.settings.appearance {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

struct MenuBarLabel: View {
    @Environment(AppStore.self) private var store
    @AppStorage("hideMenuBarTimer") private var hideTimer = false

    var body: some View {
        // Deliberately NOT a TimelineView here: using one as the root/label
        // view of a MenuBarExtra hangs NSStatusItem's AutoLayout pass
        // indefinitely (confirmed via a stack sample — the process pegs one
        // CPU core forever inside NSStatusItem._adjustLength / NSISEngine
        // constraint solving and never returns). A plain, structurally
        // stable HStack driven by TimerEngine's shared clock avoids it.
        HStack(spacing: 4) {
            Image(systemName: symbol ?? "timer")
                .imageScale(.small)
                .opacity(symbol == nil ? 0 : 1)
            Text(text(at: store.timer.now) ?? "")
                .monospacedDigit()
                .foregroundStyle(isPaused ? .secondary : .primary)
        }
    }

    private var isPaused: Bool {
        store.timer.phase == .pausedFocus || store.timer.phase == .pausedBreak
    }

    // Hidden while a timer is running replaces the icon+digits with a
    // steaming-cup glyph — distinct from the break state's plain cup —
    // instead of blanking the status item, which would look broken.
    private var isHidden: Bool { hideTimer && store.timer.phase != .idle }

    // Idle shows an icon only and focus shows digits only — one signal at a
    // time instead of stacking a state icon on every state.
    private var symbol: String? {
        if isHidden { return "cup.and.heat.waves" }
        switch store.timer.phase {
        case .idle: return "timer"
        case .breakTimer, .pausedBreak, .suggestedBreak: return "cup.and.saucer"
        case .focus, .pausedFocus: return nil
        }
    }

    private func text(at date: Date) -> String? {
        if isHidden { return nil }
        switch store.timer.phase {
        case .idle, .suggestedBreak: return nil
        case .focus where store.timer.mode == .flowmodoro:
            return formatDuration(store.timer.focusDuration(at: date), style: .timer)
        case .focus, .pausedFocus, .breakTimer, .pausedBreak:
            return formatDuration(store.timer.countdownRemaining(at: date), style: .timer)
        }
    }
}
