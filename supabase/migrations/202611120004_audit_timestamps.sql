-- Immutable ownership/club foreign keys prevent attribution changes during normal edits.
revoke update on public.club_sessions,public.club_challenges from authenticated;
grant update(title,details,location,starts_at,ends_at) on public.club_sessions to authenticated;
grant update(title,description,starts_at,ends_at,target_distance_m) on public.club_challenges to authenticated;

create function runtrack_private.touch_updated_at() returns trigger language plpgsql set search_path='' as $$
begin new.updated_at=now(); return new; end $$;
revoke all on function runtrack_private.touch_updated_at() from public,anon,authenticated;
create trigger profiles_updated before update on public.profiles for each row execute function runtrack_private.touch_updated_at();
create trigger clubs_updated before update on public.clubs for each row execute function runtrack_private.touch_updated_at();
create trigger activities_updated before update on public.activities for each row execute function runtrack_private.touch_updated_at();
create trigger sessions_updated before update on public.club_sessions for each row execute function runtrack_private.touch_updated_at();
create trigger rsvps_updated before update on public.session_rsvps for each row execute function runtrack_private.touch_updated_at();
create trigger connections_updated before update on public.health_connections for each row execute function runtrack_private.touch_updated_at();

-- Reject non-finite measurements and malformed/bloated metadata at the database boundary.
alter table public.profiles add constraint onboarding_size check(octet_length(onboarding::text)<=32768);
alter table public.clubs add constraint club_theme_object check(jsonb_typeof(theme_json)='object');
alter table public.activities add constraint activity_metadata_objects check(jsonb_typeof(device_info)='object' and jsonb_typeof(provenance)='object');
alter table public.activity_laps add constraint lap_finite_measurements check((distance_m is null or distance_m<'Infinity'::float8) and (duration_s is null or duration_s<'Infinity'::float8));
alter table public.race_results add constraint race_finite_measurements check(distance_m<'Infinity'::float8 and duration_s<'Infinity'::float8);
alter table public.race_results add constraint race_name_nonempty check(length(btrim(event_name)) between 1 and 160);
alter table public.club_challenges add constraint challenge_valid_values check(target_distance_m<'Infinity'::float8 and length(btrim(title)) between 1 and 160);
alter table public.health_connections add constraint sync_cursor_object check(jsonb_typeof(sync_cursor)='object');
