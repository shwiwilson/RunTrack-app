-- One durable transaction acknowledges an authenticated, signature-verified
-- notification batch. No browser role can resolve provider identities or enqueue.
create function public.enqueue_health_notifications(p_events jsonb)
returns integer language plpgsql security definer set search_path='' as $$
declare v_event jsonb; v_connection public.health_connections; v_id uuid; v_user uuid; v_count integer:=0;
begin
 if jsonb_typeof(p_events) is distinct from 'array' then raise exception 'Notification array required' using errcode='22023'; end if;
 if jsonb_array_length(p_events)>99 or pg_column_size(p_events)>1048576 then raise exception 'Notification batch too large' using errcode='22023'; end if;
 -- Validate the entire batch before taking locks or writing any event.
 for v_event in select value from jsonb_array_elements(p_events) loop
  if jsonb_typeof(v_event) is distinct from 'object'
   or jsonb_typeof(v_event->'provider_event_id') is distinct from 'string'
   or (v_event->>'provider_event_id') !~ '^[A-Za-z0-9_-]{43}$'
   or jsonb_typeof(v_event->'health_user_id') is distinct from 'string'
   or length(v_event->>'health_user_id') not between 1 and 1024
   or jsonb_typeof(v_event->'event_type') is distinct from 'string'
   or (v_event->>'event_type') not in ('exercise','user-deleted','user-revoked-access')
   or jsonb_typeof(v_event->'payload') is distinct from 'object'
   or v_event ? 'user_id' or v_event ? 'connection_id' then
   raise exception 'Malformed notification' using errcode='22023';
  end if;
 end loop;
 -- Deterministic lock order avoids deadlocks between overlapping batches and
 -- shares the same athlete lock as import and consent withdrawal.
 for v_user in select distinct c.user_id from public.health_connections c
  join jsonb_array_elements(p_events) e on c.provider_user_id=e->>'health_user_id'
  where c.provider='google_health' order by c.user_id loop
  perform pg_advisory_xact_lock(hashtextextended(v_user::text,1));
 end loop;
 for v_event in select value from jsonb_array_elements(p_events) loop
  select * into v_connection from public.health_connections
   where provider='google_health' and provider_user_id=v_event->>'health_user_id';
  if not found then continue; end if;
  if v_event->>'event_type'='exercise' and
   (v_connection.status not in ('connected','error') or not public.health_consent_active(v_connection.user_id)) then continue; end if;
  insert into public.sync_events(connection_id,provider,provider_event_id,event_type,payload)
   values(v_connection.id,'google_health',v_event->>'provider_event_id',v_event->>'event_type',v_event->'payload')
   on conflict(provider,provider_event_id) do nothing returning id into v_id;
  if not found then continue; end if;
  v_count:=v_count+1;
  if v_event->>'event_type' in ('user-deleted','user-revoked-access') then
   -- Queueing and withdrawal commit together; a retry after a committed batch
   -- cannot withdraw a later, newly granted connection a second time.
   perform public.withdraw_health_consent(v_connection.user_id,'provider_revoked');
  end if;
 end loop;
 return v_count;
end $$;
revoke all on function public.enqueue_health_notifications(jsonb) from public,anon,authenticated;
grant execute on function public.enqueue_health_notifications(jsonb) to service_role;
