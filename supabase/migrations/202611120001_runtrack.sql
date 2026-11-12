-- RunTrack starts with one club and no athlete data. No live/test identities are seeded.
create extension if not exists pgcrypto with schema extensions;
create schema if not exists runtrack_private;
revoke all on schema runtrack_private from public, anon, authenticated;

create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  display_name text not null default 'Runner' check (length(btrim(display_name)) between 1 and 100),
  onboarding jsonb not null default '{}'::jsonb check (jsonb_typeof(onboarding) = 'object'),
  created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create table public.clubs (
  id uuid primary key default gen_random_uuid(), name text not null check(length(btrim(name)) between 1 and 120),
  status text not null default 'active' check(status in ('active','inactive')),
  theme_json jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create table public.club_memberships (
  id uuid primary key default gen_random_uuid(), club_id uuid not null references public.clubs(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  role text not null default 'athlete' check(role in ('athlete','admin')),
  status text not null default 'active' check(status in ('active','pending','removed')),
  joined_at timestamptz not null default now(), unique(club_id,user_id)
);
create index memberships_user_idx on public.club_memberships(user_id, status);
create table runtrack_private.club_join_codes (
  id uuid primary key default gen_random_uuid(), club_id uuid not null references public.clubs(id) on delete cascade,
  code_hash text not null, created_at timestamptz not null default now(), revoked_at timestamptz
);
create unique index one_active_code_per_club on runtrack_private.club_join_codes(club_id) where revoked_at is null;
create table runtrack_private.application_settings (key text primary key, value text not null);
create table runtrack_private.bootstrap_state (
  singleton boolean primary key default true check(singleton), bootstrap_pending boolean not null default true,
  owner_user_id uuid references auth.users(id) on delete set null, completed_at timestamptz,
  check((bootstrap_pending and owner_user_id is null and completed_at is null) or (not bootstrap_pending and completed_at is not null))
);
insert into runtrack_private.bootstrap_state(singleton) values(true);
create table runtrack_private.join_attempts (
  user_id uuid primary key references auth.users(id) on delete cascade,
  window_started_at timestamptz not null default now(), attempts integer not null default 0
);

create table public.activities (
  id uuid primary key default gen_random_uuid(), user_id uuid not null references public.profiles(id) on delete cascade,
  provider text not null check(length(provider) between 1 and 64), provider_workout_id text not null,
  type text not null default 'running', device_info jsonb not null default '{}'::jsonb,
  started_at timestamptz not null, ended_at timestamptz not null, time_zone text,
  distance_m double precision check(distance_m >= 0 and distance_m < 'Infinity'::float8),
  active_duration_s double precision check(active_duration_s >= 0 and active_duration_s < 'Infinity'::float8),
  elapsed_duration_s double precision check(elapsed_duration_s >= 0 and elapsed_duration_s < 'Infinity'::float8),
  average_heart_rate double precision check(average_heart_rate > 0 and average_heart_rate < 300),
  maximum_heart_rate double precision check(maximum_heart_rate > 0 and maximum_heart_rate < 300),
  calories_kcal double precision check(calories_kcal >= 0 and calories_kcal < 'Infinity'::float8),
  elevation_gain_m double precision check(elevation_gain_m >= 0 and elevation_gain_m < 'Infinity'::float8),
  sync_status text not null default 'synced' check(sync_status in ('synced','updated','error')),
  visibility text not null default 'private' check(visibility in ('private','club')),
  shared_club_id uuid references public.clubs(id) on delete set null,
  provenance jsonb not null default '{}'::jsonb, is_verified boolean not null default false,
  duplicate_of uuid references public.activities(id) on delete set null,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
  unique(user_id,provider,provider_workout_id), check(ended_at >= started_at),
  check(active_duration_s is null or elapsed_duration_s is null or active_duration_s <= elapsed_duration_s),
  check(visibility <> 'club' or shared_club_id is not null), check(duplicate_of is distinct from id)
);
create index activities_owner_time_idx on public.activities(user_id,started_at desc);
create index activities_shared_idx on public.activities(shared_club_id,started_at desc) where visibility='club';
create index activities_duplicate_idx on public.activities(duplicate_of) where duplicate_of is not null;
create table public.activity_laps (
  id uuid primary key default gen_random_uuid(), activity_id uuid not null references public.activities(id) on delete cascade,
  lap_index integer not null check(lap_index>=0), distance_m double precision check(distance_m>=0),
  duration_s double precision check(duration_s>=0), unique(activity_id,lap_index)
);
create table public.club_sessions (
  id uuid primary key default gen_random_uuid(), club_id uuid not null references public.clubs(id) on delete cascade,
  title text not null check(length(btrim(title)) between 1 and 160), details text not null default '', location text not null default '',
  starts_at timestamptz not null, ends_at timestamptz, created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(), check(ends_at is null or ends_at >= starts_at)
);
create index sessions_club_time_idx on public.club_sessions(club_id,starts_at);
create table public.session_rsvps (
  id uuid primary key default gen_random_uuid(), session_id uuid not null references public.club_sessions(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  status text not null default 'going' check(status in ('going','cancelled')), attended boolean not null default false,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(), unique(session_id,user_id)
);
create index rsvps_user_idx on public.session_rsvps(user_id);
create table public.race_results (
  id uuid primary key default gen_random_uuid(), user_id uuid not null references public.profiles(id) on delete cascade,
  club_id uuid references public.clubs(id) on delete set null, event_name text not null, event_date date not null,
  distance_m double precision not null check(distance_m > 0), duration_s double precision not null check(duration_s > 0),
  verified boolean not null default false, evidence_url text, created_at timestamptz not null default now()
);
create index race_results_user_idx on public.race_results(user_id);
create table public.club_challenges (
  id uuid primary key default gen_random_uuid(), club_id uuid not null references public.clubs(id) on delete cascade,
  title text not null, description text not null default '', starts_at timestamptz not null, ends_at timestamptz not null,
  target_distance_m double precision not null check(target_distance_m>0), created_at timestamptz not null default now(),check(ends_at>starts_at)
);
create table public.challenge_participants (
  id uuid primary key default gen_random_uuid(), challenge_id uuid not null references public.club_challenges(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade, joined_at timestamptz not null default now(),unique(challenge_id,user_id)
);
create table public.health_connections (
  id uuid primary key default gen_random_uuid(), user_id uuid not null references public.profiles(id) on delete cascade,
  provider text not null, status text not null default 'setup_required' check(status in ('setup_required','connected','error','revoked','disconnected')),
  provider_user_id text, last_successful_sync_at timestamptz, last_error text, sync_cursor jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(), unique(user_id,provider)
);
create table runtrack_private.health_credentials (
  connection_id uuid primary key references public.health_connections(id) on delete cascade,
  access_token_ciphertext text not null, refresh_token_ciphertext text, expires_at timestamptz not null,
  scopes text[] not null default '{}', updated_at timestamptz not null default now()
);
create table public.oauth_states (
  state_hash text primary key, user_id uuid not null references auth.users(id) on delete cascade,
  expires_at timestamptz not null, consumed_at timestamptz, redirect_uri text not null, code_verifier_ciphertext text not null,
  created_at timestamptz not null default now()
);
create table public.sync_jobs (
  id uuid primary key default gen_random_uuid(), connection_id uuid not null references public.health_connections(id) on delete cascade,
  status text not null default 'pending' check(status in ('pending','running','succeeded','failed')), started_at timestamptz,finished_at timestamptz,
  error_message text,created_at timestamptz not null default now()
);
create index sync_jobs_connection_idx on public.sync_jobs(connection_id,created_at desc);
create table public.sync_events (
  id uuid primary key default gen_random_uuid(), connection_id uuid references public.health_connections(id) on delete cascade,
  provider text not null, provider_event_id text not null, event_type text not null, received_at timestamptz not null default now(),
  processed_at timestamptz, unique(provider,provider_event_id)
);

-- RLS helper functions return booleans only. They do not disclose private membership records.
create function runtrack_private.is_member(p_club uuid) returns boolean language sql stable security definer set search_path='' as $$
  select exists(select 1 from public.club_memberships where club_id=p_club and user_id=(select auth.uid()) and status='active');
$$;
create function runtrack_private.is_admin(p_club uuid) returns boolean language sql stable security definer set search_path='' as $$
  select exists(select 1 from public.club_memberships where club_id=p_club and user_id=(select auth.uid()) and role='admin' and status='active');
$$;
create function runtrack_private.session_member(p_session uuid) returns boolean language sql stable security definer set search_path='' as $$
  select exists(select 1 from public.club_sessions where id=p_session and runtrack_private.is_member(club_id));
$$;
create function runtrack_private.session_admin(p_session uuid) returns boolean language sql stable security definer set search_path='' as $$
  select exists(select 1 from public.club_sessions where id=p_session and runtrack_private.is_admin(club_id));
$$;
grant usage on schema runtrack_private to authenticated;
grant execute on function runtrack_private.is_member(uuid),runtrack_private.is_admin(uuid),runtrack_private.session_member(uuid),runtrack_private.session_admin(uuid) to authenticated;

-- Enable RLS on every application table, including non-exposed secret tables.
do $$ declare r record; begin
  for r in select schemaname,tablename from pg_tables where schemaname in ('public','runtrack_private') loop
    execute format('alter table %I.%I enable row level security',r.schemaname,r.tablename);
    execute format('revoke all on table %I.%I from anon, authenticated',r.schemaname,r.tablename);
  end loop;
end $$;
grant select on public.profiles,public.clubs,public.club_memberships,public.activities,public.activity_laps,public.club_sessions,public.session_rsvps,public.race_results,public.club_challenges,public.challenge_participants,public.health_connections,public.sync_jobs to authenticated;
grant update(display_name) on public.profiles to authenticated;
grant update(visibility,shared_club_id) on public.activities to authenticated;
grant update(name,status,theme_json) on public.clubs to authenticated;
grant insert,update,delete on public.club_sessions,public.club_challenges to authenticated;
grant insert(session_id,user_id,status),update(status),delete on public.session_rsvps to authenticated;
grant insert(challenge_id,user_id),delete on public.challenge_participants to authenticated;
grant insert(user_id,club_id,event_name,event_date,distance_m,duration_s,evidence_url),update(event_name,event_date,distance_m,duration_s,evidence_url),delete on public.race_results to authenticated;
grant all on all tables in schema public to service_role;
grant usage on schema runtrack_private to service_role;

create policy profile_read on public.profiles for select to authenticated using(id=(select auth.uid()));
create policy profile_update on public.profiles for update to authenticated using(id=(select auth.uid())) with check(id=(select auth.uid()));
create policy clubs_read on public.clubs for select to authenticated using(runtrack_private.is_member(id));
create policy clubs_update on public.clubs for update to authenticated using(runtrack_private.is_admin(id)) with check(runtrack_private.is_admin(id));
create policy memberships_read on public.club_memberships for select to authenticated using(user_id=(select auth.uid()) or runtrack_private.is_member(club_id));
create policy activities_read on public.activities for select to authenticated using(user_id=(select auth.uid()));
create policy activities_update on public.activities for update to authenticated using(user_id=(select auth.uid())) with check(user_id=(select auth.uid()) and (visibility='private' or runtrack_private.is_member(shared_club_id)));
-- Club activity sharing is exposed only through the sanitized shared_activity_feed RPC.
create policy laps_read on public.activity_laps for select to authenticated using(exists(select 1 from public.activities a where a.id=activity_id and a.user_id=(select auth.uid())));
create policy sessions_read on public.club_sessions for select to authenticated using(runtrack_private.is_member(club_id));
create policy sessions_insert on public.club_sessions for insert to authenticated with check(runtrack_private.is_admin(club_id) and created_by=(select auth.uid()));
create policy sessions_update on public.club_sessions for update to authenticated using(runtrack_private.is_admin(club_id)) with check(runtrack_private.is_admin(club_id));
create policy sessions_delete on public.club_sessions for delete to authenticated using(runtrack_private.is_admin(club_id));
create policy rsvps_read on public.session_rsvps for select to authenticated using(user_id=(select auth.uid()) or runtrack_private.session_member(session_id));
create policy rsvps_insert on public.session_rsvps for insert to authenticated with check(user_id=(select auth.uid()) and runtrack_private.session_member(session_id) and not attended);
create policy rsvps_update on public.session_rsvps for update to authenticated using(user_id=(select auth.uid()) and runtrack_private.session_member(session_id)) with check(user_id=(select auth.uid()) and runtrack_private.session_member(session_id));
create policy rsvps_delete on public.session_rsvps for delete to authenticated using(user_id=(select auth.uid()));
create policy races_read on public.race_results for select to authenticated using(user_id=(select auth.uid()));
create policy races_insert on public.race_results for insert to authenticated with check(user_id=(select auth.uid()) and not verified and (club_id is null or runtrack_private.is_member(club_id)));
create policy races_update on public.race_results for update to authenticated using(user_id=(select auth.uid())) with check(user_id=(select auth.uid()));
create policy races_delete on public.race_results for delete to authenticated using(user_id=(select auth.uid()));
create policy challenges_read on public.club_challenges for select to authenticated using(runtrack_private.is_member(club_id));
create policy challenges_insert on public.club_challenges for insert to authenticated with check(runtrack_private.is_admin(club_id));
create policy challenges_update on public.club_challenges for update to authenticated using(runtrack_private.is_admin(club_id)) with check(runtrack_private.is_admin(club_id));
create policy challenges_delete on public.club_challenges for delete to authenticated using(runtrack_private.is_admin(club_id));
create policy participants_read on public.challenge_participants for select to authenticated using(exists(select 1 from public.club_challenges c where c.id=challenge_id and runtrack_private.is_member(c.club_id)));
create policy participants_insert on public.challenge_participants for insert to authenticated with check(user_id=(select auth.uid()) and exists(select 1 from public.club_challenges c where c.id=challenge_id and runtrack_private.is_member(c.club_id)));
create policy participants_delete on public.challenge_participants for delete to authenticated using(user_id=(select auth.uid()));
create policy connections_read on public.health_connections for select to authenticated using(user_id=(select auth.uid()));
create policy jobs_read on public.sync_jobs for select to authenticated using(exists(select 1 from public.health_connections c where c.id=connection_id and c.user_id=(select auth.uid())));

-- Profile creation is explicit and idempotent. A broken profile trigger cannot block signup.
create function public.ensure_profile(p_display_name text default null) returns public.profiles language plpgsql security definer set search_path='' as $$
declare v_id uuid := auth.uid(); v_row public.profiles; v_name text;
begin
  if v_id is null then raise exception 'Sign in required' using errcode='42501'; end if;
  if not exists(select 1 from auth.users where id=v_id and email_confirmed_at is not null) then raise exception 'Verify your email before continuing' using errcode='42501'; end if;
  v_name := left(coalesce(nullif(btrim(p_display_name),''),nullif(btrim((select raw_user_meta_data->>'display_name' from auth.users where id=v_id)),''),'Runner'),100);
  insert into public.profiles(id,display_name) values(v_id,v_name) on conflict(id) do nothing;
  select * into v_row from public.profiles where id=v_id; return v_row;
end $$;
create function public.update_onboarding(p_patch jsonb) returns public.profiles language plpgsql security definer set search_path='' as $$
declare v_row public.profiles;
begin
  if auth.uid() is null then raise exception 'Sign in required' using errcode='42501'; end if;
  if jsonb_typeof(p_patch) <> 'object' or octet_length(p_patch::text)>16384 then raise exception 'Invalid onboarding update'; end if;
  update public.profiles set onboarding=onboarding||p_patch,updated_at=now() where id=auth.uid() returning * into v_row;
  if not found then raise exception 'Create your profile first'; end if;
  return v_row;
end $$;
create function public.bootstrap_status() returns jsonb language sql stable security definer set search_path='' as $$
 select jsonb_build_object('bootstrap_pending',s.bootstrap_pending,'setup_required',s.bootstrap_pending and not exists(select 1 from runtrack_private.application_settings where key='BOOTSTRAP_OWNER_EMAIL' and length(value)>3)) from runtrack_private.bootstrap_state s where singleton;
$$;
-- Backend configuration only. Never grant this RPC to browser roles.
create function public.configure_bootstrap_owner(p_email text) returns void language plpgsql security definer set search_path='' as $$
begin
 if not (select bootstrap_pending from runtrack_private.bootstrap_state where singleton) then raise exception 'Bootstrap already completed'; end if;
 if p_email is null or p_email !~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$' then raise exception 'A valid owner email is required'; end if;
 insert into runtrack_private.application_settings(key,value) values('BOOTSTRAP_OWNER_EMAIL',lower(btrim(p_email))) on conflict(key) do update set value=excluded.value;
end $$;
create function public.before_user_created(event jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare v_email text; v_owner text; v_pending boolean;
begin
 select bootstrap_pending into v_pending from runtrack_private.bootstrap_state where singleton;
 if v_pending is distinct from false then
  select value into v_owner from runtrack_private.application_settings where key='BOOTSTRAP_OWNER_EMAIL';
  if v_owner is null then return jsonb_build_object('error',jsonb_build_object('http_code',503,'message','RunTrack deployment setup is incomplete. Please try again later.')); end if;
  v_email := lower(btrim(event->'user'->>'email'));
  if v_email is null or v_email<>v_owner then return jsonb_build_object('error',jsonb_build_object('http_code',403,'message','RunTrack registration is not open yet.')); end if;
 end if;
 return '{}'::jsonb;
end $$;

create function public.join_club(p_code text) returns jsonb language plpgsql security definer set search_path='' as $$
declare v_uid uuid:=auth.uid(); v_email text; v_owner text; v_boot runtrack_private.bootstrap_state; v_club uuid; v_attempt runtrack_private.join_attempts; v_membership public.club_memberships;
begin
 if v_uid is null then raise exception 'Sign in required' using errcode='42501'; end if;
 select lower(btrim(email)) into v_email from auth.users where id=v_uid and email_confirmed_at is not null;
 if v_email is null then raise exception 'Verify your email before joining a club' using errcode='42501'; end if;
 perform public.ensure_profile();
 insert into runtrack_private.join_attempts(user_id) values(v_uid) on conflict(user_id) do nothing;
 select * into v_attempt from runtrack_private.join_attempts where user_id=v_uid for update;
 if v_attempt.window_started_at < now()-interval '15 minutes' then
  update runtrack_private.join_attempts set attempts=0,window_started_at=now() where user_id=v_uid; v_attempt.attempts:=0;
 end if;
 if v_attempt.attempts>=10 then return jsonb_build_object('ok',false,'code','rate_limited','error','Too many attempts. Please wait 15 minutes.'); end if;
 update runtrack_private.join_attempts set attempts=attempts+1 where user_id=v_uid;
 if p_code is not null and length(btrim(p_code)) between 6 and 128 then
  select j.club_id into v_club from runtrack_private.club_join_codes j join public.clubs c on c.id=j.club_id
  where j.revoked_at is null and c.status='active' and j.code_hash=extensions.crypt(upper(btrim(p_code)),j.code_hash) limit 1;
 end if;
 if v_club is null then return jsonb_build_object('ok',false,'code','invalid_code','error','Invalid club joining code.'); end if;
 select * into v_boot from runtrack_private.bootstrap_state where singleton for update;
 if v_boot.bootstrap_pending then
  select value into v_owner from runtrack_private.application_settings where key='BOOTSTRAP_OWNER_EMAIL';
  if v_owner is null then return jsonb_build_object('ok',false,'code','setup_required','error','RunTrack deployment setup is incomplete.'); end if;
  if v_email<>v_owner or v_club<>'74796e65-6272-4964-8765-686172726965'::uuid then return jsonb_build_object('ok',false,'code','bootstrap_restricted','error','RunTrack registration is not open yet.'); end if;
  insert into public.club_memberships(club_id,user_id,role,status) values(v_club,v_uid,'admin','active')
    on conflict(club_id,user_id) do update set role='admin',status='active' returning * into v_membership;
  update runtrack_private.bootstrap_state set bootstrap_pending=false,owner_user_id=v_uid,completed_at=now() where singleton;
 else
  select * into v_membership from public.club_memberships where club_id=v_club and user_id=v_uid;
  if found and v_membership.status='removed' then return jsonb_build_object('ok',false,'code','membership_removed','error','Contact the club administrator to restore your membership.'); end if;
  insert into public.club_memberships(club_id,user_id,role,status) values(v_club,v_uid,'athlete','active') on conflict(club_id,user_id) do nothing;
  select * into v_membership from public.club_memberships where club_id=v_club and user_id=v_uid;
 end if;
 return jsonb_build_object('ok',true,'club_id',v_membership.club_id,'user_id',v_uid,'role',v_membership.role,'status',v_membership.status);
end $$;
create function public.club_member_profiles(p_club_id uuid) returns table(id uuid,display_name text) language sql stable security definer set search_path='' as $$
 select p.id,p.display_name from public.profiles p join public.club_memberships m on m.user_id=p.id where m.club_id=p_club_id and (m.status='active' or runtrack_private.is_admin(p_club_id)) and runtrack_private.is_member(p_club_id);
$$;
create function public.update_membership(p_membership_id uuid,p_status text,p_role text default 'athlete') returns void language plpgsql security definer set search_path='' as $$
declare v_m public.club_memberships;
begin
 select * into v_m from public.club_memberships where id=p_membership_id;
 if not found then raise exception 'Club administrator required' using errcode='42501'; end if;
 -- Check authorization after acquiring the same lock used for role changes.
 perform 1 from public.clubs where id=v_m.club_id for update;
 if not runtrack_private.is_admin(v_m.club_id) then raise exception 'Club administrator required' using errcode='42501'; end if;
 select * into v_m from public.club_memberships where id=p_membership_id;
 if p_status not in ('active','pending','removed') or p_role not in ('athlete','admin') then raise exception 'Invalid membership'; end if;
 -- All role changes for a club are serialized, including final-admin checks.
 if v_m.role='admin' and v_m.status='active' and (p_role<>'admin' or p_status<>'active') and
   (select count(*) from public.club_memberships where club_id=v_m.club_id and role='admin' and status='active')<=1 then raise exception 'The club must retain an administrator'; end if;
 update public.club_memberships set status=p_status,role=p_role where id=p_membership_id;
end $$;
create function public.rotate_join_code(p_club_id uuid,p_code text) returns void language plpgsql security definer set search_path='' as $$
begin
 perform 1 from public.clubs where id=p_club_id for update;
 if not runtrack_private.is_admin(p_club_id) then raise exception 'Club administrator required' using errcode='42501'; end if;
 if p_code is null or length(btrim(p_code)) not between 6 and 128 then raise exception 'Use a joining code between 6 and 128 characters'; end if;
 update runtrack_private.club_join_codes set revoked_at=now() where club_id=p_club_id and revoked_at is null;
 insert into runtrack_private.club_join_codes(club_id,code_hash) values(p_club_id,extensions.crypt(upper(btrim(p_code)),extensions.gen_salt('bf',10)));
end $$;
create function public.record_attendance(p_rsvp_id uuid,p_attended boolean) returns void language plpgsql security definer set search_path='' as $$
declare v_session uuid; v_club uuid;
begin
 select r.session_id,s.club_id into v_session,v_club from public.session_rsvps r join public.club_sessions s on s.id=r.session_id where r.id=p_rsvp_id;
 perform 1 from public.clubs where id=v_club for update;
 if not runtrack_private.session_admin(v_session) then raise exception 'Club administrator required' using errcode='42501'; end if;
 if p_attended and not exists(select 1 from public.session_rsvps r join public.club_sessions s on s.id=r.session_id where r.id=p_rsvp_id and r.status='going' and s.starts_at<=now()) then raise exception 'Attendance can only be confirmed after a session starts for a runner who is going'; end if;
 update public.session_rsvps set attended=p_attended,updated_at=now() where id=p_rsvp_id;
end $$;

create function public.health_credentials_get(p_connection_id uuid) returns jsonb language sql security definer set search_path='' as $$
 select to_jsonb(t) from runtrack_private.health_credentials t where connection_id=p_connection_id;
$$;
create function public.health_credentials_store(p_connection_id uuid,p_access_token_ciphertext text,p_refresh_token_ciphertext text,p_expires_at timestamptz,p_scopes text[]) returns void language plpgsql security definer set search_path='' as $$
begin
 perform 1 from public.health_connections where id=p_connection_id and status in ('connected','error') for update;
 if not found then raise exception 'Health connection is not active' using errcode='42501'; end if;
 insert into runtrack_private.health_credentials(connection_id,access_token_ciphertext,refresh_token_ciphertext,expires_at,scopes)
 values(p_connection_id,p_access_token_ciphertext,p_refresh_token_ciphertext,p_expires_at,p_scopes)
 on conflict(connection_id) do update set access_token_ciphertext=excluded.access_token_ciphertext,refresh_token_ciphertext=excluded.refresh_token_ciphertext,expires_at=excluded.expires_at,scopes=excluded.scopes,updated_at=now();
end $$;
create function public.health_credentials_delete(p_connection_id uuid) returns void language sql security definer set search_path='' as $$ delete from runtrack_private.health_credentials where connection_id=p_connection_id; $$;
create function public.consume_health_oauth_state(p_hash text) returns jsonb language sql security definer set search_path='' as $$
 update public.oauth_states set consumed_at=now() where state_hash=p_hash and consumed_at is null and expires_at>now() returning to_jsonb(oauth_states.*);
$$;

-- Least privilege: PostgreSQL grants PUBLIC execute on new functions by default.
revoke all on all functions in schema runtrack_private from public,anon,authenticated;
grant execute on function runtrack_private.is_member(uuid),runtrack_private.is_admin(uuid),runtrack_private.session_member(uuid),runtrack_private.session_admin(uuid) to authenticated;
revoke all on all functions in schema public from public,anon,authenticated;
grant execute on function public.ensure_profile(text),public.update_onboarding(jsonb),public.join_club(text),public.club_member_profiles(uuid),public.update_membership(uuid,text,text),public.rotate_join_code(uuid,text),public.record_attendance(uuid,boolean) to authenticated;
grant execute on function public.bootstrap_status() to anon,authenticated;
grant execute on function public.before_user_created(jsonb) to supabase_auth_admin;
grant execute on function public.configure_bootstrap_owner(text),public.health_credentials_get(uuid),public.health_credentials_store(uuid,text,text,timestamptz,text[]),public.health_credentials_delete(uuid),public.consume_health_oauth_state(text) to service_role;

-- This is the only seeded club. The code is a salted hash, never available to browser queries.
insert into public.clubs(id,name,status,theme_json) values('74796e65-6272-4964-8765-686172726965','Tyne Bridge Harriers','active','{}');
insert into runtrack_private.club_join_codes(club_id,code_hash) values('74796e65-6272-4964-8765-686172726965',extensions.crypt('TBHRTA',extensions.gen_salt('bf',10)));
