begin;

alter table public.interests
  add column if not exists provider text,
  add column if not exists external_id text,
  add column if not exists artwork_url text,
  add column if not exists release_year integer,
  add column if not exists external_url text;

alter table public.interests
  drop constraint if exists interests_provider_check,
  add constraint interests_provider_check
    check (provider is null or provider in ('apple_books', 'apple_movies')),
  drop constraint if exists interests_release_year_check,
  add constraint interests_release_year_check
    check (release_year is null or release_year between 1000 and 3000),
  drop constraint if exists interests_catalog_pair_check,
  add constraint interests_catalog_pair_check
    check (
      (provider is null and external_id is null)
      or
      (provider is not null and external_id is not null)
    ),
  drop constraint if exists interests_catalog_kind_check,
  add constraint interests_catalog_kind_check
    check (
      provider is null
      or (kind = 'book' and provider = 'apple_books')
      or (kind = 'movie' and provider = 'apple_movies')
    );

create unique index if not exists interests_provider_external_id_unique
  on public.interests (provider, external_id)
  where provider is not null and external_id is not null;

create or replace function private.interest_json(p_interest public.interests)
returns jsonb
language sql
immutable
security invoker
set search_path = ''
as $$
  select jsonb_build_object(
    'id', p_interest.id,
    'kind', p_interest.kind,
    'label', p_interest.label,
    'subtitle', p_interest.subtitle,
    'provider', p_interest.provider,
    'externalId', p_interest.external_id,
    'artworkUrl', p_interest.artwork_url,
    'releaseYear', p_interest.release_year,
    'externalUrl', p_interest.external_url
  );
$$;

