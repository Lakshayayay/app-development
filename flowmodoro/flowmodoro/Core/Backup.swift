import Foundation

/// A portable, human-readable copy of everything Flowmodora stores, written
/// as JSON to a folder the user picked (see `Backups`). Plain value copies of
/// the SwiftData models, so the file format never depends on SwiftData.
/// Only live rows are included — nothing is soft-deleted in practice.
struct BackupFile: Codable {
    static let currentVersion = 1

    var version = BackupFile.currentVersion
    var exportedAt: Date
    var tasks: [TaskEntry]
    var sessions: [SessionEntry]
    var settings: SettingsEntry

    // Fields added in a later version must be Optional, so older files still
    // decode — the same rule TimerSnapshot follows.
    struct TaskEntry: Codable {
        var id: UUID
        var title: String
        var isCompleted: Bool
        var createdAt: Date
        var completedAt: Date?
        var updatedAt: Date
        var parentID: UUID?
        var timeResetAt: Date?
    }

    struct SessionEntry: Codable {
        var id: UUID
        var taskID: UUID?
        var mode: String
        var startedAt: Date
        var endedAt: Date?
        var focusedDuration: TimeInterval
        var plannedDuration: TimeInterval?
        var breakDuration: TimeInterval?
        var completed: Bool
        var interrupted: Bool
        var createdAt: Date
        var updatedAt: Date
    }

    /// Every setting except Launch at Login, which belongs to each Mac, not to
    /// the data.
    struct SettingsEntry: Codable {
        var selectedMode: String
        var selectedTaskID: UUID?
        var notificationsEnabled: Bool
        var soundEnabled: Bool
        var appearance: String
        var flowBreakRatio: Double
        var flowAutoStartBreak: Bool
        var pomodoroWorkDuration: TimeInterval
        var pomodoroShortBreakDuration: TimeInterval
        var pomodoroLongBreakDuration: TimeInterval
        var pomodoroCyclesBeforeLongBreak: Int
        var pomodoroAutoStartBreak: Bool
        var pomodoroAutoStartFocus: Bool
        var showPauseButton: Bool
        var dailyFocusGoal: TimeInterval
        var pomodoroRounds: Int
    }
}

extension BackupFile.TaskEntry {
    init(_ task: FocusTask) {
        self.init(
            id: task.id, title: task.title, isCompleted: task.isCompleted,
            createdAt: task.createdAt, completedAt: task.completedAt, updatedAt: task.updatedAt,
            parentID: task.parentID, timeResetAt: task.timeResetAt
        )
    }

    func makeModel() -> FocusTask {
        let task = FocusTask(title: title, parentID: parentID, now: createdAt)
        task.id = id
        task.isCompleted = isCompleted
        task.completedAt = completedAt
        task.updatedAt = updatedAt
        task.timeResetAt = timeResetAt
        return task
    }
}

extension BackupFile.SessionEntry {
    init(_ session: FocusSessionRecord) {
        self.init(
            id: session.id, taskID: session.taskID, mode: session.modeRawValue,
            startedAt: session.startedAt, endedAt: session.endedAt,
            focusedDuration: session.focusedDuration, plannedDuration: session.plannedDuration,
            breakDuration: session.breakDuration, completed: session.completed,
            interrupted: session.interrupted, createdAt: session.createdAt, updatedAt: session.updatedAt
        )
    }

    func makeModel() -> FocusSessionRecord {
        let record = FocusSessionRecord(
            id: id, taskID: taskID, mode: FocusMode(rawValue: mode) ?? .flowmodoro,
            startedAt: startedAt, endedAt: endedAt, focusedDuration: focusedDuration,
            plannedDuration: plannedDuration, breakDuration: breakDuration,
            completed: completed, interrupted: interrupted, now: createdAt
        )
        record.updatedAt = updatedAt
        return record
    }
}

extension BackupFile.SettingsEntry {
    init(_ s: AppSettingsRecord) {
        self.init(
            selectedMode: s.selectedModeRawValue, selectedTaskID: s.selectedTaskID,
            notificationsEnabled: s.notificationsEnabled, soundEnabled: s.soundEnabled,
            appearance: s.appearanceRawValue, flowBreakRatio: s.flowBreakRatio,
            flowAutoStartBreak: s.flowAutoStartBreak, pomodoroWorkDuration: s.pomodoroWorkDuration,
            pomodoroShortBreakDuration: s.pomodoroShortBreakDuration,
            pomodoroLongBreakDuration: s.pomodoroLongBreakDuration,
            pomodoroCyclesBeforeLongBreak: s.pomodoroCyclesBeforeLongBreak,
            pomodoroAutoStartBreak: s.pomodoroAutoStartBreak, pomodoroAutoStartFocus: s.pomodoroAutoStartFocus,
            showPauseButton: s.showPauseButton, dailyFocusGoal: s.dailyFocusGoal, pomodoroRounds: s.pomodoroRounds
        )
    }

