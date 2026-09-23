#if DEBUG
import Foundation
import SwiftData

/// `-demoData` launch argument (Debug only): an in-memory store seeded with
/// three years of sessions, so Statistics can be profiled at a realistic
/// history size without touching the real database.
enum DemoData {
    static let isActive = CommandLine.arguments.contains("-demoData")

    static func container() throws -> ModelContainer {
        let container = try ModelContainer(
            for: FocusTask.self, FocusSessionRecord.self, AppSettingsRecord.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)
        let tasks = ["Thesis", "Reading", "Code review", "Email", "Design"].map { FocusTask(title: $0) }
        tasks.forEach(context.insert)
        // AppStore only creates a settings row lazily when none exists yet;
        // seed one here with a task selected, otherwise the demo launches
        // idle with nothing for ⌘⌥S to start, blocking manual perf runs.
        let settings = AppSettingsRecord()
        settings.selectedTaskID = tasks[0].id
        context.insert(settings)
        let today = Calendar.current.startOfDay(for: .now)
        // Deterministic, so before/after benchmarks run on identical data.
        for dayOffset in 0..<1_095 {
            guard let day = Calendar.current.date(byAdding: .day, value: -dayOffset, to: today) else { continue }
            for slot in 0..<(dayOffset % 7) {
                let start = day.addingTimeInterval(TimeInterval((8 + slot) * 3_600))
                let duration = TimeInterval(((dayOffset * 7 + slot * 13) % 51 + 10) * 60)
                context.insert(FocusSessionRecord(
                    taskID: tasks[(dayOffset + slot) % tasks.count].id, mode: .pomodoro,
                    startedAt: start, endedAt: start.addingTimeInterval(duration),
                    focusedDuration: duration, plannedDuration: 25 * 60, completed: true
                ))
            }
        }
        try context.save()
        return container
    }
}
#endif
