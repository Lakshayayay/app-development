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

extension HeatmapCell {
    /// Short month name for a week column that contains a month's 1st, else nil.
    static func monthLabel(for week: [HeatmapCell], calendar: Calendar = .current) -> String? {
        guard let first = week.first(where: { calendar.component(.day, from: $0.date) == 1 }) else { return nil }
        return calendar.shortMonthSymbols[calendar.component(.month, from: first.date) - 1]
    }
}

private struct HeatmapSection: View {
    let cells: [HeatmapCell]
    let goal: TimeInterval
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovered: HeatmapCell?
    @State private var hasAppeared = false

    private static let gap: CGFloat = 3
    private static let labelWidth: CGFloat = 30
    /// The one opacity ramp: every cell and the legend read from it, so the
    /// color theme (the app's accent) can't drift between them.
    private static let levels: [Double] = [0.08, 0.3, 0.55, 0.8, 1.0]

    var body: some View {
        let weeks = stride(from: 0, to: cells.count, by: 7).map { Array(cells[$0..<min($0 + 7, cells.count)]) }
        let today = Calendar.current.startOfDay(for: .now)
        let total = cells.reduce(0) { $0 + $1.duration }
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Past year").font(.headline)
                Spacer()
                Text("\(formatDuration(total)) focused").font(.caption).foregroundStyle(.secondary)
            }
            VStack(spacing: Self.gap) {
                monthRow(weeks)
                ForEach(0..<7, id: \.self) { row in
                    HStack(spacing: Self.gap) {
                        Color.clear.frame(width: Self.labelWidth)
                            .overlay(alignment: .leading) {
                                if let label = weekdayLabel(row) { Text(label).font(.caption2).foregroundStyle(.secondary).fixedSize() }
                            }
                        ForEach(weeks.indices, id: \.self) { week in
                            if week * 7 + row < cells.count {
                                let cell = cells[week * 7 + row]
                                HeatmapDot(level: level(cell.duration), isToday: cell.date == today, isHovered: hovered == cell,
                                           hasAppeared: hasAppeared, animates: !reduceMotion, delay: Double(week) * 0.01)
                                    .equatable()
                                    .contentShape(Rectangle().inset(by: -Self.gap / 2))
                                    .onHover { inside in
                                        // Moving between cells fires leave-then-enter; a stale leave must not clear the new cell.
                                        if inside { hovered = cell } else if hovered == cell { hovered = nil }
                                    }
                            } else {
                                Color.clear.aspectRatio(1, contentMode: .fit)
                            }
                        }
                    }
                    // A scaled-up hovered cell must draw over its neighbours, rows included.
                    .zIndex(hovered?.weekday == row ? 1 : 0)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Past year focus heatmap")
            .accessibilityValue("\(formatDuration(total)) focused")
            HStack {
                Text(caption).font(.caption).foregroundStyle(.secondary)
                Spacer()
                legend
            }
        }
        .onAppear { hasAppeared = true }
    }

    /// Month names sit over the week column holding the 1st; the text is an
    /// overlay, so it overflows right across the empty columns after it.
    private func monthRow(_ weeks: [[HeatmapCell]]) -> some View {
        HStack(spacing: Self.gap) {
            Color.clear.frame(width: Self.labelWidth)
            ForEach(weeks.indices, id: \.self) { week in
                Color.clear.frame(maxWidth: .infinity)
                    .overlay(alignment: .leading) {
                        if let label = HeatmapCell.monthLabel(for: weeks[week]) {
                            Text(label).font(.caption2).foregroundStyle(.secondary).fixedSize()
                        }
                    }
            }
        }
        .frame(height: 12)
    }

    private var legend: some View {
        HStack(spacing: 4) {
            Text("Less")
            ForEach(Self.levels, id: \.self) { opacity in
                RoundedRectangle(cornerRadius: 2).fill(Color.accentColor.opacity(opacity)).frame(width: 10, height: 10)
            }
            Text("More")
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
        .accessibilityHidden(true)
    }

    /// Rows run from the locale's first weekday; label Mon/Wed/Fri-style rows 1, 3, 5.
    private func weekdayLabel(_ row: Int) -> String? {
        guard row % 2 == 1 else { return nil }
        let calendar = Calendar.current
        return calendar.shortWeekdaySymbols[(calendar.firstWeekday - 1 + row) % 7]
    }

    private var caption: String {
        guard let hovered else { return "Hover a day to see its total." }
        return "\(hovered.date.formatted(date: .abbreviated, time: .omitted)) · \(formatDuration(hovered.duration))"
    }

    private func level(_ duration: TimeInterval) -> Double {
        guard goal > 0 else { return duration > 0 ? 0.6 : Self.levels[0] }
        switch duration {
        case 0: return Self.levels[0]
        case ..<(goal / 2): return Self.levels[1]
        case ..<goal: return Self.levels[2]
        case ..<(goal * 2): return Self.levels[3]
        default: return Self.levels[4]
        }
    }
}

/// One day. Equatable so a hover change re-renders only the two cells involved.
private struct HeatmapDot: View, Equatable {
    let level: Double
    let isToday: Bool
    let isHovered: Bool
    let hasAppeared: Bool
    let animates: Bool
    let delay: Double

    var body: some View {
        RoundedRectangle(cornerRadius: 3)
            .fill(Color.accentColor.opacity(level))
            .overlay {
                // Static ring: marks "now" without an endless pulse pulling focus.
                if isToday { RoundedRectangle(cornerRadius: 4).strokeBorder(Color.accentColor, lineWidth: 1.5).padding(-2) }
            }
            .aspectRatio(1, contentMode: .fit)
            .scaleEffect(isHovered ? 1.5 : (hasAppeared ? 1 : 0.3))
            .opacity(hasAppeared ? 1 : 0)
            .animation(animates ? .spring(duration: 0.4, bounce: 0.3).delay(delay) : nil, value: hasAppeared)
            .animation(animates ? .spring(duration: 0.25, bounce: 0.4) : nil, value: isHovered)
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
