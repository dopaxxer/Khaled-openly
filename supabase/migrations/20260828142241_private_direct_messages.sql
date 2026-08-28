-- Private 1:1 messaging for Openly.
-- All message rows stay in the private schema. Clients use authenticated RPCs
-- through the application API; anon/authenticated roles receive no table grants.

create table if not exists private.direct_conversations (
  id uuid primary key default gen_random_uuid(),
  user_a uuid not null references public.profiles(id) on delete cascade,
  user_b uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint direct_conversations_distinct_users check (user_a <> user_b),
  constraint direct_conversations_canonical_pair check (user_a < user_b),
  constraint direct_conversations_unique_pair unique (user_a, user_b)
);

create table if not exists private.direct_messages (
  id uuid primary key default gen_random_uuid(),
  conversation_id uuid not null references private.direct_conversations(id) on delete cascade,
  sender_id uuid not null references public.profiles(id) on delete cascade,
  body text not null,
  client_nonce uuid not null,
  created_at timestamptz not null default now(),
  read_at timestamptz,
  constraint direct_messages_body_length
    check (char_length(btrim(body)) between 1 and 2000),
  constraint direct_messages_idempotency
    unique (conversation_id, sender_id, client_nonce)
);

create index if not exists direct_conversations_user_a_updated_idx
  on private.direct_conversations (user_a, updated_at desc);
create index if not exists direct_conversations_user_b_updated_idx
  on private.direct_conversations (user_b, updated_at desc);
create index if not exists direct_messages_conversation_created_idx
  on private.direct_messages (conversation_id, created_at desc, id desc);
create index if not exists direct_messages_unread_idx
  on private.direct_messages (conversation_id, sender_id, created_at desc)
  where read_at is null;

alter table private.direct_conversations enable row level security;
alter table private.direct_messages enable row level security;

revoke all on table private.direct_conversations from public, anon, authenticated;
revoke all on table private.direct_messages from public, anon, authenticated;

