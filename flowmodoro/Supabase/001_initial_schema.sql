create extension if not exists pgcrypto;

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

create table if not exists public.tasks (
  id uuid primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  title text not null check (char_length(title) between 1 and 200),
  is_completed boolean not null default false,
  completed_at timestamptz,
  created_at timestamptz not null,
  updated_at timestamptz not null,
  deleted_at timestamptz
);

create table if not exists public.focus_sessions (
  id uuid primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  task_id uuid,
  mode text not null check (mode in ('flowmodoro', 'pomodoro')),
  started_at timestamptz not null,
  ended_at timestamptz,
  focused_duration double precision not null check (focused_duration >= 0),
  planned_duration double precision,
  break_duration double precision,
  completed boolean not null,
  interrupted boolean not null default false,
  created_at timestamptz not null,
  updated_at timestamptz not null,
  deleted_at timestamptz
);

create table if not exists public.user_settings (
  id uuid primary key,
  user_id uuid not null unique references auth.users(id) on delete cascade,
  payload jsonb not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

alter table public.profiles enable row level security;
alter table public.tasks enable row level security;
alter table public.focus_sessions enable row level security;
alter table public.user_settings enable row level security;

create policy "users can manage own profile" on public.profiles for all using (auth.uid() = id) with check (auth.uid() = id);
create policy "users can manage own tasks" on public.tasks for all using (auth.uid() = user_id) with check (auth.uid() = user_id);
create policy "users can manage own sessions" on public.focus_sessions for all using (auth.uid() = user_id) with check (auth.uid() = user_id);
create policy "users can manage own settings" on public.user_settings for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

create index if not exists focus_sessions_user_started_idx on public.focus_sessions(user_id, started_at desc);
