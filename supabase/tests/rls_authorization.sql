-- Authorization tests for the mention and music-taste features.
--
-- Run against any Openly database that has all migrations applied:
--
--     psql "$DATABASE_URL" -f supabase/tests/rls_authorization.sql
--
-- The whole script runs in one transaction and ends with ROLLBACK, so it
-- creates and removes its own fixtures and never touches real rows. Any failed
-- assertion aborts with the message naming the rule that broke.

begin;

set local client_min_messages to notice;

create or replace function pg_temp.check(p_condition boolean, p_label text)
returns void
language plpgsql
as $$
begin
  if p_condition is not true then
    raise exception 'FAILED: %', p_label;
  end if;
  raise notice 'ok: %', p_label;
end;
$$;

-- Impersonate a Supabase API caller. Passing null gives the anonymous role.
create or replace function pg_temp.act_as(p_user_id uuid)
returns void
language plpgsql
as $$
begin
  if p_user_id is null then
    perform set_config('request.jwt.claims', null, true);
    perform set_config('role', 'anon', true);
  else
    perform set_config(
      'request.jwt.claims',
      json_build_object('sub', p_user_id::text, 'role', 'authenticated')::text,
      true
    );
    perform set_config('role', 'authenticated', true);
  end if;
end;
$$;

create or replace function pg_temp.act_as_owner()
returns void
language plpgsql
as $$
begin
  perform set_config('role', 'postgres', true);
  perform set_config('request.jwt.claims', null, true);
end;
$$;

-- private.notifications is deliberately unreadable by the API roles, so the
-- assertions about it go through this test-only helper rather than weakening
-- the grant the feature relies on. It exists for the length of the
-- transaction and disappears with the rollback.
create or replace function pg_temp.mention_recipients(p_post_id uuid, p_comment_id uuid default null)
returns text[]
language sql
security definer
set search_path = ''
as $$
  select coalesce(array_agg(profile.public_code::text order by profile.public_code), array[]::text[])
  from private.notifications notification
  join public.profiles profile on profile.id = notification.recipient_id
  where notification.kind = 'mention'
    and (
      (p_comment_id is not null and notification.comment_id = p_comment_id)
      or (p_comment_id is null and notification.comment_id is null and notification.post_id = p_post_id)
    );
$$;

-- ---------------------------------------------------------------------------
-- Fixtures: four identities. OWNER writes, PEER is mentioned, MUTER mutes
-- OWNER, BLOCKER blocks OWNER.
-- ---------------------------------------------------------------------------

do $$
declare
  ids uuid[] := array[
    '0a000000-0000-4000-8000-000000000001'::uuid,
    '0a000000-0000-4000-8000-000000000002'::uuid,
    '0a000000-0000-4000-8000-000000000003'::uuid,
    '0a000000-0000-4000-8000-000000000004'::uuid
  ];
  codes text[] := array['TAAA', 'TBBB', 'TCCC', 'TDDD'];
  i integer;
begin
  for i in 1..4 loop
    insert into auth.users (
      id, instance_id, aud, role, email, encrypted_password,
      email_confirmed_at, created_at, updated_at, raw_app_meta_data, raw_user_meta_data
    )
    values (
      ids[i], '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
      'rls-test-' || lower(codes[i]) || '@openly.test', '', now(), now(), now(),
      '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb
    );
    update public.profiles set public_code = codes[i] where id = ids[i];
  end loop;

  insert into public.mutes (muter_id, muted_id) values (ids[3], ids[1]);
  insert into public.blocks (blocker_id, blocked_id) values (ids[4], ids[1]);
end;
$$;

-- ---------------------------------------------------------------------------
-- Mentions
-- ---------------------------------------------------------------------------

select pg_temp.act_as('0a000000-0000-4000-8000-000000000001');

do $$
declare
  new_post_id uuid;
  new_comment_id uuid;
