-- Rollback-only, never execute against an occupied hosted project.
begin;
create extension if not exists pgtap with schema extensions;
set search_path=public,extensions;
select no_plan();
insert into auth.users(id,email,email_confirmed_at) values
 ('70707070-7070-4070-8070-707070707070','webhook-one@example.test',now()),
 ('71717171-7171-4171-8171-717171717171','webhook-two@example.test',now());
insert into public.profiles(id,display_name) values
 ('70707070-7070-4070-8070-707070707070','Webhook one'),
 ('71717171-7171-4171-8171-717171717171','Webhook two');
select public.record_health_consent('70707070-7070-4070-8070-707070707070','2026-11-12-v1');
select public.record_health_consent('71717171-7171-4171-8171-717171717171','2026-11-12-v1');
insert into public.health_connections(id,user_id,provider,status,provider_user_id) values
 ('72727272-7272-4272-8272-727272727272','70707070-7070-4070-8070-707070707070','google_health','connected','batch-health-one'),
 ('73737373-7373-4373-8373-737373737373','71717171-7171-4171-8171-717171717171','google_health','connected','batch-health-two'),
 ('74747474-7474-4474-8474-747474747474','70707070-7070-4070-8070-707070707070','other-provider','connected','other-health-id');
set local role authenticated;
select set_config('request.jwt.claim.sub','70707070-7070-4070-8070-707070707070',true);
select throws_ok($$select public.enqueue_health_notifications('[]')$$,'42501','permission denied for function enqueue_health_notifications','browser cannot enqueue or resolve provider identities');
reset role;
set local role anon;
select throws_ok($$select public.enqueue_health_notifications('[]')$$,'42501','permission denied for function enqueue_health_notifications','anonymous client cannot enqueue notifications');
reset role;
set local role service_role;
select public.health_credentials_store('72727272-7272-4272-8272-727272727272','access-one','refresh-one',now()+interval '1 hour',array['readonly']);
select public.health_credentials_store('73737373-7373-4373-8373-737373737373','access-two','refresh-two',now()+interval '1 hour',array['readonly']);
select is(public.enqueue_health_notifications('[]'),0,'empty signed batch has no effect');
select throws_ok($$select public.enqueue_health_notifications('{}')$$,'22023','Notification array required','RPC requires normalized array');
select throws_ok($$select public.enqueue_health_notifications((select jsonb_agg('{}'::jsonb) from generate_series(1,100)))$$,'22023','Notification batch too large','100 notifications rejected before any write');
select throws_ok($$select public.enqueue_health_notifications(jsonb_build_array(jsonb_build_object('payload',repeat('x',1048577))))$$,'22023','Notification batch too large','oversized normalized body rejected');
select is(public.enqueue_health_notifications(jsonb_build_array(
 jsonb_build_object('provider_event_id',repeat('a',43),'health_user_id','batch-health-one','event_type','exercise','payload','{"operation":"UPDATED"}'::jsonb),
 jsonb_build_object('provider_event_id',repeat('b',43),'health_user_id','batch-health-two','event_type','exercise','payload','{}'::jsonb))),2,'one batch queues both matched identities');
select is((select connection_id from public.sync_events where provider_event_id=repeat('a',43)),'72727272-7272-4272-8272-727272727272'::uuid,'event resolves first provider identity on server');
select is((select connection_id from public.sync_events where provider_event_id=repeat('b',43)),'73737373-7373-4373-8373-737373737373'::uuid,'event resolves second provider identity on server');
select is(public.enqueue_health_notifications(jsonb_build_array(
 jsonb_build_object('provider_event_id',repeat('a',43),'health_user_id','batch-health-one','event_type','exercise','payload','{}'::jsonb))),0,'duplicate delivery is idempotent');
select is(public.enqueue_health_notifications(jsonb_build_array(
 jsonb_build_object('provider_event_id',repeat('c',43),'health_user_id','unknown-health-id','event_type','exercise','payload','{}'::jsonb),
 jsonb_build_object('provider_event_id',repeat('d',43),'health_user_id','other-health-id','event_type','exercise','payload','{}'::jsonb))),0,'unknown and different-provider identities are ignored');
select throws_ok($$select public.enqueue_health_notifications(jsonb_build_array(
 jsonb_build_object('provider_event_id',repeat('e',43),'health_user_id','batch-health-one','event_type','exercise','payload','{}'::jsonb),
 jsonb_build_object('provider_event_id','bad','health_user_id','batch-health-two','event_type','exercise','payload','{}'::jsonb)))$$,'22023','Malformed notification','one malformed item rejects entire batch');
