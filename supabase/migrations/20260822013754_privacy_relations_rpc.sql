create or replace function private.get_privacy_relations()
returns table (
  kind text,
  public_code text,
  identity_color text,
  created_at timestamptz
)
language sql
stable
security definer
set search_path = ''
as $$
  select
    'blocked'::text,
    profile.public_code::text,
    profile.identity_color::text,
    relation.created_at
  from public.blocks relation
  join public.profiles profile on profile.id = relation.blocked_id
  where relation.blocker_id = (select auth.uid())

  union all

  select
    'muted'::text,
    profile.public_code::text,
    profile.identity_color::text,
    relation.created_at
  from public.mutes relation
  join public.profiles profile on profile.id = relation.muted_id
  where relation.muter_id = (select auth.uid())

  order by created_at desc;
$$;

create or replace function public.get_privacy_relations()
returns table (
  kind text,
  public_code text,
  identity_color text,
  created_at timestamptz
)
language sql
stable
security invoker
set search_path = ''
as $$ select * from private.get_privacy_relations(); $$;

revoke execute on function private.get_privacy_relations() from public, anon, authenticated;
grant execute on function private.get_privacy_relations() to authenticated;

revoke execute on function public.get_privacy_relations() from public, anon;
grant execute on function public.get_privacy_relations() to authenticated;