begin
  new_post_id := public.create_post('hello @TBBB and @TCCC and @TAAA and @TDDD and @ZZZZ');

  perform pg_temp.check(
    (select count(*) from public.mentions where source_id = new_post_id) = 3,
    'a post stores one mention row per resolvable code (self included, blocker and unknown excluded)'
  );
  perform pg_temp.check(
    not exists (
      select 1 from public.mentions m
      join public.profiles p on p.id = m.mentioned_id
      where m.source_id = new_post_id and p.public_code = 'TDDD'
    ),
    'a user who blocked the author cannot be mentioned by them'
  );
  perform pg_temp.check(
    not exists (
      select 1 from public.mentions m
      join public.profiles p on p.id = m.mentioned_id
      where m.source_id = new_post_id and p.public_code = 'ZZZZ'
    ),
    'a code that does not exist stays plain text'
  );

  perform pg_temp.check(
    pg_temp.mention_recipients(new_post_id) = array['TBBB'],
    'mentions notify only the peer: not the author, not the muter, not the blocker'
  );

  -- Re-saving the same body must not produce a second notification.
  perform public.update_own_post(new_post_id, 'hello @TBBB and @TCCC and @TAAA and @TDDD and @ZZZZ');
  perform pg_temp.check(
    pg_temp.mention_recipients(new_post_id) = array['TBBB'],
    'saving the same mentions again does not duplicate the notification'
  );

  -- Editing a mention out removes its row and its notification.
  perform public.update_own_post(new_post_id, 'now only @TAAA remains');
  perform pg_temp.check(
    (select count(*) from public.mentions where source_id = new_post_id) = 1,
    'an edit removes mention rows for codes that are gone'
  );
  perform pg_temp.check(
    pg_temp.mention_recipients(new_post_id) = array[]::text[],
    'an edit removes the notification for a mention it deleted'
  );

  -- Comment mentions carry their comment id so the notification can deep link.
  new_comment_id := public.create_comment(new_post_id, null, 'replying to @TBBB');
  perform pg_temp.check(
    pg_temp.mention_recipients(null, new_comment_id) = array['TBBB'],
    'a mention inside a comment notifies with the comment id attached'
  );

  -- Soft deleting the content clears both.
  perform public.delete_own_comment(new_comment_id);
  perform pg_temp.check(
    (select count(*) from public.mentions where source_id = new_comment_id) = 0
    and pg_temp.mention_recipients(null, new_comment_id) = array[]::text[],
    'deleting a comment removes its mentions and their notifications'
  );

  perform public.delete_own_post(new_post_id);
  perform pg_temp.check(
    (select count(*) from public.mentions where post_id = new_post_id) = 0,
    'deleting a post removes every mention on it'
  );
end;
$$;

-- Write boundary: mention rows are produced only by the definer functions.
do $$
begin
  perform pg_temp.check(
    not has_table_privilege('authenticated', 'public.mentions', 'INSERT')
    and not has_table_privilege('authenticated', 'public.mentions', 'UPDATE')
    and not has_table_privilege('authenticated', 'public.mentions', 'DELETE'),
    'no API role may write public.mentions directly'
  );
  perform pg_temp.check(
    not has_function_privilege('anon', 'public.suggest_mentions(text,integer)', 'EXECUTE')
    and not has_function_privilege('anon', 'public.create_post(text)', 'EXECUTE')
    and not has_function_privilege('anon', 'public.discover_music_people(uuid,uuid,integer,integer)', 'EXECUTE'),
    'anonymous callers cannot reach the authenticated-only functions'
  );
end;
$$;

-- Visibility: a blocked user sees neither the content nor its mentions, and
-- cannot find the blocker through autocomplete.
select pg_temp.act_as('0a000000-0000-4000-8000-000000000004');

do $$
begin
  perform pg_temp.check(
    (select count(*) from public.suggest_mentions('TAA')) = 0,
    'autocomplete never surfaces a user the caller has blocked'
  );
  perform pg_temp.check(
    (select count(*) from public.suggest_mentions('TBB')) = 1,
    'autocomplete still returns unrelated users'
  );
end;
$$;

-- ---------------------------------------------------------------------------
-- Music preferences
-- ---------------------------------------------------------------------------

select pg_temp.act_as('0a000000-0000-4000-8000-000000000001');

do $$
declare
  artist_id uuid;
begin
  select id into artist_id from public.add_music_artist('RLS Test Artist');
  perform public.set_music_artists(array[artist_id]);
  perform public.set_music_genres(array(select id from public.music_genres where slug in ('rock', 'indie')));
  perform public.set_music_settings(true, false);

  perform pg_temp.check(
    (public.get_music_profile() ->> 'discoveryOptIn')::boolean,
    'the owner reads back their own settings'
  );
  perform pg_temp.check(
    (select count(*) from public.music_preferences) = 1
    and (select count(*) from public.user_music_artists) = 1,
    'row level security limits the owner to their own preference rows'
  );
