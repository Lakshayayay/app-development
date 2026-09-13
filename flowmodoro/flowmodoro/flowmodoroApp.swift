import SwiftData
import SwiftUI

@main
struct FlowmodoraApp: App {
    private let modelContainer: ModelContainer
    @State private var store: AppStore

    init() {
        let container: ModelContainer
        do {
            container = try ModelContainer(for: FocusTask.self, FocusSessionRecord.self, AppSettingsRecord.self, OutboxEntry.self)
        } catch {
            fatalError("Flowmodora could not create its local database: \(error)")
        }
        let applicationStore = AppStore(modelContainer: container)
        modelContainer = container
        _store = State(wrappedValue: applicationStore)
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
        .defaultSize(width: 680, height: 540)

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
    @State private var now = Date.now

    var body: some View {
        // Deliberately NOT a TimelineView here: using one as the root/label
        // view of a MenuBarExtra hangs NSStatusItem's AutoLayout pass
        // indefinitely (confirmed via a stack sample — the process pegs one
        // CPU core forever inside NSStatusItem._adjustLength / NSISEngine
        // constraint solving and never returns). A plain, structurally
        // stable HStack driven by a small polling Task avoids it.
        HStack(spacing: 5) {
            if store.timer.isActive { Image(systemName: store.timer.isBreakRunning ? "cup.and.saucer" : "circle.fill").imageScale(.small) }
            Text(label(at: now)).monospacedDigit()
        }
        .task {
            while !Task.isCancelled {
                now = .now
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    private func label(at date: Date) -> String {
        switch store.timer.phase {
        case .focus where store.timer.mode == .flowmodoro:
            return formatDuration(store.timer.focusDuration(at: date), style: .timer)
        case .focus, .pausedFocus, .breakTimer, .pausedBreak:
            return formatDuration(store.timer.countdownRemaining(at: date), style: .timer)
        case .suggestedBreak: return "Break"
        case .idle: return "Flowmodora"
        }
    }
}
