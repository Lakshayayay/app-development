import Foundation

enum StatisticsPeriod: String, CaseIterable, Identifiable {
    case today = "Today"
    case week = "Week"
    case month = "Month"
    case year = "Year"
    case total = "Total"

    var id: String { rawValue }
}

struct FocusSummary: Sendable, Equatable {
    let total: TimeInterval
    let longest: TimeInterval
    let average: TimeInterval
    let sessions: Int
}

struct DailyFocus: Identifiable, Sendable, Equatable {
    let date: Date
    let duration: TimeInterval
    var id: Date { date }
}

/// Factual per-task aggregates only — total time, counts, and durations
/// traceable directly to FocusSessionRecord rows. Deliberately not a weighted
/// or composite "productivity score": the product spec explicitly rules those
/// out, and every field here is a plain sum/count/average a user can verify
/// by rereading their own History.
struct TaskFactor: Identifiable, Sendable, Equatable {
    let taskID: UUID?
    let totalFocused: TimeInterval
    let sessionCount: Int
    let meanSession: TimeInterval
    let medianSession: TimeInterval
    let interruptedCount: Int
    let lastFocusedAt: Date?
    var id: UUID? { taskID }
}

enum StatisticsEngine {
    // Interrupted sessions still represent real focused time (TimerEngine.skip
    // records the actual elapsed duration up to the point of interruption) and
    // are shown with that duration in History — excluding them here would make
    // the same underlying session tell two different stories on two screens.
    static func filteredSessions(
        _ sessions: [FocusSessionValue],
        period: StatisticsPeriod,
        calendar: Calendar = .current,
        now: Date = .now
    ) -> [FocusSessionValue] {
        guard period != .total else { return sessions }
        let start: Date
        switch period {
        case .today:
            start = calendar.startOfDay(for: now)
        case .week:
            start = calendar.dateInterval(of: .weekOfYear, for: now)?.start ?? calendar.startOfDay(for: now)
        case .month:
            start = calendar.dateInterval(of: .month, for: now)?.start ?? calendar.startOfDay(for: now)
        case .year:
            start = calendar.dateInterval(of: .year, for: now)?.start ?? calendar.startOfDay(for: now)
        case .total:
            return sessions
        }
        return sessions.filter { $0.startedAt >= start }
    }

    static func summary(_ sessions: [FocusSessionValue]) -> FocusSummary {
        let durations = sessions.map(\.focusedDuration)
        return FocusSummary(
            total: durations.reduce(0, +),
            longest: durations.max() ?? 0,
            average: durations.isEmpty ? 0 : durations.reduce(0, +) / Double(durations.count),
            sessions: durations.count
        )
    }

    static func dailyFocus(
        _ sessions: [FocusSessionValue],
        period: StatisticsPeriod,
        calendar: Calendar = .current,
        now: Date = .now
    ) -> [DailyFocus] {
        let grouped = Dictionary(grouping: filteredSessions(sessions, period: period, calendar: calendar, now: now)) {
            calendar.startOfDay(for: $0.startedAt)
        }.mapValues { $0.reduce(0) { $0 + $1.focusedDuration } }

        // Zero-fill every day from the period's start through today, so a
        // quiet day reads as "0m", not as a gap the chart silently skips.
        // .total has no natural start bound, so it stays actual-data-only.
        guard let days = dayRange(for: period, calendar: calendar, now: now) else {
            return grouped.map { DailyFocus(date: $0.key, duration: $0.value) }.sorted { $0.date < $1.date }
        }
        return days.map { DailyFocus(date: $0, duration: grouped[$0] ?? 0) }
    }

    private static func dayRange(for period: StatisticsPeriod, calendar: Calendar, now: Date) -> [Date]? {
        let today = calendar.startOfDay(for: now)
        let start: Date
        switch period {
        case .total: return nil
        case .today: start = today
        case .week: start = calendar.dateInterval(of: .weekOfYear, for: now)?.start ?? today
        case .month: start = calendar.dateInterval(of: .month, for: now)?.start ?? today
        case .year: start = calendar.dateInterval(of: .year, for: now)?.start ?? today
        }
        let startDay = calendar.startOfDay(for: start)
        let dayCount = max(0, calendar.dateComponents([.day], from: startDay, to: today).day ?? 0)
        return (0...dayCount).compactMap { calendar.date(byAdding: .day, value: $0, to: startDay) }
    }

    static func taskFactors(_ sessions: [FocusSessionValue]) -> [TaskFactor] {
        Dictionary(grouping: sessions, by: \.taskID).map { taskID, group in
            let durations = group.map(\.focusedDuration).sorted()
            let total = durations.reduce(0, +)
            let mid = durations.count / 2
            let median: TimeInterval = durations.isEmpty ? 0
                : durations.count.isMultiple(of: 2) ? (durations[mid - 1] + durations[mid]) / 2 : durations[mid]
            return TaskFactor(
                taskID: taskID,
                totalFocused: total,
                sessionCount: group.count,
                meanSession: durations.isEmpty ? 0 : total / Double(durations.count),
                medianSession: median,
                interruptedCount: group.filter(\.interrupted).count,
                lastFocusedAt: group.map(\.startedAt).max()
            )
        }.sorted { $0.totalFocused > $1.totalFocused }
    }
}

func formatDuration(_ duration: TimeInterval, style: DurationStyle = .compact) -> String {
    let seconds = max(0, Int(duration.rounded()))
    let hours = seconds / 3600
    let minutes = (seconds % 3600) / 60
    let remainingSeconds = seconds % 60
    switch style {
    case .timer:
        return String(format: "%02d:%02d:%02d", hours, minutes, remainingSeconds)
    case .compact:
        if hours > 0 { return "\(hours)h \(minutes)m" }
        if minutes > 0 { return "\(minutes)m" }
        return "\(remainingSeconds)s"
    case .minutes:
        return "\(max(1, Int((Double(seconds) / 60).rounded())))m"
    }
}

enum DurationStyle { case timer, compact, minutes }