select is((select count(*) from public.sync_events),2::bigint,'malformed batch leaves no partial enqueue');
select throws_ok($$select public.enqueue_health_notifications(jsonb_build_array(jsonb_build_object('provider_event_id',repeat('e',43),'health_user_id','batch-health-one','event_type','exercise','payload','{}'::jsonb,'connection_id','73737373-7373-4373-8373-737373737373')))$$,'22023','Malformed notification','caller cannot substitute another connection ID');
select throws_ok($$select public.enqueue_health_notifications(jsonb_build_array(jsonb_build_object('provider_event_id',repeat('e',43),'health_user_id','batch-health-one','event_type','exercise','payload','{}'::jsonb,'user_id','71717171-7171-4171-8171-717171717171')))$$,'22023','Malformed notification','caller cannot substitute another athlete');
select throws_ok($$select public.enqueue_health_notifications('[null]')$$,'22023','Malformed notification','null item rejected');
select throws_ok($$select public.enqueue_health_notifications(jsonb_build_array(jsonb_build_object('provider_event_id',repeat('e',43),'health_user_id','','event_type','exercise','payload','{}'::jsonb)))$$,'22023','Malformed notification','empty identity rejected');
select throws_ok($$select public.enqueue_health_notifications(jsonb_build_array(jsonb_build_object('provider_event_id',repeat('e',43),'health_user_id','batch-health-one','event_type','unrequested','payload','{}'::jsonb)))$$,'22023','Malformed notification','unrequested event cannot bypass normalization');
select is(public.enqueue_health_notifications(jsonb_build_array(
 jsonb_build_object('provider_event_id',repeat('r',43),'health_user_id','batch-health-one','event_type','user-revoked-access','payload','{}'::jsonb),
 jsonb_build_object('provider_event_id',repeat('s',43),'health_user_id','batch-health-one','event_type','exercise','payload','{}'::jsonb),
 jsonb_build_object('provider_event_id',repeat('t',43),'health_user_id','batch-health-two','event_type','exercise','payload','{}'::jsonb))),2,'revocation and unaffected athlete event commit in same batch; withdrawn exercise ignored');
select ok(not public.health_consent_active('70707070-7070-4070-8070-707070707070'),'queued provider revocation atomically withdraws consent');
select is(public.health_credentials_get('72727272-7272-4272-8272-727272727272'),null::jsonb,'queued revocation erases correct credentials');
select is(public.health_credentials_get('73737373-7373-4373-8373-737373737373')->>'refresh_token_ciphertext','refresh-two','revocation does not touch another athlete credentials');
select is((select status from public.health_connections where id='72727272-7272-4272-8272-727272727272'),'revoked','revocation stops matched connection');
select is((select status from public.health_connections where id='73737373-7373-4373-8373-737373737373'),'connected','unaffected connection stays active');
select public.record_health_consent('70707070-7070-4070-8070-707070707070','2026-11-12-v1');
update public.health_connections set status='connected' where id='72727272-7272-4272-8272-727272727272';
select is(public.enqueue_health_notifications(jsonb_build_array(jsonb_build_object('provider_event_id',repeat('r',43),'health_user_id','batch-health-one','event_type','user-revoked-access','payload','{}'::jsonb))),0,'replayed revocation is already durably processed');
select ok(public.health_consent_active('70707070-7070-4070-8070-707070707070'),'old revocation replay cannot withdraw later explicit grant');
select is(public.enqueue_health_notifications(jsonb_build_array(jsonb_build_object('provider_event_id',repeat('u',43),'health_user_id','batch-health-one','event_type','user-deleted','payload','{}'::jsonb))),1,'provider deletion uses same atomic withdrawal');
select ok(not public.health_consent_active('70707070-7070-4070-8070-707070707070'),'provider deletion stops future processing');
select is(public.enqueue_health_notifications((select jsonb_agg(jsonb_build_object('provider_event_id',lpad(i::text,43,'x'),'health_user_id','batch-health-two','event_type','exercise','payload','{}'::jsonb)) from generate_series(1,99) i)),99,'maximum 99-event batch persists in one RPC');
select is((select count(*) from public.sync_events),104::bigint,'only valid resolved consented notifications persisted');
reset role;
select * from finish();
rollback;
