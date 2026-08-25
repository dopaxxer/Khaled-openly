-- Favorite real-world music tracks backed by a provider-neutral catalog.
-- Additive: existing artists/genres/discovery behavior is unchanged.

create table if not exists public.music_tracks (
  id uuid primary key default gen_random_uuid(),
  provider text not null,
  external_id text not null,
  title text not null,
  artist_name text not null,
  album_name text,
  artwork_url text,
  external_url text,
  preview_url text,
  duration_ms integer,
  primary_genre text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint music_tracks_provider_allowed check (provider in ('apple_music', 'spotify', 'musicbrainz', 'lastfm')),
  constraint music_tracks_external_id_length check (char_length(btrim(external_id)) between 1 and 128),
  constraint music_tracks_title_length check (char_length(btrim(title)) between 1 and 200),
  constraint music_tracks_artist_length check (char_length(btrim(artist_name)) between 1 and 200),
  constraint music_tracks_album_length check (album_name is null or char_length(album_name) <= 200),
  constraint music_tracks_genre_length check (primary_genre is null or char_length(primary_genre) <= 80),
  constraint music_tracks_duration_range check (duration_ms is null or duration_ms between 1000 and 86400000),
  constraint music_tracks_artwork_https check (artwork_url is null or artwork_url ~ '^https://'),
  constraint music_tracks_external_https check (external_url is null or external_url ~ '^https://'),
  constraint music_tracks_preview_https check (preview_url is null or preview_url ~ '^https://'),
  constraint music_tracks_provider_external_unique unique (provider, external_id)
);

create table if not exists public.user_music_tracks (
  user_id uuid not null references public.profiles(id) on delete cascade,
  track_id uuid not null references public.music_tracks(id) on delete cascade,
  position integer not null default 0,
  created_at timestamptz not null default now(),
  primary key (user_id, track_id),
  constraint user_music_tracks_position_range check (position between 0 and 49)
);

create index if not exists music_tracks_artist_idx on public.music_tracks (artist_name);
create index if not exists user_music_tracks_track_idx on public.user_music_tracks (track_id, user_id);
create index if not exists user_music_tracks_owner_idx on public.user_music_tracks (user_id, position);

create or replace function private.touch_music_track()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

drop trigger if exists music_tracks_touch on public.music_tracks;
create trigger music_tracks_touch
before update on public.music_tracks
for each row execute function private.touch_music_track();

create or replace function private.enforce_music_track_selection_limit()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  total integer;
begin
  select count(*) into total
  from public.user_music_tracks
  where user_id = new.user_id;

  if total > 12 then
    raise exception 'A profile can list at most 12 tracks';
  end if;
  return null;
end;
$$;

drop trigger if exists user_music_tracks_limit on public.user_music_tracks;
create constraint trigger user_music_tracks_limit
after insert on public.user_music_tracks
deferrable initially deferred
for each row execute function private.enforce_music_track_selection_limit();

create or replace function private.add_music_track(
  p_provider text,
  p_external_id text,
  p_title text,
  p_artist_name text,
  p_album_name text default null,
  p_artwork_url text default null,
  p_external_url text default null,
  p_preview_url text default null,
  p_duration_ms integer default null,
  p_primary_genre text default null
)
returns table (
  id uuid,
  provider text,
  external_id text,
  title text,
  artist_name text,
  album_name text,
  artwork_url text,
  external_url text,
  preview_url text,
  duration_ms integer,
  primary_genre text
)
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  viewer uuid := (select auth.uid());
  saved public.music_tracks%rowtype;
  clean_provider text := lower(btrim(coalesce(p_provider, '')));
  clean_external_id text := btrim(coalesce(p_external_id, ''));
  clean_title text := btrim(coalesce(p_title, ''));
  clean_artist text := btrim(coalesce(p_artist_name, ''));
