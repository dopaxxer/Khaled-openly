-- Granular public music visibility + mutual, privacy-preserving music matches.
-- Additive/backwards compatible: legacy preferences_public remains supported.

alter table public.music_preferences
  add column if not exists show_tracks boolean not null default false,
  add column if not exists show_artists boolean not null default false,
  add column if not exists show_genres boolean not null default false;

update public.music_preferences
set show_tracks = preferences_public,
    show_artists = preferences_public,
    show_genres = preferences_public
where preferences_public
  and not (show_tracks or show_artists or show_genres);

create table if not exists public.music_match_interests (
  user_id uuid not null references public.profiles(id) on delete cascade,
  target_user_id uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (user_id, target_user_id),
  constraint music_match_interests_not_self check (user_id <> target_user_id)
);

create table if not exists public.music_matches (
  user_a uuid not null references public.profiles(id) on delete cascade,
  user_b uuid not null references public.profiles(id) on delete cascade,
  matched_at timestamptz not null default now(),
  primary key (user_a, user_b),
  constraint music_matches_not_self check (user_a <> user_b)
);

create index if not exists music_match_interests_target_idx
  on public.music_match_interests (target_user_id, user_id);
create index if not exists music_matches_user_b_idx
  on public.music_matches (user_b, matched_at desc);
create index if not exists music_matches_user_a_date_idx
  on public.music_matches (user_a, matched_at desc);

alter table public.music_match_interests enable row level security;
alter table public.music_matches enable row level security;

revoke all on table public.music_match_interests from public, anon, authenticated;
revoke all on table public.music_matches from public, anon, authenticated;

create or replace function private.get_music_profile()
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  with viewer as (
    select (select auth.uid()) as id
  )
  select jsonb_build_object(
    'discoveryOptIn', coalesce(pref.discovery_opt_in, false),
    'preferencesPublic', coalesce(pref.preferences_public, false),
    'showTracks', coalesce(pref.show_tracks, false),
    'showArtists', coalesce(pref.show_artists, false),
    'showGenres', coalesce(pref.show_genres, false),
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
      where link.user_id = viewer.id
    ), '[]'::jsonb),
    'artists', coalesce((
      select jsonb_agg(jsonb_build_object('id', artist.id, 'name', artist.display_name) order by link.position, artist.display_name)
      from public.user_music_artists link
      join public.music_artists artist on artist.id = link.artist_id
      where link.user_id = viewer.id
    ), '[]'::jsonb),
    'genres', coalesce((
      select jsonb_agg(jsonb_build_object('id', genre.id, 'slug', genre.slug, 'name', genre.display_name, 'nameAr', genre.display_name_ar) order by link.position, genre.sort_order)
      from public.user_music_genres link
      join public.music_genres genre on genre.id = link.genre_id
      where link.user_id = viewer.id
    ), '[]'::jsonb)
  )
  from viewer
  left join public.music_preferences pref on pref.user_id = viewer.id
  where viewer.id is not null;
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
    'showTracks', pref.show_tracks,
    'showArtists', pref.show_artists,
    'showGenres', pref.show_genres,
    'tracks', case when pref.show_tracks then coalesce((
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
    ), '[]'::jsonb) else '[]'::jsonb end,
    'artists', case when pref.show_artists then coalesce((
      select jsonb_agg(jsonb_build_object('id', artist.id, 'name', artist.display_name) order by link.position, artist.display_name)
      from public.user_music_artists link
      join public.music_artists artist on artist.id = link.artist_id
      where link.user_id = profile.id
    ), '[]'::jsonb) else '[]'::jsonb end,
    'genres', case when pref.show_genres then coalesce((
      select jsonb_agg(jsonb_build_object('id', genre.id, 'slug', genre.slug, 'name', genre.display_name, 'nameAr', genre.display_name_ar) order by link.position, genre.sort_order)
      from public.user_music_genres link
      join public.music_genres genre on genre.id = link.genre_id
      where link.user_id = profile.id
    ), '[]'::jsonb) else '[]'::jsonb end
  )
  from public.profiles profile
  join public.music_preferences pref on pref.user_id = profile.id
  where profile.public_code = upper(btrim(coalesce(p_public_code, '')))
    and (pref.show_tracks or pref.show_artists or pref.show_genres)
    and private.can_view_content(profile.id);
