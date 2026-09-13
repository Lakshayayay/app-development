# Optional Supabase synchronization

The app is deliberately local-first. SwiftData is authoritative for runtime behavior, history, and statistics. `OutboxEntry` records local changes without blocking the user — but only once sync is actually configured (`LocalSyncEngine.status.isConfigured`). No transport exists yet to drain the outbox, so `AppStore.save()` does not queue entries while sync is unconfigured; earlier builds queued unconditionally, which grew the table forever with rows nothing would ever consume. A future transport should:

1. read pending outbox entries,
2. authenticate with an optional Supabase email session,
3. upsert by the client-generated UUID,
4. apply remote task/settings rows only when `updated_at` is newer,
5. soft-delete with `deleted_at`,
6. remove an outbox entry only after a successful response.

Focus sessions are append-oriented and idempotent by `id`; duplicate retries must not create a second row. Mutable tasks use last-write-wins by `updated_at`. The app must continue to show local data if every remote request fails.

The SQL migration in `Supabase/001_initial_schema.sql` enables RLS for every user-owned table. A publishable client key may be supplied through app configuration; a service-role key must never be shipped in the macOS bundle.