create or replace function private.add_catalog_interest(
  p_kind text,
  p_provider text,
  p_external_id text,
  p_label text,
  p_subtitle text default null,
  p_artwork_url text default null,
  p_release_year integer default null,
  p_external_url text default null
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  viewer uuid := (select auth.uid());
  clean_kind text := lower(btrim(coalesce(p_kind, '')));
  clean_provider text := lower(btrim(coalesce(p_provider, '')));
  clean_external_id text := btrim(coalesce(p_external_id, ''));
  clean_label text := btrim(coalesce(p_label, ''));
  clean_subtitle text := nullif(btrim(coalesce(p_subtitle, '')), '');
  norm_label text;
  norm_subtitle text;
  row_value public.interests%rowtype;
begin
  if viewer is null or not private.is_active_user() then raise exception 'Unauthorized'; end if;
  if clean_kind not in ('book', 'movie') then raise exception 'Invalid catalog interest kind'; end if;
  if (clean_kind = 'book' and clean_provider <> 'apple_books')
     or (clean_kind = 'movie' and clean_provider <> 'apple_movies') then
    raise exception 'Invalid catalog provider';
  end if;
  if clean_external_id !~ '^[0-9]{1,20}$' then raise exception 'Invalid external id'; end if;
  if char_length(clean_label) < 1 or char_length(clean_label) > 160 then raise exception 'Invalid interest label'; end if;
  if clean_subtitle is not null and char_length(clean_subtitle) > 160 then raise exception 'Invalid interest subtitle'; end if;
  if p_artwork_url is not null and (char_length(p_artwork_url) > 1000 or p_artwork_url !~ '^https://') then
    raise exception 'Invalid artwork url';
  end if;
  if p_external_url is not null and (char_length(p_external_url) > 1000 or p_external_url !~ '^https://') then
    raise exception 'Invalid external url';
  end if;
  if p_release_year is not null and (p_release_year < 1000 or p_release_year > 3000) then
    raise exception 'Invalid release year';
  end if;

  select * into row_value
  from public.interests interest
  where interest.provider = clean_provider
    and interest.external_id = clean_external_id;

  if row_value.id is not null then
    update public.interests
    set label = clean_label,
        subtitle = clean_subtitle,
        normalized_label = private.normalize_interest_text(clean_label),
        normalized_subtitle = private.normalize_interest_text(clean_subtitle),
        artwork_url = coalesce(p_artwork_url, artwork_url),
        release_year = coalesce(p_release_year, release_year),
        external_url = coalesce(p_external_url, external_url)
    where id = row_value.id
    returning * into row_value;

    return private.interest_json(row_value);
  end if;

  norm_label := private.normalize_interest_text(clean_label);
  norm_subtitle := private.normalize_interest_text(clean_subtitle);

  insert into public.interests (
    kind, label, subtitle, normalized_label, normalized_subtitle,
    created_by, provider, external_id, artwork_url, release_year, external_url
  )
  values (
    clean_kind, clean_label, clean_subtitle, norm_label, norm_subtitle,
    viewer, clean_provider, clean_external_id, p_artwork_url, p_release_year, p_external_url
  )
  on conflict (kind, normalized_label, normalized_subtitle) do update
  set provider = coalesce(public.interests.provider, excluded.provider),
      external_id = coalesce(public.interests.external_id, excluded.external_id),
      artwork_url = coalesce(excluded.artwork_url, public.interests.artwork_url),
      release_year = coalesce(excluded.release_year, public.interests.release_year),
      external_url = coalesce(excluded.external_url, public.interests.external_url)
  returning * into row_value;

  return private.interest_json(row_value);
end;
$$;

create or replace function private.get_interest_profile()
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  with viewer as (select (select auth.uid()) as id)
  select jsonb_build_object(
    'discoveryOptIn', coalesce(pref.discovery_opt_in, false),
    'preferencesPublic', coalesce(pref.preferences_public, false),
    'items', coalesce((
      select jsonb_agg(
        private.interest_json(interest) || jsonb_build_object('position', link.position)
        order by link.position, interest.label
      )
      from public.user_interests link
      join public.interests interest on interest.id = link.interest_id
      where link.user_id = viewer.id
    ), '[]'::jsonb)
  )
  from viewer
  left join public.interest_preferences pref on pref.user_id = viewer.id
  where viewer.id is not null;
$$;

create or replace function private.get_public_interest_profile(p_public_code text)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object(
    'publicCode', profile.public_code,
    'identityColor', profile.identity_color,
    'items', coalesce((
      select jsonb_agg(private.interest_json(interest) order by link.position, interest.label)
      from public.user_interests link
      join public.interests interest on interest.id = link.interest_id
      where link.user_id = profile.id
    ), '[]'::jsonb)
  )
  from public.profiles profile
  join public.interest_preferences pref on pref.user_id = profile.id
  where profile.public_code = upper(btrim(coalesce(p_public_code, '')))
    and pref.preferences_public
    and private.can_view_content(profile.id);
$$;

create or replace function private.taste_similarity_to(p_target_id uuid)
returns table (
  compatibility integer,
  shared_book_count integer,
  shared_movie_count integer,
  shared_topic_count integer,
  shared_items jsonb,
  music_compatibility integer
)
language sql
stable
security definer
set search_path = ''
as $$
  with viewer as (select (select auth.uid()) as id),
  mine as (
    select interest.id, interest.kind
    from public.user_interests link
    join public.interests interest on interest.id = link.interest_id
    cross join viewer
    where link.user_id = viewer.id
  ),
  theirs as (
    select interest.id, interest.kind
    from public.user_interests link
    join public.interests interest on interest.id = link.interest_id
    where link.user_id = p_target_id
  ),
  overlap as (
    select interest.*
    from mine
    join theirs on theirs.id = mine.id
    join public.interests interest on interest.id = mine.id
  ),
  counts as (
    select
      count(*) filter (where kind = 'book')::integer as books,
      count(*) filter (where kind = 'movie')::integer as movies,
      count(*) filter (where kind = 'topic')::integer as topics,
      coalesce(
        jsonb_agg(
          private.interest_json(overlap)
          order by case kind when 'topic' then 0 when 'book' then 1 else 2 end, label
        ) filter (where id is not null),
        '[]'::jsonb
      ) as items
    from overlap
  ),
  totals as (
    select
      (select count(*) from mine where kind = 'book')::integer as my_books,
      (select count(*) from theirs where kind = 'book')::integer as their_books,
      (select count(*) from mine where kind = 'movie')::integer as my_movies,
      (select count(*) from theirs where kind = 'movie')::integer as their_movies,
      (select count(*) from mine where kind = 'topic')::integer as my_topics,
      (select count(*) from theirs where kind = 'topic')::integer as their_topics
  ),
  music as (
    select case
      when exists (
        select 1
        from public.music_preferences pref
        where pref.user_id = p_target_id and pref.discovery_opt_in
      )
      then coalesce((select similarity.compatibility from private.music_similarity_to(p_target_id) similarity), 0)
      else 0
    end::integer as score
  ),
  score as (
    select counts.*,
      music.score as music_score,
      (2 * counts.books + 2 * counts.movies + 3 * counts.topics)::numeric as generic_raw,
      (2 * least(totals.my_books, totals.their_books)
        + 2 * least(totals.my_movies, totals.their_movies)
        + 3 * least(totals.my_topics, totals.their_topics))::numeric as generic_ceiling
    from counts, totals, music
  )
  select
    case
      when score.generic_raw <= 0 and score.music_score <= 0 then 0
      else round(
        100
        * case
            when score.generic_ceiling > 0 and score.music_score > 0
              then 0.75 * least(1::numeric, score.generic_raw / score.generic_ceiling)
                 + 0.25 * (score.music_score::numeric / 100)
            when score.generic_ceiling > 0
              then least(1::numeric, score.generic_raw / score.generic_ceiling)
            else score.music_score::numeric / 100
          end
        * least(1::numeric, (score.generic_raw + score.music_score::numeric / 20) / 6)
      )::integer
    end as compatibility,
    score.books,
    score.movies,
    score.topics,
    score.items,
    score.music_score
  from score;
$$;

create or replace function public.add_catalog_interest(
  p_kind text,
  p_provider text,
  p_external_id text,
  p_label text,
  p_subtitle text default null,
  p_artwork_url text default null,
  p_release_year integer default null,
  p_external_url text default null
)
returns jsonb
language sql
volatile
security invoker
set search_path = ''
as $$
  select private.add_catalog_interest(
    p_kind, p_provider, p_external_id, p_label, p_subtitle,
    p_artwork_url, p_release_year, p_external_url
  );
$$;

revoke execute on function private.interest_json(public.interests) from public, anon, authenticated;
revoke execute on function private.add_catalog_interest(text, text, text, text, text, text, integer, text)
  from public, anon, authenticated;
grant execute on function private.add_catalog_interest(text, text, text, text, text, text, integer, text)
  to authenticated;

revoke execute on function public.add_catalog_interest(text, text, text, text, text, text, integer, text)
  from public, anon;
grant execute on function public.add_catalog_interest(text, text, text, text, text, text, integer, text)
  to authenticated;

commit;
