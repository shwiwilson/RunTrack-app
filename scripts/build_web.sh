#!/bin/sh
set -eu
public_config=${1:-env.json}
# Reject accidentally supplying backend secrets even if Dart would ignore them.
python3 - "$public_config" <<'PY'
import base64,json,sys,urllib.parse
config=json.load(open(sys.argv[1]))
allowed={'SUPABASE_URL','SUPABASE_PUBLISHABLE_KEY','SUPABASE_ANON_KEY'}
if set(config)-allowed: raise SystemExit('Frontend configuration may contain only the Supabase URL and public key.')
url=urllib.parse.urlparse(config.get('SUPABASE_URL',''))
if not url.hostname or (url.scheme!='https' and not(url.hostname in ('127.0.0.1','localhost') and url.scheme=='http')):
 raise SystemExit('Use an HTTPS project URL, or the isolated localhost development API.')
key=config.get('SUPABASE_PUBLISHABLE_KEY',config.get('SUPABASE_ANON_KEY',''))
valid=key.startswith('sb_publishable_') and 'REPLACE' not in key
if not valid:
 try:
  payload=key.split('.')[1]; valid=json.loads(base64.urlsafe_b64decode(payload+'='*(-len(payload)%4)))['role']=='anon'
 except Exception: valid=False
if not valid: raise SystemExit('A public publishable/anon key is required. Never build with a secret or service-role key.')
PY
flutter build web --release --no-web-resources-cdn --dart-define-from-file="$public_config"
