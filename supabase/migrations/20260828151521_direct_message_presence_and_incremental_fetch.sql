create table if not exists private.direct_message_presence (
  conversation_id uuid not null references private.direct_conversations(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  last_seen_at timestamptz not null default now(),
  typing_until timestamptz,
  primary key (conversation_id, user_id)
);

alter table private.direct_message_presence enable row level security;
revoke all on table private.direct_message_presence from public, anon, authenticated;

drop policy if exists direct_message_presence_explicit_deny on private.direct_message_presence;
create policy direct_message_presence_explicit_deny
on private.direct_message_presence
for all to anon, authenticated
using (false)
with check (false);

create or replace function private.touch_direct_message_presence(
  p_conversation_id uuid,
  p_typing boolean default false
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  viewer uuid := (select auth.uid());
begin
  if viewer is null then raise exception 'Unauthorized'; end if;
  if not private.is_direct_conversation_member(p_conversation_id) then
    raise exception 'Conversation unavailable';
  end if;

  insert into private.direct_message_presence (
    conversation_id, user_id, last_seen_at, typing_until
  )
  values (
    p_conversation_id, viewer, now(),
    case when coalesce(p_typing, false) then now() + interval '4 seconds' else null end
  )
  on conflict (conversation_id, user_id) do update
  set last_seen_at = excluded.last_seen_at,
      typing_until = excluded.typing_until;

  return jsonb_build_object('ok', true);
end;
$$;

create or replace function private.get_direct_message_presence(p_conversation_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  viewer uuid := (select auth.uid());
  peer uuid;
  peer_last_seen timestamptz;
  peer_typing_until timestamptz;
  is_online boolean := false;
begin
  if viewer is null then raise exception 'Unauthorized'; end if;

  select case
    when conversation.user_a = viewer then conversation.user_b
    when conversation.user_b = viewer then conversation.user_a
    else null
  end
  into peer
  from private.direct_conversations conversation
  where conversation.id = p_conversation_id;

  if peer is null then raise exception 'Conversation unavailable'; end if;

  select presence.last_seen_at, presence.typing_until
  into peer_last_seen, peer_typing_until
  from private.direct_message_presence presence
  where presence.conversation_id = p_conversation_id
    and presence.user_id = peer;

  is_online := peer_last_seen is not null
    and peer_last_seen >= now() - interval '45 seconds';

  return jsonb_build_object(
    'online', is_online,
    'typing', is_online and peer_typing_until is not null and peer_typing_until > now(),
    'lastSeenAt', peer_last_seen
  );
end;
$$;

create or replace function private.get_direct_messages_after(
  p_conversation_id uuid,
  p_after timestamptz,
  p_after_id uuid,
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
  if viewer is null then raise exception 'Unauthorized'; end if;
  if not exists (
    select 1
    from private.direct_conversations conversation
    where conversation.id = p_conversation_id
      and (conversation.user_a = viewer or conversation.user_b = viewer)
  ) then
    raise exception 'Conversation unavailable';
  end if;

  return query
  select message.id, message.body, message.created_at, message.read_at,
         profile.public_code::text, profile.identity_color::text,
         message.sender_id = viewer
  from private.direct_messages message
  join public.profiles profile on profile.id = message.sender_id
  where message.conversation_id = p_conversation_id
    and (
      p_after is null
      or p_after_id is null
      or (message.created_at, message.id) > (p_after, p_after_id)
    )
  order by message.created_at asc, message.id asc
  limit greatest(1, least(coalesce(p_limit, 50), 100));
end;
$$;

create or replace function public.touch_direct_message_presence(
  p_conversation_id uuid,
  p_typing boolean default false
)
returns jsonb
language sql volatile security invoker set search_path = ''
as $$ select private.touch_direct_message_presence(p_conversation_id, p_typing); $$;

create or replace function public.get_direct_message_presence(p_conversation_id uuid)
returns jsonb
language sql stable security invoker set search_path = ''
as $$ select private.get_direct_message_presence(p_conversation_id); $$;

create or replace function public.get_direct_messages_after(
  p_conversation_id uuid,
  p_after timestamptz,
  p_after_id uuid,
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
language sql stable security invoker set search_path = ''
as $$
  select * from private.get_direct_messages_after(
    p_conversation_id, p_after, p_after_id, p_limit
  );
$$;

revoke execute on function private.touch_direct_message_presence(uuid, boolean) from public, anon, authenticated;
revoke execute on function private.get_direct_message_presence(uuid) from public, anon, authenticated;
revoke execute on function private.get_direct_messages_after(uuid, timestamptz, uuid, integer) from public, anon, authenticated;
grant execute on function private.touch_direct_message_presence(uuid, boolean) to authenticated;
grant execute on function private.get_direct_message_presence(uuid) to authenticated;
grant execute on function private.get_direct_messages_after(uuid, timestamptz, uuid, integer) to authenticated;

revoke execute on function public.touch_direct_message_presence(uuid, boolean) from public, anon;
revoke execute on function public.get_direct_message_presence(uuid) from public, anon;
revoke execute on function public.get_direct_messages_after(uuid, timestamptz, uuid, integer) from public, anon;
grant execute on function public.touch_direct_message_presence(uuid, boolean) to authenticated;
grant execute on function public.get_direct_message_presence(uuid) to authenticated;
grant execute on function public.get_direct_messages_after(uuid, timestamptz, uuid, integer) to authenticated;
