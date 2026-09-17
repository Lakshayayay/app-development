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
struct TaskTotal: Sendable, Equatable {
    let today: TimeInterval
    let total: TimeInterval
}

struct Streak: Sendable, Equatable {
    let current: Int
    let best: Int
}

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

    /// One total-per-calendar-day pass — cached once per AppStore.reload()
    /// (see AppStore.dailyTotals) instead of regrouped by every screen that
    /// needs a day bucket (History chart, streak, heatmap).
    static func dailyTotals(_ sessions: [FocusSessionValue], calendar: Calendar = .current) -> [Date: TimeInterval] {
        Dictionary(grouping: sessions) { calendar.startOfDay(for: $0.startedAt) }
            .mapValues { $0.reduce(0) { $0 + $1.focusedDuration } }
    }

    static func dailyFocus(
        _ sessions: [FocusSessionValue],
        period: StatisticsPeriod,
        calendar: Calendar = .current,
        now: Date = .now
    ) -> [DailyFocus] {
        let grouped = dailyTotals(filteredSessions(sessions, period: period, calendar: calendar, now: now), calendar: calendar)

        // Zero-fill every day from the period's start through today, so a
        // quiet day reads as "0m", not as a gap the chart silently skips.
        // .total has no natural start bound, so it stays actual-data-only.
        guard let days = dayRange(for: period, calendar: calendar, now: now) else {
            return grouped.map { DailyFocus(date: $0.key, duration: $0.value) }.sorted { $0.date < $1.date }
        }
        return zeroFilled(grouped, days: days)
    }

    /// Every day in `days`, defaulting missing entries to 0.
    static func zeroFilled(_ grouped: [Date: TimeInterval], days: [Date]) -> [DailyFocus] {
        days.map { DailyFocus(date: $0, duration: grouped[$0] ?? 0) }
    }

    /// Every calendar day from `start` through `end`, inclusive — shared by
    /// the period charts (dayRange below) and the heatmap (52 trailing weeks).
    static func days(from start: Date, through end: Date, calendar: Calendar = .current) -> [Date] {
        let startDay = calendar.startOfDay(for: start)
        let endDay = calendar.startOfDay(for: end)
        let dayCount = max(0, calendar.dateComponents([.day], from: startDay, to: endDay).day ?? 0)
        return (0...dayCount).compactMap { calendar.date(byAdding: .day, value: $0, to: startDay) }
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
        return days(from: start, through: now, calendar: calendar)
    }

    /// A day "counts" once its total meets `goal`. Current streak counts
    /// consecutive counting days ending today; a day still in progress that
    /// hasn't reached goal yet doesn't break the streak — it just isn't
    /// counted yet, so the streak reads as of yesterday until it is.
    static func streak(_ dailyTotals: [Date: TimeInterval], goal: TimeInterval, calendar: Calendar = .current, now: Date = .now) -> Streak {
        guard goal > 0, let earliest = dailyTotals.keys.min() else { return Streak(current: 0, best: 0) }
        let today = calendar.startOfDay(for: now)
        func counts(_ day: Date) -> Bool { (dailyTotals[day] ?? 0) >= goal }

        var best = 0
        var running = 0
        var current = 0
        for day in days(from: earliest, through: today, calendar: calendar) {
            let runningThroughYesterday = running
            if counts(day) {
                running += 1
                best = max(best, running)
            } else {
                running = 0
            }
            if day == today {
                current = counts(today) ? running : runningThroughYesterday
            }
        }
        return Streak(current: current, best: best)
    }

    /// Per-task today/total focused time, cached once per AppStore.reload()
    /// instead of recomputed on every popover render — see AppStore.taskTotals.
    static func taskTotals(_ sessions: [FocusSessionValue], calendar: Calendar = .current, now: Date = .now) -> [UUID: TaskTotal] {
        func sum(_ values: [FocusSessionValue]) -> [UUID: TimeInterval] {
            Dictionary(grouping: values.compactMap { session in session.taskID.map { (session, $0) } }, by: \.1)
                .mapValues { $0.reduce(0) { $0 + $1.0.focusedDuration } }
        }
        let todayByTask = sum(filteredSessions(sessions, period: .today, calendar: calendar, now: now))
        let totalByTask = sum(sessions)
        var result: [UUID: TaskTotal] = [:]
        for taskID in Set(todayByTask.keys).union(totalByTask.keys) {
            result[taskID] = TaskTotal(today: todayByTask[taskID] ?? 0, total: totalByTask[taskID] ?? 0)
        }
        return result
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
        // Subtle by default: m:ss, growing to h:mm:ss only past an hour —
        // no leading zeroes standing in for time that hasn't happened yet.
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, remainingSeconds)
        }
        return String(format: "%d:%02d", minutes, remainingSeconds)
    case .compact:
        if hours > 0 { return "\(hours)h \(minutes)m" }
        if minutes > 0 { return "\(minutes)m" }
        return "\(remainingSeconds)s"
    case .minutes:
        return "\(max(1, Int((Double(seconds) / 60).rounded())))m"
    }
}

enum DurationStyle { case timer, compact, minutes }
