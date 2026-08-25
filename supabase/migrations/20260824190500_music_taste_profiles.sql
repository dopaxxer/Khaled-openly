-- Optional music-taste profiles and music-based people discovery.
--
-- Additive only. Everything here is opt-in: a user who never opens the music
-- screens has no rows in any of these tables and is invisible to discovery.
-- No listening history is collected and no external provider is required, but
-- the catalog is provider-neutral so Spotify/Apple Music identifiers can be
-- attached later without reshaping the schema.

-- ---------------------------------------------------------------------------
-- Name normalisation
-- ---------------------------------------------------------------------------

-- Folds a display name to a comparison key so "Sigur Rós", "sigur ros" and
-- "  SIGUR  ROS!! " collapse to one artist, and so do the common Arabic
-- spellings of the same name.
--
-- Steps: lowercase, Unicode NFD decomposition, fold the letters that do not
-- decompose (ى -> ي, ة -> ه, ٱ -> ا), strip combining marks, then reduce
-- everything that is not a Latin letter, a digit or an Arabic letter to a
-- single space. NFD makes the hamza forms (أ إ آ ؤ ئ) fold for free because
-- their hamza becomes a combining mark that the strip step removes.
--
-- The character classes are assembled from chr() rather than written as
-- literal code points: several of them are invisible or combining characters
-- that do not survive being copied between tools.
-- lib/musicNormalize.js and MusicSupport.swift implement the same steps.
create or replace function private.normalize_music_name(p_value text)
returns text
language sql
immutable
set search_path = ''
as $$
  select nullif(
    btrim(
      regexp_replace(
        regexp_replace(
          translate(
            normalize(lower(btrim(coalesce(p_value, ''))), NFD),
            -- teh marbuta, alef maksura and alef wasla do not decompose, so
            -- fold them explicitly: ة -> ه, ى -> ي, ٱ -> ا.
            chr(1577) || chr(1609) || chr(1649),
            chr(1607) || chr(1610) || chr(1575)
          ),
          -- Strip combining marks: U+0300-U+036F (Latin), U+0610-U+061A,
          -- U+064B-U+065F, U+0670, U+06D6-U+06ED (Arabic) and U+0640 tatweel.
          '[' || chr(768) || '-' || chr(879)
              || chr(1552) || '-' || chr(1562)
              || chr(1611) || '-' || chr(1631)
              || chr(1648)
              || chr(1750) || '-' || chr(1773)
              || chr(1600) || ']',
          '',
          'g'
        ),
        -- Keep only a-z, 0-9 and the Arabic block U+0600-U+06FF; everything
        -- else collapses to a single space.
        '[^a-z0-9' || chr(1536) || '-' || chr(1791) || ']+',
        ' ',
        'g'
      )
    ),
    ''
  );
$$;

-- ---------------------------------------------------------------------------
-- Catalog
-- ---------------------------------------------------------------------------

create table if not exists public.music_genres (
  id uuid primary key default gen_random_uuid(),
  slug text not null unique,
  display_name text not null,
  display_name_ar text not null,
  search_text text not null default '',
  sort_order integer not null default 100,
  created_at timestamptz not null default now(),
  constraint music_genres_slug_format check (slug ~ '^[a-z0-9]+(-[a-z0-9]+)*$'),
  constraint music_genres_display_length check (char_length(btrim(display_name)) between 1 and 60),
  constraint music_genres_display_ar_length check (char_length(btrim(display_name_ar)) between 1 and 60)
);

create table if not exists public.music_artists (
  id uuid primary key default gen_random_uuid(),
  display_name text not null,
  normalized_name text not null unique,
  created_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now(),
  constraint music_artists_display_length check (char_length(btrim(display_name)) between 1 and 80),
  constraint music_artists_normalized_length check (char_length(normalized_name) between 1 and 80)
);

-- Provider-neutral hook for a future Spotify/Apple Music import. Nothing in
-- this release writes to it; it exists so adding an integration later is a
-- data migration rather than a schema redesign.
create table if not exists public.music_artist_links (
  artist_id uuid not null references public.music_artists(id) on delete cascade,
  provider text not null check (provider in ('spotify', 'apple_music', 'musicbrainz', 'lastfm')),
  external_id text not null,
  created_at timestamptz not null default now(),
  primary key (provider, external_id),
  constraint music_artist_links_unique_per_provider unique (artist_id, provider),
  constraint music_artist_links_external_id_length check (char_length(btrim(external_id)) between 1 and 128)
);

