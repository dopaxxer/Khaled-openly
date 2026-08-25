-- Optional, provider-verified music attachment for a text post.
-- Additive and backwards compatible: the one-argument write RPCs remain
-- available for already-published clients.

alter table public.posts
  add column if not exists track_id uuid references public.music_tracks(id) on delete set null;

create index if not exists posts_track_idx
  on public.posts (track_id)
  where track_id is not null;

-- The existing privilege migration grants SELECT on the whole posts table,
-- while INSERT and UPDATE are column-scoped. Do not grant either write
-- privilege for track_id: attachment writes go through these definer RPCs.

create or replace function private.create_post(p_body text, p_track_id uuid)
returns uuid
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  viewer uuid := (select auth.uid());
  clean_body text := btrim(coalesce(p_body, ''));
  new_id uuid;
begin
  if viewer is null or not private.is_active_user() then
    raise exception 'Unauthorized';
  end if;
  if char_length(clean_body) < 1 or char_length(clean_body) > 3000 then
    raise exception 'Invalid post length';
  end if;
  if p_track_id is not null and not exists (
    select 1
    from public.music_tracks track
    where track.id = p_track_id
  ) then
    raise exception 'Invalid track';
  end if;

  insert into public.posts (author_id, body, track_id)
  values (viewer, clean_body, p_track_id)
  returning id into new_id;

  perform private.sync_mentions('post', new_id, new_id, null, viewer, clean_body);
  return new_id;
end;
$$;

create or replace function public.create_post(p_body text, p_track_id uuid)
returns uuid
language sql
volatile
security invoker
set search_path = ''
as $$ select private.create_post(p_body, p_track_id); $$;

create or replace function private.update_own_post(
  p_post_id uuid,
  p_body text,
  p_track_id uuid
)
returns boolean
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  viewer uuid := (select auth.uid());
  clean_body text := btrim(coalesce(p_body, ''));
  affected bigint;
begin
  if viewer is null or not private.is_active_user() then
    raise exception 'Unauthorized';
  end if;
  if char_length(clean_body) < 1 or char_length(clean_body) > 3000 then
    raise exception 'Invalid post length';
  end if;
  if p_track_id is not null and not exists (
    select 1
    from public.music_tracks track
    where track.id = p_track_id
  ) then
    raise exception 'Invalid track';
  end if;

  update public.posts
  set body = clean_body,
      track_id = p_track_id
  where id = p_post_id
    and author_id = viewer
    and deleted_at is null;

  get diagnostics affected = row_count;
  if affected <> 1 then
    return false;
  end if;

  perform private.sync_mentions('post', p_post_id, p_post_id, null, viewer, clean_body);
  return true;
end;
$$;

create or replace function public.update_own_post(
  p_post_id uuid,
  p_body text,
  p_track_id uuid
)
returns boolean
language sql
volatile
security invoker
set search_path = ''
as $$ select private.update_own_post(p_post_id, p_body, p_track_id); $$;

revoke execute on function private.create_post(text, uuid) from public, anon, authenticated;
grant execute on function private.create_post(text, uuid) to authenticated;

revoke execute on function public.create_post(text, uuid) from public, anon;
grant execute on function public.create_post(text, uuid) to authenticated;

revoke execute on function private.update_own_post(uuid, text, uuid) from public, anon, authenticated;
grant execute on function private.update_own_post(uuid, text, uuid) to authenticated;

revoke execute on function public.update_own_post(uuid, text, uuid) from public, anon;
grant execute on function public.update_own_post(uuid, text, uuid) to authenticated;

-- PostgreSQL cannot replace a function when its RETURNS TABLE shape changes.
-- Drop only these exact signatures, then recreate them in the same migration
-- transaction. Repeating the migration performs the same safe replacement.
drop function if exists public.get_timeline(timestamptz, uuid, integer);
drop function if exists public.get_user_posts(text, integer);
drop function if exists public.search_posts(text, integer);
drop function if exists public.get_bookmarked_posts(integer);
drop function if exists private.get_bookmarked_posts(integer);

create or replace function public.get_timeline(
  p_cursor_created_at timestamptz default null,
  p_cursor_id uuid default null,
  p_limit integer default 30
)
returns table (
  id uuid,
  body text,
  created_at timestamptz,
  author_code text,
  author_color text,
  comment_count bigint,
  track_id uuid,
  track_title text,
  track_artist text,
  track_artwork_url text,
  track_preview_url text,
  track_external_url text
)
language sql
stable
security invoker
set search_path = ''
as $$
  select
    post.id,
    post.body,
    post.created_at,
    profile.public_code::text,
    profile.identity_color::text,
    count(comment.id)::bigint,
    track.id,
    track.title,
    track.artist_name,
    track.artwork_url,
    track.preview_url,
    track.external_url
  from public.posts post
  join public.profiles profile on profile.id = post.author_id
  left join public.comments comment
    on comment.post_id = post.id
   and comment.deleted_at is null
  left join public.music_tracks track on track.id = post.track_id
  where post.deleted_at is null
    and private.can_view_content(post.author_id)
    and (
      p_cursor_created_at is null
      or post.created_at < p_cursor_created_at
      or (post.created_at = p_cursor_created_at and post.id < p_cursor_id)
    )
  group by
    post.id,
    post.body,
    post.created_at,
    profile.public_code,
    profile.identity_color,
    track.id,
    track.title,
    track.artist_name,
    track.artwork_url,
    track.preview_url,
    track.external_url
  order by post.created_at desc, post.id desc
  limit greatest(1, least(coalesce(p_limit, 30), 50));
$$;

