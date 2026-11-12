-- Server ingestion is transactional and cannot be invoked with a browser publishable key.
alter table public.activities add column provider_seen_at timestamptz not null default now();
create unique index health_provider_identity_unique on public.health_connections(provider,provider_user_id) where provider_user_id is not null;
alter table public.sync_events add column payload jsonb not null default '{}'::jsonb;
alter table public.sync_jobs add column lease_expires_at timestamptz;
create index sync_events_pending_idx on public.sync_events(received_at) where processed_at is null;
create function public.claim_health_sync(p_connection_id uuid) returns uuid language plpgsql security definer set search_path='' as $$
declare v_id uuid;
begin
  perform pg_advisory_xact_lock(hashtextextended(p_connection_id::text,0));
  if exists(select 1 from public.sync_jobs where connection_id=p_connection_id and status='running' and lease_expires_at>now()) then return null; end if;
  update public.sync_jobs set status='failed',finished_at=now(),error_message='Sync lease expired' where connection_id=p_connection_id and status='running';
  insert into public.sync_jobs(connection_id,status,started_at,lease_expires_at) values(p_connection_id,'running',now(),now()+interval '10 minutes') returning id into v_id;
  return v_id;
end $$;
create function public.upsert_health_activity(p_activity jsonb,p_laps jsonb default '[]'::jsonb) returns uuid language plpgsql security definer set search_path='' as $$
declare a public.activities; v_id uuid; v_duplicate uuid;
begin
  a := jsonb_populate_record(null::public.activities,p_activity);
  if a.provider is null or a.provider_workout_id is null or a.user_id is null then raise exception 'Provider source identity required'; end if;
  if not exists(select 1 from public.health_connections where user_id=a.user_id and provider=a.provider and status in ('connected','error')) then raise exception 'Health connection required'; end if;
  perform pg_advisory_xact_lock(hashtextextended(a.user_id::text,1));
  -- Distances alone never establish duplicates. Only explicit origin source identity does.
  if nullif(a.provenance->>'origin_workout_id','') is not null and nullif(a.provenance->>'origin_provider','') is not null then
    select id into v_duplicate from public.activities where user_id=a.user_id and duplicate_of is null
      and provenance->>'origin_workout_id'=a.provenance->>'origin_workout_id' and provenance->>'origin_provider'=a.provenance->>'origin_provider'
      and not(provider=a.provider and provider_workout_id=a.provider_workout_id) order by created_at limit 1;
  end if;
  insert into public.activities(user_id,provider,provider_workout_id,type,started_at,ended_at,time_zone,distance_m,active_duration_s,elapsed_duration_s,average_heart_rate,maximum_heart_rate,calories_kcal,elevation_gain_m,device_info,provenance,sync_status,duplicate_of)
    values(a.user_id,a.provider,a.provider_workout_id,a.type,a.started_at,a.ended_at,a.time_zone,a.distance_m,a.active_duration_s,a.elapsed_duration_s,a.average_heart_rate,a.maximum_heart_rate,a.calories_kcal,a.elevation_gain_m,coalesce(a.device_info,'{}'::jsonb),coalesce(a.provenance,'{}'::jsonb),'synced',v_duplicate)
    on conflict(user_id,provider,provider_workout_id) do update set type=excluded.type,started_at=excluded.started_at,ended_at=excluded.ended_at,time_zone=excluded.time_zone,distance_m=excluded.distance_m,active_duration_s=excluded.active_duration_s,elapsed_duration_s=excluded.elapsed_duration_s,average_heart_rate=excluded.average_heart_rate,maximum_heart_rate=excluded.maximum_heart_rate,calories_kcal=excluded.calories_kcal,elevation_gain_m=excluded.elevation_gain_m,device_info=excluded.device_info,provenance=excluded.provenance,sync_status='synced',duplicate_of=excluded.duplicate_of,provider_seen_at=now(),updated_at=now()
    returning id into v_id;
  -- Owner visibility and club sharing are preserved when the source record changes.
  delete from public.activity_laps where activity_id=v_id;
  insert into public.activity_laps(activity_id,lap_index,distance_m,duration_s)
    select v_id,(value->>'lap_index')::int,(value->>'distance_m')::double precision,(value->>'active_duration_s')::double precision from jsonb_array_elements(p_laps);
  return v_id;
end $$;
revoke all on function public.claim_health_sync(uuid),public.upsert_health_activity(jsonb,jsonb) from public,anon,authenticated;
grant execute on function public.claim_health_sync(uuid),public.upsert_health_activity(jsonb,jsonb) to service_role;
