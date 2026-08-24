create extension if not exists pgcrypto with schema extensions;

create schema if not exists private;
revoke all on schema private from public, anon, authenticated;

create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  public_code varchar(8) not null unique,
  identity_color varchar(7) not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint profiles_public_code_format check (public_code ~ '^[A-HJ-NP-Z2-9]{4,8}$'),
  constraint profiles_identity_color_format check (identity_color ~ '^#[0-9A-F]{6}$')
);

create table private.accounts (
  user_id uuid primary key references auth.users(id) on delete cascade,
  status text not null default 'active' check (status in ('active', 'suspended', 'banned')),
  role text not null default 'user' check (role in ('user', 'admin')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.posts (
  id uuid primary key default gen_random_uuid(),
  author_id uuid not null references public.profiles(id) on delete cascade,
  body text not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  constraint posts_body_length check (char_length(btrim(body)) between 1 and 3000)
);

create table public.comments (
  id uuid primary key default gen_random_uuid(),
  post_id uuid not null references public.posts(id) on delete cascade,
  author_id uuid not null references public.profiles(id) on delete cascade,
  parent_comment_id uuid references public.comments(id) on delete set null,
  body text not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  constraint comments_body_length check (char_length(btrim(body)) between 1 and 2000)
);

create table public.follows (
  follower_id uuid not null references public.profiles(id) on delete cascade,
  followed_id uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (follower_id, followed_id),
  constraint follows_not_self check (follower_id <> followed_id)
);

create table public.mutes (
  muter_id uuid not null references public.profiles(id) on delete cascade,
  muted_id uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (muter_id, muted_id),
  constraint mutes_not_self check (muter_id <> muted_id)
);

create table public.blocks (
  blocker_id uuid not null references public.profiles(id) on delete cascade,
  blocked_id uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (blocker_id, blocked_id),
  constraint blocks_not_self check (blocker_id <> blocked_id)
);

create table public.reports (
  id uuid primary key default gen_random_uuid(),
  reporter_id uuid not null references public.profiles(id) on delete cascade,
  target_type text not null check (target_type in ('post', 'comment')),
  target_id uuid not null,
  reason text not null check (reason in ('spam', 'harassment', 'hate', 'threat', 'sexual', 'illegal', 'other')),
  description text,
  status text not null default 'open' check (status in ('open', 'reviewing', 'resolved', 'dismissed')),
  created_at timestamptz not null default now(),
  constraint reports_description_length check (description is null or char_length(description) <= 1000)
);

create index posts_timeline_idx on public.posts (created_at desc, id desc) where deleted_at is null;
create index posts_author_timeline_idx on public.posts (author_id, created_at desc, id desc) where deleted_at is null;
create index comments_post_timeline_idx on public.comments (post_id, created_at, id) where deleted_at is null;
create index comments_author_idx on public.comments (author_id);
create index comments_parent_idx on public.comments (parent_comment_id) where parent_comment_id is not null;
create index follows_followed_idx on public.follows (followed_id);
create index mutes_muted_idx on public.mutes (muted_id);
create index blocks_blocked_idx on public.blocks (blocked_id, blocker_id);
create index reports_status_created_idx on public.reports (status, created_at desc);
create index reports_reporter_created_idx on public.reports (reporter_id, created_at desc);

create or replace function private.generate_public_code()
returns text
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  alphabet constant text := 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';
  candidate text;
  code_length integer;
  attempt integer;
  position integer;
begin
  for attempt in 1..60 loop
    code_length := case when attempt <= 45 then 4 else 5 end;
    candidate := '';
    for position in 1..code_length loop
      candidate := candidate || substr(alphabet, 1 + floor(random() * length(alphabet))::integer, 1);
    end loop;
    if not exists (select 1 from public.profiles where public_code = candidate) then
      return candidate;
    end if;
  end loop;
  raise exception 'Unable to generate a unique public code';
end;
$$;

create or replace function private.touch_updated_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  colors constant text[] := array[
    '#D95D39', '#3F7CAC', '#7A6F9B', '#4C956C', '#B56576', '#2A9D8F',
    '#8D6A9F', '#C07F00', '#5C80BC', '#9C6644', '#6B8E23', '#A44A3F'
  ];
begin
  insert into public.profiles (id, public_code, identity_color)
  values (
    new.id,
    private.generate_public_code(),
    colors[1 + floor(random() * array_length(colors, 1))::integer]
  )
  on conflict (id) do nothing;

  insert into private.accounts (user_id)
  values (new.id)
  on conflict (user_id) do nothing;
  return new;
end;
$$;

create or replace function public.is_active_user()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from private.accounts account
    where account.user_id = (select auth.uid())
      and account.status = 'active'
  );
$$;

create or replace function public.is_admin()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from private.accounts account
    where account.user_id = (select auth.uid())
      and account.status = 'active'
      and account.role = 'admin'
  );