-- ---------------------------------------------------------------------------
-- Per-user preferences
-- ---------------------------------------------------------------------------

-- discovery_opt_in  -> may appear in Music Discovery results at all.
-- preferences_public -> the full list shows on the public profile page.
-- The two are independent: discovery only ever reveals the overlap with the
-- viewer, so a user can be discoverable without publishing their whole list.
create table if not exists public.music_preferences (
  user_id uuid primary key references public.profiles(id) on delete cascade,
  discovery_opt_in boolean not null default false,
  preferences_public boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.user_music_artists (
  user_id uuid not null references public.profiles(id) on delete cascade,
  artist_id uuid not null references public.music_artists(id) on delete cascade,
  position integer not null default 0,
  created_at timestamptz not null default now(),
  primary key (user_id, artist_id),
  constraint user_music_artists_position_range check (position between 0 and 49)
);

create table if not exists public.user_music_genres (
  user_id uuid not null references public.profiles(id) on delete cascade,
  genre_id uuid not null references public.music_genres(id) on delete cascade,
  position integer not null default 0,
  created_at timestamptz not null default now(),
  primary key (user_id, genre_id),
  constraint user_music_genres_position_range check (position between 0 and 49)
);

create index if not exists music_artists_normalized_idx
  on public.music_artists (normalized_name text_pattern_ops);
create index if not exists music_artists_created_by_idx
  on public.music_artists (created_by)
  where created_by is not null;
create index if not exists music_genres_sort_idx
  on public.music_genres (sort_order, slug);
create index if not exists music_genres_search_idx
  on public.music_genres (search_text text_pattern_ops);
create index if not exists music_artist_links_artist_idx
  on public.music_artist_links (artist_id);
-- Discovery walks from a shared artist/genre back to its listeners, so the
-- reverse direction of each primary key needs its own index.
create index if not exists user_music_artists_artist_idx
  on public.user_music_artists (artist_id, user_id);
create index if not exists user_music_genres_genre_idx
  on public.user_music_genres (genre_id, user_id);
create index if not exists user_music_artists_owner_idx
  on public.user_music_artists (user_id, position);
create index if not exists user_music_genres_owner_idx
  on public.user_music_genres (user_id, position);
create index if not exists music_preferences_discoverable_idx
  on public.music_preferences (user_id)
  where discovery_opt_in;

-- ---------------------------------------------------------------------------
-- Integrity triggers
-- ---------------------------------------------------------------------------

create or replace function private.set_music_artist_normalized_name()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.display_name := btrim(new.display_name);
  new.normalized_name := private.normalize_music_name(new.display_name);
  if new.normalized_name is null then
    raise exception 'Artist name must contain at least one letter or digit';
  end if;
  return new;
end;
$$;

create or replace function private.set_music_genre_search_text()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.search_text := btrim(
    coalesce(private.normalize_music_name(new.display_name), '') || ' ' ||
    coalesce(private.normalize_music_name(new.display_name_ar), '') || ' ' ||
    coalesce(new.slug, '')
  );
  return new;
end;
$$;

-- The RPCs below already cap the list sizes; the trigger keeps the cap true
-- even for a client that writes the table directly through its own row-level
-- security policies.
create or replace function private.enforce_music_selection_limit()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  total integer;
  cap integer;
begin
  if tg_table_name = 'user_music_artists' then
    cap := 30;
    select count(*) into total from public.user_music_artists where user_id = new.user_id;
  else
    cap := 15;
    select count(*) into total from public.user_music_genres where user_id = new.user_id;
  end if;

  if total > cap then
    raise exception 'Too many music selections (limit %)', cap;
  end if;
  return null;
end;
$$;

create or replace function private.touch_music_preferences()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

drop trigger if exists music_artists_normalize on public.music_artists;
create trigger music_artists_normalize
before insert or update of display_name on public.music_artists
for each row execute function private.set_music_artist_normalized_name();

drop trigger if exists music_genres_search on public.music_genres;
create trigger music_genres_search
before insert or update of display_name, display_name_ar, slug on public.music_genres
for each row execute function private.set_music_genre_search_text();

drop trigger if exists user_music_artists_limit on public.user_music_artists;
create constraint trigger user_music_artists_limit
after insert on public.user_music_artists
deferrable initially deferred
for each row execute function private.enforce_music_selection_limit();

drop trigger if exists user_music_genres_limit on public.user_music_genres;
create constraint trigger user_music_genres_limit
after insert on public.user_music_genres
deferrable initially deferred
for each row execute function private.enforce_music_selection_limit();

drop trigger if exists music_preferences_touch on public.music_preferences;
create trigger music_preferences_touch
before update on public.music_preferences
for each row execute function private.touch_music_preferences();

-- ---------------------------------------------------------------------------
-- Genre catalog seed
-- ---------------------------------------------------------------------------

insert into public.music_genres (slug, display_name, display_name_ar, sort_order) values
  ('pop', 'Pop', 'بوب', 10),
  ('rock', 'Rock', 'روك', 20),
  ('indie', 'Indie', 'إندي', 30),
  ('alternative', 'Alternative', 'بديل', 40),
  ('hip-hop', 'Hip-Hop', 'هيب هوب', 50),
  ('rap', 'Rap', 'راب', 60),
  ('rnb', 'R&B', 'آر أند بي', 70),
  ('soul', 'Soul', 'سول', 80),
  ('jazz', 'Jazz', 'جاز', 90),
  ('blues', 'Blues', 'بلوز', 100),
  ('classical', 'Classical', 'كلاسيكي', 110),
  ('electronic', 'Electronic', 'إلكتروني', 120),
  ('house', 'House', 'هاوس', 130),
  ('techno', 'Techno', 'تكنو', 140),
  ('ambient', 'Ambient', 'أمبينت', 150),
  ('lofi', 'Lo-Fi', 'لو فاي', 160),
  ('metal', 'Metal', 'ميتال', 170),
  ('punk', 'Punk', 'بانك', 180),
  ('folk', 'Folk', 'فولك', 190),
  ('country', 'Country', 'كانتري', 200),
  ('reggae', 'Reggae', 'ريغي', 210),
  ('latin', 'Latin', 'لاتيني', 220),
  ('arabic-pop', 'Arabic Pop', 'بوب عربي', 230),
  ('tarab', 'Tarab', 'طرب', 240),
  ('khaleeji', 'Khaleeji', 'خليجي', 250),
  ('shaabi', 'Shaabi', 'شعبي', 260),
  ('mahraganat', 'Mahraganat', 'مهرجانات', 270),
  ('sufi', 'Sufi', 'صوفي', 280),
  ('soundtrack', 'Soundtrack', 'موسيقى تصويرية', 290),
  ('instrumental', 'Instrumental', 'موسيقى بلا كلمات', 300)
on conflict (slug) do nothing;

-- ---------------------------------------------------------------------------
-- Catalog search and artist creation
-- ---------------------------------------------------------------------------

create or replace function private.search_music_genres(p_query text, p_limit integer default 30)
returns table (id uuid, slug text, display_name text, display_name_ar text)
language sql
stable
security definer
set search_path = ''
as $$
  with needle as (
    select private.normalize_music_name(p_query) as value
  )
  select genre.id, genre.slug, genre.display_name, genre.display_name_ar
  from public.music_genres genre, needle
  where needle.value is null or position(needle.value in genre.search_text) > 0
  order by
    case when needle.value is not null and genre.search_text like needle.value || '%' then 0 else 1 end,
    genre.sort_order,
    genre.slug
  limit greatest(1, least(coalesce(p_limit, 30), 50));
$$;

create or replace function private.search_music_artists(p_query text, p_limit integer default 20)
returns table (id uuid, display_name text, listener_count bigint)
language sql
stable
security definer
set search_path = ''
as $$
  with needle as (
    select private.normalize_music_name(p_query) as value
  )
  select
    artist.id,
    artist.display_name,
    (select count(*)::bigint from public.user_music_artists link where link.artist_id = artist.id)
  from public.music_artists artist, needle
  where needle.value is not null
    and char_length(needle.value) <= 80
    and position(needle.value in artist.normalized_name) > 0
  order by
    case when artist.normalized_name like needle.value || '%' then 0 else 1 end,
    artist.normalized_name
  limit greatest(1, least(coalesce(p_limit, 20), 25));
$$;

-- Returns the existing artist when the name normalises to one that is already
-- in the catalog, so capitalisation, spacing, punctuation and the Arabic
-- spelling variants cannot create duplicate rows.
create or replace function private.add_music_artist(p_name text)
returns table (id uuid, display_name text, created boolean)
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  viewer uuid := (select auth.uid());
  clean_name text := btrim(coalesce(p_name, ''));
  normalized text;
  existing public.music_artists%rowtype;
  inserted public.music_artists%rowtype;
begin
  if viewer is null or not private.is_active_user() then
    raise exception 'Unauthorized';
  end if;
  if char_length(clean_name) < 1 or char_length(clean_name) > 80 then
    raise exception 'Artist name must be between 1 and 80 characters';
  end if;

  normalized := private.normalize_music_name(clean_name);
  if normalized is null then
    raise exception 'Artist name must contain at least one letter or digit';
  end if;

  select * into existing from public.music_artists where normalized_name = normalized;
  if found then
    return query select existing.id, existing.display_name, false;
    return;
  end if;

  insert into public.music_artists (display_name, created_by)
  values (clean_name, viewer)
  on conflict (normalized_name) do nothing
  returning * into inserted;

  if inserted.id is null then
    select * into existing from public.music_artists where normalized_name = normalized;
    return query select existing.id, existing.display_name, false;
    return;
  end if;

  return query select inserted.id, inserted.display_name, true;
end;
$$;

-- ---------------------------------------------------------------------------
-- Reading and writing the viewer's own preferences
-- ---------------------------------------------------------------------------

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

create or replace function private.set_music_settings(
  p_discovery_opt_in boolean,
  p_preferences_public boolean
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  viewer uuid := (select auth.uid());
begin
  if viewer is null or not private.is_active_user() then
    raise exception 'Unauthorized';
  end if;

  insert into public.music_preferences (user_id, discovery_opt_in, preferences_public)
  values (viewer, coalesce(p_discovery_opt_in, false), coalesce(p_preferences_public, false))
  on conflict (user_id) do update
  set discovery_opt_in = excluded.discovery_opt_in,
      preferences_public = excluded.preferences_public;

  return private.get_music_profile();
end;
$$;

-- Replace-all keeps add, remove and reorder as one idempotent, atomic call:
-- the array order becomes the stored order.
create or replace function private.set_music_artists(p_artist_ids uuid[])
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  viewer uuid := (select auth.uid());
  ids uuid[] := coalesce(p_artist_ids, array[]::uuid[]);
begin
  if viewer is null or not private.is_active_user() then
    raise exception 'Unauthorized';
  end if;
  if coalesce(array_length(ids, 1), 0) > 30 then
    raise exception 'A profile can list at most 30 artists';
  end if;

  delete from public.user_music_artists
  where user_id = viewer
    and not (artist_id = any(ids));

  insert into public.user_music_artists (user_id, artist_id, position)
  select viewer, entry.artist_id, (entry.ordinality - 1)::integer
  from (
    select distinct on (value) value as artist_id, ordinality
    from unnest(ids) with ordinality as source(value, ordinality)
    order by value, ordinality
  ) entry
  where exists (select 1 from public.music_artists artist where artist.id = entry.artist_id)
  on conflict (user_id, artist_id) do update set position = excluded.position;

  insert into public.music_preferences (user_id) values (viewer)
  on conflict (user_id) do nothing;

  return private.get_music_profile();
end;
$$;

create or replace function private.set_music_genres(p_genre_ids uuid[])
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  viewer uuid := (select auth.uid());
  ids uuid[] := coalesce(p_genre_ids, array[]::uuid[]);
begin
  if viewer is null or not private.is_active_user() then
    raise exception 'Unauthorized';
  end if;
  if coalesce(array_length(ids, 1), 0) > 15 then
    raise exception 'A profile can list at most 15 genres';
  end if;

  delete from public.user_music_genres
  where user_id = viewer
    and not (genre_id = any(ids));

  insert into public.user_music_genres (user_id, genre_id, position)
  select viewer, entry.genre_id, (entry.ordinality - 1)::integer
  from (
    select distinct on (value) value as genre_id, ordinality
    from unnest(ids) with ordinality as source(value, ordinality)
    order by value, ordinality
  ) entry
  where exists (select 1 from public.music_genres genre where genre.id = entry.genre_id)
  on conflict (user_id, genre_id) do update set position = excluded.position;

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

  delete from public.user_music_artists where user_id = viewer;
  delete from public.user_music_genres where user_id = viewer;
  delete from public.music_preferences where user_id = viewer;

  return private.get_music_profile();
end;
$$;

-- The public view of somebody else's taste. Returns nothing unless that user
-- published their list and is visible to the viewer.
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

-- ---------------------------------------------------------------------------
-- Discovery
-- ---------------------------------------------------------------------------

-- Compatibility formula (documented in README and mirrored by
-- lib/musicScore.js, which the unit tests treat as the executable spec):
--
--   raw        = 3 x sharedArtists + 1 x sharedGenres
--   ceiling    = 3 x min(myArtists, theirArtists) + 1 x min(myGenres, theirGenres)
--   overlap    = ceiling = 0 ? 0 : raw / ceiling
--   confidence = min(1, raw / 6)
--   score      = round(100 x overlap x confidence)
--
-- An artist match is worth three genre matches. `overlap` measures how much of
-- the smaller of the two profiles is shared, and `confidence` stops a single
-- thin match from reading as a perfect one: one shared genre can never exceed
-- 17%, and one shared artist can never exceed 50%. A pair needs at least one
-- shared artist or two shared genres to be listed at all, and `ceiling` is
-- guarded against zero. The result is deterministic and every point of it is
-- explained by the shared artists and genres returned alongside it.
create or replace function private.discover_music_people(
  p_artist_id uuid default null,
  p_genre_id uuid default null,
  p_limit integer default 20,
  p_offset integer default 0
)
returns table (
  public_code text,
  identity_color text,
  compatibility integer,
  shared_artist_count integer,
  shared_genre_count integer,
  shared_artists jsonb,
  shared_genres jsonb,
  total_matches bigint
)
language sql
stable
security definer
set search_path = ''
as $$
  with viewer as (
    select (select auth.uid()) as id
  ),
  viewer_artists as (
    select link.artist_id from public.user_music_artists link, viewer
    where link.user_id = viewer.id
  ),
  viewer_genres as (
    select link.genre_id from public.user_music_genres link, viewer
    where link.user_id = viewer.id
  ),
  viewer_totals as (
    select
      (select count(*)::integer from viewer_artists) as artist_count,
      (select count(*)::integer from viewer_genres) as genre_count
  ),
  candidates as (
    select pref.user_id
    from public.music_preferences pref, viewer
    where viewer.id is not null
      and pref.discovery_opt_in
      and pref.user_id <> viewer.id
      and private.can_view_user(pref.user_id)
      and not exists (
        select 1 from public.mutes mute
        where mute.muter_id = viewer.id and mute.muted_id = pref.user_id
      )
      and (p_artist_id is null or exists (
        select 1 from public.user_music_artists link
        where link.user_id = pref.user_id and link.artist_id = p_artist_id
      ))
      and (p_genre_id is null or exists (
        select 1 from public.user_music_genres link
        where link.user_id = pref.user_id and link.genre_id = p_genre_id
      ))
  ),
  taste_overlap as (
    select
      candidate.user_id,
      coalesce(artist_overlap.hits, 0) as shared_artist_count,
      coalesce(genre_overlap.hits, 0) as shared_genre_count,
      coalesce(artist_overlap.items, '[]'::jsonb) as shared_artists,
      coalesce(genre_overlap.items, '[]'::jsonb) as shared_genres,
      (select count(*)::integer from public.user_music_artists link where link.user_id = candidate.user_id) as their_artist_count,
      (select count(*)::integer from public.user_music_genres link where link.user_id = candidate.user_id) as their_genre_count
    from candidates candidate
    left join lateral (
      select
        count(*)::integer as hits,
        jsonb_agg(jsonb_build_object('id', artist.id, 'name', artist.display_name) order by artist.display_name) as items
      from public.user_music_artists link
      join viewer_artists mine on mine.artist_id = link.artist_id
      join public.music_artists artist on artist.id = link.artist_id
      where link.user_id = candidate.user_id
    ) artist_overlap on true
    left join lateral (
      select
        count(*)::integer as hits,
        jsonb_agg(jsonb_build_object('id', genre.id, 'slug', genre.slug, 'name', genre.display_name, 'nameAr', genre.display_name_ar) order by genre.sort_order) as items
      from public.user_music_genres link
      join viewer_genres mine on mine.genre_id = link.genre_id
      join public.music_genres genre on genre.id = link.genre_id
      where link.user_id = candidate.user_id
    ) genre_overlap on true
  ),
  scored as (
    select
      overlap.*,
      (3 * overlap.shared_artist_count + overlap.shared_genre_count) as raw_score,
      (3 * least(totals.artist_count, overlap.their_artist_count)
        + least(totals.genre_count, overlap.their_genre_count)) as score_ceiling
    from taste_overlap overlap, viewer_totals totals
    where overlap.shared_artist_count >= 1 or overlap.shared_genre_count >= 2
  ),
  ranked as (
    select
      scored.*,
      case
        when scored.score_ceiling <= 0 then 0
        else round(
          100
          * least(1::numeric, scored.raw_score::numeric / scored.score_ceiling::numeric)
          * least(1::numeric, scored.raw_score::numeric / 6::numeric)
        )::integer
      end as compatibility
    from scored
  )
  select
    profile.public_code::text,
    profile.identity_color::text,
    ranked.compatibility,
    ranked.shared_artist_count,
    ranked.shared_genre_count,
    ranked.shared_artists,
    ranked.shared_genres,
    count(*) over () as total_matches
  from ranked
  join public.profiles profile on profile.id = ranked.user_id
  where ranked.compatibility > 0
  order by
    ranked.compatibility desc,
    ranked.shared_artist_count desc,
    ranked.shared_genre_count desc,
    profile.public_code asc
  limit greatest(1, least(coalesce(p_limit, 20), 50))
  offset greatest(0, least(coalesce(p_offset, 0), 500));
$$;

-- ---------------------------------------------------------------------------
-- Public wrappers (security invoker, thin)
-- ---------------------------------------------------------------------------

create or replace function public.search_music_genres(p_query text default null, p_limit integer default 30)
returns table (id uuid, slug text, display_name text, display_name_ar text)
language sql stable security invoker set search_path = ''
as $$ select * from private.search_music_genres(p_query, p_limit); $$;

create or replace function public.search_music_artists(p_query text, p_limit integer default 20)
returns table (id uuid, display_name text, listener_count bigint)
language sql stable security invoker set search_path = ''
as $$ select * from private.search_music_artists(p_query, p_limit); $$;

create or replace function public.add_music_artist(p_name text)
returns table (id uuid, display_name text, created boolean)
language sql volatile security invoker set search_path = ''
as $$ select * from private.add_music_artist(p_name); $$;

create or replace function public.get_music_profile()
returns jsonb
language sql stable security invoker set search_path = ''
as $$ select private.get_music_profile(); $$;

create or replace function public.set_music_settings(p_discovery_opt_in boolean, p_preferences_public boolean)
returns jsonb
language sql volatile security invoker set search_path = ''
as $$ select private.set_music_settings(p_discovery_opt_in, p_preferences_public); $$;

create or replace function public.set_music_artists(p_artist_ids uuid[])
returns jsonb
language sql volatile security invoker set search_path = ''
as $$ select private.set_music_artists(p_artist_ids); $$;

create or replace function public.set_music_genres(p_genre_ids uuid[])
returns jsonb
language sql volatile security invoker set search_path = ''
as $$ select private.set_music_genres(p_genre_ids); $$;

create or replace function public.clear_music_preferences()
returns jsonb
language sql volatile security invoker set search_path = ''
as $$ select private.clear_music_preferences(); $$;

create or replace function public.get_public_music_profile(p_public_code text)
returns jsonb
language sql stable security invoker set search_path = ''
as $$ select private.get_public_music_profile(p_public_code); $$;

create or replace function public.discover_music_people(
  p_artist_id uuid default null,
  p_genre_id uuid default null,
  p_limit integer default 20,
  p_offset integer default 0
)
returns table (
  public_code text,
  identity_color text,
  compatibility integer,
  shared_artist_count integer,
  shared_genre_count integer,
  shared_artists jsonb,
  shared_genres jsonb,
  total_matches bigint
)
language sql stable security invoker set search_path = ''
as $$ select * from private.discover_music_people(p_artist_id, p_genre_id, p_limit, p_offset); $$;

-- ---------------------------------------------------------------------------
-- Row level security
-- ---------------------------------------------------------------------------

alter table public.music_genres enable row level security;
alter table public.music_artists enable row level security;
alter table public.music_artist_links enable row level security;
alter table public.music_preferences enable row level security;
alter table public.user_music_artists enable row level security;
alter table public.user_music_genres enable row level security;

-- The catalog is public reference data: readable by everyone, written only by
-- the definer functions above.
drop policy if exists music_genres_public_read on public.music_genres;
create policy music_genres_public_read on public.music_genres
for select to anon, authenticated using (true);

drop policy if exists music_artists_public_read on public.music_artists;
create policy music_artists_public_read on public.music_artists
for select to anon, authenticated using (true);

drop policy if exists music_artist_links_public_read on public.music_artist_links;
create policy music_artist_links_public_read on public.music_artist_links
for select to anon, authenticated using (true);

-- Everything that ties a taste to a person is owner-only at the row level.
-- Cross-user reads happen exclusively through the definer functions, which
-- apply the opt-in, visibility, block and mute rules.
drop policy if exists music_preferences_owner_read on public.music_preferences;
create policy music_preferences_owner_read on public.music_preferences
for select to authenticated
using (user_id = (select auth.uid()));

drop policy if exists music_preferences_owner_insert on public.music_preferences;
create policy music_preferences_owner_insert on public.music_preferences
for insert to authenticated
with check (user_id = (select auth.uid()) and private.is_active_user());

drop policy if exists music_preferences_owner_update on public.music_preferences;
create policy music_preferences_owner_update on public.music_preferences
for update to authenticated
using (user_id = (select auth.uid()) and private.is_active_user())
with check (user_id = (select auth.uid()) and private.is_active_user());

drop policy if exists music_preferences_owner_delete on public.music_preferences;
create policy music_preferences_owner_delete on public.music_preferences
for delete to authenticated
using (user_id = (select auth.uid()));

drop policy if exists user_music_artists_owner_read on public.user_music_artists;
create policy user_music_artists_owner_read on public.user_music_artists
for select to authenticated
using (user_id = (select auth.uid()));

drop policy if exists user_music_artists_owner_insert on public.user_music_artists;
create policy user_music_artists_owner_insert on public.user_music_artists
for insert to authenticated
with check (user_id = (select auth.uid()) and private.is_active_user());

drop policy if exists user_music_artists_owner_update on public.user_music_artists;
create policy user_music_artists_owner_update on public.user_music_artists
for update to authenticated
using (user_id = (select auth.uid()) and private.is_active_user())
with check (user_id = (select auth.uid()) and private.is_active_user());

drop policy if exists user_music_artists_owner_delete on public.user_music_artists;
create policy user_music_artists_owner_delete on public.user_music_artists
for delete to authenticated
using (user_id = (select auth.uid()));

drop policy if exists user_music_genres_owner_read on public.user_music_genres;
create policy user_music_genres_owner_read on public.user_music_genres
for select to authenticated
using (user_id = (select auth.uid()));

drop policy if exists user_music_genres_owner_insert on public.user_music_genres;
create policy user_music_genres_owner_insert on public.user_music_genres
for insert to authenticated
with check (user_id = (select auth.uid()) and private.is_active_user());

drop policy if exists user_music_genres_owner_update on public.user_music_genres;
create policy user_music_genres_owner_update on public.user_music_genres
for update to authenticated
using (user_id = (select auth.uid()) and private.is_active_user())
with check (user_id = (select auth.uid()) and private.is_active_user());

drop policy if exists user_music_genres_owner_delete on public.user_music_genres;
create policy user_music_genres_owner_delete on public.user_music_genres
for delete to authenticated
using (user_id = (select auth.uid()));

-- ---------------------------------------------------------------------------
-- Privileges
-- ---------------------------------------------------------------------------

-- Supabase default privileges hand new public objects to anon and
-- authenticated. Take everything back first, then grant the exact surface.
revoke all on table public.music_genres from public, anon, authenticated;
revoke all on table public.music_artists from public, anon, authenticated;
revoke all on table public.music_artist_links from public, anon, authenticated;
revoke all on table public.music_preferences from public, anon, authenticated;
revoke all on table public.user_music_artists from public, anon, authenticated;
revoke all on table public.user_music_genres from public, anon, authenticated;

grant select on table public.music_genres to anon, authenticated;
grant select on table public.music_artists to anon, authenticated;
grant select on table public.music_artist_links to anon, authenticated;

grant select, delete on table public.music_preferences to authenticated;
grant insert (user_id, discovery_opt_in, preferences_public) on table public.music_preferences to authenticated;
grant update (discovery_opt_in, preferences_public) on table public.music_preferences to authenticated;

grant select, delete on table public.user_music_artists to authenticated;
grant insert (user_id, artist_id, position) on table public.user_music_artists to authenticated;
grant update (position) on table public.user_music_artists to authenticated;

grant select, delete on table public.user_music_genres to authenticated;
grant insert (user_id, genre_id, position) on table public.user_music_genres to authenticated;
grant update (position) on table public.user_music_genres to authenticated;

revoke execute on function private.normalize_music_name(text) from public, anon, authenticated;
revoke execute on function private.set_music_artist_normalized_name() from public, anon, authenticated;
revoke execute on function private.set_music_genre_search_text() from public, anon, authenticated;
revoke execute on function private.enforce_music_selection_limit() from public, anon, authenticated;
revoke execute on function private.touch_music_preferences() from public, anon, authenticated;
revoke execute on function private.search_music_genres(text, integer) from public, anon, authenticated;
revoke execute on function private.search_music_artists(text, integer) from public, anon, authenticated;
revoke execute on function private.add_music_artist(text) from public, anon, authenticated;
revoke execute on function private.get_music_profile() from public, anon, authenticated;
revoke execute on function private.set_music_settings(boolean, boolean) from public, anon, authenticated;
revoke execute on function private.set_music_artists(uuid[]) from public, anon, authenticated;
revoke execute on function private.set_music_genres(uuid[]) from public, anon, authenticated;
revoke execute on function private.clear_music_preferences() from public, anon, authenticated;
revoke execute on function private.get_public_music_profile(text) from public, anon, authenticated;
revoke execute on function private.discover_music_people(uuid, uuid, integer, integer) from public, anon, authenticated;

grant execute on function private.search_music_genres(text, integer) to anon, authenticated;
grant execute on function private.search_music_artists(text, integer) to anon, authenticated;
grant execute on function private.add_music_artist(text) to authenticated;
grant execute on function private.get_music_profile() to authenticated;
grant execute on function private.set_music_settings(boolean, boolean) to authenticated;
grant execute on function private.set_music_artists(uuid[]) to authenticated;
grant execute on function private.set_music_genres(uuid[]) to authenticated;
grant execute on function private.clear_music_preferences() to authenticated;
grant execute on function private.get_public_music_profile(text) to anon, authenticated;
grant execute on function private.discover_music_people(uuid, uuid, integer, integer) to authenticated;

revoke execute on function public.search_music_genres(text, integer) from public;
revoke execute on function public.search_music_artists(text, integer) from public;
revoke execute on function public.add_music_artist(text) from public, anon;
revoke execute on function public.get_music_profile() from public, anon;
revoke execute on function public.set_music_settings(boolean, boolean) from public, anon;
revoke execute on function public.set_music_artists(uuid[]) from public, anon;
revoke execute on function public.set_music_genres(uuid[]) from public, anon;
revoke execute on function public.clear_music_preferences() from public, anon;
revoke execute on function public.get_public_music_profile(text) from public;
revoke execute on function public.discover_music_people(uuid, uuid, integer, integer) from public, anon;

grant execute on function public.search_music_genres(text, integer) to anon, authenticated;
grant execute on function public.search_music_artists(text, integer) to anon, authenticated;
grant execute on function public.add_music_artist(text) to authenticated;
grant execute on function public.get_music_profile() to authenticated;
grant execute on function public.set_music_settings(boolean, boolean) to authenticated;
grant execute on function public.set_music_artists(uuid[]) to authenticated;
grant execute on function public.set_music_genres(uuid[]) to authenticated;
grant execute on function public.clear_music_preferences() to authenticated;
grant execute on function public.get_public_music_profile(text) to anon, authenticated;
grant execute on function public.discover_music_people(uuid, uuid, integer, integer) to authenticated;
