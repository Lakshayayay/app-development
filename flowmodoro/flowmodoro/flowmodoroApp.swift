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
        WindowGroup(id: "mainWindow") {
            ContentView().environment(store)
        }
        .windowStyle(.hiddenTitleBar)

        MenuBarExtra {
            ContentView().environment(store)
        } label: {
            MenuBarLabel().environment(store)
        }
        .menuBarExtraStyle(.window)

        Window("History", id: "history") {
            HistoryView().environment(store)
        }
        .defaultSize(width: 460, height: 520)

        Window("Statistics", id: "statistics") {
            StatisticsView().environment(store)
        }
        .defaultSize(width: 680, height: 540)

        Window("Settings", id: "settings") {
            SettingsView().environment(store)
        }
        .defaultSize(width: 540, height: 660)
    }
}

struct MenuBarLabel: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        let _ = store.clockTick
        HStack(spacing: 5) {
            if store.timer.isActive { Image(systemName: store.timer.isBreakRunning ? "cup.and.saucer" : "circle.fill").imageScale(.small) }
            Text(label(at: .now)).monospacedDigit()
        }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(500))
                store.refreshTimer()
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
