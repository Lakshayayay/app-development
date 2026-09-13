import Foundation
import SwiftUI
import WidgetKit

struct FlowmodoWidgetEntry: TimelineEntry {
    let date: Date
    let taskTitle: String
    let timerText: String
    let todayText: String
}

struct FlowmodoWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> FlowmodoWidgetEntry {
        FlowmodoWidgetEntry(date: .now, taskTitle: "Deep Work", timerText: "42:18", todayText: "Today 2h 14m")
    }

    func getSnapshot(in context: Context, completion: @escaping (FlowmodoWidgetEntry) -> Void) {
        completion(entry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<FlowmodoWidgetEntry>) -> Void) {
        completion(Timeline(entries: [entry()], policy: .after(.now.addingTimeInterval(60))))
    }

    private func entry() -> FlowmodoWidgetEntry {
        FlowmodoWidgetEntry(date: .now, taskTitle: "Ready to focus", timerText: "—", todayText: "Today 0m")
    }
}

struct FlowmodoWidgetView: View {
    let entry: FlowmodoWidgetEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(entry.taskTitle).font(.headline).lineLimit(1)
            Text(entry.timerText).font(.system(size: 30, weight: .medium, design: .rounded)).monospacedDigit()
            Text(entry.todayText).font(.caption).foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
        .containerBackground(.background, for: .widget)
    }
}

@main
struct FlowmodoWidget: Widget {
    let kind = "FlowmodoWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: FlowmodoWidgetProvider()) { entry in
            FlowmodoWidgetView(entry: entry)
        }
        .configurationDisplayName("Flowmodo")
        .description("See your current focus and today's total.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
