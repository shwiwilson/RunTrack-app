-- Sharing an activity shares training totals, never the user's detailed health fields.
create function public.shared_activity_feed(p_club_id uuid)
returns table(id uuid,user_id uuid,provider text,provider_workout_id text,type text,started_at timestamptz,ended_at timestamptz,time_zone text,distance_m double precision,active_duration_s double precision,elapsed_duration_s double precision,visibility text,shared_club_id uuid,duplicate_of uuid)
language sql stable security definer set search_path='' as $$
 select a.id,a.user_id,a.provider,a.id::text,a.type,a.started_at,a.ended_at,a.time_zone,a.distance_m,a.active_duration_s,a.elapsed_duration_s,a.visibility,a.shared_club_id,a.duplicate_of
 from public.activities a where a.shared_club_id=p_club_id and a.visibility='club' and a.duplicate_of is null
 and runtrack_private.is_member(p_club_id)
 and exists(select 1 from public.club_memberships m where m.club_id=p_club_id and m.user_id=a.user_id and m.status='active')
 order by a.started_at desc,a.id;
$$;
revoke all on function public.shared_activity_feed(uuid) from public,anon;
grant execute on function public.shared_activity_feed(uuid) to authenticated;
