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
        let applicationStore = AppStore(modelContainer: container, defaults: Self.makeDefaults())
        modelContainer = container
        _store = State(wrappedValue: applicationStore)
    }

    /// Demo data gets its own defaults, so a `-demoData` run never touches
    /// the real timer snapshot or writes into the real backup folder.
    private static func makeDefaults() -> UserDefaults {
        #if DEBUG
        if DemoData.isActive { return UserDefaults(suiteName: "flowmodo.demo")! }
        #endif
        return .standard
    }

    private static func makeContainer() throws -> ModelContainer {
        #if DEBUG
        if DemoData.isActive { return try DemoData.container() }
        #endif
        return try ModelContainer(for: FocusTask.self, FocusSessionRecord.self, AppSettingsRecord.self)
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
        .defaultSize(width: 540, height: 800)
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
            Image(systemName: content.symbol ?? "timer")
                .imageScale(.small)
                .opacity(content.symbol == nil ? 0 : 1)
            Text(content.text ?? "")
                .monospacedDigit()
                .foregroundStyle(isPaused ? .secondary : .primary)
        }
    }

    private var content: MenuBarLabelContent {
        Self.content(
            phase: store.timer.phase,
            mode: store.timer.mode,
            hidden: hideTimer,
            remaining: store.timer.countdownRemaining(at: store.timer.now),
            elapsed: store.timer.focusDuration(at: store.timer.now)
        )
    }

    private var isPaused: Bool {
        store.timer.phase == .pausedFocus || store.timer.phase == .pausedBreak
    }

    /// Hiding applies only to focus: a break should always be legible as a
    /// break instead of looking like the timer was simply hidden.
    static func content(phase: TimerPhase, mode: FocusMode, hidden: Bool, remaining: TimeInterval, elapsed: TimeInterval) -> MenuBarLabelContent {
        let focusIsHidden = hidden && (phase == .focus || phase == .pausedFocus)
        if focusIsHidden { return MenuBarLabelContent(symbol: "cup.and.heat.waves", text: nil) }

        switch phase {
        case .idle:
            return MenuBarLabelContent(symbol: "timer", text: nil)
        case .focus where mode == .flowmodoro:
            return MenuBarLabelContent(symbol: nil, text: formatDuration(elapsed, style: .timer))
        case .focus, .pausedFocus:
            return MenuBarLabelContent(symbol: nil, text: formatDuration(remaining, style: .timer))
        case .breakTimer, .pausedBreak:
            return MenuBarLabelContent(symbol: nil, text: hidden ? "BREAK" : "BREAK \(formatDuration(remaining, style: .timer))")
        case .suggestedBreak:
            return MenuBarLabelContent(symbol: nil, text: "BREAK READY")
        }
    }
}

struct MenuBarLabelContent: Equatable {
    let symbol: String?
    let text: String?
}
