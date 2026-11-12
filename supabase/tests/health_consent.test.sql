-- Rollback-only fixtures for the disposable local project.
begin;
create extension if not exists pgtap with schema extensions;
set search_path=public,extensions;
select no_plan();
insert into auth.users(id,email,email_confirmed_at) values
 ('60606060-6060-4060-8060-606060606060','consent-one@example.test',now()),
 ('61616161-6161-4161-8161-616161616161','consent-two@example.test',now()),
 ('62626262-6262-4262-8262-626262626262','consent-unverified@example.test',null);
insert into public.profiles(id,display_name) values
 ('60606060-6060-4060-8060-606060606060','Consent one'),
 ('61616161-6161-4161-8161-616161616161','Consent two'),
 ('62626262-6262-4262-8262-626262626262','Unverified consent fixture');
select ok(not public.health_consent_active('60606060-6060-4060-8060-606060606060'),'new accounts have no inferred consent');
select throws_ok($$insert into public.health_connections(user_id,provider,status) values('60606060-6060-4060-8060-606060606060','google_health','connected')$$,'42501','Explicit health consent required','connection cannot be activated without explicit consent');
set local role authenticated;
select set_config('request.jwt.claim.sub','60606060-6060-4060-8060-606060606060',true);
select throws_ok($$select public.record_health_consent('61616161-6161-4161-8161-616161616161','2026-11-12-v1')$$,'42501','permission denied for function record_health_consent','browser cannot forge consent for another account');
select throws_ok($$select public.withdraw_health_consent('61616161-6161-4161-8161-616161616161','disconnect')$$,'42501','permission denied for function withdraw_health_consent','browser cannot withdraw another account consent');
select throws_ok($$insert into public.health_data_consents(user_id,provider,consent_version,action,reason,recorded_at) values(auth.uid(),'google_health','2026-11-12-v1','granted','connect','2000-01-01')$$,'42501','permission denied for table health_data_consents','browser cannot forge a consent timestamp');
reset role;
set local role service_role;
select throws_ok($$select public.record_health_consent('60606060-6060-4060-8060-606060606060','obsolete')$$,'22023','Current explicit health consent required','stale consent text is rejected');
select throws_ok($$select public.record_health_consent('62626262-6262-4262-8262-626262626262','2026-11-12-v1')$$,'42501','Verified account required','unverified account cannot grant health consent');
select ok(public.record_health_consent('60606060-6060-4060-8060-606060606060','2026-11-12-v1')>0,'verified service action appends consent');
select ok(public.health_consent_active('60606060-6060-4060-8060-606060606060'),'latest explicit grant permits processing');
select ok((select recorded_at between now() and clock_timestamp() from public.health_data_consents where user_id='60606060-6060-4060-8060-606060606060'),'consent time comes from database clock');
select throws_ok($$update public.health_data_consents set recorded_at='2000-01-01'$$,'42501','permission denied for table health_data_consents','service role cannot rewrite append-only evidence');
select throws_ok($$delete from public.health_data_consents$$,'42501','permission denied for table health_data_consents','service role cannot erase consent evidence directly');
insert into public.health_connections(id,user_id,provider,status,provider_user_id) values('63636363-6363-4363-8363-636363636363','60606060-6060-4060-8060-606060606060','google_health','connected','consent-health-id');
select public.health_credentials_store('63636363-6363-4363-8363-636363636363','encrypted-access','encrypted-refresh',now()+interval '1 hour',array['readonly']);
insert into public.oauth_states(state_hash,user_id,expires_at,redirect_uri,code_verifier_ciphertext,health_consent_id)
 select 'consent-state','60606060-6060-4060-8060-606060606060',now()+interval '10 minutes','https://example.test/callback','encrypted-fixture',id from public.health_data_consents where user_id='60606060-6060-4060-8060-606060606060';
select public.upsert_health_activity('{"user_id":"60606060-6060-4060-8060-606060606060","provider":"google_health","provider_workout_id":"consented-run","started_at":"2026-11-01T10:00:00Z","ended_at":"2026-11-01T10:30:00Z","type":"running","distance_m":5000}');
reset role;
set local role authenticated;
select is((select count(*) from public.health_data_consents),1::bigint,'athlete can read their own consent history');
select set_config('request.jwt.claim.sub','61616161-6161-4161-8161-616161616161',true);
select is((select count(*) from public.health_data_consents),0::bigint,'another athlete cannot read consent history');
reset role;
set local role service_role;
select is(public.withdraw_health_consent('60606060-6060-4060-8060-606060606060','disconnect')->>'refresh_token_ciphertext','encrypted-refresh','withdrawal returns encrypted token only to trusted server for remote revocation');
select ok(not public.health_consent_active('60606060-6060-4060-8060-606060606060'),'withdrawal disables all health processing');
select is((select count(*) from public.health_data_consents where user_id='60606060-6060-4060-8060-606060606060'),2::bigint,'withdrawal appends evidence while retaining original grant');
select is(public.health_credentials_get('63636363-6363-4363-8363-636363636363'),null::jsonb,'withdrawal atomically erases local credentials');
select is((select count(*) from public.oauth_states where user_id='60606060-6060-4060-8060-606060606060'),0::bigint,'withdrawal cancels pending OAuth states');
select is((select status from public.health_connections where id='63636363-6363-4363-8363-636363636363'),'disconnected','withdrawal atomically stops the connection');
select is((select count(*) from public.activities where user_id='60606060-6060-4060-8060-606060606060'),1::bigint,'withdrawal retains already imported athlete history');
select throws_ok($$update public.health_connections set status='error' where id='63636363-6363-4363-8363-636363636363'$$,'42501','Explicit health consent required','stale OAuth callback cannot restore a withdrawn connection');
select throws_ok($$insert into public.activities(user_id,provider,provider_workout_id,started_at,ended_at) values('60606060-6060-4060-8060-606060606060','google_health','late-run',now(),now())$$,'42501','Explicit health consent required','in-flight sync cannot insert after withdrawal');
select public.record_health_consent('60606060-6060-4060-8060-606060606060','2026-11-12-v1');
select ok(not public.health_consent_active('60606060-6060-4060-8060-606060606060',(select min(id) from public.health_data_consents where user_id='60606060-6060-4060-8060-606060606060')),'a later grant does not revive an old OAuth state');
select ok(public.health_consent_active('60606060-6060-4060-8060-606060606060'),'a new explicit grant can enable a new connection');
select public.withdraw_health_consent('60606060-6060-4060-8060-606060606060','provider_revoked');
select public.withdraw_health_consent('60606060-6060-4060-8060-606060606060','provider_revoked');
select is((select count(*) from public.health_data_consents where user_id='60606060-6060-4060-8060-606060606060'),4::bigint,'repeated provider revocation is idempotent');
select is((select status from public.health_connections where id='63636363-6363-4363-8363-636363636363'),'revoked','provider revocation disables connection and records withdrawal');
reset role;
delete from auth.users where id='60606060-6060-4060-8060-606060606060';
select is((select count(*) from public.health_data_consents where user_id='60606060-6060-4060-8060-606060606060'),0::bigint,'account deletion cascades personal consent evidence');
select * from finish();
rollback;