begin
  if viewer is null or not private.is_active_user() then
    raise exception 'Unauthorized';
  end if;
  if clean_provider not in ('apple_music', 'spotify', 'musicbrainz', 'lastfm') then
    raise exception 'Unsupported music provider';
  end if;
  if char_length(clean_external_id) < 1 or char_length(clean_external_id) > 128 then
    raise exception 'Invalid external track id';
  end if;
  if clean_provider = 'apple_music' and clean_external_id !~ '^[0-9]{1,20}$' then
    raise exception 'Invalid Apple track id';
  end if;
  if char_length(clean_title) < 1 or char_length(clean_title) > 200 then
    raise exception 'Invalid track title';
  end if;
  if char_length(clean_artist) < 1 or char_length(clean_artist) > 200 then
    raise exception 'Invalid artist name';
  end if;
  if p_artwork_url is not null and p_artwork_url !~ '^https://' then
    raise exception 'Artwork URL must use HTTPS';
  end if;
  if p_external_url is not null and p_external_url !~ '^https://' then
    raise exception 'External URL must use HTTPS';
  end if;
  if p_preview_url is not null and p_preview_url !~ '^https://' then
    raise exception 'Preview URL must use HTTPS';
  end if;

  insert into public.music_tracks (
    provider, external_id, title, artist_name, album_name,
    artwork_url, external_url, preview_url, duration_ms, primary_genre
  ) values (
    clean_provider,
    clean_external_id,
    clean_title,
    clean_artist,
    nullif(btrim(coalesce(p_album_name, '')), ''),
    nullif(btrim(coalesce(p_artwork_url, '')), ''),
    nullif(btrim(coalesce(p_external_url, '')), ''),
    nullif(btrim(coalesce(p_preview_url, '')), ''),
    p_duration_ms,
    nullif(btrim(coalesce(p_primary_genre, '')), '')
  )
  on conflict on constraint music_tracks_provider_external_unique do update
  set title = excluded.title,
      artist_name = excluded.artist_name,
      album_name = excluded.album_name,
      artwork_url = coalesce(excluded.artwork_url, public.music_tracks.artwork_url),
      external_url = coalesce(excluded.external_url, public.music_tracks.external_url),
      preview_url = coalesce(excluded.preview_url, public.music_tracks.preview_url),
      duration_ms = coalesce(excluded.duration_ms, public.music_tracks.duration_ms),
      primary_genre = coalesce(excluded.primary_genre, public.music_tracks.primary_genre)
  returning * into saved;

  return query select
    saved.id, saved.provider, saved.external_id, saved.title, saved.artist_name,
    saved.album_name, saved.artwork_url, saved.external_url, saved.preview_url,
    saved.duration_ms, saved.primary_genre;
end;
$$;

create or replace function private.get_music_profile()
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object(
    'discoveryOptIn', coalesce((select pref.discovery_opt_in from public.music_preferences pref where pref.user_id = (select auth.uid())), false),
    'preferencesPublic', coalesce((select pref.preferences_public from public.music_preferences pref where pref.user_id = (select auth.uid())), false),
    'tracks', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', track.id,
        'provider', track.provider,
        'externalId', track.external_id,
        'title', track.title,
        'artist', track.artist_name,
        'album', track.album_name,
        'artworkUrl', track.artwork_url,
        'externalUrl', track.external_url,
        'previewUrl', track.preview_url,
        'durationMs', track.duration_ms,
        'genre', track.primary_genre
      ) order by link.position, track.title)
      from public.user_music_tracks link
      join public.music_tracks track on track.id = link.track_id
      where link.user_id = (select auth.uid())
    ), '[]'::jsonb),
    'artists', coalesce((
      select jsonb_agg(jsonb_build_object('id', artist.id, 'name', artist.display_name) order by link.position, artist.display_name)
      from public.user_music_artists link
      join public.music_artists artist on artist.id = link.artist_id
      where link.user_id = (select auth.uid())
    ), '[]'::jsonb),
    'genres', coalesce((
      select jsonb_agg(jsonb_build_object('id', genre.id, 'slug', genre.slug, 'name', genre.display_name, 'nameAr', genre.display_name_ar) order by link.position, genre.sort_order)
      from public.user_music_genres link
      join public.music_genres genre on genre.id = link.genre_id
      where link.user_id = (select auth.uid())
    ), '[]'::jsonb)
  )
  where (select auth.uid()) is not null;
$$;

create or replace function private.set_music_tracks(p_track_ids uuid[])
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  viewer uuid := (select auth.uid());
  ids uuid[] := coalesce(p_track_ids, array[]::uuid[]);
begin
  if viewer is null or not private.is_active_user() then
    raise exception 'Unauthorized';
  end if;
  if coalesce(array_length(ids, 1), 0) > 12 then
    raise exception 'A profile can list at most 12 tracks';
  end if;

  delete from public.user_music_tracks
  where user_id = viewer
    and not (track_id = any(ids));

  insert into public.user_music_tracks (user_id, track_id, position)
  select viewer, entry.track_id, (entry.ordinality - 1)::integer
  from (
    select distinct on (value) value as track_id, ordinality
    from unnest(ids) with ordinality as source(value, ordinality)
    order by value, ordinality
  ) entry
  where exists (select 1 from public.music_tracks track where track.id = entry.track_id)
  on conflict (user_id, track_id) do update set position = excluded.position;

  insert into public.music_preferences (user_id) values (viewer)
  on conflict (user_id) do nothing;

  return private.get_music_profile();
end;
$$;

create or replace function private.clear_music_preferences()
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  viewer uuid := (select auth.uid());
begin
  if viewer is null then
    raise exception 'Unauthorized';
  end if;

  delete from public.user_music_tracks where user_id = viewer;
  delete from public.user_music_artists where user_id = viewer;
  delete from public.user_music_genres where user_id = viewer;
  delete from public.music_preferences where user_id = viewer;

  return private.get_music_profile();
end;
$$;

