import Foundation
import Observation
import Supabase

enum SupabaseConfig {
    static let projectURL = URL(string: "https://bqprlhfixgcpfhxthrss.supabase.co")!

    // The anon/publishable key is designed to be embedded in client apps —
    // Row Level Security (see Supabase/001_initial_schema.sql) is the actual
    // authorization boundary, not this key's secrecy. A service-role key must
    // never appear here or anywhere in this app.
    static let anonKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImJxcHJsaGZpeGdjcGZoeHRocnNzIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODkyMjA4MTMsImV4cCI6MjEwNDc5NjgxM30.vhQ_OzFlV5noHfZHaug9hbSqQN6h_XvkEwzM58K_m9Y"
}

// MARK: - Row shapes matching Supabase/001_initial_schema.sql

struct SupabaseTaskRow: Codable, Sendable {
    let id: UUID
    let user_id: UUID
    let title: String
    let is_completed: Bool
    let completed_at: Date?
    let created_at: Date
    let updated_at: Date
    let deleted_at: Date?
}

struct SupabaseFocusSessionRow: Codable, Sendable {
    let id: UUID
    let user_id: UUID
    let task_id: UUID?
    let mode: String
    let started_at: Date
    let ended_at: Date?
    let focused_duration: Double
    let planned_duration: Double?
    let break_duration: Double?
    let completed: Bool
    let interrupted: Bool
    let created_at: Date
    let updated_at: Date
    let deleted_at: Date?
}

/// user_settings.payload is jsonb — a nested Codable value serializes into it directly.
struct SupabaseSettingsPayload: Codable, Sendable {
    let selectedMode: String
    let flowBreakRatio: Double
    let pomodoroWorkDuration: Double
    let pomodoroShortBreakDuration: Double
    let pomodoroLongBreakDuration: Double
    let pomodoroCyclesBeforeLongBreak: Int
    let dailyFocusGoal: Double
}

struct SupabaseSettingsRow: Codable, Sendable {
    let id: UUID
    let user_id: UUID
    let payload: SupabaseSettingsPayload
    let updated_at: Date
}

struct SyncStatus: Equatable, Sendable {
    var isConfigured = false
    var pendingChanges = 0
    var message = "Local only"
}

/// Owns the Supabase client, auth state, and the transport half of sync.
/// AppStore owns the outbox and decides *what* to send; this decides how to
/// authenticate and how to actually reach Supabase. Local-first is preserved:
/// nothing here is on the path of starting a timer or recording a session —
/// see docs/SYNC.md.
@MainActor
@Observable
final class LocalSyncEngine {
    private(set) var status = SyncStatus()
    private(set) var currentEmail: String?
    private(set) var currentUserID: UUID?

    let client: SupabaseClient
    private var authTask: Task<Void, Never>?

    init() {
        client = SupabaseClient(supabaseURL: SupabaseConfig.projectURL, supabaseKey: SupabaseConfig.anonKey)
        let authClient = client.auth
        authTask = Task { [weak self] in
            for await (_, session) in authClient.authStateChanges {
                guard let self else { return }
                self.currentEmail = session?.user.email
                self.currentUserID = session?.user.id
                self.status.isConfigured = session != nil
                self.refresh(pendingChanges: self.status.pendingChanges)
            }
        }
    }

    func refresh(pendingChanges: Int) {
        status.pendingChanges = pendingChanges
        status.message = status.isConfigured
            ? (pendingChanges == 0 ? "Synced" : "\(pendingChanges) change\(pendingChanges == 1 ? "" : "s") queued")
            : "Local only"
    }

    // MARK: - Auth (email OTP — see docs/SYNC.md for the dashboard step this needs)

    func requestSignIn(email: String) async throws {
        try await client.auth.signInWithOTP(email: email)
    }

    func verifySignIn(email: String, code: String) async throws {
        try await client.auth.verifyOTP(email: email, token: code, type: .email)
    }

    func signOut() async throws {
        try await client.auth.signOut()
    }

    // MARK: - Transport

    func upsertTask(_ row: SupabaseTaskRow) async throws {
        try await client.from("tasks").upsert(row).execute()
    }

    func upsertFocusSession(_ row: SupabaseFocusSessionRow) async throws {
        try await client.from("focus_sessions").upsert(row).execute()
    }

    func upsertSettings(_ row: SupabaseSettingsRow) async throws {
        try await client.from("user_settings").upsert(row).execute()
    }
}
