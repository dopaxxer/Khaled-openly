-- User mentions for posts and comments.
--
-- Additive only: no existing table, column, policy or function is dropped or
-- renamed. Mentions are parsed on the server from the stored body using the
-- authenticated identity, never from client-supplied profile IDs, and the
-- parse runs inside the same transaction as the content insert so a post can
-- never exist without its mention rows (or vice versa).

create table if not exists public.mentions (
  id uuid primary key default gen_random_uuid(),
  source_type text not null check (source_type in ('post', 'comment')),
  source_id uuid not null,
  post_id uuid not null references public.posts(id) on delete cascade,
  comment_id uuid references public.comments(id) on delete cascade,
  mentioner_id uuid not null references public.profiles(id) on delete cascade,
  mentioned_id uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  -- Referential integrity for the polymorphic source is carried by the two
  -- real foreign keys; this ties source_id to whichever one applies so the
  -- pair can never drift apart.
  constraint mentions_source_shape check (
    (source_type = 'post' and comment_id is null and source_id = post_id)
    or (source_type = 'comment' and comment_id is not null and source_id = comment_id)
  ),
  constraint mentions_unique_per_source unique (source_type, source_id, mentioned_id)
);

create index if not exists mentions_mentioned_created_idx
  on public.mentions (mentioned_id, created_at desc, id desc);
create index if not exists mentions_source_idx
  on public.mentions (source_type, source_id);
create index if not exists mentions_post_idx
  on public.mentions (post_id);
create index if not exists mentions_comment_idx
  on public.mentions (comment_id)
  where comment_id is not null;
create index if not exists mentions_mentioner_idx
  on public.mentions (mentioner_id);

-- Autocomplete matches an uppercased prefix. The unique index on public_code
-- uses the database collation and cannot serve LIKE 'AB%', so add a pattern
-- index for the prefix pass.
create index if not exists profiles_public_code_pattern_idx
  on public.profiles (public_code varchar_pattern_ops);

-- ---------------------------------------------------------------------------
-- Parsing and resolution
-- ---------------------------------------------------------------------------

-- The single canonical mention grammar, mirrored verbatim in lib/mentions.js
-- (web + API) and MentionSupport.swift (iOS):
--
--   (^|[^A-Za-z0-9_@])@([A-Za-z0-9]{4,8})(?![A-Za-z0-9_])
--
-- The leading alternation is consumed and the trailing constraint is a
-- lookahead, so "@AAAA @BBBB" yields both codes in every engine. Anything
-- attached to a preceding word character (an e-mail address, for example) is
-- not a mention. Tokens outside the public-code alphabet are dropped here so
-- they stay plain text rather than becoming a failed lookup.
create or replace function private.parse_mention_codes(p_body text, p_limit integer default 10)
returns text[]
language plpgsql
immutable
set search_path = ''
as $$
declare
  match_row text[];
  candidate text;
  result text[] := array[]::text[];
  cap integer := greatest(0, least(coalesce(p_limit, 10), 25));
begin
  if p_body is null or cap = 0 then
    return result;
  end if;

  for match_row in
    select regexp_matches(p_body, '(^|[^A-Za-z0-9_@])@([A-Za-z0-9]{4,8})(?![A-Za-z0-9_])', 'g')
  loop
    candidate := upper(match_row[2]);
    continue when candidate !~ '^[A-HJ-NP-Z2-9]{4,8}$';
    continue when candidate = any(result);
    result := result || candidate;
    exit when coalesce(array_length(result, 1), 0) >= cap;
  end loop;

  return result;
end;
$$;

-- Resolves parsed codes to live, visible profiles. Blocked pairs and
-- suspended accounts resolve to nothing, so a blocked user cannot mention the
-- user who blocked them and the text simply stays plain.
create or replace function private.resolve_mention_codes(p_codes text[])
returns table (user_id uuid, public_code text, identity_color text)
language sql
stable
security definer
set search_path = ''
as $$
  select profile.id, profile.public_code::text, profile.identity_color::text
  from public.profiles profile
  where profile.public_code = any(coalesce(p_codes, array[]::text[]))
    and private.can_view_user(profile.id)
  order by profile.public_code;
$$;

create or replace function private.resolve_mentions(p_body text)
returns table (public_code text, identity_color text)
language sql
stable
security definer
set search_path = ''
as $$
  select resolved.public_code, resolved.identity_color
  from private.resolve_mention_codes(private.parse_mention_codes(p_body, 10)) resolved;
