# Reproducible setup and deployment

The implementation is in the existing Flutter project. See [production-release.md](production-release.md) for the current hosted deployment and first-account instructions. This guide describes how to reproduce its setup. The original local `env.json` project has not been changed. Do not deploy test users or point destructive test commands at a hosted database.

## Prerequisites and local checks

Tested with Flutter 3.44.0 stable / Dart 3.12.0, Node 22, Docker and Supabase CLI 3.1.0. Direct packages are current stable versions compatible with this SDK; `web` stays on 1.1.1 because 1.1.2 requires Dart 3.13. The lockfile records the resolved dependency set. Install Flutter from [the stable channel](https://docs.flutter.dev/install) and use the checked-in lockfile.

```sh
flutter pub get
flutter analyze
flutter test
npx --yes supabase@3.1.0 start
npx --yes supabase@3.1.0 test db
```

See [database.md](database.md) for the local function-server command and the guarded `python3 scripts/test_local_auth.py` integration suite. That suite verifies real local Auth/email/API interactions and restores the isolated database to zero users. It refuses an existing nonempty test stack. The local inbox is at `http://127.0.0.1:56324`.

## Dedicated production backend

Follow every step in [database.md](database.md): create a **fresh dedicated** project, apply all versioned migrations, privately configure `BOOTSTRAP_OWNER_EMAIL`, enable the Before User Created hook, require email confirmation, configure a real SMTP sender and precise Auth redirect URLs. Owner configuration creates no account. Do not register a test account in the intended clean launch project.

Use a separate staging project for end-to-end verification. On the clean launch project, run `scripts/verify_clean_database.sql` read-only and verify the hosted hook and SMTP configuration separately. The required launch state is one active Tyne Bridge Harriers club, its protected `TBHRTA` code, bootstrap pending, no owner identity and zero users/application records.

## Edge Functions

The CLI supplies `SUPABASE_URL`, `SUPABASE_ANON_KEY` and `SUPABASE_SERVICE_ROLE_KEY` to the server runtime. They must never be added to frontend defines. Set `APP_URL` to the exact root HTTPS origin of this PWA. With the CLI linked only to the new project:

```sh
npx --yes supabase@3.1.0 secrets set APP_URL=https://YOUR_RUNTRACK_DOMAIN
npx --yes supabase@3.1.0 functions deploy
```

All function JWT gateway checks are disabled in `supabase/config.toml` for current publishable-key compatibility. This does **not** make account functions public: each validates the bearer token with Supabase Auth, requires a verified email and derives the user ID server-side. OAuth callbacks use one-time state; health webhooks and scheduled sync use their documented separate server authentication. Test unauthenticated function rejection in staging before launch.

`delete-account` additionally rechecks the runner's current password, attempts Google revocation and deletes only the authenticated identity. Foreign-key cascades erase personal records/credentials. Club-authored sessions retain content with no author ID. Deleting a founding owner never reopens bootstrap. Promote another club administrator before deleting the sole administrator.

`export-data` exports only the authenticated identity's rows, paginates history and omits provider credentials and other runners' private data. The web app downloads the export as JSON. Store exports securely.

## Google Health and automatic sync

Follow [health.md](health.md) for exact Google Cloud OAuth/client approval, read-only scope, account identity check, encryption, webhook and scheduled reconciliation setup. `.env.example` lists backend placeholders only. Missing configuration deliberately leaves the UI in **Setup required**; it never creates a pretend connection. Google/provider approval and a real linked Health account are required to verify live workout retrieval.

Keep token-encryption keys and webhook/scheduler secrets in Supabase secrets. Do not send this file to Flutter. Do not assume all watch ecosystems export complete workout data; the onboarding wizard explains native Apple Health/Health Connect configuration and provider limits.

## Frontend configuration and release

```sh
cp env.example.json env.json
# Replace only the project URL and publishable key with values from the new project.
sh scripts/build_web.sh env.json
```

Only the URL and publishable key belong in `env.json`; it is gitignored. `SUPABASE_ANON_KEY` remains supported for legacy **anon** keys. The application and build script reject service-role/secret keys and remote plain HTTP. Build output is `build/web`. A build without defines intentionally opens a helpful deployment-setup screen.

Host the contents of `build/web` at the root of the final HTTPS domain. For Vercel use the included `vercel.json` with output directory `build/web`; supply Flutter/build tools in your CI or deploy the prebuilt directory. Preserve real static files before the SPA index fallback. Verify `/`, `/manifest.json`, `/sw.js`, `/offline.html`, icons, Flutter assets and Auth callback URLs resolve correctly. The included headers disable location/camera/microphone, framing and MIME sniffing. Use no-cache for index/bootstrap/service-worker files, and appropriate immutable caching for hashed assets.

The custom service worker caches only a public offline notice. It never caches API responses, account exports or training data. The PWA manifest uses branded icons and standalone display. On iPhone install using Safari Share → Add to Home Screen; on Android use the browser's Install app option. Password reset/email verification uses PKCE: open the email in the browser/device that requested it. The SDK persists sessions and renews tokens; signing out removes the session and unmounts the athlete's views.

## Before accepting the first real athlete

1. Confirm staging checks and mobile/desktop browser smoke tests pass. Verify actual staging email delivery, confirmation, recovery, refresh, owner bootstrap, normal athlete permissions, session/RSVP persistence and account deletion/export.
2. Confirm hosted Auth **Before User Created** hook is enabled, and `BOOTSTRAP_OWNER_EMAIL` privately matches the intended verified address. The pending website explains that registration is reserved for that address without revealing it.
3. Run the read-only clean-database audit on the launch project. Never copy staging data into it.
4. Set the final exact Auth Site URL, normal redirect and `?flow=recovery` redirect allowlist entries; set Edge `APP_URL` and Google callback URI. Configure real SMTP and check sender/domain requirements.
5. Deploy the release directory, verify HTTPS/assets/PWA/install behaviour, then the owner creates the **first account through the website**, verifies email, signs in and enters `TBHRTA`. Only that transaction grants founding admin and opens public registration. Nothing in the deployment creates an athlete account.

## Operational privacy

Before public launch, the club operator must publish their actual controller/contact details, purposes, lawful basis, retention and rights process. No operator identity or retention promise is invented in this repository. Collect only the data needed; Google access is optional/read-only, training is private by default, and club sharing is explicit. Review provider health-data policies and configure operational access, backups and deletion schedules for your deployment. The implementation does not by itself establish legal compliance.

## Repeatable browser smoke check

Serve the release directory locally on port 3000, then run this read-only check. It creates no athlete accounts. The full first-user scenario is also recorded in the verification report; real Auth/security writes are covered by the guarded local HTTP suite.

```sh
npm install --prefix /tmp/runtrack-browser playwright@1.65.0
/tmp/runtrack-browser/node_modules/.bin/playwright install chromium
python3 -m http.server 3000 --directory build/web --bind 127.0.0.1
# In another terminal:
NODE_PATH=/tmp/runtrack-browser/node_modules node scripts/smoke_web.cjs
```

Screenshots and the JSON result go to gitignored `test-results/`. Both the unconfigured setup surface and a configured welcome/registration layout are supported.