create or replace function private.can_direct_message(p_target_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  with viewer as (select (select auth.uid()) as id)
  select coalesce((
    select
      viewer.id is not null
      and p_target_id is not null
      and viewer.id <> p_target_id
      and exists (
        select 1 from private.accounts account
        where account.user_id = viewer.id and account.status = 'active'
      )
      and exists (
        select 1 from private.accounts account
        where account.user_id = p_target_id and account.status = 'active'
      )
      and not exists (
        select 1
        from public.blocks block
        where (block.blocker_id = viewer.id and block.blocked_id = p_target_id)
           or (block.blocker_id = p_target_id and block.blocked_id = viewer.id)
      )
    from viewer
  ), false);
$$;

create or replace function private.start_direct_conversation(p_public_code text)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  viewer uuid := (select auth.uid());
  target_id uuid;
  target_code text;
  target_color text;
  first_user uuid;
  second_user uuid;
  conversation_id uuid;
begin
  if viewer is null then
    raise exception 'Unauthorized';
  end if;

  select profile.id, profile.public_code::text, profile.identity_color::text
    into target_id, target_code, target_color
  from public.profiles profile
  where profile.public_code = upper(btrim(coalesce(p_public_code, '')))
  limit 1;

  if target_id is null or target_id = viewer then
    raise exception 'Messaging target unavailable';
  end if;

  if not private.can_direct_message(target_id) then
    raise exception 'Messaging unavailable';
  end if;

  if viewer < target_id then
    first_user := viewer;
    second_user := target_id;
  else
    first_user := target_id;
    second_user := viewer;
  end if;

  insert into private.direct_conversations (user_a, user_b)
  values (first_user, second_user)
  on conflict (user_a, user_b) do nothing
  returning id into conversation_id;

  if conversation_id is null then
    select conversation.id into conversation_id
    from private.direct_conversations conversation
    where conversation.user_a = first_user
      and conversation.user_b = second_user;
  end if;

  return jsonb_build_object(
    'conversationId', conversation_id,
    'publicCode', target_code,
    'identityColor', target_color,
    'canMessage', true
  );
end;
$$;

create or replace function private.get_direct_conversation(p_conversation_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  viewer uuid := (select auth.uid());
  peer_id uuid;
  peer_code text;
  peer_color text;
  created_time timestamptz;
  unread_count bigint;
begin
  if viewer is null then
    raise exception 'Unauthorized';
  end if;

  select
    case when conversation.user_a = viewer then conversation.user_b else conversation.user_a end,
    conversation.created_at
  into peer_id, created_time
  from private.direct_conversations conversation
  where conversation.id = p_conversation_id
    and (conversation.user_a = viewer or conversation.user_b = viewer);

  if peer_id is null then
    return null;
  end if;

  select profile.public_code::text, profile.identity_color::text
    into peer_code, peer_color
  from public.profiles profile
  where profile.id = peer_id;

  select count(*) into unread_count
  from private.direct_messages message
  where message.conversation_id = p_conversation_id
    and message.sender_id <> viewer
    and message.read_at is null;

  return jsonb_build_object(
    'conversationId', p_conversation_id,
    'publicCode', peer_code,
    'identityColor', peer_color,
    'createdAt', created_time,
    'unreadCount', unread_count,
    'canMessage', private.can_direct_message(peer_id)
  );
end;
$$;

create or replace function private.get_direct_conversations(
  p_limit integer default 30,
  p_offset integer default 0
)
returns table (
  conversation_id uuid,
  public_code text,
  identity_color text,
  last_message_body text,
  last_message_at timestamptz,
  last_message_is_mine boolean,
  unread_count bigint,
  can_message boolean,
  total_conversations bigint
)
language sql
stable
security definer
set search_path = ''
as $$
  with viewer as (
    select (select auth.uid()) as id
  ),
  mine as (
    select
      conversation.id,
      conversation.created_at,
      conversation.updated_at,
      case when conversation.user_a = viewer.id
        then conversation.user_b
        else conversation.user_a
      end as peer_id,
      viewer.id as viewer_id
    from private.direct_conversations conversation, viewer
    where viewer.id is not null
      and (conversation.user_a = viewer.id or conversation.user_b = viewer.id)
  ),
  enriched as (
    select
      mine.*,
      profile.public_code::text as public_code,
      profile.identity_color::text as identity_color,
      last_message.body as last_message_body,
      last_message.created_at as last_message_at,
      case
        when last_message.id is null then false
        else last_message.sender_id = mine.viewer_id
      end as last_message_is_mine,
      (
        select count(*)
        from private.direct_messages unread
        where unread.conversation_id = mine.id
          and unread.sender_id <> mine.viewer_id
          and unread.read_at is null
      ) as unread_count,
      private.can_direct_message(mine.peer_id) as can_message
    from mine
    join public.profiles profile on profile.id = mine.peer_id
    left join lateral (
      select message.id, message.body, message.created_at, message.sender_id
      from private.direct_messages message
      where message.conversation_id = mine.id
      order by message.created_at desc, message.id desc
      limit 1
    ) last_message on true
  )
  select
    enriched.id,
    enriched.public_code,
    enriched.identity_color,
    enriched.last_message_body,
    enriched.last_message_at,
    enriched.last_message_is_mine,
    enriched.unread_count,
    enriched.can_message,
    count(*) over ()
  from enriched
  order by coalesce(enriched.last_message_at, enriched.created_at) desc, enriched.id
  limit greatest(1, least(coalesce(p_limit, 30), 50))
  offset greatest(0, least(coalesce(p_offset, 0), 500));
$$;

create or replace function private.get_direct_messages(
  p_conversation_id uuid,
  p_before timestamptz default null,
  p_limit integer default 50
)
returns table (
  id uuid,
  body text,
  created_at timestamptz,
  read_at timestamptz,
  sender_code text,
  sender_color text,
  is_mine boolean
)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  viewer uuid := (select auth.uid());
begin
  if viewer is null then
    raise exception 'Unauthorized';
  end if;

  if not exists (
    select 1
    from private.direct_conversations conversation
    where conversation.id = p_conversation_id
      and (conversation.user_a = viewer or conversation.user_b = viewer)
  ) then
    raise exception 'Conversation unavailable';
  end if;

  return query
  select
    message.id,
    message.body,
    message.created_at,
    message.read_at,
    profile.public_code::text,
    profile.identity_color::text,
    message.sender_id = viewer
  from private.direct_messages message
  join public.profiles profile on profile.id = message.sender_id
  where message.conversation_id = p_conversation_id
    and (p_before is null or message.created_at < p_before)
  order by message.created_at desc, message.id desc
  limit greatest(1, least(coalesce(p_limit, 50), 100));
end;
$$;

create or replace function private.send_direct_message(
  p_conversation_id uuid,
  p_body text,
  p_client_nonce uuid
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  viewer uuid := (select auth.uid());
  peer_id uuid;
  clean_body text := btrim(coalesce(p_body, ''));
  message_id uuid;
  message_body text;
  message_created_at timestamptz;
  message_read_at timestamptz;
  sender_code text;
  sender_color text;
begin
  if viewer is null then
    raise exception 'Unauthorized';
  end if;

  if p_client_nonce is null then
    raise exception 'Invalid client nonce';
  end if;

  if char_length(clean_body) < 1 or char_length(clean_body) > 2000 then
    raise exception 'Invalid message body';
  end if;

  select case when conversation.user_a = viewer then conversation.user_b else conversation.user_a end
    into peer_id
  from private.direct_conversations conversation
  where conversation.id = p_conversation_id
    and (conversation.user_a = viewer or conversation.user_b = viewer);

  if peer_id is null then
    raise exception 'Conversation unavailable';
  end if;

  if not private.can_direct_message(peer_id) then
    raise exception 'Messaging unavailable';
  end if;

  insert into private.direct_messages (
    conversation_id, sender_id, body, client_nonce
  )
  values (
    p_conversation_id, viewer, clean_body, p_client_nonce
  )
  on conflict (conversation_id, sender_id, client_nonce) do nothing
  returning id, body, created_at, read_at
    into message_id, message_body, message_created_at, message_read_at;

  if message_id is null then
    select message.id, message.body, message.created_at, message.read_at
      into message_id, message_body, message_created_at, message_read_at
    from private.direct_messages message
    where message.conversation_id = p_conversation_id
      and message.sender_id = viewer
      and message.client_nonce = p_client_nonce;
  end if;

  update private.direct_conversations conversation
  set updated_at = greatest(conversation.updated_at, message_created_at)
  where conversation.id = p_conversation_id;

  select profile.public_code::text, profile.identity_color::text
    into sender_code, sender_color
  from public.profiles profile
  where profile.id = viewer;

  return jsonb_build_object(
    'id', message_id,
    'body', message_body,
    'createdAt', message_created_at,
    'readAt', message_read_at,
    'senderCode', sender_code,
    'senderColor', sender_color,
    'isMine', true
  );
end;
$$;

create or replace function private.mark_direct_conversation_read(p_conversation_id uuid)
returns integer
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  viewer uuid := (select auth.uid());
  changed integer := 0;
begin
  if viewer is null then
    raise exception 'Unauthorized';
  end if;

  if not exists (
    select 1
    from private.direct_conversations conversation
    where conversation.id = p_conversation_id
      and (conversation.user_a = viewer or conversation.user_b = viewer)
  ) then
    raise exception 'Conversation unavailable';
  end if;

  update private.direct_messages message
  set read_at = now()
  where message.conversation_id = p_conversation_id
    and message.sender_id <> viewer
    and message.read_at is null;

  get diagnostics changed = row_count;
  return changed;
end;
$$;

create or replace function private.get_unread_direct_message_count()
returns bigint
language sql
stable
security definer
set search_path = ''
as $$
  with viewer as (select (select auth.uid()) as id)
  select count(*)
  from private.direct_messages message
  join private.direct_conversations conversation
    on conversation.id = message.conversation_id
  cross join viewer
  where viewer.id is not null
    and (conversation.user_a = viewer.id or conversation.user_b = viewer.id)
    and message.sender_id <> viewer.id
    and message.read_at is null;
$$;

create or replace function public.start_direct_conversation(p_public_code text)
returns jsonb
language sql
volatile
security invoker
set search_path = ''
as $$ select private.start_direct_conversation(p_public_code); $$;

create or replace function public.get_direct_conversation(p_conversation_id uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$ select private.get_direct_conversation(p_conversation_id); $$;

create or replace function public.get_direct_conversations(
  p_limit integer default 30,
  p_offset integer default 0
)
returns table (
  conversation_id uuid,
  public_code text,
  identity_color text,
  last_message_body text,
  last_message_at timestamptz,
  last_message_is_mine boolean,
  unread_count bigint,
  can_message boolean,
  total_conversations bigint
)
language sql
stable
security invoker
set search_path = ''
as $$ select * from private.get_direct_conversations(p_limit, p_offset); $$;

create or replace function public.get_direct_messages(
  p_conversation_id uuid,
  p_before timestamptz default null,
  p_limit integer default 50
)
returns table (
  id uuid,
  body text,
  created_at timestamptz,
  read_at timestamptz,
  sender_code text,
  sender_color text,
  is_mine boolean
)
language sql
stable
security invoker
set search_path = ''
as $$ select * from private.get_direct_messages(p_conversation_id, p_before, p_limit); $$;

create or replace function public.send_direct_message(
  p_conversation_id uuid,
  p_body text,
  p_client_nonce uuid
)
returns jsonb
language sql
volatile
security invoker
set search_path = ''
as $$ select private.send_direct_message(p_conversation_id, p_body, p_client_nonce); $$;

create or replace function public.mark_direct_conversation_read(p_conversation_id uuid)
returns integer
language sql
volatile
security invoker
set search_path = ''
as $$ select private.mark_direct_conversation_read(p_conversation_id); $$;

create or replace function public.get_unread_direct_message_count()
returns bigint
language sql
stable
security invoker
set search_path = ''
as $$ select private.get_unread_direct_message_count(); $$;

revoke execute on function private.can_direct_message(uuid) from public, anon, authenticated;
revoke execute on function private.start_direct_conversation(text) from public, anon, authenticated;
revoke execute on function private.get_direct_conversation(uuid) from public, anon, authenticated;
revoke execute on function private.get_direct_conversations(integer, integer) from public, anon, authenticated;
revoke execute on function private.get_direct_messages(uuid, timestamptz, integer) from public, anon, authenticated;
revoke execute on function private.send_direct_message(uuid, text, uuid) from public, anon, authenticated;
revoke execute on function private.mark_direct_conversation_read(uuid) from public, anon, authenticated;
revoke execute on function private.get_unread_direct_message_count() from public, anon, authenticated;

grant execute on function private.can_direct_message(uuid) to authenticated;
grant execute on function private.start_direct_conversation(text) to authenticated;
grant execute on function private.get_direct_conversation(uuid) to authenticated;
grant execute on function private.get_direct_conversations(integer, integer) to authenticated;
grant execute on function private.get_direct_messages(uuid, timestamptz, integer) to authenticated;
grant execute on function private.send_direct_message(uuid, text, uuid) to authenticated;
grant execute on function private.mark_direct_conversation_read(uuid) to authenticated;
grant execute on function private.get_unread_direct_message_count() to authenticated;

revoke execute on function public.start_direct_conversation(text) from public, anon;
revoke execute on function public.get_direct_conversation(uuid) from public, anon;
revoke execute on function public.get_direct_conversations(integer, integer) from public, anon;
revoke execute on function public.get_direct_messages(uuid, timestamptz, integer) from public, anon;
revoke execute on function public.send_direct_message(uuid, text, uuid) from public, anon;
revoke execute on function public.mark_direct_conversation_read(uuid) from public, anon;
revoke execute on function public.get_unread_direct_message_count() from public, anon;

grant execute on function public.start_direct_conversation(text) to authenticated;
grant execute on function public.get_direct_conversation(uuid) to authenticated;
grant execute on function public.get_direct_conversations(integer, integer) to authenticated;
grant execute on function public.get_direct_messages(uuid, timestamptz, integer) to authenticated;
grant execute on function public.send_direct_message(uuid, text, uuid) to authenticated;
grant execute on function public.mark_direct_conversation_read(uuid) to authenticated;
grant execute on function public.get_unread_direct_message_count() to authenticated;
