create or replace function private.is_active_user()
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

create or replace function private.is_admin()
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

create or replace function private.can_view_user(target_user_id uuid)
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

create or replace function private.can_view_content(content_author_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select private.can_view_user(content_author_id)
    and (
      (select auth.uid()) is null
      or not exists (
        select 1 from public.mutes relation
        where relation.muter_id = (select auth.uid())
          and relation.muted_id = content_author_id
      )
    );
$$;

create or replace function private.get_private_follower_count()
returns bigint
language sql
stable
security definer
set search_path = ''
as $$
  select case
    when (select auth.uid()) is null then 0::bigint
    else (select count(*)::bigint from public.follows where followed_id = (select auth.uid()))
  end;
$$;

create or replace function private.unblock_user(p_public_code text)
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

create or replace function private.moderate_report(p_report_id uuid, p_action text)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  report_row public.reports%rowtype;
  target_author_id uuid;
begin
  if not private.is_admin() then
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

alter policy profiles_public_read on public.profiles
using (private.can_view_user(id));

alter policy posts_public_read on public.posts
using (deleted_at is null and private.can_view_content(author_id));
alter policy posts_owner_insert on public.posts
with check (author_id = (select auth.uid()) and private.is_active_user());
alter policy posts_owner_update on public.posts
using (author_id = (select auth.uid()) and private.is_active_user())
with check (author_id = (select auth.uid()) and private.is_active_user());

alter policy comments_public_read on public.comments
using (
  deleted_at is null
  and private.can_view_content(author_id)
  and exists (select 1 from public.posts post where post.id = comments.post_id)
);
alter policy comments_owner_insert on public.comments
with check (
  author_id = (select auth.uid())
  and private.is_active_user()
  and exists (select 1 from public.posts post where post.id = comments.post_id)
);
alter policy comments_owner_update on public.comments
using (author_id = (select auth.uid()) and private.is_active_user())
with check (author_id = (select auth.uid()) and private.is_active_user());

alter policy follows_owner_insert on public.follows
with check (
  follower_id = (select auth.uid())
  and followed_id <> (select auth.uid())
  and private.is_active_user()
  and private.can_view_user(followed_id)
);
alter policy mutes_owner_insert on public.mutes
with check (muter_id = (select auth.uid()) and muted_id <> (select auth.uid()) and private.is_active_user());
alter policy blocks_owner_insert on public.blocks
with check (blocker_id = (select auth.uid()) and blocked_id <> (select auth.uid()) and private.is_active_user());

alter policy reports_owner_or_admin_read on public.reports
using (reporter_id = (select auth.uid()) or private.is_admin());
alter policy reports_owner_insert on public.reports
with check (reporter_id = (select auth.uid()) and private.is_active_user());
alter policy reports_admin_update on public.reports
using (private.is_admin())
with check (private.is_admin());

create policy accounts_explicit_deny on private.accounts
for all to anon, authenticated
using (false)
with check (false);

create or replace function public.is_admin()
returns boolean
language sql
stable
security invoker
set search_path = ''
as $$ select private.is_admin(); $$;

create or replace function public.get_private_follower_count()
returns bigint
language sql
stable
security invoker
set search_path = ''
as $$ select private.get_private_follower_count(); $$;

create or replace function public.unblock_user(p_public_code text)
returns boolean
language sql
volatile
security invoker
set search_path = ''
as $$ select private.unblock_user(p_public_code); $$;

create or replace function public.moderate_report(p_report_id uuid, p_action text)
returns boolean
language sql
volatile
security invoker
set search_path = ''
as $$ select private.moderate_report(p_report_id, p_action); $$;

drop function public.can_view_content(uuid);
drop function public.can_view_user(uuid);
drop function public.is_active_user();

grant usage on schema private to anon, authenticated;
revoke execute on all functions in schema private from public, anon, authenticated;
grant execute on function private.can_view_user(uuid) to anon, authenticated;
grant execute on function private.can_view_content(uuid) to anon, authenticated;
grant execute on function private.is_active_user() to authenticated;
grant execute on function private.is_admin() to authenticated;
grant execute on function private.get_private_follower_count() to authenticated;
grant execute on function private.unblock_user(text) to authenticated;
grant execute on function private.moderate_report(uuid, text) to authenticated;

revoke execute on function public.is_admin() from public, anon;
revoke execute on function public.get_private_follower_count() from public, anon;
revoke execute on function public.unblock_user(text) from public, anon;
revoke execute on function public.moderate_report(uuid, text) from public, anon;
grant execute on function public.is_admin() to authenticated;
grant execute on function public.get_private_follower_count() to authenticated;
grant execute on function public.unblock_user(text) to authenticated;
grant execute on function public.moderate_report(uuid, text) to authenticated;