$$;

create or replace function private.set_music_profile_settings(
  p_discovery_opt_in boolean,
  p_show_tracks boolean,
  p_show_artists boolean,
  p_show_genres boolean
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  viewer uuid := (select auth.uid());
  tracks_visible boolean := coalesce(p_show_tracks, false);
  artists_visible boolean := coalesce(p_show_artists, false);
  genres_visible boolean := coalesce(p_show_genres, false);
begin
  if viewer is null or not private.is_active_user() then
    raise exception 'Unauthorized';
  end if;

  insert into public.music_preferences (user_id, discovery_opt_in, preferences_public, show_tracks, show_artists, show_genres)
  values (viewer, coalesce(p_discovery_opt_in, false), tracks_visible or artists_visible or genres_visible, tracks_visible, artists_visible, genres_visible)
  on conflict (user_id) do update
  set discovery_opt_in = excluded.discovery_opt_in,
      preferences_public = excluded.preferences_public,
      show_tracks = excluded.show_tracks,
      show_artists = excluded.show_artists,
      show_genres = excluded.show_genres;

  return private.get_music_profile();
end;
$$;

create or replace function private.set_music_settings(p_discovery_opt_in boolean, p_preferences_public boolean)
returns jsonb
language sql
volatile
security definer
set search_path = ''
as $$
  select private.set_music_profile_settings(p_discovery_opt_in, p_preferences_public, p_preferences_public, p_preferences_public);
$$;

create or replace function private.music_similarity_to(p_target_id uuid)
returns table (compatibility integer, shared_artist_count integer, shared_genre_count integer, shared_artists jsonb, shared_genres jsonb)
language sql
stable
security definer
set search_path = ''
as $$
  with viewer as (select (select auth.uid()) as id),
  my_artists as (select artist_id from public.user_music_artists, viewer where user_id = viewer.id),
  their_artists as (select artist_id from public.user_music_artists where user_id = p_target_id),
  my_genres as (select genre_id from public.user_music_genres, viewer where user_id = viewer.id),
  their_genres as (select genre_id from public.user_music_genres where user_id = p_target_id),
  artist_overlap as (
    select count(*)::integer as hits,
      coalesce(jsonb_agg(jsonb_build_object('id', artist.id, 'name', artist.display_name) order by artist.display_name), '[]'::jsonb) as items
    from my_artists mine
    join their_artists theirs on theirs.artist_id = mine.artist_id
    join public.music_artists artist on artist.id = mine.artist_id
  ),
  genre_overlap as (
    select count(*)::integer as hits,
      coalesce(jsonb_agg(jsonb_build_object('id', genre.id, 'slug', genre.slug, 'name', genre.display_name, 'nameAr', genre.display_name_ar) order by genre.sort_order), '[]'::jsonb) as items
    from my_genres mine
    join their_genres theirs on theirs.genre_id = mine.genre_id
    join public.music_genres genre on genre.id = mine.genre_id
  ),
  totals as (
    select (select count(*)::integer from my_artists) as my_artist_count,
      (select count(*)::integer from their_artists) as their_artist_count,
      (select count(*)::integer from my_genres) as my_genre_count,
      (select count(*)::integer from their_genres) as their_genre_count
  ),
  score as (
    select artist_overlap.hits as shared_artist_count,
      genre_overlap.hits as shared_genre_count,
      artist_overlap.items as shared_artists,
      genre_overlap.items as shared_genres,
      (3 * artist_overlap.hits + genre_overlap.hits) as raw_score,
      (3 * least(totals.my_artist_count, totals.their_artist_count) + least(totals.my_genre_count, totals.their_genre_count)) as score_ceiling
    from artist_overlap, genre_overlap, totals
  )
  select case
      when not (score.shared_artist_count >= 1 or score.shared_genre_count >= 2) then 0
      when score.score_ceiling <= 0 then 0
      else round(100 * least(1::numeric, score.raw_score::numeric / score.score_ceiling::numeric) * least(1::numeric, score.raw_score::numeric / 6::numeric))::integer
    end,
    score.shared_artist_count, score.shared_genre_count, score.shared_artists, score.shared_genres
  from score;
$$;

create or replace function private.set_music_match_interest(p_public_code text, p_interested boolean)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  viewer uuid := (select auth.uid());
  target uuid;
  target_code text;
  target_color text;
  first_user uuid;
  second_user uuid;
  score_row record;
  is_matched boolean := false;
  match_time timestamptz;
begin
  if viewer is null or not private.is_active_user() then raise exception 'Unauthorized'; end if;
  if not exists (select 1 from public.music_preferences pref where pref.user_id = viewer and pref.discovery_opt_in) then
    raise exception 'Enable music discovery first';
  end if;

  select profile.id, profile.public_code, profile.identity_color into target, target_code, target_color
  from public.profiles profile
  join public.music_preferences pref on pref.user_id = profile.id
  where profile.public_code = upper(btrim(coalesce(p_public_code, '')))
    and profile.id <> viewer
    and pref.discovery_opt_in
    and private.can_view_user(profile.id);

  if target is null then raise exception 'Target is not available for music discovery'; end if;

  if viewer::text < target::text then first_user := viewer; second_user := target;
  else first_user := target; second_user := viewer; end if;

  select exists (select 1 from public.music_matches match where match.user_a = first_user and match.user_b = second_user) into is_matched;

  if coalesce(p_interested, false) then
    select * into score_row from private.music_similarity_to(target);
    if score_row.compatibility is null or score_row.compatibility <= 0 then raise exception 'No eligible music overlap'; end if;

    insert into public.music_match_interests (user_id, target_user_id)
    values (viewer, target)
    on conflict (user_id, target_user_id) do nothing;

    if exists (select 1 from public.music_match_interests reverse_interest where reverse_interest.user_id = target and reverse_interest.target_user_id = viewer) then
      insert into public.music_matches (user_a, user_b) values (first_user, second_user) on conflict (user_a, user_b) do nothing;
    end if;
  elsif not is_matched then
    delete from public.music_match_interests where user_id = viewer and target_user_id = target;
  end if;

  select match.matched_at into match_time from public.music_matches match where match.user_a = first_user and match.user_b = second_user;
  is_matched := match_time is not null;

  return jsonb_build_object(
    'publicCode', target_code,
    'identityColor', target_color,
    'interested', exists (select 1 from public.music_match_interests mine where mine.user_id = viewer and mine.target_user_id = target),
    'matched', is_matched,
    'matchedAt', match_time
  );
end;
$$;

create or replace function private.get_music_interest_states(p_public_codes text[])
returns table (public_code text, interested boolean, matched boolean)
language sql
stable
security definer
set search_path = ''
as $$
  with viewer as (select (select auth.uid()) as id)
  select profile.public_code::text,
    exists (select 1 from public.music_match_interests mine, viewer where mine.user_id = viewer.id and mine.target_user_id = profile.id) as interested,
    exists (select 1 from public.music_matches match, viewer where (match.user_a = viewer.id and match.user_b = profile.id) or (match.user_b = viewer.id and match.user_a = profile.id)) as matched
  from public.profiles profile, viewer
  where viewer.id is not null
    and profile.id <> viewer.id
    and profile.public_code = any(coalesce(p_public_codes, array[]::text[]))
    and private.can_view_user(profile.id);
$$;

create or replace function private.get_music_matches(p_limit integer default 20, p_offset integer default 0)
returns table (public_code text, identity_color text, compatibility integer, shared_artist_count integer, shared_genre_count integer, shared_artists jsonb, shared_genres jsonb, matched_at timestamptz, total_matches bigint)
language sql
stable
security definer
set search_path = ''
as $$
  with viewer as (select (select auth.uid()) as id),
  pairs as (
    select case when match.user_a = viewer.id then match.user_b else match.user_a end as target_id, match.matched_at
    from public.music_matches match, viewer
    where viewer.id is not null and (match.user_a = viewer.id or match.user_b = viewer.id)
  ),
  visible as (
    select pairs.target_id, pairs.matched_at
    from pairs, viewer
    where private.can_view_user(pairs.target_id)
      and not exists (select 1 from public.mutes mute where mute.muter_id = viewer.id and mute.muted_id = pairs.target_id)
  )
  select profile.public_code::text, profile.identity_color::text,
    similarity.compatibility, similarity.shared_artist_count, similarity.shared_genre_count,
    similarity.shared_artists, similarity.shared_genres, visible.matched_at,
    count(*) over () as total_matches
  from visible
  join public.profiles profile on profile.id = visible.target_id
  cross join lateral private.music_similarity_to(visible.target_id) similarity
  order by visible.matched_at desc, profile.public_code asc
  limit greatest(1, least(coalesce(p_limit, 20), 50))
  offset greatest(0, least(coalesce(p_offset, 0), 500));
$$;

create or replace function private.remove_music_match(p_public_code text)
returns boolean
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  viewer uuid := (select auth.uid());
  target uuid;
  first_user uuid;
  second_user uuid;
  removed boolean := false;
begin
  if viewer is null then raise exception 'Unauthorized'; end if;
  select profile.id into target from public.profiles profile where profile.public_code = upper(btrim(coalesce(p_public_code, ''))) and profile.id <> viewer;
  if target is null then return false; end if;

  if viewer::text < target::text then first_user := viewer; second_user := target;
  else first_user := target; second_user := viewer; end if;

  delete from public.music_matches where user_a = first_user and user_b = second_user;
  removed := found;
  delete from public.music_match_interests where (user_id = viewer and target_user_id = target) or (user_id = target and target_user_id = viewer);
  return removed;
end;
$$;

create or replace function public.set_music_profile_settings(p_discovery_opt_in boolean, p_show_tracks boolean, p_show_artists boolean, p_show_genres boolean)
returns jsonb language sql volatile security invoker set search_path = ''
as $$ select private.set_music_profile_settings(p_discovery_opt_in, p_show_tracks, p_show_artists, p_show_genres); $$;

create or replace function public.set_music_match_interest(p_public_code text, p_interested boolean)
returns jsonb language sql volatile security invoker set search_path = ''
as $$ select private.set_music_match_interest(p_public_code, p_interested); $$;

create or replace function public.get_music_interest_states(p_public_codes text[])
returns table (public_code text, interested boolean, matched boolean)
language sql stable security invoker set search_path = ''
as $$ select * from private.get_music_interest_states(p_public_codes); $$;

create or replace function public.get_music_matches(p_limit integer default 20, p_offset integer default 0)
returns table (public_code text, identity_color text, compatibility integer, shared_artist_count integer, shared_genre_count integer, shared_artists jsonb, shared_genres jsonb, matched_at timestamptz, total_matches bigint)
language sql stable security invoker set search_path = ''
as $$ select * from private.get_music_matches(p_limit, p_offset); $$;

create or replace function public.remove_music_match(p_public_code text)
returns boolean language sql volatile security invoker set search_path = ''
as $$ select private.remove_music_match(p_public_code); $$;

revoke execute on function private.set_music_profile_settings(boolean, boolean, boolean, boolean) from public, anon, authenticated;
revoke execute on function private.music_similarity_to(uuid) from public, anon, authenticated;
revoke execute on function private.set_music_match_interest(text, boolean) from public, anon, authenticated;
revoke execute on function private.get_music_interest_states(text[]) from public, anon, authenticated;
revoke execute on function private.get_music_matches(integer, integer) from public, anon, authenticated;
revoke execute on function private.remove_music_match(text) from public, anon, authenticated;

grant execute on function private.set_music_profile_settings(boolean, boolean, boolean, boolean) to authenticated;
grant execute on function private.set_music_match_interest(text, boolean) to authenticated;
grant execute on function private.get_music_interest_states(text[]) to authenticated;
grant execute on function private.get_music_matches(integer, integer) to authenticated;
grant execute on function private.remove_music_match(text) to authenticated;

revoke execute on function public.set_music_profile_settings(boolean, boolean, boolean, boolean) from public, anon;
revoke execute on function public.set_music_match_interest(text, boolean) from public, anon;
revoke execute on function public.get_music_interest_states(text[]) from public, anon;
revoke execute on function public.get_music_matches(integer, integer) from public, anon;
revoke execute on function public.remove_music_match(text) from public, anon;

grant execute on function public.set_music_profile_settings(boolean, boolean, boolean, boolean) to authenticated;
grant execute on function public.set_music_match_interest(text, boolean) to authenticated;
grant execute on function public.get_music_interest_states(text[]) to authenticated;
grant execute on function public.get_music_matches(integer, integer) to authenticated;
grant execute on function public.remove_music_match(text) to authenticated;

revoke update (show_tracks, show_artists, show_genres) on public.music_preferences from authenticated;
