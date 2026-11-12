#!/usr/bin/env python3
"""Exercise real local Supabase HTTP/Auth/database flows, then restore zero-user state.

Refuses every endpoint except the isolated runtrack-clean local stack. Test identities
and provider fixtures are only created here, never in migrations or production.
"""
import datetime
import html
import json
import re
import subprocess
import time
import urllib.error
import urllib.parse
import urllib.request

BASE = 'http://127.0.0.1:56321'
MAIL = 'http://127.0.0.1:56324'
CONTAINER = 'supabase_db_runtrack-clean'
CLI = ['npx', '--yes', 'supabase@3.1.0']
OWNER = 'owner@runtrack.test'
ATHLETE = 'athlete@runtrack.test'
PASSWORD = 'Local-test-only-Password-842!'
NEW_PASSWORD = 'Local-test-only-Recovered-Password-381!'
passed = []


def sql(statement):
    return subprocess.check_output(
        ['docker', 'exec', '-i', CONTAINER, 'psql', '-U', 'postgres', '-d', 'postgres', '-At', '-v', 'ON_ERROR_STOP=1'],
        input=statement.encode(), stderr=subprocess.PIPE).decode().strip()


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


def request(path, data=None, token=None, method=None, key=None, follow=True):
    headers = {'apikey': key or PUBLIC_KEY, 'Content-Type': 'application/json'}
    if token:
        headers['Authorization'] = 'Bearer ' + token
    if path.startswith('/rest/'):
        headers['Prefer'] = 'return=representation'
    req = urllib.request.Request(BASE + path, data=None if data is None else json.dumps(data).encode(),
                                 headers=headers, method=method or ('POST' if data is not None else 'GET'))
    opener = urllib.request.build_opener() if follow else urllib.request.build_opener(NoRedirect)
    try:
        response = opener.open(req, timeout=20)
    except urllib.error.HTTPError as exc:
        response = exc
    raw = response.read().decode()
    try:
        payload = json.loads(raw) if raw else None
    except json.JSONDecodeError:
        payload = raw
    return response.status, payload, response.headers


def check(condition, name):
    if not condition:
        raise AssertionError(name)
    passed.append(name)
    print('PASS ' + name, flush=True)


def rpc(name, data=None, token=None):
    status, payload, _ = request('/rest/v1/rpc/' + name, data or {}, token)
    if status >= 300:
        raise AssertionError('RPC ' + name + ' failed: ' + str(payload))
    return payload


def mail_link(email, kind):
    for _ in range(40):
        with urllib.request.urlopen(MAIL + '/api/v1/messages', timeout=10) as response:
            messages = json.load(response).get('messages', [])
        for message in messages:
            recipients = [item.get('Address') for item in message.get('To', [])]
            if email not in recipients:
                continue
            with urllib.request.urlopen(MAIL + '/api/v1/message/' + message['ID'], timeout=10) as response:
                detail = json.load(response)
            content = html.unescape(detail.get('HTML', '') + '\n' + detail.get('Text', ''))
            for url in re.findall(r'https?://[^\s<>"\']+', content):
                if '/auth/v1/verify?' in url and ('type=' + kind) in url:
                    check(url.startswith(BASE + '/auth/v1/verify?'), 'email verification URL uses local API')
                    return url
        time.sleep(0.25)
    raise AssertionError('No ' + kind + ' email found for ' + email)


def verify(email, kind='signup'):
    url = mail_link(email, kind)
    status, _, headers = request(url.removeprefix(BASE), follow=False)
    check(status in (302, 303), kind + ' email token verified by Supabase')
    location = headers.get('Location', '')
    check('error=' not in location, kind + ' verification has no auth error')
    return urllib.parse.parse_qs(urllib.parse.urlsplit(location).fragment)


def signup(email):
    status, payload, _ = request('/auth/v1/signup', {'email': email, 'password': PASSWORD,
          'data': {'display_name': 'Local HTTP test runner'}})
    check(status == 200 and payload.get('id'), email + ' registered through public Auth HTTP API')
    check(not payload.get('access_token'), 'signup requires email verification')
    return payload['id']


def login(email, password=PASSWORD):
    status, payload, _ = request('/auth/v1/token?grant_type=password', {'email': email, 'password': password})
    check(status == 200 and payload.get('access_token'), email + ' signs in')
    return payload