end;
$$;

select pg_temp.act_as('0a000000-0000-4000-8000-000000000002');

do $$
declare
  artist_id uuid;
begin
  perform pg_temp.check(
    (select count(*) from public.music_preferences) = 0
    and (select count(*) from public.user_music_artists) = 0
    and (select count(*) from public.user_music_genres) = 0,
    'an unrelated user cannot read anyone else''s private music settings'
  );
  perform pg_temp.check(
    public.get_public_music_profile('TAAA') is null,
    'a list that was not published is invisible even to a signed-in stranger'
  );

  -- Same artist and genres, so the two are a strong match.
  select id into artist_id from public.add_music_artist('RLS Test Artist');
  perform public.set_music_artists(array[artist_id]);
  perform public.set_music_genres(array(select id from public.music_genres where slug in ('rock', 'indie')));
  perform public.set_music_settings(true, true);

  perform pg_temp.check(
    (select count(*) from public.add_music_artist('  rls   test artist!! ') where created) = 0,
    'a differently spelled name resolves to the existing artist instead of a duplicate'
  );
end;
$$;

select pg_temp.act_as('0a000000-0000-4000-8000-000000000001');

do $$
declare
  result_row record;
begin
  select * into result_row from public.discover_music_people() where public_code = 'TBBB';
  perform pg_temp.check(found, 'a user who opted in and shares taste appears in discovery');
  perform pg_temp.check(
    result_row.compatibility between 1 and 100
    and result_row.shared_artist_count = 1
    and result_row.shared_genre_count = 2,
    'the result explains itself with the exact shared artists and genres'
  );
  perform pg_temp.check(
    not exists (select 1 from public.discover_music_people() where public_code = 'TAAA'),
    'discovery never returns the viewer themselves'
  );
  perform pg_temp.check(
    public.get_public_music_profile('TBBB') is not null,
    'a published list is readable'
  );
end;
$$;

-- Opting out has to take effect immediately.
select pg_temp.act_as('0a000000-0000-4000-8000-000000000002');
select public.set_music_settings(false, true);

select pg_temp.act_as('0a000000-0000-4000-8000-000000000001');

do $$
begin
  perform pg_temp.check(
    not exists (select 1 from public.discover_music_people() where public_code = 'TBBB'),
    'opting out removes a user from discovery at once'
  );
end;
$$;

-- A blocked user is never discoverable, however well the taste matches.
select pg_temp.act_as('0a000000-0000-4000-8000-000000000004');

do $$
declare
  artist_id uuid;
begin
  select id into artist_id from public.add_music_artist('RLS Test Artist');
  perform public.set_music_artists(array[artist_id]);
  perform public.set_music_genres(array(select id from public.music_genres where slug in ('rock', 'indie')));
  perform public.set_music_settings(true, true);
end;
$$;

select pg_temp.act_as('0a000000-0000-4000-8000-000000000001');

do $$
begin
  perform pg_temp.check(
    not exists (select 1 from public.discover_music_people() where public_code = 'TDDD'),
    'a user who blocked the viewer stays out of discovery despite a perfect match'
  );
end;
$$;

-- Clearing removes everything the account stored.
do $$
begin
  perform public.clear_music_preferences();
  perform pg_temp.check(
    (select count(*) from public.music_preferences) = 0
    and (select count(*) from public.user_music_artists) = 0
    and (select count(*) from public.user_music_genres) = 0,
    'clearing removes every music row belonging to the account'
  );
end;
$$;

-- Anonymous callers get the public catalog and nothing else.
select pg_temp.act_as(null);

do $$
begin
  perform pg_temp.check(
    (select count(*) from public.music_genres) > 0,
    'the genre catalog is public reference data'
  );
  -- Stronger than "sees no rows": anon has no SELECT grant on the
  -- person-linked music tables at all, so the read is refused before row
  -- level security is even consulted.
  perform pg_temp.check(
    not has_table_privilege('anon', 'public.music_preferences', 'SELECT')
    and not has_table_privilege('anon', 'public.user_music_artists', 'SELECT')
    and not has_table_privilege('anon', 'public.user_music_genres', 'SELECT'),
    'anonymous callers cannot read the person-linked music tables at all'
  );
end;
$$;

select pg_temp.act_as_owner();
select 'ALL RLS ASSERTIONS PASSED' as result;

rollback;
