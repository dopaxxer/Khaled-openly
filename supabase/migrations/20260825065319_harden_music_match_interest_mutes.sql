-- A stale discovery card must not let the viewer express interest in an
-- identity they muted after the card was loaded.
create or replace function private.set_music_match_interest(
  p_public_code text,
  p_interested boolean
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  viewer uuid := (select auth.uid());
  target uuid;
  target_code text;
  target_color text;
  first_user uuid;
  second_user uuid;
  score_row record;
  is_matched boolean := false;
  match_time timestamptz;
begin
  if viewer is null or not private.is_active_user() then
    raise exception 'Unauthorized';
  end if;

  if not exists (
    select 1
    from public.music_preferences pref
    where pref.user_id = viewer and pref.discovery_opt_in
  ) then
    raise exception 'Enable music discovery first';
  end if;

  select profile.id, profile.public_code, profile.identity_color
  into target, target_code, target_color
  from public.profiles profile
  join public.music_preferences pref on pref.user_id = profile.id
  where profile.public_code = upper(btrim(coalesce(p_public_code, '')))
    and profile.id <> viewer
    and pref.discovery_opt_in
    and private.can_view_user(profile.id)
    and not exists (
      select 1
      from public.mutes mute
      where mute.muter_id = viewer
        and mute.muted_id = profile.id
    );

  if target is null then
    raise exception 'Target is not available for music discovery';
  end if;

  if viewer::text < target::text then
    first_user := viewer;
    second_user := target;
  else
    first_user := target;
    second_user := viewer;
  end if;

  select exists (
    select 1
    from public.music_matches match
    where match.user_a = first_user and match.user_b = second_user
  ) into is_matched;

  if coalesce(p_interested, false) then
    select * into score_row from private.music_similarity_to(target);
    if score_row.compatibility is null or score_row.compatibility <= 0 then
      raise exception 'No eligible music overlap';
    end if;

    insert into public.music_match_interests (user_id, target_user_id)
    values (viewer, target)
    on conflict (user_id, target_user_id) do nothing;

    if exists (
      select 1
      from public.music_match_interests reverse_interest
      where reverse_interest.user_id = target
        and reverse_interest.target_user_id = viewer
    ) then
      insert into public.music_matches (user_a, user_b)
      values (first_user, second_user)
      on conflict (user_a, user_b) do nothing;
    end if;
  elsif not is_matched then
    delete from public.music_match_interests
    where user_id = viewer and target_user_id = target;
  end if;

  select match.matched_at
  into match_time
  from public.music_matches match
  where match.user_a = first_user and match.user_b = second_user;

  is_matched := match_time is not null;

  return jsonb_build_object(
    'publicCode', target_code,
    'identityColor', target_color,
    'interested', exists (
      select 1
      from public.music_match_interests mine
      where mine.user_id = viewer and mine.target_user_id = target
    ),
    'matched', is_matched,
    'matchedAt', match_time
  );
end;
$$;
