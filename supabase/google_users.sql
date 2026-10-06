create table if not exists public.google_users (
  user_id text primary key,
  email text not null,
  name text not null default '',
  picture text not null default '',
  created_at timestamptz not null default now(),
  last_login_at timestamptz not null default now()
);

alter table public.google_users enable row level security;
