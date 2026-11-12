-- Exact provider origin identity is durable evidence of duplication. Rebuild the
-- small affected groups after source edits/deletes so no phantom totals survive.
create index activity_origin_identity_idx on public.activities(user_id,(provenance->>'origin_provider'),(provenance->>'origin_workout_id'))
 where nullif(provenance->>'origin_provider','') is not null and nullif(provenance->>'origin_workout_id','') is not null;
create function runtrack_private.rebalance_activity_origin(p_user uuid,p_origin_provider text,p_origin_workout_id text)
returns void language sql security definer set search_path='' as $$
 with ranked as (
  select a.id,first_value(a.id) over(order by a.created_at,a.id) canonical
  from public.activities a where a.user_id=p_user and nullif(p_origin_provider,'') is not null
   and nullif(p_origin_workout_id,'') is not null and a.provenance->>'origin_provider'=p_origin_provider
   and a.provenance->>'origin_workout_id'=p_origin_workout_id
 )
 update public.activities a set duplicate_of=case when r.id=r.canonical then null else r.canonical end
 from ranked r where a.id=r.id and a.duplicate_of is distinct from case when r.id=r.canonical then null else r.canonical end;
$$;
create function runtrack_private.activity_origin_changed() returns trigger language plpgsql security definer set search_path='' as $$
begin
 -- A profile cascade removes all this person's records. Do not rebuild groups
 -- between individual rows of that cascade.
 if tg_op in ('DELETE','UPDATE') and exists(select 1 from public.profiles where id=old.user_id) then
  perform runtrack_private.rebalance_activity_origin(old.user_id,old.provenance->>'origin_provider',old.provenance->>'origin_workout_id');
 end if;
 if tg_op in ('INSERT','UPDATE') then
  if nullif(new.provenance->>'origin_provider','') is null or nullif(new.provenance->>'origin_workout_id','') is null then
   update public.activities set duplicate_of=null where id=new.id and duplicate_of is not null;
  else
   perform runtrack_private.rebalance_activity_origin(new.user_id,new.provenance->>'origin_provider',new.provenance->>'origin_workout_id');
  end if;
 end if;
 return null;
end $$;
create trigger activities_rebalance_origin after insert or update of provenance or delete on public.activities
 for each row execute function runtrack_private.activity_origin_changed();
revoke all on function runtrack_private.rebalance_activity_origin(uuid,text,text),runtrack_private.activity_origin_changed() from public,anon,authenticated;

-- Reconciliation and ingestion acquire the same user lock before mutations.
-- An incomplete/failed provider sync never calls this function.
create function public.reconcile_health_deletions(p_connection_id uuid,p_seen_before timestamptz)
returns integer language plpgsql security definer set search_path='' as $$
declare v_connection public.health_connections; v_deleted integer;
begin
 select * into v_connection from public.health_connections where id=p_connection_id and status in ('connected','error') for update;
 if not found then raise exception 'Health connection is not active' using errcode='42501'; end if;
 if p_seen_before is null or p_seen_before>now()+interval '1 minute' then raise exception 'Invalid provider reconciliation time'; end if;
 perform pg_advisory_xact_lock(hashtextextended(v_connection.user_id::text,1));
 delete from public.activities where user_id=v_connection.user_id and provider=v_connection.provider and provider_seen_at<p_seen_before;
 get diagnostics v_deleted=row_count;
 return v_deleted;
end $$;
revoke all on function public.reconcile_health_deletions(uuid,timestamptz) from public,anon,authenticated;
grant execute on function public.reconcile_health_deletions(uuid,timestamptz) to service_role;

-- Repair already-derived links on upgrades; no activity/source records are removed.
do $$ declare r record; begin
 for r in select distinct user_id,provenance->>'origin_provider' as origin_provider,provenance->>'origin_workout_id' as origin_workout_id from public.activities loop
  perform runtrack_private.rebalance_activity_origin(r.user_id,r.origin_provider,r.origin_workout_id);
 end loop;
 update public.activities set duplicate_of=null where duplicate_of is not null and
  (nullif(provenance->>'origin_provider','') is null or nullif(provenance->>'origin_workout_id','') is null);
end $$;
