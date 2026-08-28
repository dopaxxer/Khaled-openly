-- Harden private direct messaging after the initial schema landed.
-- A mute in either direction prevents new DMs; private rows remain inaccessible
-- outside authenticated RPCs; new messages emit member-only Realtime broadcasts.

drop policy if exists direct_conversations_explicit_deny on private.direct_conversations;
create policy direct_conversations_explicit_deny
on private.direct_conversations
for all to anon, authenticated
using (false)
with check (false);

drop policy if exists direct_messages_explicit_deny on private.direct_messages;
create policy direct_messages_explicit_deny
on private.direct_messages
for all to anon, authenticated
using (false)
with check (false);

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
      and not exists (
        select 1
        from public.mutes mute
        where (mute.muter_id = viewer.id and mute.muted_id = p_target_id)
           or (mute.muter_id = p_target_id and mute.muted_id = viewer.id)
      )
    from viewer
  ), false);
$$;

create or replace function private.is_direct_conversation_member(p_conversation_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce((
    select
      private.is_active_user()
      and exists (
        select 1
        from private.direct_conversations conversation
        where conversation.id = p_conversation_id
          and (
            conversation.user_a = (select auth.uid())
            or conversation.user_b = (select auth.uid())
          )
      )
  ), false);
$$;

create or replace function public.can_join_direct_message_topic(p_topic text)
returns boolean
language sql
stable
security invoker
set search_path = ''
as $$
  select case
    when coalesce(p_topic, '') ~ '^dm:[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$'
      then private.is_direct_conversation_member(split_part(p_topic, ':', 2)::uuid)
    else false
  end;
$$;

revoke execute on function private.is_direct_conversation_member(uuid) from public, anon, authenticated;
grant execute on function private.is_direct_conversation_member(uuid) to authenticated;

revoke execute on function public.can_join_direct_message_topic(text) from public, anon;
grant execute on function public.can_join_direct_message_topic(text) to authenticated;

create or replace function private.broadcast_direct_message_insert()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform realtime.broadcast_changes(
    'dm:' || new.conversation_id::text,
    'INSERT',
    'INSERT',
    tg_table_name,
    tg_table_schema,
    new,
    old
  );
  return null;
end;
$$;

revoke execute on function private.broadcast_direct_message_insert() from public, anon, authenticated;

drop trigger if exists broadcast_direct_message_insert on private.direct_messages;
create trigger broadcast_direct_message_insert
after insert on private.direct_messages
for each row
execute function private.broadcast_direct_message_insert();

drop policy if exists direct_message_broadcast_receive on realtime.messages;
create policy direct_message_broadcast_receive
on realtime.messages
for select
to authenticated
using (public.can_join_direct_message_topic(topic));
