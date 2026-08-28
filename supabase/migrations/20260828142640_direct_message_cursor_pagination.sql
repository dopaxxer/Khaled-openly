create or replace function private.get_direct_messages_page(
  p_conversation_id uuid,
  p_before timestamptz default null,
  p_before_id uuid default null,
  p_limit integer default 31
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
    select 1 from private.direct_conversations conversation
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
      p_before is null
      or p_before_id is null
      or (message.created_at, message.id) < (p_before, p_before_id)
    )
  order by message.created_at desc, message.id desc
  limit greatest(1, least(coalesce(p_limit, 31), 101));
end;
$$;

create or replace function public.get_direct_messages_page(
  p_conversation_id uuid,
  p_before timestamptz default null,
  p_before_id uuid default null,
  p_limit integer default 31
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
as $$
  select * from private.get_direct_messages_page(
    p_conversation_id, p_before, p_before_id, p_limit
  );
$$;

revoke execute on function private.get_direct_messages_page(uuid, timestamptz, uuid, integer)
  from public, anon, authenticated;
grant execute on function private.get_direct_messages_page(uuid, timestamptz, uuid, integer)
  to authenticated;

revoke execute on function public.get_direct_messages_page(uuid, timestamptz, uuid, integer)
  from public, anon;
grant execute on function public.get_direct_messages_page(uuid, timestamptz, uuid, integer)
  to authenticated;
