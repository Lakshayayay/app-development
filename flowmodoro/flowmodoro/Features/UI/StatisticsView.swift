import Charts
import SwiftUI

private extension LinearGradient {
    /// The accent, lifted toward white at the top: more "pop" than a flat
    /// fill while staying the app's single accent hue in light and dark.
    static var barFill: LinearGradient {
        LinearGradient(colors: [Color.accentColor.mix(with: .white, by: 0.3), .accentColor], startPoint: .top, endPoint: .bottom)
    }
}

/// Readout for a selected mark: a Liquid Glass capsule floating over the
/// chart, like the popover's controls. Text stays in primary and secondary
/// colors, never the series color.
private struct ChartCallout: View {
    let title: String
    let detail: String

    var body: some View {
        VStack(spacing: 1) {
            Text(title).font(.callout.weight(.semibold).monospacedDigit())
            Text(detail).font(.caption2).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .glassEffect(.regular, in: .capsule)
    }
}

/// Every section reads only the AppStore properties it needs (dailyTotals,
/// streak, sessionValues, …) — @Observable tracks access per-property, so a
/// timer tick (store.timer.now) never invalidates this screen: nothing here
/// touches it.
struct StatisticsView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var period: StatisticsPeriod = .week

    private static let periods: [StatisticsPeriod] = [.week, .month, .year, .total]

    var body: some View {
        // Everything that scales with history is derived here, once per store
        // write or period change, and passed down as plain values. The sections
        // own their hover/selection state, so a pointer move re-runs only them.
        let values = StatisticsEngine.filteredSessions(store.sessionValues, period: period)
        let goal = store.settings.dailyFocusGoal
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HeroRow()
                HeatmapSection(cells: HeatmapCell.pastYear(store.dailyTotals), goal: goal)
                VStack(alignment: .leading, spacing: 10) {
                    Picker("Period", selection: $period) {
                        ForEach(Self.periods) { Text($0 == .total ? "All" : $0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    ProgressSection(
                        daily: StatisticsEngine.dailyFocus(store.sessionValues, period: period),
                        summary: StatisticsEngine.summary(values),
                        goal: goal
                    )
                    .animation(reduceMotion ? nil : .smooth(duration: 0.25), value: period)
                }
                TaskBreakdownSection(bars: taskBars(values))
            }
            .padding(24)
        }
        .navigationTitle("Statistics")
        .frame(minWidth: 680, minHeight: 720)
    }

    private func taskBars(_ values: [FocusSessionValue]) -> [TaskBar] {
        // Subtask time is already folded into its domain here.
        let sorted = StatisticsEngine.domainTotals(values, parentOf: store.parentOf)
        var bars = sorted.prefix(8).map { TaskBar(name: store.taskTitle(for: $0.taskID), duration: $0.total) }
        let other = sorted.dropFirst(8).reduce(0) { $0 + $1.total }
        if other > 0 { bars.append(TaskBar(name: "Other", duration: other)) }
        return bars
    }
}

private struct TaskBar: Identifiable, Equatable {
    let name: String
    let duration: TimeInterval
    var id: String { name }
}

// MARK: - Hero row

private struct HeroRow: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        HStack(spacing: 12) {
            VStack(spacing: 8) {
                ProgressRing(progress: todayProgress, lineWidth: 8)
                    .frame(width: 64, height: 64)
                    .overlay { Text(formatDuration(store.todayTotal, style: .minutes)).font(.caption.weight(.semibold)) }
                Text("Today").font(.caption).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))

