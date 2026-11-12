-- Read-only launch audit. Run against the NEW dedicated project immediately before deployment.
select jsonb_pretty(jsonb_build_object(
 'registered_users',(select count(*) from auth.users),
 'athlete_profiles',(select count(*) from public.profiles),
 'club_memberships',(select count(*) from public.club_memberships),
 'running_activities',(select count(*) from public.activities),
 'race_results',(select count(*) from public.race_results),
 'club_sessions',(select count(*) from public.club_sessions),
 'rsvp_records',(select count(*) from public.session_rsvps),
 'connected_health_accounts',(select count(*) from public.health_connections),
 'clubs',(select count(*) from public.clubs),
 'bootstrap_pending',(select bootstrap_pending from runtrack_private.bootstrap_state where singleton),
 'owner_user_id',(select owner_user_id from runtrack_private.bootstrap_state where singleton),
 'bootstrap_owner_configured',exists(select 1 from runtrack_private.application_settings where key='BOOTSTRAP_OWNER_EMAIL')
));
do $$begin
 if exists(select 1 from auth.users) or exists(select 1 from public.profiles) or exists(select 1 from public.club_memberships)
 or exists(select 1 from public.activities) or exists(select 1 from public.race_results) or exists(select 1 from public.club_sessions)
 or exists(select 1 from public.session_rsvps) or exists(select 1 from public.health_connections) or exists(select 1 from public.challenge_participants)
 then raise exception 'Launch audit FAILED: application data is not empty. No data has been deleted.'; end if;
 if (select count(*) from public.clubs)<>1 or not exists(select 1 from public.clubs where id='74796e65-6272-4964-8765-686172726965' and name='Tyne Bridge Harriers' and status='active')
 then raise exception 'Launch audit FAILED: expected exactly the active Tyne Bridge Harriers club.'; end if;
 if not (select bootstrap_pending from runtrack_private.bootstrap_state where singleton) then raise exception 'Launch audit FAILED: bootstrap already completed.'; end if;
 if not exists(select 1 from runtrack_private.club_join_codes where club_id='74796e65-6272-4964-8765-686172726965' and revoked_at is null and code_hash=extensions.crypt('TBHRTA',code_hash)) then raise exception 'Launch audit FAILED: joining code not configured.'; end if;
end $$;