$$;

create or replace function private.suggest_mention_codes(p_query text, p_limit integer default 8)
returns table (public_code text, identity_color text)
language sql
stable
security definer
set search_path = ''
as $$
  with needle as (
    select upper(btrim(coalesce(p_query, ''))) as value
  )
  select profile.public_code::text, profile.identity_color::text
  from public.profiles profile, needle
  where needle.value <> ''
    and needle.value ~ '^[A-HJ-NP-Z2-9]{1,8}$'
    and position(needle.value in profile.public_code) > 0
    and private.can_view_user(profile.id)
  order by
    case when profile.public_code like needle.value || '%' then 0 else 1 end,
    profile.public_code
  limit greatest(1, least(coalesce(p_limit, 8), 10));
$$;

-- ---------------------------------------------------------------------------
-- Notifications
-- ---------------------------------------------------------------------------

-- Widen the notification kind and shape checks additively. Both existing
-- kinds keep exactly the shape they had; 'mention' is allowed to carry a
-- comment_id (comment mention) or not (post mention).
do $$
declare
  constraint_row record;
begin
  for constraint_row in
    select conname
    from pg_constraint
    where conrelid = 'private.notifications'::regclass
      and contype = 'c'
      and pg_get_constraintdef(oid) like '%kind%'
  loop
    execute format('alter table private.notifications drop constraint %I', constraint_row.conname);
  end loop;
end;
$$;

alter table private.notifications
  add constraint notifications_kind_allowed
  check (kind in ('reply', 'like', 'mention'));

alter table private.notifications
  add constraint notifications_shape_valid
  check (
    (kind = 'reply' and comment_id is not null)
    or (kind = 'like' and comment_id is null)
    or kind = 'mention'
  );

-- One mention notification per (recipient, actor, source). Two partial
-- indexes because a post mention has a null comment_id and null is never
-- equal to null in a unique index.
create unique index if not exists notifications_mention_post_unique_idx
  on private.notifications (recipient_id, actor_id, post_id)
  where kind = 'mention' and comment_id is null;

create unique index if not exists notifications_mention_comment_unique_idx
  on private.notifications (recipient_id, actor_id, comment_id)
  where kind = 'mention' and comment_id is not null;

-- ---------------------------------------------------------------------------
-- Transactional mention synchronisation
-- ---------------------------------------------------------------------------

-- Called from inside the content-creation functions, so the mention rows and
-- the post/comment they describe commit or roll back together. Returns the
-- number of mention rows that were newly created.
create or replace function private.sync_mentions(
  p_source_type text,
  p_source_id uuid,
  p_post_id uuid,
  p_comment_id uuid,
  p_author_id uuid,
  p_body text
)
returns integer
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  codes text[];
  target record;
  created_ids uuid[] := array[]::uuid[];
  removed_ids uuid[] := array[]::uuid[];
begin
  codes := private.parse_mention_codes(p_body, 10);

  -- An edit that removed a mention must remove its row. Comparing against the
  -- freshly parsed codes keeps the stored body the only source of truth.
  with removed as (
    delete from public.mentions existing
    where existing.source_type = p_source_type
      and existing.source_id = p_source_id
      and not exists (
        select 1
        from public.profiles profile
        where profile.id = existing.mentioned_id
          and profile.public_code = any(codes)
      )
    returning existing.mentioned_id
  )
  select coalesce(array_agg(removed.mentioned_id), array[]::uuid[])
  into removed_ids
  from removed;

  -- A notification that points at content which no longer mentions the
  -- recipient is misleading, so it goes with the mention row. Re-adding the
  -- same mention later notifies once more; the API rate-limits edits so this
  -- cannot be used to hammer someone's notification list.
  if coalesce(array_length(removed_ids, 1), 0) > 0 then
    delete from private.notifications stale
    where stale.kind = 'mention'
      and stale.actor_id = p_author_id
      and stale.recipient_id = any(removed_ids)
      and stale.post_id = p_post_id
      and stale.comment_id is not distinct from p_comment_id;
  end if;

  if coalesce(array_length(codes, 1), 0) = 0 then
    return 0;
  end if;

  for target in
    select resolved.user_id from private.resolve_mention_codes(codes) resolved
  loop
    insert into public.mentions (
      source_type, source_id, post_id, comment_id, mentioner_id, mentioned_id
    )
    values (
      p_source_type, p_source_id, p_post_id, p_comment_id, p_author_id, target.user_id
    )
    on conflict (source_type, source_id, mentioned_id) do nothing;

    if found then
      created_ids := created_ids || target.user_id;
    end if;
  end loop;

  -- Self-mentions are stored (so the author still sees the link rendered) but
  -- never notify. A recipient who muted the author is not notified either;
  -- can_view_user already excluded blocked pairs during resolution.
  insert into private.notifications (recipient_id, actor_id, kind, post_id, comment_id)
  select recipient, p_author_id, 'mention', p_post_id, p_comment_id
  from unnest(created_ids) as recipient
  where recipient <> p_author_id
    and not exists (
      select 1 from public.mutes mute
      where mute.muter_id = recipient and mute.muted_id = p_author_id
    )
  on conflict do nothing;

  return coalesce(array_length(created_ids, 1), 0);
