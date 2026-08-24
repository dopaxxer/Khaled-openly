-- Additive, backwards-compatible product capabilities for Openly.
-- Existing identities, posts, comments, relationships and moderation data are preserved.

alter table public.profiles
  add column if not exists status text,
  add column if not exists bio text;

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'profiles_status_length' and conrelid = 'public.profiles'::regclass
  ) then
    alter table public.profiles
      add constraint profiles_status_length
      check (status is null or char_length(status) <= 60);
  end if;

  if not exists (
    select 1 from pg_constraint
    where conname = 'profiles_bio_length' and conrelid = 'public.profiles'::regclass
  ) then
    alter table public.profiles
      add constraint profiles_bio_length
      check (bio is null or char_length(bio) <= 240);
  end if;
end;
$$;

create table if not exists private.post_likes (
  user_id uuid not null references public.profiles(id) on delete cascade,
  post_id uuid not null references public.posts(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (user_id, post_id)
);

create table if not exists private.bookmarks (
  user_id uuid not null references public.profiles(id) on delete cascade,
  post_id uuid not null references public.posts(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (user_id, post_id)
);

create table if not exists private.notifications (
  id uuid primary key default gen_random_uuid(),
  recipient_id uuid not null references public.profiles(id) on delete cascade,
  actor_id uuid not null references public.profiles(id) on delete cascade,
  kind text not null check (kind in ('reply', 'like')),
  post_id uuid not null references public.posts(id) on delete cascade,
  comment_id uuid references public.comments(id) on delete cascade,
  read_at timestamptz,
  created_at timestamptz not null default now(),
  constraint notifications_not_self check (recipient_id <> actor_id),
  constraint notifications_comment_shape check (
    (kind = 'reply' and comment_id is not null)
    or (kind = 'like' and comment_id is null)
  )
);

create table if not exists private.account_deletion_requests (
  user_id uuid primary key references public.profiles(id) on delete cascade,
  requested_at timestamptz not null default now()
);

create index if not exists post_likes_post_created_idx
  on private.post_likes (post_id, created_at desc);
create index if not exists bookmarks_user_created_idx
  on private.bookmarks (user_id, created_at desc, post_id);
create index if not exists notifications_recipient_created_idx
  on private.notifications (recipient_id, created_at desc, id desc);
create index if not exists notifications_recipient_unread_idx
  on private.notifications (recipient_id, created_at desc)
  where read_at is null;
create unique index if not exists notifications_like_unique_idx
  on private.notifications (recipient_id, actor_id, post_id, kind)
  where kind = 'like';
create unique index if not exists notifications_reply_unique_idx
  on private.notifications (recipient_id, actor_id, comment_id, kind)
  where kind = 'reply';

alter table private.post_likes enable row level security;
alter table private.bookmarks enable row level security;
alter table private.notifications enable row level security;
alter table private.account_deletion_requests enable row level security;

drop policy if exists post_likes_explicit_deny on private.post_likes;
create policy post_likes_explicit_deny on private.post_likes
for all to anon, authenticated using (false) with check (false);

drop policy if exists bookmarks_explicit_deny on private.bookmarks;
create policy bookmarks_explicit_deny on private.bookmarks
for all to anon, authenticated using (false) with check (false);

drop policy if exists notifications_explicit_deny on private.notifications;
create policy notifications_explicit_deny on private.notifications
for all to anon, authenticated using (false) with check (false);

drop policy if exists account_deletion_requests_explicit_deny on private.account_deletion_requests;
create policy account_deletion_requests_explicit_deny on private.account_deletion_requests
for all to anon, authenticated using (false) with check (false);

drop policy if exists profiles_owner_update on public.profiles;
create policy profiles_owner_update on public.profiles
for update to authenticated
using (id = (select auth.uid()) and private.is_active_user())
with check (id = (select auth.uid()) and private.is_active_user());

revoke update on table public.profiles from anon, authenticated;
grant update (status, bio) on table public.profiles to authenticated;

create or replace function private.get_post_engagement(p_post_ids uuid[])
returns table (
  post_id uuid,
  like_count bigint,
  viewer_has_liked boolean,
  viewer_has_bookmarked boolean
)
language sql
stable
security definer
set search_path = ''
as $$
  select
    post.id,
    (select count(*)::bigint from private.post_likes item where item.post_id = post.id),
    case when (select auth.uid()) is null then false else exists (
      select 1 from private.post_likes item
      where item.post_id = post.id and item.user_id = (select auth.uid())
    ) end,
    case when (select auth.uid()) is null then false else exists (
      select 1 from private.bookmarks item
      where item.post_id = post.id and item.user_id = (select auth.uid())
    ) end
  from public.posts post
  where post.id = any(coalesce(p_post_ids, array[]::uuid[]))
    and post.deleted_at is null
    and private.can_view_content(post.author_id);
$$;

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

  return p_liked;
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

  return p_bookmarked;
end;
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
  bookmarked_at timestamptz
)
language sql
stable
security definer
set search_path = ''
as $$
  select
    post.id,
    post.body,
    post.created_at,
    profile.public_code::text,
    profile.identity_color::text,
    (select count(*)::bigint from public.comments comment
      where comment.post_id = post.id and comment.deleted_at is null),
    (select count(*)::bigint from private.post_likes item where item.post_id = post.id),
    bookmark.created_at
  from private.bookmarks bookmark
  join public.posts post on post.id = bookmark.post_id
  join public.profiles profile on profile.id = post.author_id
  where bookmark.user_id = (select auth.uid())
    and post.deleted_at is null
    and private.can_view_content(post.author_id)
  order by bookmark.created_at desc, post.id desc
  limit greatest(1, least(coalesce(p_limit, 50), 100));
$$;

create or replace function private.create_like_notification()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  target_id uuid;
begin
  select post.author_id into target_id from public.posts post where post.id = new.post_id;
  if target_id is null or target_id = new.user_id then return new; end if;

  insert into private.notifications (recipient_id, actor_id, kind, post_id)
  values (target_id, new.user_id, 'like', new.post_id)
  on conflict do nothing;
  return new;
end;
$$;

create or replace function private.create_reply_notification()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  target_id uuid;
begin
  if new.parent_comment_id is not null then
    select comment.author_id into target_id
    from public.comments comment where comment.id = new.parent_comment_id;
  else
    select post.author_id into target_id
    from public.posts post where post.id = new.post_id;
  end if;

  if target_id is null or target_id = new.author_id then return new; end if;

  insert into private.notifications (recipient_id, actor_id, kind, post_id, comment_id)
  values (target_id, new.author_id, 'reply', new.post_id, new.id)
  on conflict do nothing;
  return new;
end;
$$;

drop trigger if exists post_likes_create_notification on private.post_likes;
create trigger post_likes_create_notification
after insert on private.post_likes
for each row execute function private.create_like_notification();

drop trigger if exists comments_create_notification on public.comments;
create trigger comments_create_notification
after insert on public.comments
for each row execute function private.create_reply_notification();

create or replace function private.get_notifications(p_limit integer default 50)
returns table (
  id uuid,
  kind text,
  post_id uuid,
  comment_id uuid,
  actor_code text,
  actor_color text,
  read_at timestamptz,
  created_at timestamptz
)
language sql
stable
security definer
set search_path = ''
as $$
  select
    notification.id,
    notification.kind,
    notification.post_id,
    notification.comment_id,
    actor.public_code::text,
    actor.identity_color::text,
    notification.read_at,
    notification.created_at
  from private.notifications notification
  join public.profiles actor on actor.id = notification.actor_id
  join public.posts post on post.id = notification.post_id and post.deleted_at is null
  where notification.recipient_id = (select auth.uid())
    and private.can_view_content(notification.actor_id)
  order by notification.created_at desc, notification.id desc
  limit greatest(1, least(coalesce(p_limit, 50), 100));
$$;

create or replace function private.get_unread_notification_count()
returns bigint
language sql
stable
security definer
set search_path = ''
as $$
  select case when (select auth.uid()) is null then 0::bigint else count(*)::bigint end
  from private.notifications notification
  where notification.recipient_id = (select auth.uid())
    and notification.read_at is null
    and private.can_view_content(notification.actor_id);
$$;

create or replace function private.mark_notifications_read(p_ids uuid[] default null)
returns bigint
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  affected bigint;
begin
  if (select auth.uid()) is null then raise exception 'Unauthorized'; end if;

  update private.notifications
  set read_at = coalesce(read_at, now())
  where recipient_id = (select auth.uid())
    and read_at is null
    and (p_ids is null or id = any(p_ids));

  get diagnostics affected = row_count;
  return affected;
end;
$$;

create or replace function private.request_account_deletion()
returns boolean
language plpgsql
volatile
security definer
set search_path = ''
as $$
begin
  if (select auth.uid()) is null then raise exception 'Unauthorized'; end if;
  insert into private.account_deletion_requests (user_id, requested_at)
  values ((select auth.uid()), now())
  on conflict (user_id) do update set requested_at = excluded.requested_at;
  return true;
end;
$$;

create or replace function public.get_post_engagement(p_post_ids uuid[])
returns table (
  post_id uuid,
  like_count bigint,
  viewer_has_liked boolean,
  viewer_has_bookmarked boolean
)
language sql
stable
security invoker
set search_path = ''
as $$ select * from private.get_post_engagement(p_post_ids); $$;

create or replace function public.set_post_like(p_post_id uuid, p_liked boolean)
returns boolean
language sql
volatile
security invoker
set search_path = ''
as $$ select private.set_post_like(p_post_id, p_liked); $$;

create or replace function public.set_post_bookmark(p_post_id uuid, p_bookmarked boolean)
returns boolean
language sql
volatile
security invoker
set search_path = ''
as $$ select private.set_post_bookmark(p_post_id, p_bookmarked); $$;

create or replace function public.get_bookmarked_posts(p_limit integer default 50)
returns table (
  id uuid,
  body text,
  created_at timestamptz,
  author_code text,
  author_color text,
  comment_count bigint,
  like_count bigint,
  bookmarked_at timestamptz
)
language sql
stable
security invoker
set search_path = ''
as $$ select * from private.get_bookmarked_posts(p_limit); $$;

create or replace function public.get_notifications(p_limit integer default 50)
returns table (
  id uuid,
  kind text,
  post_id uuid,
  comment_id uuid,
  actor_code text,
  actor_color text,
  read_at timestamptz,
  created_at timestamptz
)
language sql
stable
security invoker
set search_path = ''
as $$ select * from private.get_notifications(p_limit); $$;

create or replace function public.get_unread_notification_count()
returns bigint
language sql
stable
security invoker
set search_path = ''
as $$ select private.get_unread_notification_count(); $$;

create or replace function public.mark_notifications_read(p_ids uuid[] default null)
returns bigint
language sql
volatile
security invoker
set search_path = ''
as $$ select private.mark_notifications_read(p_ids); $$;

create or replace function public.request_account_deletion()
returns boolean
language sql
volatile
security invoker
set search_path = ''
as $$ select private.request_account_deletion(); $$;

revoke all on table private.post_likes from public, anon, authenticated;
revoke all on table private.bookmarks from public, anon, authenticated;
revoke all on table private.notifications from public, anon, authenticated;
revoke all on table private.account_deletion_requests from public, anon, authenticated;

revoke execute on function private.get_post_engagement(uuid[]) from public, anon, authenticated;
revoke execute on function private.set_post_like(uuid, boolean) from public, anon, authenticated;
revoke execute on function private.set_post_bookmark(uuid, boolean) from public, anon, authenticated;
revoke execute on function private.get_bookmarked_posts(integer) from public, anon, authenticated;
revoke execute on function private.get_notifications(integer) from public, anon, authenticated;
revoke execute on function private.get_unread_notification_count() from public, anon, authenticated;
revoke execute on function private.mark_notifications_read(uuid[]) from public, anon, authenticated;
revoke execute on function private.request_account_deletion() from public, anon, authenticated;
revoke execute on function private.create_like_notification() from public, anon, authenticated;
revoke execute on function private.create_reply_notification() from public, anon, authenticated;

grant execute on function private.get_post_engagement(uuid[]) to anon, authenticated;
grant execute on function private.set_post_like(uuid, boolean) to authenticated;
grant execute on function private.set_post_bookmark(uuid, boolean) to authenticated;
grant execute on function private.get_bookmarked_posts(integer) to authenticated;
grant execute on function private.get_notifications(integer) to authenticated;
grant execute on function private.get_unread_notification_count() to authenticated;
grant execute on function private.mark_notifications_read(uuid[]) to authenticated;
grant execute on function private.request_account_deletion() to authenticated;

revoke execute on function public.get_post_engagement(uuid[]) from public;
revoke execute on function public.set_post_like(uuid, boolean) from public, anon;
revoke execute on function public.set_post_bookmark(uuid, boolean) from public, anon;
revoke execute on function public.get_bookmarked_posts(integer) from public, anon;
revoke execute on function public.get_notifications(integer) from public, anon;
revoke execute on function public.get_unread_notification_count() from public, anon;
revoke execute on function public.mark_notifications_read(uuid[]) from public, anon;
revoke execute on function public.request_account_deletion() from public, anon;

grant execute on function public.get_post_engagement(uuid[]) to anon, authenticated;
grant execute on function public.set_post_like(uuid, boolean) to authenticated;
grant execute on function public.set_post_bookmark(uuid, boolean) to authenticated;
grant execute on function public.get_bookmarked_posts(integer) to authenticated;
grant execute on function public.get_notifications(integer) to authenticated;
grant execute on function public.get_unread_notification_count() to authenticated;
grant execute on function public.mark_notifications_read(uuid[]) to authenticated;
grant execute on function public.request_account_deletion() to authenticated;

