-- Supabase grants exposed-schema functions to API roles through default
-- privileges. Keep destructive RPCs unavailable to anonymous callers.
revoke all on function public.delete_own_post(uuid) from anon;
revoke all on function public.delete_own_comment(uuid) from anon;