            StatTile(
                title: "Streak",
                value: "\(store.streak.current) day\(store.streak.current == 1 ? "" : "s")",
                detail: "Best \(store.streak.best)",
                symbol: store.streak.current > 0 ? "flame.fill" : "flame",
                tint: store.streak.current > 0 ? .orange : .secondary
            )
            StatTile(title: "This week", value: formatDuration(thisWeek), detail: weekTrend, symbol: "calendar", tint: .accentColor)
        }
    }

    private var todayProgress: Double {
        store.settings.dailyFocusGoal > 0 ? min(1, store.todayTotal / store.settings.dailyFocusGoal) : 0
    }

    private var weekRange: (this: [Date], last: [Date]) {
        let cal = Calendar.current
        let weekStart = cal.dateInterval(of: .weekOfYear, for: .now)?.start ?? cal.startOfDay(for: .now)
        let lastStart = cal.date(byAdding: .day, value: -7, to: weekStart) ?? weekStart
        let lastEnd = cal.date(byAdding: .day, value: -1, to: weekStart) ?? weekStart
        return (StatisticsEngine.days(from: weekStart, through: .now, calendar: cal),
                StatisticsEngine.days(from: lastStart, through: lastEnd, calendar: cal))
    }

    private var thisWeek: TimeInterval { weekRange.this.reduce(0) { $0 + (store.dailyTotals[$1] ?? 0) } }
    private var lastWeek: TimeInterval { weekRange.last.reduce(0) { $0 + (store.dailyTotals[$1] ?? 0) } }

    private var weekTrend: String {
        guard lastWeek > 0 else { return "—" }
        let change = Int(((thisWeek - lastWeek) / lastWeek * 100).rounded())
        return "\(change >= 0 ? "↑" : "↓")\(abs(change))% vs last week"
    }
}

private struct StatTile: View {
    let title: String
    let value: String
    var detail: String?
    var symbol: String?
    var tint: Color = .secondary

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                if let symbol { Image(systemName: symbol).foregroundStyle(tint) }
                Text(title).font(.caption).foregroundStyle(.secondary)
            }
            Text(value).font(.title3.monospacedDigit().weight(.medium))
            if let detail { Text(detail).font(.caption2).foregroundStyle(.secondary) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
    }
}

/// A stripped-down version of the timer ring (Features/UI/FlowmodoraTimerView)
/// for a static value — no ticking clock, no phase-driven animation, so
/// they're kept separate rather than sharing one parameterized view.
private struct ProgressRing: View {
    let progress: Double
    var lineWidth: CGFloat = 10

