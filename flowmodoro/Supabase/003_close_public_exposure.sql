-- Follow-up from the same get_advisors check that produced 002: this one
-- closes an actual security exposure rather than a performance advisory.
-- Not yet applied to the live project — needs an explicit owner go-ahead
-- (see docs/SYNC.md) before running this against the database.

-- daily_focus_logs is a SECURITY DEFINER view over focus_sessions that anon
-- could SELECT: it bypassed RLS and exposed every user's user_id and daily
-- focus totals to anyone holding the app's embedded anon key. Nothing in the
-- app reads it. security_invoker makes it obey the caller's RLS; the revoke
-- removes anon access outright. (Dropping the view is equally fine.)
alter view public.daily_focus_logs set (security_invoker = true);
revoke all on public.daily_focus_logs from anon;

-- public.movies: RLS is off and anon can SELECT/INSERT/DELETE. It isn't
-- Flowmodora's (it came from the pgvector/Gemini migrations) but shares this
-- project and key. Uncomment ONLY after confirming what uses it: RLS with no
-- policies blocks anon/authenticated; service-role access is unaffected.
-- alter table public.movies enable row level security;
