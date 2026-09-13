# Optional Supabase synchronization

The app is deliberately local-first. SwiftData is authoritative for runtime behavior, history, and statistics. `OutboxEntry` records local changes without blocking the user — but only once sync is actually configured (`LocalSyncEngine.status.isConfigured`, true once a user is signed in). `AppStore.save()` does not queue entries while signed out; earlier builds queued unconditionally, which grew the table forever with rows nothing would ever consume.

## Transport (implemented)

`Core/Supabase.swift` holds the `SupabaseClient` (project URL + anon/publishable key — see the note on that key below) and `LocalSyncEngine`, which owns auth state and the actual upsert calls. `AppStore.attemptSync()` is the drain: it reads every pending `OutboxEntry`, builds the matching row (`SupabaseTaskRow` / `SupabaseFocusSessionRow` / `SupabaseSettingsRow`) from the in-memory `tasks`/`sessions`/`settings` already loaded, upserts it, and deletes the outbox entry only on success. A row that fails (offline, transient error) stays queued — the periodic 1-second timer-refresh loop and every subsequent `save()` retry it. Upserting by the client-generated UUID makes retries idempotent, matching the append-oriented design below.

- Focus sessions are append-oriented and idempotent by `id`; duplicate retries must not create a second row.
- Mutable tasks use last-write-wins by `updated_at` (enforced by re-upserting the full row each time; the server does not currently reject a stale write — see "Not yet implemented" below).
- The app continues to show local data if every remote request fails; nothing in `attemptSync()` blocks the timer, task, or statistics code paths.

## Authentication

Email one-time-code sign-in (`LocalSyncEngine.requestSignIn(email:)` → `Supabase.Auth.signInWithOTP(email:)`, then `verifySignIn(email:code:)` → `Auth.verifyOTP(email:token:type:.email)`), exposed as a small form in Settings → Sync. The Supabase SDK persists the session in the Keychain itself; `LocalSyncEngine` observes `Auth.authStateChanges` to keep `status.isConfigured`, `currentEmail`, and `currentUserID` current, including across relaunches once a session is restored.

**Dashboard step required for this to work as OTP codes, not magic links:** Supabase's default "Magic Link" email template only includes `{{ .ConfirmationURL }}`. Since this app asks the user to type in a code rather than open a link (no custom URL scheme / `onOpenURL` handling exists, by design — that's real added surface area this implementation deliberately avoided), the project's email template must be edited to include `{{ .Token }}` for the emailed code to actually appear: Supabase Dashboard → Authentication → Email Templates → Magic Link. Until that's done, `requestSignIn` will still succeed and an email will still send, but it won't contain a code to type into the app.

## Not yet implemented

- **Conflict resolution**: `attemptSync()` always pushes local state; it does not yet pull remote rows or compare `updated_at` before overwriting. For a single-device user this is harmless. Multi-device last-write-wins (the design this schema was built for) needs a pull path added before that's safe.
- **Soft-delete propagation**: local task/session deletion (`deletedAt`) isn't wired to a remote delete/tombstone yet — there's no delete UI at all in the app currently, so this has no caller yet.
- **RLS verification**: `Supabase/001_initial_schema.sql` enables RLS for every user-owned table and was written before this transport existed. It has not been tested end-to-end against a signed-in and a wrong-signed-in user from this environment (schema application and testing both require dashboard/SQL-editor access this session didn't have). Do this before relying on it for anything real.

The anon/publishable key is meant to be embedded in a client app — Row Level Security is the actual authorization boundary, not the key's secrecy. It lives in `Core/Supabase.swift` (`SupabaseConfig.anonKey`). A service-role key must never be shipped in the macOS bundle or committed anywhere in this repo.
