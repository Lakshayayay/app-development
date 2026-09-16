-- Follow-up from the get_advisors check run against the live project
-- (docs/ARCHITECTURE.md's Sync section, "RLS verification" item): confirmed RLS is already
-- enabled on all four Flowmodora tables. This migration only fixes two
-- performance advisories on top of that — no security-behavior change.

-- auth_rls_initplan (WARN): auth.uid() was being re-evaluated per row.
-- Wrapping it in a scalar subquery lets Postgres evaluate it once per
-- statement instead — same policy, same access rules, faster at scale.
-- See: https://supabase.com/docs/guides/database/postgres/row-level-security#call-functions-with-select
drop policy if exists "users can manage own profile" on public.profiles;
create policy "users can manage own profile" on public.profiles
  for all using ((select auth.uid()) = id) with check ((select auth.uid()) = id);

drop policy if exists "users can manage own tasks" on public.tasks;
create policy "users can manage own tasks" on public.tasks
  for all using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);

drop policy if exists "users can manage own sessions" on public.focus_sessions;
create policy "users can manage own sessions" on public.focus_sessions
  for all using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);

drop policy if exists "users can manage own settings" on public.user_settings;
create policy "users can manage own settings" on public.user_settings
  for all using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);

-- unindexed_foreign_keys (INFO): tasks.user_id had no covering index
-- (focus_sessions.user_id is already covered by focus_sessions_user_started_idx).
create index if not exists tasks_user_id_idx on public.tasks(user_id);
