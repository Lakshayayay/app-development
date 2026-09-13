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

enum StatisticsEngine {
    static func filteredSessions(
        _ sessions: [FocusSessionValue],
        period: StatisticsPeriod,
        calendar: Calendar = .current,
        now: Date = .now
    ) -> [FocusSessionValue] {
        guard period != .total else { return sessions.filter { !$0.interrupted } }
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
            return sessions.filter { !$0.interrupted }
        }
        return sessions.filter { !$0.interrupted && $0.startedAt >= start }
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
        }
        return grouped.map { DailyFocus(date: $0.key, duration: $0.value.reduce(0) { $0 + $1.focusedDuration }) }
            .sorted { $0.date < $1.date }
    }

    static func focusByTask(_ sessions: [FocusSessionValue]) -> [(taskID: UUID?, duration: TimeInterval)] {
        Dictionary(grouping: sessions.filter { !$0.interrupted }, by: \.taskID)
            .map { (taskID: $0.key, duration: $0.value.reduce(0) { $0 + $1.focusedDuration }) }
            .sorted { $0.duration > $1.duration }
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