create or replace function public.get_user_posts(
  p_public_code text,
  p_limit integer default 100
)
returns table (
  id uuid,
  body text,
  created_at timestamptz,
  author_code text,
  author_color text,
  comment_count bigint,
  track_id uuid,
  track_title text,
  track_artist text,
  track_artwork_url text,
  track_preview_url text,
  track_external_url text
)
language sql
stable
security invoker
set search_path = ''
as $$
  select
    post.id,
    post.body,
    post.created_at,
    profile.public_code::text,
    profile.identity_color::text,
    count(comment.id)::bigint,
    track.id,
    track.title,
    track.artist_name,
    track.artwork_url,
    track.preview_url,
    track.external_url
  from public.posts post
  join public.profiles profile on profile.id = post.author_id
  left join public.comments comment
    on comment.post_id = post.id
   and comment.deleted_at is null
  left join public.music_tracks track on track.id = post.track_id
  where post.deleted_at is null
    and private.can_view_content(post.author_id)
    and profile.public_code = upper(btrim(p_public_code))
  group by
    post.id,
    post.body,
    post.created_at,
    profile.public_code,
    profile.identity_color,
    track.id,
    track.title,
    track.artist_name,
    track.artwork_url,
    track.preview_url,
    track.external_url
  order by post.created_at desc, post.id desc
  limit greatest(1, least(coalesce(p_limit, 100), 100));
$$;

create or replace function public.search_posts(
  p_query text,
  p_limit integer default 30
)
returns table (
  id uuid,
  body text,
  created_at timestamptz,
  author_code text,
  author_color text,
  comment_count bigint,
  track_id uuid,
  track_title text,
  track_artist text,
  track_artwork_url text,
  track_preview_url text,
  track_external_url text
)
language sql
stable
security invoker
set search_path = ''
as $$
  select
    post.id,
    post.body,
    post.created_at,
    profile.public_code::text,
    profile.identity_color::text,
    count(comment.id)::bigint,
    track.id,
    track.title,
    track.artist_name,
    track.artwork_url,
    track.preview_url,
    track.external_url
  from public.posts post
  join public.profiles profile on profile.id = post.author_id
  left join public.comments comment
    on comment.post_id = post.id
   and comment.deleted_at is null
  left join public.music_tracks track on track.id = post.track_id
  where post.deleted_at is null
    and private.can_view_content(post.author_id)
    and char_length(btrim(p_query)) between 1 and 120
    and position(lower(btrim(p_query)) in lower(post.body)) > 0
  group by
    post.id,
    post.body,
    post.created_at,
    profile.public_code,
    profile.identity_color,
    track.id,
    track.title,
    track.artist_name,
    track.artwork_url,
    track.preview_url,
    track.external_url
  order by post.created_at desc, post.id desc
  limit greatest(1, least(coalesce(p_limit, 30), 50));
$$;

create or replace function private.get_bookmarked_posts(p_limit integer default 50)
returns table (
  id uuid,
  body text,
  created_at timestamptz,
  author_code text,
  author_color text,
  comment_count bigint,
  like_count bigint,
  bookmarked_at timestamptz,
  track_id uuid,
  track_title text,
  track_artist text,
  track_artwork_url text,
  track_preview_url text,
  track_external_url text
)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  viewer uuid := (select auth.uid());
begin
  if viewer is null or not private.is_active_user() then
    raise exception 'Unauthorized';
  end if;

  return query
  select
    post.id,
    post.body,
    post.created_at,
    profile.public_code::text,
    profile.identity_color::text,
    (select count(*)::bigint
      from public.comments comment
      where comment.post_id = post.id
        and comment.deleted_at is null),
    (select count(*)::bigint
      from private.post_likes item
      where item.post_id = post.id),
    bookmark.created_at,
    track.id,
    track.title,
    track.artist_name,
    track.artwork_url,
    track.preview_url,
    track.external_url
  from private.bookmarks bookmark
  join public.posts post on post.id = bookmark.post_id
  join public.profiles profile on profile.id = post.author_id
  left join public.music_tracks track on track.id = post.track_id
  where bookmark.user_id = viewer
    and post.deleted_at is null
    and private.can_view_content(post.author_id)
  order by bookmark.created_at desc, post.id desc
  limit greatest(1, least(coalesce(p_limit, 50), 100));
end;
$$;

create or replace function public.get_bookmarked_posts(p_limit integer default 50)
returns table (
  id uuid,
  body text,
  created_at timestamptz,
  author_code text,
  author_color text,
  comment_count bigint,
  like_count bigint,
  bookmarked_at timestamptz,
  track_id uuid,
  track_title text,
  track_artist text,
  track_artwork_url text,
  track_preview_url text,
  track_external_url text
)
language sql
stable
security invoker
set search_path = ''
as $$ select * from private.get_bookmarked_posts(p_limit); $$;

revoke execute on function public.get_timeline(timestamptz, uuid, integer) from public, anon, authenticated;
grant execute on function public.get_timeline(timestamptz, uuid, integer) to anon, authenticated;

revoke execute on function public.get_user_posts(text, integer) from public, anon, authenticated;
grant execute on function public.get_user_posts(text, integer) to anon, authenticated;

revoke execute on function public.search_posts(text, integer) from public, anon, authenticated;
grant execute on function public.search_posts(text, integer) to anon, authenticated;

revoke execute on function private.get_bookmarked_posts(integer) from public, anon, authenticated;
grant execute on function private.get_bookmarked_posts(integer) to authenticated;

revoke execute on function public.get_bookmarked_posts(integer) from public, anon, authenticated;
grant execute on function public.get_bookmarked_posts(integer) to authenticated;