if __name__ == '__main__':
    config = open('supabase/config.toml', encoding='utf8').read()
    if 'project_id = "runtrack-clean"' not in config or 'port = 56321' not in config:
        raise SystemExit('Refusing: expected isolated runtrack-clean local configuration.')
    status_data = json.loads(subprocess.check_output(CLI + ['status', '-o', 'json'], stderr=subprocess.PIPE))
    if status_data.get('API_URL') != BASE:
        raise SystemExit('Refusing nonlocal endpoint.')
    PUBLIC_KEY = status_data.get('PUBLISHABLE_KEY') or status_data['ANON_KEY']
    SERVICE_KEY = status_data.get('SECRET_KEY') or status_data['SERVICE_ROLE_KEY']
    if sql('select count(*) from auth.users;') != '0':
        raise SystemExit('Refusing: disposable local database already has identities; reset it deliberately first.')
    if sql("select count(*) from runtrack_private.application_settings where key='BOOTSTRAP_OWNER_EMAIL';") != '0':
        raise SystemExit('Refusing: local owner configuration already exists; reset the disposable stack deliberately first.')
    try:
        urllib.request.urlopen(urllib.request.Request(MAIL + '/api/v1/messages', method='DELETE'), timeout=10).close()
        status, _, _ = request('/auth/v1/signup', {'email': OWNER, 'password': PASSWORD})
        check(status >= 400 and sql('select count(*) from auth.users;') == '0', 'missing bootstrap configuration blocks actual signup')
        sql("select public.configure_bootstrap_owner('owner@runtrack.test');")
        status, _, _ = request('/auth/v1/signup', {'email': 'intruder@runtrack.test', 'password': PASSWORD,
             'data': {'email': OWNER, 'role': 'admin'}})
        check(status >= 400 and sql('select count(*) from auth.users;') == '0', 'Before User Created hook blocks direct nonowner signup and metadata spoofing')
        owner_id = signup(OWNER)
        status, _, _ = request('/auth/v1/token?grant_type=password', {'email': OWNER, 'password': PASSWORD})
        check(status >= 400, 'unverified owner cannot sign in')
        verify(OWNER)
        owner = login(OWNER)
        owner_token = owner['access_token']
        rpc('ensure_profile', {'p_display_name': 'Founding runner'}, owner_token)
        rpc('ensure_profile', {}, owner_token)
        check(sql('select count(*) from public.profiles;') == '1', 'profile creation is reliable and idempotent after real registration')
        result = rpc('join_club', {'p_code': 'INVALID'}, owner_token)
        check(not result['ok'] and sql('select count(*) from public.club_memberships;') == '0', 'invalid joining code creates no membership')
        result = rpc('join_club', {'p_code': ' tbhrta '}, owner_token)
        check(result['ok'] and result['role'] == 'admin', 'verified designated owner bootstraps atomically using normalized code')
        club_id = result['club_id']
        check(not rpc('bootstrap_status')['bootstrap_pending'], 'bootstrap releases public registrations')
        result = rpc('join_club', {'p_code': 'TBHRTA'}, owner_token)
        check(result['role'] == 'admin' and sql('select count(*) from public.club_memberships;') == '1', 'bootstrap retry is idempotent')
        athlete_id = signup(ATHLETE)
        verify(ATHLETE)
        athlete = login(ATHLETE)
        athlete_token = athlete['access_token']
        rpc('ensure_profile', {}, athlete_token)
        result = rpc('join_club', {'p_code': 'TBHRTA'}, athlete_token)
        check(result['ok'] and result['role'] == 'athlete', 'later public registrant joins as athlete only')
        status, _, _ = request('/rest/v1/club_memberships?user_id=eq.' + athlete_id, {'role': 'admin'}, athlete_token, method='PATCH')
        check(status >= 400, 'direct API self promotion rejected')
        start = (datetime.datetime.now(datetime.timezone.utc) + datetime.timedelta(days=1)).isoformat()
        status, sessions, _ = request('/rest/v1/club_sessions', {'club_id': club_id, 'title': 'Local integration test session',
             'details': 'Disposable test data', 'starts_at': start, 'created_by': owner_id}, owner_token)
        check(status == 201 and len(sessions) == 1, 'club administrator creates persistent session through RLS')
        session_id = sessions[0]['id']
        status, sessions, _ = request('/rest/v1/club_sessions?id=eq.' + session_id, token=athlete_token)
        check(status == 200 and len(sessions) == 1, 'athlete can reload the persisted club session')
        status, _, _ = request('/rest/v1/club_sessions', {'club_id': club_id, 'title': 'Forbidden', 'starts_at': start, 'created_by': athlete_id}, athlete_token)
        check(status >= 400, 'athlete session creation rejected by RLS')
        status, rsvps, _ = request('/rest/v1/session_rsvps', {'session_id': session_id, 'user_id': athlete_id, 'status': 'going'}, athlete_token)
        check(status == 201 and len(rsvps) == 1, 'athlete RSVP written')
        rsvp_id = rsvps[0]['id']
        status, rsvps, _ = request('/rest/v1/session_rsvps?id=eq.' + rsvp_id, token=athlete_token)
        check(status == 200 and rsvps[0]['status'] == 'going', 'RSVP survives a new request')
        status, rsvps, _ = request('/rest/v1/session_rsvps?id=eq.' + rsvp_id, {'status': 'cancelled'}, athlete_token, method='PATCH')
        check(status == 200 and rsvps[0]['status'] == 'cancelled', 'RSVP cancellation persists')
        status, _, _ = request('/functions/v1/export-data', {}, token=None)
        check(status == 401, 'data export requires a genuine verified session')
        status, exported, _ = request('/functions/v1/export-data', {'user_id': owner_id}, athlete_token)
        check(status == 200 and exported['identity']['id'] == athlete_id and
              all(row['id'] == athlete_id for row in exported['profiles']),
              'data export ignores tampered user ID and returns caller records only')
        status, _, _ = request('/functions/v1/health-connect', {}, athlete_token)
        check(status == 400, 'health connection rejects missing explicit consent')
        status, setup, _ = request('/functions/v1/health-connect', {'health_data_consent': True, 'consent_version': '2026-11-12-v1'}, athlete_token)
        check(status == 200 and setup.get('status') == 'setup_required' and sql('select count(*) from health_connections;') == '0',
              'missing real Google credentials returns setup required without a fake connection')
        # Provider-shaped test fixture exists only inside this disposable local database.
        status, _, _ = request('/rest/v1/activities', {'user_id': owner_id, 'provider': 'test', 'provider_workout_id': 'private-1',
             'started_at': start, 'ended_at': start, 'distance_m': 0, 'average_heart_rate': 140}, SERVICE_KEY, key=SERVICE_KEY)
        check(status == 201, 'isolated provider fixture stored')
        status, rows, _ = request('/rest/v1/activities?user_id=eq.' + owner_id, token=athlete_token)
        check(status == 200 and rows == [], 'cross-user private workout access denied over HTTP')
        status, payload, _ = request('/auth/v1/token?grant_type=refresh_token', {'refresh_token': athlete['refresh_token']})
        check(status == 200 and payload.get('access_token'), 'persisted refresh token restores session')
        athlete_token = payload['access_token']
        time.sleep(1.1)
        status, _, _ = request('/auth/v1/recover', {'email': ATHLETE, 'redirect_to': 'http://localhost:3000/'})
        check(status == 200, 'password recovery request accepted')
        recovery = verify(ATHLETE, 'recovery')
        recovery_token = recovery.get('access_token', [None])[0]
        check(bool(recovery_token), 'verified recovery grants reset session')
        status, _, _ = request('/auth/v1/user', {'password': NEW_PASSWORD}, recovery_token, method='PUT')
        check(status == 200, 'password reset updates actual Auth credentials')
        athlete = login(ATHLETE, NEW_PASSWORD)
        athlete_token = athlete['access_token']
        status, _, _ = request('/functions/v1/delete-account', {'confirmation': 'DELETE', 'password': 'wrong-password', 'user_id': owner_id}, athlete_token)
        check(status == 403 and sql('select count(*) from auth.users;') == '2', 'account deletion rejects wrong password')
        status, deleted, _ = request('/functions/v1/delete-account', {'confirmation': 'DELETE', 'password': NEW_PASSWORD, 'user_id': owner_id}, athlete_token)
        check(status == 200 and deleted.get('deleted') and
              sql("select count(*) from auth.users where id='" + athlete_id + "';") == '0' and
              sql("select count(*) from auth.users where id='" + owner_id + "';") == '1',
              'account deletion ignores tampered victim ID and erases only authenticated caller')
        check(sql("select count(*) from public.session_rsvps where user_id='" + athlete_id + "';") == '0',
              'account deletion cascades personal RSVP records')
        print('All %d local HTTP assertions passed.' % len(passed), flush=True)
    finally:
        # Exact guarded local stack only; never pass --linked, --db-url, or any project ref.
        subprocess.run(CLI + ['db', 'reset', '--local', '--yes'], check=True, stdout=subprocess.DEVNULL)
        subprocess.run(['docker', 'exec', '-i', CONTAINER, 'psql', '-U', 'postgres', '-d', 'postgres', '-v', 'ON_ERROR_STOP=1'],
                       input=open('scripts/verify_clean_database.sql', 'rb').read(), check=True)
        print('Disposable database reset: zero application users/data; one club; bootstrap pending.', flush=True)
