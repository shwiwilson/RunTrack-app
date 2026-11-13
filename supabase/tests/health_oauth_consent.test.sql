-- Rollback-only fixtures: exact grant and OAuth-state binding must survive races.
begin;
create extension if not exists pgtap with schema extensions;
set search_path=public,extensions;
select no_plan();
insert into auth.users(id,email,email_confirmed_at) values('80808080-8080-4080-8080-808080808080','oauth-consent@example.test',now());
insert into public.profiles(id,display_name) values('80808080-8080-4080-8080-808080808080','OAuth consent fixture');
create temporary table grants(old_id bigint,new_id bigint);
insert into grants(old_id) values(public.record_health_consent('80808080-8080-4080-8080-808080808080','2026-11-12-v1'));
insert into public.oauth_states(state_hash,user_id,expires_at,redirect_uri,code_verifier_ciphertext,health_consent_id)
 select 'oauth-old-state','80808080-8080-4080-8080-808080808080',now()+interval '10 minutes','https://example.test/callback','encrypted',old_id from grants;
select throws_ok($$select public.prepare_health_oauth_connection('80808080-8080-4080-8080-808080808080',(select old_id from grants),'oauth-old-state')$$,'42501','Health connection request is no longer active','unconsumed OAuth state cannot prepare a connection');
select public.consume_health_oauth_state('oauth-old-state');
select is(public.prepare_health_oauth_connection('80808080-8080-4080-8080-808080808080',(select old_id from grants),'oauth-old-state')->>'status','error','consumed state with exact current consent can prepare connection');
select is(public.complete_health_oauth_connection((select id from public.health_connections where user_id='80808080-8080-4080-8080-808080808080'),(select old_id from grants),'oauth-old-state','google-old-id','access-old','refresh-old',now()+interval '1 hour',array['readonly'])->>'status','connected','OAuth credentials and provider identity activate atomically');
select is(public.health_credentials_get((select id from public.health_connections where user_id='80808080-8080-4080-8080-808080808080'))->>'refresh_token_ciphertext','refresh-old','complete callback stores encrypted credentials');
select public.upsert_health_activity('{"user_id":"80808080-8080-4080-8080-808080808080","provider":"google_health","provider_workout_id":"existing-run","type":"running","started_at":"2026-11-01T10:00:00Z","ended_at":"2026-11-01T10:30:00Z"}');
select public.withdraw_health_consent('80808080-8080-4080-8080-808080808080','disconnect');
select throws_ok($$select public.reconcile_health_deletions((select id from public.health_connections where user_id='80808080-8080-4080-8080-808080808080'),now())$$,'42501','Health connection is not active','in-flight reconciliation cannot remove history after disconnect');
select is((select count(*) from public.activities where user_id='80808080-8080-4080-8080-808080808080'),1::bigint,'disconnect retains previously imported history');
select throws_ok($$select public.health_credentials_store((select id from public.health_connections where user_id='80808080-8080-4080-8080-808080808080'),'late-access','late-refresh',now()+interval '1 hour',array['readonly'])$$,'42501','Health connection is not active','late refresh cannot restore credentials after disconnect');
update grants set new_id=public.record_health_consent('80808080-8080-4080-8080-808080808080','2026-11-12-v1');
select throws_ok($$select public.prepare_health_oauth_connection('80808080-8080-4080-8080-808080808080',(select old_id from grants),'oauth-old-state')$$,'42501','Current explicit health consent required','new consent cannot revive an older callback');
select throws_ok($$select public.complete_health_oauth_connection((select id from public.health_connections where user_id='80808080-8080-4080-8080-808080808080'),(select old_id from grants),'oauth-old-state','google-old-id','late-access','late-refresh',now()+interval '1 hour',array['readonly'])$$,'42501','Current explicit health consent required','old callback cannot overwrite credentials after reconsent');
select is(public.health_credentials_get((select id from public.health_connections where user_id='80808080-8080-4080-8080-808080808080')),null::jsonb,'rejected callback leaves credentials erased');
insert into public.oauth_states(state_hash,user_id,expires_at,redirect_uri,code_verifier_ciphertext,health_consent_id,consumed_at)
 select 'oauth-new-state','80808080-8080-4080-8080-808080808080',now()+interval '10 minutes','https://example.test/callback','encrypted',new_id,now() from grants;
select is(public.prepare_health_oauth_connection('80808080-8080-4080-8080-808080808080',(select new_id from grants),'oauth-new-state')->>'status','error','a new consumed state permits reconnect after explicit reconsent');
select is(public.complete_health_oauth_connection((select id from public.health_connections where user_id='80808080-8080-4080-8080-808080808080'),(select new_id from grants),'oauth-new-state','google-new-id','access-new','refresh-new',now()+interval '1 hour',array['readonly'])->>'provider_user_id','google-new-id','new callback atomically installs the new provider identity');
select throws_ok($$select public.complete_health_oauth_connection((select id from public.health_connections where user_id='80808080-8080-4080-8080-808080808080'),(select new_id from grants),'oauth-old-state','google-old-id','late-access','late-refresh',now()+interval '1 hour',array['readonly'])$$,'42501','Health connection request is no longer active','current grant cannot be substituted into a cancelled state');
set local role authenticated;
select throws_ok($$select public.prepare_health_oauth_connection('80808080-8080-4080-8080-808080808080',1,'spoofed')$$,'42501','permission denied for function prepare_health_oauth_connection','browser cannot invoke callback preparation');
select throws_ok($$select public.complete_health_oauth_connection('81818181-8181-4181-8181-818181818181',1,'spoofed','spoofed','a','r',now(),array['readonly'])$$,'42501','permission denied for function complete_health_oauth_connection','browser cannot write OAuth credentials or identities');
reset role;
select * from finish();
rollback;
