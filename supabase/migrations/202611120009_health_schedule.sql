-- Provisioning is deliberately separate from activation: applying this migration
-- creates no schedule and contains no credential. Only the temporary server-side
-- bootstrap bridge may supply the existing Edge reconciliation secret.
create extension if not exists pg_cron with schema pg_catalog;
create extension if not exists pg_net with schema extensions;
create extension if not exists supabase_vault with schema vault;

-- This stores setup outcomes only, never a credential or an IAM access token.
create table runtrack_private.health_delivery_setup (
 singleton boolean primary key default true check(singleton),
 subscriber_nonce_sha256 text not null check(subscriber_nonce_sha256 ~ '^[a-f0-9]{64}$'),
 subscriber_verified_at timestamptz not null default clock_timestamp()
);
alter table runtrack_private.health_delivery_setup enable row level security;
revoke all on runtrack_private.health_delivery_setup from public,anon,authenticated,service_role;

create function public.install_runtrack_health_schedule(p_reconcile_secret text)
returns jsonb language plpgsql security definer set search_path='' as $$
declare
 v_existing text;
 v_count integer;
 v_job_id bigint;
 v_command constant text := $command$select net.http_post(
 url := 'https://cwdhymutbulafmtkfhqf.supabase.co/functions/v1/health-sync',
 headers := jsonb_build_object('Content-Type','application/json','Authorization','Bearer ' ||
   (select decrypted_secret from vault.decrypted_secrets where name='runtrack_health_reconcile')),
 body := '{}'::jsonb,
 timeout_milliseconds := 95000
);$command$;
begin
 if p_reconcile_secret is null or length(p_reconcile_secret)<24 or length(p_reconcile_secret)>512
    or p_reconcile_secret ~ '[[:space:]]' then
  raise exception 'Invalid reconciliation credential' using errcode='22023';
 end if;
 -- The advisory lock makes retries idempotent without replacing a different key.
 perform pg_advisory_xact_lock(hashtextextended('runtrack_health_schedule',0));
 select count(*) into v_count from vault.secrets where name='runtrack_health_reconcile';
 if v_count>1 then raise exception 'Ambiguous reconciliation vault entry'; end if;
 if v_count=1 then
  select decrypted_secret into v_existing from vault.decrypted_secrets where name='runtrack_health_reconcile';
  if v_existing is distinct from p_reconcile_secret then
   raise exception 'Existing reconciliation vault entry differs; no credential was replaced';
  end if;
 else
  perform vault.create_secret(p_reconcile_secret,'runtrack_health_reconcile','Existing RunTrack Edge reconciliation credential');
 end if;
 select jobid into v_job_id from cron.job where jobname='runtrack-health-reconcile';
 if v_job_id is not null then
  if exists(select 1 from cron.job where jobid=v_job_id and
    (command<>v_command or schedule<>'* * * * *')) then
   raise exception 'Existing RunTrack schedule differs; no job was replaced';
  end if;
  perform cron.alter_job(v_job_id,active:=true);
 else
  v_job_id := cron.schedule('runtrack-health-reconcile','* * * * *',v_command);
 end if;
 return jsonb_build_object('scheduler_enabled',true,'vault_secret_present',true,'schedule','* * * * *');
end;
$$;
revoke all on function public.install_runtrack_health_schedule(text) from public,anon,authenticated;
grant execute on function public.install_runtrack_health_schedule(text) to service_role;

comment on function public.install_runtrack_health_schedule(text) is
'Operator provisioning only. Existing Edge secret is copied directly into Vault without returning it. Does not rotate secrets.';

create function public.record_runtrack_health_subscriber(p_nonce_sha256 text)
returns jsonb language plpgsql security definer set search_path='' as $$
begin
 if p_nonce_sha256 is null or p_nonce_sha256 !~ '^[a-f0-9]{64}$' then
  raise exception 'Invalid setup fingerprint' using errcode='22023';
 end if;
 insert into runtrack_private.health_delivery_setup(singleton,subscriber_nonce_sha256,subscriber_verified_at)
 values(true,p_nonce_sha256,clock_timestamp())
 on conflict(singleton) do update set subscriber_nonce_sha256=excluded.subscriber_nonce_sha256,
  subscriber_verified_at=excluded.subscriber_verified_at;
 return jsonb_build_object('subscriber_active',true);
end;
$$;
revoke all on function public.record_runtrack_health_subscriber(text) from public,anon,authenticated;
grant execute on function public.record_runtrack_health_subscriber(text) to service_role;

create function public.runtrack_health_delivery_status(p_nonce_sha256 text)
returns jsonb language sql stable security definer set search_path='' as $$
 select jsonb_build_object(
  'subscriber_active',exists(select 1 from runtrack_private.health_delivery_setup
    where singleton and subscriber_nonce_sha256=p_nonce_sha256 and subscriber_verified_at>now()-interval '15 minutes'),
  'scheduler_enabled',exists(select 1 from cron.job
    where jobname='runtrack-health-reconcile' and active and schedule='* * * * *'),
  'vault_secret_present',exists(select 1 from vault.secrets where name='runtrack_health_reconcile')
 );
$$;
revoke all on function public.runtrack_health_delivery_status(text) from public,anon,authenticated;
grant execute on function public.runtrack_health_delivery_status(text) to service_role;