    func apply(to s: AppSettingsRecord) {
        s.selectedModeRawValue = selectedMode
        s.selectedTaskID = selectedTaskID
        s.notificationsEnabled = notificationsEnabled
        s.soundEnabled = soundEnabled
        s.appearanceRawValue = appearance
        s.flowBreakRatio = flowBreakRatio
        s.flowAutoStartBreak = flowAutoStartBreak
        s.pomodoroWorkDuration = pomodoroWorkDuration
        s.pomodoroShortBreakDuration = pomodoroShortBreakDuration
        s.pomodoroLongBreakDuration = pomodoroLongBreakDuration
        s.pomodoroCyclesBeforeLongBreak = pomodoroCyclesBeforeLongBreak
        s.pomodoroAutoStartBreak = pomodoroAutoStartBreak
        s.pomodoroAutoStartFocus = pomodoroAutoStartFocus
        s.showPauseButton = showPauseButton
        s.dailyFocusGoal = dailyFocusGoal
        s.pomodoroRounds = pomodoroRounds
        s.updatedAt = .now
    }
}

enum BackupError: LocalizedError {
    case unreadable
    case newerVersion
    case timerRunning

    var errorDescription: String? {
        switch self {
        case .unreadable: "That file isn't a Flowmodora backup, or it's damaged."
        case .newerVersion: "This backup was made by a newer version of Flowmodora. Update the app to restore it."
        case .timerRunning: "Stop the timer before restoring a backup."
        }
    }
}

/// Where backups go and how they're written: one file per day in a folder the
/// user picked, newest 14 kept. The app is sandboxed, so a security-scoped
/// bookmark (stored in `defaults`) keeps access to that folder across launches.
/// No bookmark in `defaults` = backups off — which is what tests and
/// `-demoData` rely on, since they run with their own defaults.
struct Backups {
    let defaults: UserDefaults

    static let keepDays = 14
    private static let bookmarkKey = "backupFolderBookmark"
    private static let lastBackupKey = "lastBackupAt"
    nonisolated private static let dateStyle = Date.ISO8601FormatStyle(includingFractionalSeconds: true)

    var folderURL: URL? {
        guard let data = defaults.data(forKey: Self.bookmarkKey) else { return nil }
        var isStale = false
        guard let url = try? URL(resolvingBookmarkData: data, options: .withSecurityScope, bookmarkDataIsStale: &isStale) else { return nil }
        if isStale, let fresh = try? url.bookmarkData(options: .withSecurityScope) {
            defaults.set(fresh, forKey: Self.bookmarkKey)
        }
        return url
    }

    var lastBackupAt: Date? { defaults.object(forKey: Self.lastBackupKey) as? Date }

    func setFolder(_ url: URL) throws {
        defaults.set(try url.bookmarkData(options: .withSecurityScope), forKey: Self.bookmarkKey)
    }

    /// Writes today's file atomically, then deletes all but the newest
    /// `keepDays` backups. Returns nil (and writes nothing) if no folder has
    /// been chosen.
    @discardableResult
    func write(_ file: BackupFile, now: Date = .now) throws -> URL? {
        guard let folder = folderURL else { return nil }
        let scoped = folder.startAccessingSecurityScopedResource()
        defer { if scoped { folder.stopAccessingSecurityScopedResource() } }

        let day = now.formatted(Date.ISO8601FormatStyle(timeZone: .current).year().month().day())
        let url = folder.appending(path: "Flowmodora-\(day).json")
        try Self.encoder().encode(file).write(to: url, options: .atomic)
        defaults.set(now, forKey: Self.lastBackupKey)

        // Only ever touches files this app named, never anything else in the folder.
        let backups = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.wholeMatch(of: /Flowmodora-\d{4}-\d{2}-\d{2}\.json/) != nil }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
        for old in backups.dropFirst(Self.keepDays) {
            try? FileManager.default.removeItem(at: old)
        }
        return url
    }

    static func read(from url: URL) throws -> BackupFile {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        struct VersionProbe: Decodable { var version: Int }
        guard let data = try? Data(contentsOf: url),
              let probe = try? JSONDecoder().decode(VersionProbe.self, from: data)
        else { throw BackupError.unreadable }
        guard probe.version <= BackupFile.currentVersion else { throw BackupError.newerVersion }
        guard let file = try? decoder().decode(BackupFile.self, from: data) else { throw BackupError.unreadable }
        return file
    }

    /// Pretty-printed with sorted keys, so the file reads well and diffs
    /// cleanly if the folder is ever kept in git. Dates are ISO 8601 with
    /// milliseconds.
    static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(date.formatted(dateStyle))
        }
        return encoder
    }

    static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            try Date(decoder.singleValueContainer().decode(String.self), strategy: dateStyle)
        }
        return decoder
    }

    /// Suggested starting folder for the chooser. The sandbox points
    /// NSHomeDirectory() at the app's container, so the real home — where
    /// iCloud Drive lives — comes from the user database instead.
    static var iCloudDriveURL: URL? {
        guard let home = getpwuid(getuid())?.pointee.pw_dir else { return nil }
        return URL(fileURLWithPath: String(cString: home)).appending(path: "Library/Mobile Documents/com~apple~CloudDocs")
    }
}
