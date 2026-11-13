begin;
create extension if not exists pgtap with schema extensions;
set search_path=public,extensions;
select plan(17);
-- Local test database only. Never replace an existing schedule/Vault entry.
do $$ begin
 if exists(select 1 from vault.secrets where name='runtrack_health_reconcile')
    or exists(select 1 from cron.job where jobname='runtrack-health-reconcile') then
  raise exception 'Scheduler tests require an unprovisioned local test database';
 end if;
end $$;
select ok(not has_function_privilege('anon','public.install_runtrack_health_schedule(text)','EXECUTE'),'anon cannot provision scheduler');
select ok(not has_function_privilege('authenticated','public.install_runtrack_health_schedule(text)','EXECUTE'),'athletes and browser admins cannot provision scheduler');
select ok(has_function_privilege('service_role','public.install_runtrack_health_schedule(text)','EXECUTE'),'server role can provision scheduler');
select throws_ok($$select public.install_runtrack_health_schedule('short')$$,'22023','Invalid reconciliation credential','weak credential rejected');
select is((public.install_runtrack_health_schedule('fixture-reconciliation-secret-long-enough')->>'scheduler_enabled')::boolean,true,'scheduler activated');
select is((select count(*)::integer from cron.job where jobname='runtrack-health-reconcile' and active and schedule='* * * * *'),1,'one active one-minute schedule');
select is((select count(*)::integer from vault.secrets where name='runtrack_health_reconcile'),1,'one encrypted vault entry');
select ok((select decrypted_secret='fixture-reconciliation-secret-long-enough' from vault.decrypted_secrets where name='runtrack_health_reconcile'),'existing runtime credential copied exactly');
select ok((select command not like '%fixture-reconciliation-secret-long-enough%' from cron.job where jobname='runtrack-health-reconcile'),'cron command contains no plaintext credential');
select is((public.install_runtrack_health_schedule('fixture-reconciliation-secret-long-enough')->>'vault_secret_present')::boolean,true,'repeat provisioning is idempotent');
select throws_ok($$select public.install_runtrack_health_schedule('fixture-different-secret-long-enough')$$,'P0001','Existing reconciliation vault entry differs; no credential was replaced','different credential cannot rotate existing entry');
select is((select count(*)::integer from cron.job where jobname='runtrack-health-reconcile'),1,'retry never duplicates schedule');
select ok(not has_function_privilege('authenticated','public.record_runtrack_health_subscriber(text)','EXECUTE'),'browser cannot record subscriber readiness');
select ok(not has_function_privilege('anon','public.runtrack_health_delivery_status(text)','EXECUTE'),'anonymous role cannot inspect operator readiness');
select is((public.record_runtrack_health_subscriber(repeat('a',64))->>'subscriber_active')::boolean,true,'server records nonsecret setup outcome');
select is((public.runtrack_health_delivery_status(repeat('a',64))->>'subscriber_active')::boolean,true,'matching setup session can observe success');
select is((public.runtrack_health_delivery_status(repeat('b',64))->>'subscriber_active')::boolean,false,'different setup session cannot reuse stale success');
select * from finish();
rollback;