end;
$$;

create or replace function private.create_post(p_body text)
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

  insert into public.posts (author_id, body)
  values (viewer, clean_body)
  returning id into new_id;

  perform private.sync_mentions('post', new_id, new_id, null, viewer, clean_body);
  return new_id;
end;
$$;

create or replace function private.create_comment(
  p_post_id uuid,
  p_parent_comment_id uuid,
  p_body text
)
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
  if char_length(clean_body) < 1 or char_length(clean_body) > 2000 then
    raise exception 'Invalid comment length';
  end if;
  if not exists (
    select 1 from public.posts post
    where post.id = p_post_id
      and post.deleted_at is null
      and private.can_view_content(post.author_id)
  ) then
    raise exception 'Not found';
  end if;

  insert into public.comments (post_id, author_id, parent_comment_id, body)
  values (p_post_id, viewer, p_parent_comment_id, clean_body)
  returning id into new_id;

  perform private.sync_mentions('comment', new_id, p_post_id, new_id, viewer, clean_body);
  return new_id;
end;
$$;

create or replace function private.update_own_post(p_post_id uuid, p_body text)
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

  update public.posts
  set body = clean_body
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

-- ---------------------------------------------------------------------------
-- Reading mentions back
-- ---------------------------------------------------------------------------

create or replace function private.get_mentions(p_source_type text, p_source_ids uuid[])
returns table (source_id uuid, public_code text, identity_color text)
language sql
stable
security definer
set search_path = ''
as $$
  select mention.source_id, mentioned.public_code::text, mentioned.identity_color::text
  from public.mentions mention
  join public.profiles mentioned on mentioned.id = mention.mentioned_id
  join public.posts post on post.id = mention.post_id and post.deleted_at is null
  left join public.comments comment on comment.id = mention.comment_id
  where mention.source_type = p_source_type
    and mention.source_id = any(coalesce(p_source_ids, array[]::uuid[]))
    and (mention.comment_id is null or comment.deleted_at is null)
    and private.can_view_content(mention.mentioner_id)
    and private.can_view_user(mention.mentioned_id)
  order by mention.source_id, mentioned.public_code;
$$;

-- ---------------------------------------------------------------------------
-- Cleanup on soft delete
-- ---------------------------------------------------------------------------

-- Hard deletes are covered by the foreign keys. Posts and comments are soft
-- deleted, so the mention rows and their notifications are removed here.
create or replace function private.cleanup_mentions_on_soft_delete()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if old.deleted_at is null and new.deleted_at is not null then
    if tg_table_name = 'posts' then
      delete from public.mentions where post_id = new.id;
      delete from private.notifications where post_id = new.id and kind = 'mention';
    else
      delete from public.mentions where source_type = 'comment' and source_id = new.id;
      delete from private.notifications where comment_id = new.id and kind = 'mention';
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists posts_cleanup_mentions on public.posts;
create trigger posts_cleanup_mentions
after update of deleted_at on public.posts
for each row execute function private.cleanup_mentions_on_soft_delete();

drop trigger if exists comments_cleanup_mentions on public.comments;
create trigger comments_cleanup_mentions
after update of deleted_at on public.comments
for each row execute function private.cleanup_mentions_on_soft_delete();

-- ---------------------------------------------------------------------------
-- Public wrappers (security invoker, thin)
-- ---------------------------------------------------------------------------