create or replace function private.get_public_music_profile(p_public_code text)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object(
    'publicCode', profile.public_code,
    'identityColor', profile.identity_color,
    'discoveryOptIn', pref.discovery_opt_in,
    'tracks', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', track.id,
        'provider', track.provider,
        'externalId', track.external_id,
        'title', track.title,
        'artist', track.artist_name,
        'album', track.album_name,
        'artworkUrl', track.artwork_url,
        'externalUrl', track.external_url,
        'previewUrl', track.preview_url,
        'durationMs', track.duration_ms,
        'genre', track.primary_genre
      ) order by link.position, track.title)
      from public.user_music_tracks link
      join public.music_tracks track on track.id = link.track_id
      where link.user_id = profile.id
    ), '[]'::jsonb),
    'artists', coalesce((
      select jsonb_agg(jsonb_build_object('id', artist.id, 'name', artist.display_name) order by link.position, artist.display_name)
      from public.user_music_artists link
      join public.music_artists artist on artist.id = link.artist_id
      where link.user_id = profile.id
    ), '[]'::jsonb),
    'genres', coalesce((
      select jsonb_agg(jsonb_build_object('id', genre.id, 'slug', genre.slug, 'name', genre.display_name, 'nameAr', genre.display_name_ar) order by link.position, genre.sort_order)
      from public.user_music_genres link
      join public.music_genres genre on genre.id = link.genre_id
      where link.user_id = profile.id
    ), '[]'::jsonb)
  )
  from public.profiles profile
  join public.music_preferences pref on pref.user_id = profile.id
  where profile.public_code = upper(btrim(coalesce(p_public_code, '')))
    and pref.preferences_public
    and private.can_view_content(profile.id);
$$;

create or replace function public.add_music_track(
  p_provider text,
  p_external_id text,
  p_title text,
  p_artist_name text,
  p_album_name text default null,
  p_artwork_url text default null,
  p_external_url text default null,
  p_preview_url text default null,
  p_duration_ms integer default null,
  p_primary_genre text default null
)
returns table (
  id uuid,
  provider text,
  external_id text,
  title text,
  artist_name text,
  album_name text,
  artwork_url text,
  external_url text,
  preview_url text,
  duration_ms integer,
  primary_genre text
)
language sql volatile security invoker set search_path = ''
as $$
  select * from private.add_music_track(
    p_provider, p_external_id, p_title, p_artist_name, p_album_name,
    p_artwork_url, p_external_url, p_preview_url, p_duration_ms, p_primary_genre
  );
$$;

create or replace function public.set_music_tracks(p_track_ids uuid[])
returns jsonb
language sql volatile security invoker set search_path = ''
as $$ select private.set_music_tracks(p_track_ids); $$;

alter table public.music_tracks enable row level security;
alter table public.user_music_tracks enable row level security;

drop policy if exists music_tracks_public_read on public.music_tracks;
create policy music_tracks_public_read on public.music_tracks
for select to anon, authenticated using (true);

drop policy if exists user_music_tracks_owner_read on public.user_music_tracks;
create policy user_music_tracks_owner_read on public.user_music_tracks
for select to authenticated
using (user_id = (select auth.uid()));

drop policy if exists user_music_tracks_owner_insert on public.user_music_tracks;
create policy user_music_tracks_owner_insert on public.user_music_tracks
for insert to authenticated
with check (user_id = (select auth.uid()) and private.is_active_user());

drop policy if exists user_music_tracks_owner_update on public.user_music_tracks;
create policy user_music_tracks_owner_update on public.user_music_tracks
for update to authenticated
using (user_id = (select auth.uid()) and private.is_active_user())
with check (user_id = (select auth.uid()) and private.is_active_user());

drop policy if exists user_music_tracks_owner_delete on public.user_music_tracks;
create policy user_music_tracks_owner_delete on public.user_music_tracks
for delete to authenticated
using (user_id = (select auth.uid()));

revoke all on table public.music_tracks from public, anon, authenticated;
revoke all on table public.user_music_tracks from public, anon, authenticated;
grant select on table public.music_tracks to anon, authenticated;
grant select, delete on table public.user_music_tracks to authenticated;
grant insert (user_id, track_id, position) on table public.user_music_tracks to authenticated;
grant update (position) on table public.user_music_tracks to authenticated;

revoke execute on function private.touch_music_track() from public, anon, authenticated;
revoke execute on function private.enforce_music_track_selection_limit() from public, anon, authenticated;
revoke execute on function private.add_music_track(text, text, text, text, text, text, text, text, integer, text) from public, anon, authenticated;
revoke execute on function private.set_music_tracks(uuid[]) from public, anon, authenticated;
grant execute on function private.add_music_track(text, text, text, text, text, text, text, text, integer, text) to authenticated;
grant execute on function private.set_music_tracks(uuid[]) to authenticated;

revoke execute on function public.add_music_track(text, text, text, text, text, text, text, text, integer, text) from public, anon;
revoke execute on function public.set_music_tracks(uuid[]) from public, anon;
grant execute on function public.add_music_track(text, text, text, text, text, text, text, text, integer, text) to authenticated;
grant execute on function public.set_music_tracks(uuid[]) to authenticated;
