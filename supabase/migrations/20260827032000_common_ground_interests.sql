begin;

create table if not exists public.interests (
  id uuid primary key default gen_random_uuid(),
  kind text not null check (kind in ('book', 'movie', 'topic')),
  label text not null check (char_length(btrim(label)) between 1 and 160),
  subtitle text null check (subtitle is null or char_length(btrim(subtitle)) <= 160),
  normalized_label text not null,
  normalized_subtitle text not null default '',
  created_by uuid null references public.profiles(id) on delete set null,
  created_at timestamptz not null default now(),
  constraint interests_normalized_label_not_blank check (char_length(normalized_label) between 1 and 160),
  constraint interests_unique_identity unique (kind, normalized_label, normalized_subtitle)
);

create table if not exists public.interest_preferences (
  user_id uuid primary key references public.profiles(id) on delete cascade,
  discovery_opt_in boolean not null default false,
  preferences_public boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.user_interests (
  user_id uuid not null references public.profiles(id) on delete cascade,
  interest_id uuid not null references public.interests(id) on delete cascade,
  position integer not null default 0 check (position between 0 and 35),
  created_at timestamptz not null default now(),
  primary key (user_id, interest_id)
);

create index if not exists user_interests_interest_idx on public.user_interests (interest_id, user_id);
create index if not exists interest_preferences_discovery_idx on public.interest_preferences (discovery_opt_in, user_id);
create index if not exists interests_kind_label_idx on public.interests (kind, normalized_label);

alter table public.interests enable row level security;
alter table public.interest_preferences enable row level security;
alter table public.user_interests enable row level security;

revoke all on table public.interests from public, anon, authenticated;
revoke all on table public.interest_preferences from public, anon, authenticated;
revoke all on table public.user_interests from public, anon, authenticated;

drop policy if exists "No direct interest catalog access" on public.interests;
create policy "No direct interest catalog access"
  on public.interests for all to anon, authenticated
  using (false) with check (false);

drop policy if exists "No direct interest preference access" on public.interest_preferences;
create policy "No direct interest preference access"
  on public.interest_preferences for all to anon, authenticated
  using (false) with check (false);

drop policy if exists "No direct user interest access" on public.user_interests;
create policy "No direct user interest access"
  on public.user_interests for all to anon, authenticated
  using (false) with check (false);

insert into public.interests (kind, label, subtitle, normalized_label, normalized_subtitle)
values
  ('topic', 'علم النفس', 'Psychology', 'علم النفس', 'psychology'),
  ('topic', 'علم الأعصاب', 'Neuroscience', 'علم الأعصاب', 'neuroscience'),
  ('topic', 'الفلسفة', 'Philosophy', 'الفلسفة', 'philosophy'),
  ('topic', 'التقنية', 'Technology', 'التقنية', 'technology'),
  ('topic', 'الفن', 'Art', 'الفن', 'art'),
  ('topic', 'السفر', 'Travel', 'السفر', 'travel'),
  ('topic', 'العلاقات', 'Relationships', 'العلاقات', 'relationships'),
  ('topic', 'السينما', 'Cinema', 'السينما', 'cinema'),
  ('topic', 'الكتب والأدب', 'Books & literature', 'الكتب والأدب', 'books & literature'),
  ('topic', 'الذكاء الاصطناعي', 'Artificial intelligence', 'الذكاء الاصطناعي', 'artificial intelligence'),
  ('book', 'The Stranger', 'Albert Camus', 'the stranger', 'albert camus'),
  ('book', 'Crime and Punishment', 'Fyodor Dostoevsky', 'crime and punishment', 'fyodor dostoevsky'),
  ('book', '1984', 'George Orwell', '1984', 'george orwell'),
  ('book', 'Man''s Search for Meaning', 'Viktor E. Frankl', 'man''s search for meaning', 'viktor e. frankl'),
  ('book', 'The Little Prince', 'Antoine de Saint-Exupéry', 'the little prince', 'antoine de saint-exupéry'),
  ('book', 'The Alchemist', 'Paulo Coelho', 'the alchemist', 'paulo coelho'),
  ('movie', 'Interstellar', 'Christopher Nolan', 'interstellar', 'christopher nolan'),
  ('movie', 'Inception', 'Christopher Nolan', 'inception', 'christopher nolan'),
  ('movie', 'The Matrix', 'The Wachowskis', 'the matrix', 'the wachowskis'),
  ('movie', 'Fight Club', 'David Fincher', 'fight club', 'david fincher'),
  ('movie', 'Her', 'Spike Jonze', 'her', 'spike jonze'),
  ('movie', 'Eternal Sunshine of the Spotless Mind', 'Michel Gondry', 'eternal sunshine of the spotless mind', 'michel gondry')
on conflict (kind, normalized_label, normalized_subtitle) do nothing;

create or replace function private.normalize_interest_text(p_value text)
returns text
language sql
immutable
security invoker
set search_path = ''
as $$
  select lower(regexp_replace(btrim(coalesce(p_value, '')), '[[:space:]]+', ' ', 'g'));
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
        jsonb_build_object(
          'id', interest.id,
          'kind', interest.kind,
          'label', interest.label,
          'subtitle', interest.subtitle,
          'position', link.position
        )
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

create or replace function private.search_interests(
  p_query text default null,
  p_kind text default null,
  p_limit integer default 30
)
returns table (
  id uuid,
  kind text,
  label text,
  subtitle text,
  popularity bigint
)
language sql
stable
security definer
set search_path = ''
as $$
  with query as (
    select private.normalize_interest_text(p_query) as q,
      case when p_kind in ('book', 'movie', 'topic') then p_kind else null end as k
  )
  select interest.id,
    interest.kind,
    interest.label,
    interest.subtitle,
    count(link.user_id)::bigint as popularity
  from public.interests interest
  cross join query
  left join public.user_interests link on link.interest_id = interest.id
  where (query.k is null or interest.kind = query.k)
    and (
      query.q = ''
      or interest.normalized_label like '%' || query.q || '%'
      or interest.normalized_subtitle like '%' || query.q || '%'
    )
  group by interest.id
  order by
    case when query.q <> '' and interest.normalized_label = query.q then 0
         when query.q <> '' and interest.normalized_label like query.q || '%' then 1
         else 2 end,
    count(link.user_id) desc,
    interest.label asc
  limit greatest(1, least(coalesce(p_limit, 30), 50));
$$;

create or replace function private.add_interest(
  p_kind text,
  p_label text,
  p_subtitle text default null
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
  clean_label text := btrim(coalesce(p_label, ''));
  clean_subtitle text := nullif(btrim(coalesce(p_subtitle, '')), '');
  norm_label text;
  norm_subtitle text;
  row_value public.interests%rowtype;
begin
  if viewer is null or not private.is_active_user() then raise exception 'Unauthorized'; end if;
  if clean_kind not in ('book', 'movie', 'topic') then raise exception 'Invalid interest kind'; end if;
  if char_length(clean_label) < 1 or char_length(clean_label) > 160 then raise exception 'Invalid interest label'; end if;
  if clean_subtitle is not null and char_length(clean_subtitle) > 160 then raise exception 'Invalid interest subtitle'; end if;

  norm_label := private.normalize_interest_text(clean_label);
  norm_subtitle := private.normalize_interest_text(clean_subtitle);

  insert into public.interests (kind, label, subtitle, normalized_label, normalized_subtitle, created_by)
  values (clean_kind, clean_label, clean_subtitle, norm_label, norm_subtitle, viewer)
  on conflict (kind, normalized_label, normalized_subtitle) do nothing;

  select * into row_value
  from public.interests interest
  where interest.kind = clean_kind
    and interest.normalized_label = norm_label
    and interest.normalized_subtitle = norm_subtitle;

  return jsonb_build_object(
    'id', row_value.id,
    'kind', row_value.kind,
    'label', row_value.label,
    'subtitle', row_value.subtitle
  );
end;
$$;

create or replace function private.set_interest_profile(
  p_discovery_opt_in boolean,
  p_preferences_public boolean,
  p_interest_ids uuid[]
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  viewer uuid := (select auth.uid());
  clean_ids uuid[] := coalesce(p_interest_ids, array[]::uuid[]);
  total_count integer;
  distinct_count integer;
  invalid_count integer;
  too_many_in_kind boolean;
begin
  if viewer is null or not private.is_active_user() then raise exception 'Unauthorized'; end if;

  total_count := cardinality(clean_ids);
  select count(distinct value)::integer into distinct_count from unnest(clean_ids) value;
  if total_count > 36 then raise exception 'Too many interests'; end if;
  if distinct_count <> total_count then raise exception 'Duplicate interests'; end if;

  select count(*)::integer into invalid_count
  from unnest(clean_ids) value
  left join public.interests interest on interest.id = value
  where interest.id is null;
  if invalid_count > 0 then raise exception 'Unknown interest'; end if;

  select exists (
    select 1
    from unnest(clean_ids) value
    join public.interests interest on interest.id = value
    group by interest.kind
    having count(*) > 12
  ) into too_many_in_kind;
  if too_many_in_kind then raise exception 'Too many interests in one category'; end if;

  insert into public.interest_preferences (user_id, discovery_opt_in, preferences_public, updated_at)
  values (viewer, coalesce(p_discovery_opt_in, false), coalesce(p_preferences_public, false), now())
  on conflict (user_id) do update
  set discovery_opt_in = excluded.discovery_opt_in,
      preferences_public = excluded.preferences_public,
      updated_at = now();

  delete from public.user_interests where user_id = viewer;

  insert into public.user_interests (user_id, interest_id, position)
  select viewer, clean_ids[position], position - 1
  from generate_subscripts(clean_ids, 1) position;

  return private.get_interest_profile();
end;
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
      select jsonb_agg(
        jsonb_build_object(
          'id', interest.id,
          'kind', interest.kind,
          'label', interest.label,
          'subtitle', interest.subtitle
        )
        order by link.position, interest.label
      )
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
    select interest.id, interest.kind, interest.label, interest.subtitle
    from mine
    join theirs on theirs.id = mine.id
    join public.interests interest on interest.id = mine.id
  ),
  counts as (
    select
      count(*) filter (where kind = 'book')::integer as books,
      count(*) filter (where kind = 'movie')::integer as movies,
      count(*) filter (where kind = 'topic')::integer as topics,
      coalesce(jsonb_agg(
        jsonb_build_object('id', id, 'kind', kind, 'label', label, 'subtitle', subtitle)
        order by case kind when 'topic' then 0 when 'book' then 1 else 2 end, label
      ) filter (where id is not null), '[]'::jsonb) as items
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

create or replace function private.discover_interest_people(
  p_kind text default null,
  p_limit integer default 20,
  p_offset integer default 0
)
returns table (
  public_code text,
  identity_color text,
  compatibility integer,
  shared_book_count integer,
  shared_movie_count integer,
  shared_topic_count integer,
  shared_items jsonb,
  music_compatibility integer,
  total_matches bigint
)
language sql
stable
security definer
set search_path = ''
as $$
  with viewer as (select (select auth.uid()) as id),
  candidates as (
    select profile.id, profile.public_code, profile.identity_color, pref.preferences_public
    from public.profiles profile
    join public.interest_preferences pref on pref.user_id = profile.id
    cross join viewer
    where viewer.id is not null
      and profile.id <> viewer.id
      and pref.discovery_opt_in
      and private.can_view_user(profile.id)
      and not exists (
        select 1 from public.mutes mute
        where mute.muter_id = viewer.id and mute.muted_id = profile.id
      )
      and (
        p_kind is null
        or p_kind not in ('book', 'movie', 'topic')
        or exists (
          select 1
          from public.user_interests mine
          join public.user_interests theirs on theirs.interest_id = mine.interest_id
          join public.interests interest on interest.id = mine.interest_id
          where mine.user_id = viewer.id
            and theirs.user_id = profile.id
            and interest.kind = p_kind
        )
      )
  ),
  ranked as (
    select candidate.*,
      similarity.compatibility,
      similarity.shared_book_count,
      similarity.shared_movie_count,
      similarity.shared_topic_count,
      case when candidate.preferences_public then similarity.shared_items else '[]'::jsonb end as shared_items,
      similarity.music_compatibility
    from candidates candidate
    cross join lateral private.taste_similarity_to(candidate.id) similarity
    where similarity.compatibility > 0
  )
  select ranked.public_code::text,
    ranked.identity_color::text,
    ranked.compatibility,
    ranked.shared_book_count,
    ranked.shared_movie_count,
    ranked.shared_topic_count,
    ranked.shared_items,
    ranked.music_compatibility,
    count(*) over () as total_matches
  from ranked
  order by ranked.compatibility desc, ranked.public_code asc
  limit greatest(1, least(coalesce(p_limit, 20), 50))
  offset greatest(0, least(coalesce(p_offset, 0), 500));
$$;

create or replace function public.get_interest_profile()
returns jsonb language sql stable security invoker set search_path = ''
as $$ select private.get_interest_profile(); $$;

create or replace function public.search_interests(p_query text default null, p_kind text default null, p_limit integer default 30)
returns table (id uuid, kind text, label text, subtitle text, popularity bigint)
language sql stable security invoker set search_path = ''
as $$ select * from private.search_interests(p_query, p_kind, p_limit); $$;

create or replace function public.add_interest(p_kind text, p_label text, p_subtitle text default null)
returns jsonb language sql volatile security invoker set search_path = ''
as $$ select private.add_interest(p_kind, p_label, p_subtitle); $$;

create or replace function public.set_interest_profile(p_discovery_opt_in boolean, p_preferences_public boolean, p_interest_ids uuid[])
returns jsonb language sql volatile security invoker set search_path = ''
as $$ select private.set_interest_profile(p_discovery_opt_in, p_preferences_public, p_interest_ids); $$;

create or replace function public.get_public_interest_profile(p_public_code text)
returns jsonb language sql stable security invoker set search_path = ''
as $$ select private.get_public_interest_profile(p_public_code); $$;

create or replace function public.discover_interest_people(p_kind text default null, p_limit integer default 20, p_offset integer default 0)
returns table (
  public_code text,
  identity_color text,
  compatibility integer,
  shared_book_count integer,
  shared_movie_count integer,
  shared_topic_count integer,
  shared_items jsonb,
  music_compatibility integer,
  total_matches bigint
)
language sql stable security invoker set search_path = ''
as $$ select * from private.discover_interest_people(p_kind, p_limit, p_offset); $$;

revoke execute on function private.normalize_interest_text(text) from public, anon, authenticated;
revoke execute on function private.get_interest_profile() from public, anon, authenticated;
revoke execute on function private.search_interests(text, text, integer) from public, anon, authenticated;
revoke execute on function private.add_interest(text, text, text) from public, anon, authenticated;
revoke execute on function private.set_interest_profile(boolean, boolean, uuid[]) from public, anon, authenticated;
revoke execute on function private.get_public_interest_profile(text) from public, anon, authenticated;
revoke execute on function private.taste_similarity_to(uuid) from public, anon, authenticated;
revoke execute on function private.discover_interest_people(text, integer, integer) from public, anon, authenticated;

grant execute on function private.get_interest_profile() to authenticated;
grant execute on function private.search_interests(text, text, integer) to authenticated;
grant execute on function private.add_interest(text, text, text) to authenticated;
grant execute on function private.set_interest_profile(boolean, boolean, uuid[]) to authenticated;
grant execute on function private.get_public_interest_profile(text) to anon, authenticated;
grant execute on function private.discover_interest_people(text, integer, integer) to authenticated;

revoke execute on function public.get_interest_profile() from public, anon;
revoke execute on function public.search_interests(text, text, integer) from public, anon;
revoke execute on function public.add_interest(text, text, text) from public, anon;
revoke execute on function public.set_interest_profile(boolean, boolean, uuid[]) from public, anon;
revoke execute on function public.get_public_interest_profile(text) from public;
revoke execute on function public.discover_interest_people(text, integer, integer) from public, anon;

grant execute on function public.get_interest_profile() to authenticated;
grant execute on function public.search_interests(text, text, integer) to authenticated;
grant execute on function public.add_interest(text, text, text) to authenticated;
grant execute on function public.set_interest_profile(boolean, boolean, uuid[]) to authenticated;
grant execute on function public.get_public_interest_profile(text) to anon, authenticated;
grant execute on function public.discover_interest_people(text, integer, integer) to authenticated;

commit;