$$;

create or replace function public.can_view_user(target_user_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select
    exists (
      select 1 from private.accounts account
      where account.user_id = target_user_id and account.status = 'active'
    )
    and (
      (select auth.uid()) is null
      or not exists (
        select 1 from public.blocks relation
        where (relation.blocker_id = (select auth.uid()) and relation.blocked_id = target_user_id)
           or (relation.blocker_id = target_user_id and relation.blocked_id = (select auth.uid()))
      )
    );
$$;

create or replace function public.can_view_content(content_author_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select public.can_view_user(content_author_id)
    and (
      (select auth.uid()) is null
      or not exists (
        select 1 from public.mutes relation
        where relation.muter_id = (select auth.uid())
          and relation.muted_id = content_author_id
      )
    );
$$;

create or replace function private.validate_comment_parent()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.parent_comment_id is not null and not exists (
    select 1 from public.comments parent
    where parent.id = new.parent_comment_id
      and parent.post_id = new.post_id
      and parent.deleted_at is null
  ) then
    raise exception 'Parent comment must belong to the same post';
  end if;
  return new;
end;
$$;

create or replace function private.validate_report_target()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.target_type = 'post' and not exists (
    select 1 from public.posts where id = new.target_id and deleted_at is null
  ) then
    raise exception 'Reported post does not exist';
  end if;
  if new.target_type = 'comment' and not exists (
    select 1 from public.comments where id = new.target_id and deleted_at is null
  ) then
    raise exception 'Reported comment does not exist';
  end if;
  return new;
end;
$$;

create or replace function private.handle_block_relations()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  delete from public.follows
  where (follower_id = new.blocker_id and followed_id = new.blocked_id)
     or (follower_id = new.blocked_id and followed_id = new.blocker_id);
  return new;
end;
$$;

create trigger profiles_touch_updated_at before update on public.profiles
for each row execute function private.touch_updated_at();
create trigger accounts_touch_updated_at before update on private.accounts
for each row execute function private.touch_updated_at();
create trigger posts_touch_updated_at before update on public.posts
for each row execute function private.touch_updated_at();
create trigger comments_touch_updated_at before update on public.comments
for each row execute function private.touch_updated_at();
create trigger comments_validate_parent before insert or update of parent_comment_id, post_id on public.comments
for each row execute function private.validate_comment_parent();
create trigger reports_validate_target before insert or update of target_type, target_id on public.reports
for each row execute function private.validate_report_target();
create trigger blocks_remove_relations after insert on public.blocks
for each row execute function private.handle_block_relations();
create trigger on_auth_user_created after insert on auth.users
for each row execute function public.handle_new_user();

insert into public.profiles (id, public_code, identity_color, created_at)
select
  auth_user.id,
  private.generate_public_code(),
  (array['#D95D39', '#3F7CAC', '#7A6F9B', '#4C956C', '#B56576', '#2A9D8F', '#8D6A9F', '#C07F00', '#5C80BC', '#9C6644', '#6B8E23', '#A44A3F'])[1 + floor(random() * 12)::integer],
  auth_user.created_at
from auth.users auth_user
where not exists (select 1 from public.profiles profile where profile.id = auth_user.id);

insert into private.accounts (user_id, created_at)
select auth_user.id, auth_user.created_at
from auth.users auth_user
where not exists (select 1 from private.accounts account where account.user_id = auth_user.id);

alter table public.profiles enable row level security;
alter table private.accounts enable row level security;
alter table public.posts enable row level security;
alter table public.comments enable row level security;
alter table public.follows enable row level security;
alter table public.mutes enable row level security;
alter table public.blocks enable row level security;
alter table public.reports enable row level security;

create policy profiles_public_read on public.profiles
for select to anon, authenticated
using (public.can_view_user(id));

create policy posts_public_read on public.posts
for select to anon, authenticated
using (deleted_at is null and public.can_view_content(author_id));
create policy posts_owner_insert on public.posts
for insert to authenticated
with check (author_id = (select auth.uid()) and public.is_active_user());
create policy posts_owner_update on public.posts
for update to authenticated
using (author_id = (select auth.uid()) and public.is_active_user())
with check (author_id = (select auth.uid()) and public.is_active_user());

create policy comments_public_read on public.comments
for select to anon, authenticated
using (
  deleted_at is null
  and public.can_view_content(author_id)
  and exists (select 1 from public.posts post where post.id = comments.post_id)
);
create policy comments_owner_insert on public.comments
for insert to authenticated
with check (
  author_id = (select auth.uid())
  and public.is_active_user()
  and exists (select 1 from public.posts post where post.id = comments.post_id)
);
create policy comments_owner_update on public.comments
for update to authenticated
using (author_id = (select auth.uid()) and public.is_active_user())
with check (author_id = (select auth.uid()) and public.is_active_user());

create policy follows_owner_read on public.follows
for select to authenticated
using (follower_id = (select auth.uid()));
create policy follows_owner_insert on public.follows
for insert to authenticated
with check (
  follower_id = (select auth.uid())
  and followed_id <> (select auth.uid())
  and public.is_active_user()
  and public.can_view_user(followed_id)
);
create policy follows_owner_delete on public.follows
for delete to authenticated
using (follower_id = (select auth.uid()));

create policy mutes_owner_read on public.mutes
for select to authenticated
using (muter_id = (select auth.uid()));
create policy mutes_owner_insert on public.mutes
for insert to authenticated
with check (muter_id = (select auth.uid()) and muted_id <> (select auth.uid()) and public.is_active_user());
create policy mutes_owner_delete on public.mutes
for delete to authenticated
using (muter_id = (select auth.uid()));

create policy blocks_owner_read on public.blocks
for select to authenticated
using (blocker_id = (select auth.uid()));
create policy blocks_owner_insert on public.blocks
for insert to authenticated
with check (blocker_id = (select auth.uid()) and blocked_id <> (select auth.uid()) and public.is_active_user());
create policy blocks_owner_delete on public.blocks
for delete to authenticated
using (blocker_id = (select auth.uid()));

create policy reports_owner_or_admin_read on public.reports
for select to authenticated
using (reporter_id = (select auth.uid()) or public.is_admin());
create policy reports_owner_insert on public.reports
for insert to authenticated
with check (reporter_id = (select auth.uid()) and public.is_active_user());
create policy reports_admin_update on public.reports
for update to authenticated
using (public.is_admin())
with check (public.is_admin());

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
  comment_count bigint
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
    count(comment.id)::bigint
  from public.posts post
  join public.profiles profile on profile.id = post.author_id
  left join public.comments comment on comment.post_id = post.id and comment.deleted_at is null
  where post.deleted_at is null
    and (
      p_cursor_created_at is null
      or post.created_at < p_cursor_created_at
      or (post.created_at = p_cursor_created_at and post.id < p_cursor_id)
    )
  group by post.id, post.body, post.created_at, profile.public_code, profile.identity_color
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
  comment_count bigint
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
    count(comment.id)::bigint
  from public.posts post
  join public.profiles profile on profile.id = post.author_id
  left join public.comments comment on comment.post_id = post.id and comment.deleted_at is null
  where post.deleted_at is null and profile.public_code = upper(btrim(p_public_code))
  group by post.id, post.body, post.created_at, profile.public_code, profile.identity_color
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
  comment_count bigint
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
    count(comment.id)::bigint
  from public.posts post
  join public.profiles profile on profile.id = post.author_id
  left join public.comments comment on comment.post_id = post.id and comment.deleted_at is null
  where post.deleted_at is null
    and char_length(btrim(p_query)) between 1 and 120
    and position(lower(btrim(p_query)) in lower(post.body)) > 0
  group by post.id, post.body, post.created_at, profile.public_code, profile.identity_color
  order by post.created_at desc, post.id desc
  limit greatest(1, least(coalesce(p_limit, 30), 50));
$$;

create or replace function public.get_private_follower_count()
returns bigint
language sql
stable
security definer
set search_path = ''
as $$
  select count(*)::bigint from public.follows where followed_id = (select auth.uid());
$$;

create or replace function public.unblock_user(p_public_code text)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  target_user_id uuid;
begin
  if (select auth.uid()) is null then
    raise exception 'Unauthorized';
  end if;
  select id into target_user_id
  from public.profiles
  where public_code = upper(btrim(p_public_code));
  if target_user_id is null then return false; end if;

  delete from public.blocks
  where blocker_id = (select auth.uid()) and blocked_id = target_user_id;
  return found;
end;
$$;

create or replace function public.moderate_report(p_report_id uuid, p_action text)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  report_row public.reports%rowtype;
  target_author_id uuid;
begin
  if not public.is_admin() then
    raise exception 'Forbidden';
  end if;
  if p_action not in ('resolve', 'dismiss', 'delete-content', 'suspend-author', 'ban-author') then
    raise exception 'Invalid moderation action';
  end if;

  select * into report_row from public.reports where id = p_report_id for update;
  if not found then return false; end if;

  if p_action = 'resolve' then
    update public.reports set status = 'resolved' where id = p_report_id;
    return true;
  elsif p_action = 'dismiss' then
    update public.reports set status = 'dismissed' where id = p_report_id;
    return true;
  elsif report_row.target_type = 'post' then
    select author_id into target_author_id from public.posts where id = report_row.target_id;
    if p_action = 'delete-content' then
      update public.posts set deleted_at = now() where id = report_row.target_id;
    end if;
  else
    select author_id into target_author_id from public.comments where id = report_row.target_id;
    if p_action = 'delete-content' then
      update public.comments set deleted_at = now() where id = report_row.target_id;
    end if;
  end if;

  if p_action in ('suspend-author', 'ban-author') and target_author_id is not null then
    update private.accounts
    set status = case when p_action = 'ban-author' then 'banned' else 'suspended' end
    where user_id = target_author_id;
  end if;
  update public.reports set status = 'resolved' where id = p_report_id;
  return true;
end;
$$;

revoke all on all tables in schema public from public, anon, authenticated;
revoke all on all tables in schema private from public, anon, authenticated;
grant usage on schema public to anon, authenticated;
grant select on public.profiles, public.posts, public.comments to anon, authenticated;
grant insert (author_id, body) on public.posts to authenticated;
grant update (body, updated_at, deleted_at) on public.posts to authenticated;
grant insert (post_id, author_id, parent_comment_id, body) on public.comments to authenticated;
grant update (body, updated_at, deleted_at) on public.comments to authenticated;
grant select, delete on public.follows, public.mutes, public.blocks to authenticated;
grant insert (follower_id, followed_id) on public.follows to authenticated;
grant insert (muter_id, muted_id) on public.mutes to authenticated;
grant insert (blocker_id, blocked_id) on public.blocks to authenticated;
grant select on public.reports to authenticated;
grant insert (reporter_id, target_type, target_id, reason, description) on public.reports to authenticated;
grant update (status) on public.reports to authenticated;

revoke execute on all functions in schema public from public, anon, authenticated;
revoke execute on all functions in schema private from public, anon, authenticated;
grant execute on function public.can_view_user(uuid) to anon, authenticated;
grant execute on function public.can_view_content(uuid) to anon, authenticated;
grant execute on function public.is_active_user() to authenticated;
grant execute on function public.is_admin() to authenticated;
grant execute on function public.get_timeline(timestamptz, uuid, integer) to anon, authenticated;
grant execute on function public.get_user_posts(text, integer) to anon, authenticated;
grant execute on function public.search_posts(text, integer) to anon, authenticated;
grant execute on function public.get_private_follower_count() to authenticated;
grant execute on function public.unblock_user(text) to authenticated;
grant execute on function public.moderate_report(uuid, text) to authenticated;