create or replace function public.suggest_mentions(p_query text, p_limit integer default 8)
returns table (public_code text, identity_color text)
language sql
stable
security invoker
set search_path = ''
as $$ select * from private.suggest_mention_codes(p_query, p_limit); $$;

create or replace function public.resolve_mentions(p_body text)
returns table (public_code text, identity_color text)
language sql
stable
security invoker
set search_path = ''
as $$ select * from private.resolve_mentions(p_body); $$;

create or replace function public.get_mentions(p_source_type text, p_source_ids uuid[])
returns table (source_id uuid, public_code text, identity_color text)
language sql
stable
security invoker
set search_path = ''
as $$ select * from private.get_mentions(p_source_type, p_source_ids); $$;

create or replace function public.create_post(p_body text)
returns uuid
language sql
volatile
security invoker
set search_path = ''
as $$ select private.create_post(p_body); $$;

create or replace function public.create_comment(
  p_post_id uuid,
  p_parent_comment_id uuid,
  p_body text
)
returns uuid
language sql
volatile
security invoker
set search_path = ''
as $$ select private.create_comment(p_post_id, p_parent_comment_id, p_body); $$;

create or replace function public.update_own_post(p_post_id uuid, p_body text)
returns boolean
language sql
volatile
security invoker
set search_path = ''
as $$ select private.update_own_post(p_post_id, p_body); $$;

-- ---------------------------------------------------------------------------
-- Row level security and privileges
-- ---------------------------------------------------------------------------

alter table public.mentions enable row level security;

drop policy if exists mentions_visible_read on public.mentions;
create policy mentions_visible_read on public.mentions
for select to anon, authenticated
using (
  private.can_view_content(mentioner_id)
  and private.can_view_user(mentioned_id)
  and exists (
    select 1 from public.posts post
    where post.id = mentions.post_id and post.deleted_at is null
  )
  and (
    mentions.comment_id is null
    or exists (
      select 1 from public.comments comment
      where comment.id = mentions.comment_id and comment.deleted_at is null
    )
  )
);

-- Supabase default privileges grant everything on new public tables and
-- functions to the API roles. Take it all back and hand out only what the
-- clients need. Mention rows are written exclusively by the definer
-- functions above, so no role gets insert, update or delete.
revoke all on table public.mentions from public, anon, authenticated;
grant select on table public.mentions to anon, authenticated;

revoke execute on function private.parse_mention_codes(text, integer) from public, anon, authenticated;
revoke execute on function private.resolve_mention_codes(text[]) from public, anon, authenticated;
revoke execute on function private.resolve_mentions(text) from public, anon, authenticated;
revoke execute on function private.suggest_mention_codes(text, integer) from public, anon, authenticated;
revoke execute on function private.sync_mentions(text, uuid, uuid, uuid, uuid, text) from public, anon, authenticated;
revoke execute on function private.create_post(text) from public, anon, authenticated;
revoke execute on function private.create_comment(uuid, uuid, text) from public, anon, authenticated;
revoke execute on function private.update_own_post(uuid, text) from public, anon, authenticated;
revoke execute on function private.get_mentions(text, uuid[]) from public, anon, authenticated;
revoke execute on function private.cleanup_mentions_on_soft_delete() from public, anon, authenticated;

grant execute on function private.suggest_mention_codes(text, integer) to authenticated;
grant execute on function private.resolve_mentions(text) to authenticated;
grant execute on function private.get_mentions(text, uuid[]) to anon, authenticated;
grant execute on function private.create_post(text) to authenticated;
grant execute on function private.create_comment(uuid, uuid, text) to authenticated;
grant execute on function private.update_own_post(uuid, text) to authenticated;

revoke execute on function public.suggest_mentions(text, integer) from public, anon;
revoke execute on function public.resolve_mentions(text) from public, anon;
revoke execute on function public.get_mentions(text, uuid[]) from public;
revoke execute on function public.create_post(text) from public, anon;
revoke execute on function public.create_comment(uuid, uuid, text) from public, anon;
revoke execute on function public.update_own_post(uuid, text) from public, anon;

grant execute on function public.suggest_mentions(text, integer) to authenticated;
grant execute on function public.resolve_mentions(text) to authenticated;
grant execute on function public.get_mentions(text, uuid[]) to anon, authenticated;
grant execute on function public.create_post(text) to authenticated;
grant execute on function public.create_comment(uuid, uuid, text) to authenticated;
grant execute on function public.update_own_post(uuid, text) to authenticated;
