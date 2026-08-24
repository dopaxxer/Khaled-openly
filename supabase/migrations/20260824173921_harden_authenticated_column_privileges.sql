-- Keep RLS as the row boundary and use column grants as the field boundary.
-- This prevents authenticated clients from rewriting immutable IDs/timestamps
-- through PostgREST while preserving the fields used by the application.

create or replace function private.delete_own_post(p_post_id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  affected bigint;
begin
  if (select auth.uid()) is null or not private.is_active_user() then
    raise exception 'Unauthorized';
  end if;

  update public.posts
  set deleted_at = now()
  where id = p_post_id
    and author_id = (select auth.uid())
    and deleted_at is null;

  get diagnostics affected = row_count;
  return affected = 1;
end;
$$;

create or replace function public.delete_own_post(p_post_id uuid)
returns boolean
language sql
set search_path = ''
as $$ select private.delete_own_post(p_post_id); $$;

create or replace function private.delete_own_comment(p_comment_id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  affected bigint;
begin
  if (select auth.uid()) is null or not private.is_active_user() then
    raise exception 'Unauthorized';
  end if;

  update public.comments
  set deleted_at = now()
  where id = p_comment_id
    and author_id = (select auth.uid())
    and deleted_at is null;

  get diagnostics affected = row_count;
  return affected = 1;
end;
$$;

create or replace function public.delete_own_comment(p_comment_id uuid)
returns boolean
language sql
set search_path = ''
as $$ select private.delete_own_comment(p_comment_id); $$;

revoke all on function private.delete_own_post(uuid) from public;
revoke all on function private.delete_own_comment(uuid) from public;
revoke all on function public.delete_own_post(uuid) from public;
revoke all on function public.delete_own_comment(uuid) from public;
grant execute on function private.delete_own_post(uuid) to authenticated;
grant execute on function private.delete_own_comment(uuid) to authenticated;
grant execute on function public.delete_own_post(uuid) to authenticated;
grant execute on function public.delete_own_comment(uuid) to authenticated;

revoke insert, update on table public.profiles from authenticated;
grant update (public_code, identity_color, status, bio) on table public.profiles to authenticated;

revoke insert, update on table public.posts from authenticated;
grant insert (author_id, body) on table public.posts to authenticated;
grant update (body) on table public.posts to authenticated;

revoke insert, update on table public.comments from authenticated;
grant insert (post_id, author_id, parent_comment_id, body) on table public.comments to authenticated;

revoke insert on table public.follows from authenticated;
grant insert (follower_id, followed_id) on table public.follows to authenticated;

revoke insert on table public.mutes from authenticated;
grant insert (muter_id, muted_id) on table public.mutes to authenticated;

revoke insert on table public.blocks from authenticated;
grant insert (blocker_id, blocked_id) on table public.blocks to authenticated;

revoke insert, update on table public.reports from authenticated;
grant insert (reporter_id, target_type, target_id, reason, description) on table public.reports to authenticated;

revoke insert on table public.device_visits from authenticated;
grant insert (
  user_id,
  session_id,
  page_path,
  device_type,
  device_model,
  os,
  os_version,
  browser,
  browser_version,
  user_agent,
  platform,
  language,
  timezone,
  screen_width,
  screen_height,
  pixel_ratio,
  touch_points
) on table public.device_visits to authenticated;
