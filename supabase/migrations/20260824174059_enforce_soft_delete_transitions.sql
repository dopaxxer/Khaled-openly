-- Keep the currently deployed API backward-compatible while ensuring a
-- client can only move a live row into the deleted state, never undelete it or
-- forge the deletion timestamp.

create or replace function private.enforce_soft_delete_transition()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if old.deleted_at is null and new.deleted_at is not null then
    new.deleted_at := now();
  elsif old.deleted_at is distinct from new.deleted_at then
    raise exception 'Invalid soft-delete transition';
  end if;
  return new;
end;
$$;

revoke all on function private.enforce_soft_delete_transition() from public;
revoke all on function private.enforce_soft_delete_transition() from anon;
revoke all on function private.enforce_soft_delete_transition() from authenticated;

drop trigger if exists posts_enforce_soft_delete on public.posts;
create trigger posts_enforce_soft_delete
before update of deleted_at on public.posts
for each row execute function private.enforce_soft_delete_transition();

drop trigger if exists comments_enforce_soft_delete on public.comments;
create trigger comments_enforce_soft_delete
before update of deleted_at on public.comments
for each row execute function private.enforce_soft_delete_transition();

grant update (deleted_at) on table public.posts to authenticated;
grant update (deleted_at) on table public.comments to authenticated;
