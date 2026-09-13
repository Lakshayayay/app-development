# Local data model

## FocusTask

`id`, `title`, completion timestamps, update timestamp, and optional soft-delete timestamp. There are intentionally no tags, projects, notes, due dates, or external IDs in v1.

## FocusSessionRecord

One logical focus interval. Paused time is excluded from `focusedDuration`. `modeRawValue` stores the stable Codable form of `FocusMode`. The session UUID is created before local recording so a future remote upload can be idempotent.

## AppSettingsRecord

Stores user preferences only; it never contains authentication secrets. Supabase tokens belong in Keychain when the remote transport is enabled.

## OutboxEntry

An append-only local intent to upsert a task, settings record, or focus session. It is safe to retry because remote IDs are client-generated UUIDs and the future Supabase contract uses `upsert` on those IDs.

## Migration strategy

Future schema changes should add a new SwiftData model version and `SchemaMigrationPlan`, preserving existing UUIDs and timestamps. Do not silently change the meaning of `focusedDuration` or the calendar attribution rule.
