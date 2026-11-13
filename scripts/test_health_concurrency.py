#!/usr/bin/env python3
"""Exercise consent-withdrawal races only in the isolated local Supabase stack."""
import pathlib
import subprocess
import time

CONTAINER = 'supabase_db_runtrack-clean'
USER = '82828282-8282-4282-8282-828282828282'
CONNECTION = '83838383-8383-4383-8383-838383838383'
PSQL = ['docker', 'exec', '-i', CONTAINER, 'psql', '-X', '-qAt', '-U', 'postgres', '-d', 'postgres', '-v', 'ON_ERROR_STOP=1']


def sql(statement, check=True):
    result = subprocess.run(PSQL, input=statement, text=True, capture_output=True, timeout=15)
    if check and result.returncode:
        raise AssertionError(result.stderr)
    return result


def race(operation, application, expected_error='Health connection is not active'):
    # Withdrawal owns the athlete lock. A competing operation must wait for that
    # lock without first holding the connection row needed by withdrawal.
    holder = subprocess.Popen(PSQL, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                              stderr=subprocess.PIPE, text=True, bufsize=1)
    holder.stdin.write(f"""begin;
select pg_advisory_xact_lock(hashtextextended('{USER}',1));
\\echo LOCKED
select pg_sleep(3);
select public.withdraw_health_consent('{USER}','disconnect');
commit;
""")
    holder.stdin.close()
    waiter = None
    try:
        while holder.stdout.readline().strip() != 'LOCKED':
            if holder.poll() is not None:
                raise AssertionError('Withdrawal lock holder exited early')
        waiter = subprocess.Popen(PSQL, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                                  stderr=subprocess.PIPE, text=True)
        waiter.stdin.write(f"set application_name='{application}'; set statement_timeout='8s'; {operation};")
        waiter.stdin.close()
        deadline = time.monotonic() + 2
        while time.monotonic() < deadline:
            if sql(f"select exists(select 1 from pg_stat_activity where application_name='{application}' and wait_event='advisory');").stdout.strip() == 't':
                break
            time.sleep(0.02)
        else:
            raise AssertionError('Competing operation did not wait for athlete lock')
        # This succeeds only if the competing operation has not taken the row
        # lock first, which previously deadlocked against disconnect.
        sql(f"set lock_timeout='500ms'; update public.health_connections set last_error='local lock probe' where id='{CONNECTION}';")
        if holder.wait(timeout=10) != 0:
            raise AssertionError(holder.stderr.read())
        if waiter.wait(timeout=10) == 0:
            raise AssertionError('Operation unexpectedly succeeded after consent withdrawal')
        error = waiter.stderr.read()
        if expected_error not in error:
            raise AssertionError(error)
        assert sql(f"select status='disconnected' from public.health_connections where id='{CONNECTION}';").stdout.strip() == 't'
        assert sql(f"select public.health_credentials_get('{CONNECTION}') is null;").stdout.strip() == 't'
        print('PASS withdrawal serializes with ' + application, flush=True)
    finally:
        for process in (waiter, holder):
            if process is not None and process.poll() is None:
                process.kill()
                process.wait(timeout=5)


if __name__ == '__main__':
    config = pathlib.Path('supabase/config.toml').read_text()
    if 'project_id = "runtrack-clean"' not in config or 'port = 56321' not in config:
        raise SystemExit('Refusing: expected isolated runtrack-clean local configuration.')
    if sql(f"select exists(select 1 from auth.users where id='{USER}');").stdout.strip() != 'f':
        raise SystemExit('Refusing: concurrency fixture identity already exists.')
    try:
        sql(f"""insert into auth.users(id,email,email_confirmed_at) values('{USER}','consent-race@example.test',now());
insert into public.profiles(id,display_name) values('{USER}','Local consent race');
select public.record_health_consent('{USER}','2026-11-12-v1');
insert into public.health_connections(id,user_id,provider,status) values('{CONNECTION}','{USER}','google_health','connected');
select public.health_credentials_store('{CONNECTION}','local-access','local-refresh',now()+interval '1 hour',array['readonly']);
select public.upsert_health_activity('{{"user_id":"{USER}","provider":"google_health","provider_workout_id":"retained-run","type":"running","started_at":"2026-11-01T10:00:00Z","ended_at":"2026-11-01T10:30:00Z"}}');
""")
        race(f"select public.reconcile_health_deletions('{CONNECTION}',now())", 'runtrack_reconcile_race')
        assert sql(f"select count(*) from public.activities where user_id='{USER}';").stdout.strip() == '1'
        sql(f"select public.record_health_consent('{USER}','2026-11-12-v1'); update public.health_connections set status='connected' where id='{CONNECTION}';")
        race(f"select public.health_credentials_store('{CONNECTION}','late-access','late-refresh',now()+interval '1 hour',array['readonly'])", 'runtrack_refresh_race')
        grant = sql(f"select public.record_health_consent('{USER}','2026-11-12-v1');").stdout.strip()
        sql(f"""update public.health_connections set status='connected' where id='{CONNECTION}';
insert into public.oauth_states(state_hash,user_id,expires_at,redirect_uri,code_verifier_ciphertext,health_consent_id,consumed_at)
values('concurrent-oauth-state','{USER}',now()+interval '10 minutes','https://example.test/callback','encrypted',{grant},now());""")
        race(f"select public.complete_health_oauth_connection('{CONNECTION}',{grant},'concurrent-oauth-state','old-provider-id','late-access','late-refresh',now()+interval '1 hour',array['readonly'])",
             'runtrack_callback_race', 'Current explicit health consent required')
        print('All local consent concurrency assertions passed.', flush=True)
    finally:
        sql(f"delete from auth.users where id='{USER}' and email='consent-race@example.test';")
