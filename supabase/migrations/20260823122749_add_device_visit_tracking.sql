create table if not exists public.device_visits (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  session_id uuid,
  page_path text not null,
  device_type text,
  device_model text,
  os text,
  os_version text,
  browser text,
  browser_version text,
  user_agent text,
  platform text,
  language text,
  timezone text,
  screen_width integer,
  screen_height integer,
  pixel_ratio numeric(6,2),
  touch_points integer,
  created_at timestamptz not null default now(),
  constraint device_visits_page_path_len check (char_length(page_path) between 1 and 1024),
  constraint device_visits_user_agent_len check (user_agent is null or char_length(user_agent) <= 2048),
  constraint device_visits_device_model_len check (device_model is null or char_length(device_model) <= 256)
);

create index if not exists device_visits_user_created_idx
  on public.device_visits (user_id, created_at desc);
create index if not exists device_visits_session_created_idx
  on public.device_visits (session_id, created_at desc);

alter table public.device_visits enable row level security;

revoke all on table public.device_visits from anon, authenticated;
grant insert on table public.device_visits to authenticated;

drop policy if exists "authenticated users can insert own device visits" on public.device_visits;
create policy "authenticated users can insert own device visits"
  on public.device_visits
  for insert
  to authenticated
  with check ((select auth.uid()) = user_id);
