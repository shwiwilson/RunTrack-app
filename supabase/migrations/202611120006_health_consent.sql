-- Explicit health-data consent is separate from native-app setup and Google OAuth.
-- Existing accounts receive no inferred or backfilled consent.
create table public.health_data_consents (
 id bigint generated always as identity primary key,
 user_id uuid not null references public.profiles(id) on delete cascade,
 provider text not null check(provider='google_health'),
 consent_version text not null,
 action text not null check(action in ('granted','withdrawn')),
 reason text not null check(reason in ('connect','disconnect','provider_revoked')),
 recorded_at timestamptz not null default clock_timestamp()
);
create index health_data_consent_latest on public.health_data_consents(user_id,provider,id desc);
alter table public.health_data_consents enable row level security;
create policy health_consent_self_read on public.health_data_consents for select to authenticated using(user_id=(select auth.uid()));
revoke all on public.health_data_consents from public,anon,authenticated,service_role;
grant select on public.health_data_consents to authenticated,service_role;
revoke all on sequence public.health_data_consents_id_seq from public,anon,authenticated,service_role;

create function public.health_consent_active(p_user_id uuid,p_consent_id bigint default null)
returns boolean language sql stable security definer set search_path='' as $$
 select coalesce((select c.action='granted' and c.consent_version='2026-11-12-v1'
   and (p_consent_id is null or c.id=p_consent_id)
  from public.health_data_consents c where c.user_id=p_user_id and c.provider='google_health' order by c.id desc limit 1),false);
$$;
create function public.record_health_consent(p_user_id uuid,p_consent_version text)
returns bigint language plpgsql security definer set search_path='' as $$
declare v_id bigint;
begin
 if p_consent_version is distinct from '2026-11-12-v1' then raise exception 'Current explicit health consent required' using errcode='22023'; end if;
 if not exists(select 1 from auth.users u join public.profiles p on p.id=u.id where u.id=p_user_id and u.email_confirmed_at is not null) then
  raise exception 'Verified account required' using errcode='42501';
 end if;
 perform pg_advisory_xact_lock(hashtextextended(p_user_id::text,1));
 insert into public.health_data_consents(user_id,provider,consent_version,action,reason)
 values(p_user_id,'google_health',p_consent_version,'granted','connect') returning id into v_id;
 return v_id;
end $$;
create function public.withdraw_health_consent(p_user_id uuid,p_reason text)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_credentials jsonb;
begin
 if p_reason not in ('disconnect','provider_revoked') or p_reason is null then raise exception 'Invalid withdrawal reason' using errcode='22023'; end if;
 perform pg_advisory_xact_lock(hashtextextended(p_user_id::text,1));
 select to_jsonb(t) into v_credentials from runtrack_private.health_credentials t
 join public.health_connections c on c.id=t.connection_id where c.user_id=p_user_id and c.provider='google_health';
 if not coalesce((select action='withdrawn' and reason=p_reason from public.health_data_consents
  where user_id=p_user_id and provider='google_health' order by id desc limit 1),false) then
  insert into public.health_data_consents(user_id,provider,consent_version,action,reason)
  values(p_user_id,'google_health','2026-11-12-v1','withdrawn',p_reason);
 end if;
 delete from runtrack_private.health_credentials where connection_id in
  (select id from public.health_connections where user_id=p_user_id and provider='google_health');
 delete from public.oauth_states where user_id=p_user_id;
 update public.health_connections set status=case when p_reason='disconnect' then 'disconnected' else 'revoked' end,
  provider_user_id=case when p_reason='disconnect' then null else provider_user_id end,
  sync_cursor='{}'::jsonb,
  last_error=case when p_reason='disconnect' then null else 'Google Health access was revoked. Reconnect to sync again.' end
 where user_id=p_user_id and provider='google_health';
 return v_credentials;
end $$;

alter table public.oauth_states add column health_consent_id bigint references public.health_data_consents(id) on delete cascade;
-- Ingestion shares the withdrawal lock. A request already fetching from Google
-- cannot insert an exercise after its consent was withdrawn.
create function runtrack_private.require_health_import_consent() returns trigger language plpgsql security definer set search_path='' as $$
begin
 if new.provider='google_health' then
  perform pg_advisory_xact_lock(hashtextextended(new.user_id::text,1));
  if not public.health_consent_active(new.user_id) then raise exception 'Explicit health consent required' using errcode='42501'; end if;
 end if;
 return new;
end $$;
create trigger health_import_consent before insert on public.activities for each row execute function runtrack_private.require_health_import_consent();
-- Prevent a stale OAuth callback from restoring a withdrawn connection.
create function runtrack_private.require_health_connection_consent() returns trigger language plpgsql security definer set search_path='' as $$
begin
 if new.provider='google_health' and new.status in ('connected','error') and not public.health_consent_active(new.user_id) then
  raise exception 'Explicit health consent required' using errcode='42501';
 end if;
 return new;
end $$;
create trigger health_connection_consent before insert or update of status on public.health_connections for each row execute function runtrack_private.require_health_connection_consent();
revoke all on function public.health_consent_active(uuid,bigint),public.record_health_consent(uuid,text),public.withdraw_health_consent(uuid,text),runtrack_private.require_health_import_consent(),runtrack_private.require_health_connection_consent() from public,anon,authenticated;
grant execute on function public.health_consent_active(uuid,bigint),public.record_health_consent(uuid,text),public.withdraw_health_consent(uuid,text) to service_role;
