-- A mutation result is an operation-success flag, not the requested state.
-- Returning false for a successful removal made the API report an error after
-- the row had already been deleted. Keep the existing API contract: true means
-- the mutation completed successfully for both insert and delete paths.

create or replace function private.set_post_like(p_post_id uuid, p_liked boolean)
returns boolean
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  viewer_id uuid := (select auth.uid());
  author_id uuid;
begin
  if viewer_id is null or not private.is_active_user() then
    raise exception 'Unauthorized';
  end if;

  select post.author_id into author_id
  from public.posts post
  where post.id = p_post_id
    and post.deleted_at is null
    and private.can_view_content(post.author_id);

  if author_id is null then raise exception 'Not found'; end if;

  if p_liked then
    insert into private.post_likes (user_id, post_id)
    values (viewer_id, p_post_id)
    on conflict (user_id, post_id) do nothing;
  else
    delete from private.post_likes
    where user_id = viewer_id and post_id = p_post_id;
  end if;

  return true;
end;
$$;

create or replace function private.set_post_bookmark(p_post_id uuid, p_bookmarked boolean)
returns boolean
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  viewer_id uuid := (select auth.uid());
begin
  if viewer_id is null or not private.is_active_user() then
    raise exception 'Unauthorized';
  end if;

  if not exists (
    select 1 from public.posts post
    where post.id = p_post_id
      and post.deleted_at is null
      and private.can_view_content(post.author_id)
  ) then
    raise exception 'Not found';
  end if;

  if p_bookmarked then
    insert into private.bookmarks (user_id, post_id)
    values (viewer_id, p_post_id)
    on conflict (user_id, post_id) do nothing;
  else
    delete from private.bookmarks
    where user_id = viewer_id and post_id = p_post_id;
  end if;

  return true;
end;
$$;