    var body: some View {
        ZStack {
            Circle().stroke(Color.secondary.opacity(0.2), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(Color.accentColor, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
    }
}

// MARK: - Heatmap

struct HeatmapCell: Identifiable, Equatable {
    let date: Date
    let weekIndex: Int
    let weekday: Int
    let duration: TimeInterval
    var id: Date { date }

    /// 52 trailing weeks from a week start through today, in day order, so a
    /// cell's index is always `weekIndex * 7 + weekday`.
    static func pastYear(_ dailyTotals: [Date: TimeInterval], calendar: Calendar = .current, now: Date = .now) -> [HeatmapCell] {
        let today = calendar.startOfDay(for: now)
        guard let start = calendar.date(byAdding: .day, value: -363, to: today) else { return [] }
        let weekStart = calendar.dateInterval(of: .weekOfYear, for: start)?.start ?? start
        return StatisticsEngine.days(from: weekStart, through: today, calendar: calendar).map { day in
            let offset = calendar.dateComponents([.day], from: weekStart, to: day).day ?? 0
            return HeatmapCell(date: day, weekIndex: offset / 7, weekday: offset % 7, duration: dailyTotals[day] ?? 0)
        }
    }
}

private struct HeatmapSection: View {
    let cells: [HeatmapCell]
    let goal: TimeInterval
    @State private var hovered: HeatmapCell?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Past year").font(.headline)
            Chart(cells) { cell in
                RectangleMark(x: .value("Week", cell.weekIndex), y: .value("Weekday", 6 - cell.weekday))
                    .foregroundStyle(Color.accentColor.opacity(level(cell.duration)))
                    .cornerRadius(3)
            }
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
            .frame(height: 110)
            .chartOverlay { proxy in
                GeometryReader { geo in
                    Rectangle().fill(.clear).contentShape(Rectangle())
                        .onContinuousHover { phase in
                            guard let plotFrame = proxy.plotFrame else { return }
                            var cell: HeatmapCell?
                            if case .active(let location) = phase {
                                let origin = geo[plotFrame].origin
                                if let (week, row) = proxy.value(at: CGPoint(x: location.x - origin.x, y: location.y - origin.y), as: (Int, Int).self),
                                   (0...6).contains(row) {
                                    let index = week * 7 + (6 - row)
                                    cell = cells.indices.contains(index) ? cells[index] : nil
                                }
                            }
                            // Dozens of pointer events land inside one cell; only a new cell re-renders.
                            if cell != hovered { hovered = cell }
                        }
                }
            }
            Text(caption).font(.caption).foregroundStyle(.secondary)
        }
    }

    private var caption: String {
        guard let hovered else { return "Hover a day to see its total. Darker means more focused." }
        return "\(hovered.date.formatted(date: .abbreviated, time: .omitted)) · \(formatDuration(hovered.duration))"
    }

    private func level(_ duration: TimeInterval) -> Double {
        guard goal > 0 else { return duration > 0 ? 0.6 : 0.08 }
        switch duration {
        case 0: return 0.08
        case ..<(goal / 2): return 0.3
        case ..<goal: return 0.55
        case ..<(goal * 2): return 0.8
        default: return 1.0
        }
    }
}

// MARK: - Progress (bars over the selected period)

private struct ProgressSection: View {
    let daily: [DailyFocus]
    let summary: FocusSummary
    let goal: TimeInterval
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selectedDay: Date?
    @State private var hasAppeared = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                StatTile(title: "Focus time", value: formatDuration(summary.total))
                StatTile(title: "Sessions", value: "\(summary.sessions)")
            }
            if daily.allSatisfy({ $0.duration == 0 }) {
                Text("Start a session to see your focus pattern.").foregroundStyle(.secondary)
            } else {
                Chart {
                    ForEach(daily) { day in
                        BarMark(x: .value("Day", day.date, unit: .day),
                                y: .value("Minutes", hasAppeared ? day.duration / 60 : 0))
                            .foregroundStyle(LinearGradient.barFill.opacity(barOpacity(day)))
                            .cornerRadius(4)
                    }
                    RuleMark(y: .value("Goal", goal / 60))
                        .foregroundStyle(.secondary)
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    if let match {
                        RuleMark(x: .value("Day", match.date, unit: .day))
                            .foregroundStyle(Color.secondary.opacity(0.25))
                            .annotation(position: .top, spacing: 4, overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                                ChartCallout(title: formatDuration(match.duration),
                                             detail: match.date.formatted(.dateTime.month(.abbreviated).day()))
                            }
                    }
                }
                .frame(height: 160)
                .chartXSelection(value: Binding(
                    get: { selectedDay },
                    set: { date in
                        let day = date.map { Calendar.current.startOfDay(for: $0) }
                        if day != selectedDay { selectedDay = day }
                    }
                ))
                .onAppear {
                    // Bars rise from the baseline once per window open.
                    withAnimation(reduceMotion ? nil : .spring(duration: 0.3, bounce: 0.2)) { hasAppeared = true }
                }
            }
        }
    }

    private var match: DailyFocus? {
        selectedDay.flatMap { day in daily.first { $0.date == day } }
    }

    private func barOpacity(_ day: DailyFocus) -> Double {
        let base = day.duration >= goal ? 1 : 0.45
        guard let match else { return base }
        return match.date == day.date ? 1 : base * 0.5
    }
}

// MARK: - By task

private struct TaskBreakdownSection: View {
    let bars: [TaskBar]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("By task").font(.headline)
            if bars.isEmpty {
                Text("No sessions in this period yet.").foregroundStyle(.secondary)
            } else {
                Chart(bars) { bar in
                    BarMark(x: .value("Minutes", bar.duration / 60), y: .value("Task", bar.name))
                        .foregroundStyle(Color.accentColor.gradient)
                        .cornerRadius(6)
                        .annotation(position: .trailing, overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                            Text(formatDuration(bar.duration)).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                        }
                }
                .chartXAxis(.hidden) // every bar is labelled directly
                .frame(height: CGFloat(bars.count) * 48 + 12)
            }
        }
    }
}
