#!/bin/sh
set -eu

# This is a static Flutter build. Supabase service credentials stay in Supabase;
# the only deployment values written below are the URL and public browser key.
flutter_version=3.44.0
flutter_revision=559ffa3f75e7402d65a8def9c28389a9b2e6fe42
repository_directory=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$repository_directory"

if ! command -v python3 >/dev/null 2>&1; then
  echo 'Python 3 is required to validate the public build configuration.' >&2
  exit 1
fi
temporary_directory=$(mktemp -d "${TMPDIR:-/tmp}/runtrack-vercel.XXXXXX")
trap 'rm -rf "$temporary_directory"' EXIT HUP INT TERM

# Fail before downloading an SDK or producing a deployable build if the
# deployment has not supplied a real public project configuration.
python3 - "$temporary_directory/public.json" <<'PY'
import base64
import json
import os
import sys
from urllib.parse import urlsplit

url = os.environ.get('SUPABASE_URL', '').strip()
key = os.environ.get('SUPABASE_PUBLISHABLE_KEY', '').strip() or os.environ.get('SUPABASE_ANON_KEY', '').strip()
parsed = urlsplit(url)
if (parsed.scheme != 'https' or not parsed.hostname or parsed.username or parsed.password
        or parsed.path not in ('', '/') or parsed.query or parsed.fragment
        or parsed.hostname in ('localhost', '127.0.0.1') or 'YOUR_PROJECT' in url.upper()):
    raise SystemExit('Set SUPABASE_URL to the production HTTPS project URL in Vercel.')
valid = key.startswith('sb_publishable_') and 'REPLACE' not in key.upper()
if not valid:
    try:
        payload = key.split('.')[1]
        role = json.loads(base64.urlsafe_b64decode(payload + '=' * (-len(payload) % 4))).get('role')
        valid = role == 'anon'
    except (ValueError, IndexError, TypeError, AttributeError):
        valid = False
if not valid:
    raise SystemExit('Set SUPABASE_PUBLISHABLE_KEY to a public browser key. Secret/service-role keys are forbidden.')
with open(sys.argv[1], 'w', encoding='utf-8') as config:
    json.dump({'SUPABASE_URL': url.rstrip('/'), 'SUPABASE_PUBLISHABLE_KEY': key}, config)
print('Production Supabase public configuration validated.')
PY

matches_pinned_sdk() {
  "$1" --version --machine > "$temporary_directory/flutter-version.json" 2>/dev/null || return 1
  python3 - "$temporary_directory/flutter-version.json" "$flutter_version" "$flutter_revision" <<'PY'
import json
import sys
try:
    version = json.load(open(sys.argv[1], encoding='utf-8'))
    valid = version.get('frameworkVersion') == sys.argv[2] and version.get('frameworkRevision') == sys.argv[3]
except (ValueError, OSError):
    valid = False
raise SystemExit(0 if valid else 1)
PY
}

# Vercel caches node_modules even with the Other framework preset. Keeping the
# versioned SDK and pub packages here also makes a cold cache safe to rebuild.
cache_directory="$repository_directory/node_modules/.cache/runtrack"
native_flutter=$(command -v flutter || true)
if [ -n "$native_flutter" ] && matches_pinned_sdk "$native_flutter"; then
  flutter_command="$native_flutter"
else
  sdk_directory="$cache_directory/flutter-$flutter_version"
  if [ ! -x "$sdk_directory/bin/flutter" ] || ! matches_pinned_sdk "$sdk_directory/bin/flutter"; then
    if ! command -v git >/dev/null 2>&1; then
      echo 'Git is required to install the pinned official Flutter SDK.' >&2
      exit 1
    fi
    rm -rf "$sdk_directory"
    mkdir -p "$cache_directory"
    git clone --depth 1 --single-branch --branch "$flutter_version" \
      https://github.com/flutter/flutter.git "$sdk_directory"
    if [ "$(git -C "$sdk_directory" rev-parse HEAD)" != "$flutter_revision" ]; then
      echo 'The downloaded Flutter revision differs from the tested release.' >&2
      exit 1
    fi
  fi
  flutter_command="$sdk_directory/bin/flutter"
fi
PATH="$(dirname "$flutter_command"):$PATH"
export PATH
if [ "${VERCEL:-}" = '1' ]; then
  PUB_CACHE="$cache_directory/pub"
  export PUB_CACHE
fi

flutter --suppress-analytics precache --web
flutter --suppress-analytics pub get --enforce-lockfile
sh scripts/build_web.sh "$temporary_directory/public.json"
