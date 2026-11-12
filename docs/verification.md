# Implementation and local verification report

12 November 2026. Work was performed directly in the existing repository, retaining its useful card/avatar/typography/theme components and Provider state management. Existing uncommitted changes were incorporated; no branch reset or remote project reset was performed.

**This records the local implementation stage before deployment.** See [production-release.md](production-release.md) for subsequent hosted configuration and first-account instructions. A successful build alone is not evidence of hosted Auth, email or Google configuration.

## Changes implemented

- Real Supabase Auth registration, email verification, sign-in/out, persistent sessions, PKCE recovery/reset, profile editing, password-confirmed account deletion and paginated JSON export.
- A versioned normalized PostgreSQL backend, RLS and column grants, private training records, explicit sanitized club sharing, verified-email owner bootstrap, a fail-closed Before User Created hook, hashed/rate-limited joining codes and trusted admin operations.
- Exactly one seeded active Tyne Bridge Harriers club. No seeded users, athlete profiles, activities, race results, memberships, sessions, RSVPs, connected accounts, earned awards or ranking rows.
- A canonical activity model with optional measurements, UTC instants, active-time pace, source provenance, laps and duplicate lifecycle handling. Statistics, whole-workout PBs and achievements derive from stored activities and confirmed attendance. No extrapolated splits, recovery/HRV/sleep/readiness figures or unsupported verification claims.
- Real dashboard/activity details, visibility controls, club session create/edit/delete, persistent RSVPs/cancellation, authorized attendance, club name/code/membership administration, challenges, explicit-share leaderboards and private unverified race results. Empty screens explain the next genuine action.
- Persistent iPhone/Android watch onboarding and production Google Health v4 OAuth/PKCE/state, linked identity checks, encrypted tokens, refresh/revocation, resumable reconciliation, signed webhooks and disconnect code. Missing credentials return Setup required and create no pretend connection.
- Branded PWA manifest/icons, narrow/mobile layouts, offline notice, secure public-only configuration, deployment headers and reproducible setup/build scripts.

## Database migrations

| File | Purpose |
| --- | --- |
| `202611120001_runtrack.sql` | Core normalized tables, foreign keys/indexes, RLS/grants, owner hook/bootstrap, protected join/admin functions and the single empty club seed |
| `202611120002_private_club_feed.sql` | Sanitized explicit-share activity projection; private health fields never become club data |
| `202611120003_health_ingestion.sql` | Service-only idempotent ingestion, encrypted credential support, sync leases and provenance matching |
| `202611120004_audit_timestamps.sql` | Immutable ownership columns, audit timestamps and finite/valid metadata constraints |
| `202611120005_duplicate_lifecycle.sql` | Exact-origin recanonicalization after source edits/deletion and protected full-reconciliation deletions |

PBs, achievements and leaderboards are projections of genuine records rather than independently populated database copies. Consequently an empty history yields zero earned awards and ranking entries by construction.

## Automated verification

| Check | Actual result |
| --- | --- |
| `flutter pub get` | Passed, current stable direct dependencies compatible with Flutter 3.44 / Dart 3.12 |
| `flutter analyze` | Passed, no issues |
| `flutter test` | 38 passed |
| `flutter build web --release` | Passed; final `build/web` deliberately has no project defines and displays setup guidance |
| Configured local release build using `scripts/build_web.sh` | Passed; separate temporary browser build uses only the isolated local API/public key |
| Deno strict check | All seven Edge Function entrypoints passed |
| Repeatable release browser smoke | Desktop/mobile setup surface, PWA manifest and uncaught-runtime checks passed via `scripts/smoke_web.cjs` |
| Deno health tests | 13 passed: normalization/absence/DST, linked identity, encryption/state, expiry/revocation, lease conflict, cancellation and cryptographic webhook spoofing/tampering checks |
| PostgreSQL security suite | 127 passed across three suites after a fresh five-migration reset |
| Real HTTP Auth/database/Edge suite | 44 passed again against the final schema/functions; the suite reset the local database afterward |

The Flutter tests include actual SDK request contracts, full history pagination, own-only reads, sanitized club feed, immutable identity/attendance/verification payloads, failed database operations, uncertain writes, activity calculations and narrow empty-state layouts. Test fixtures exist only under `test/`, `supabase/tests/` and guarded local scripts.

Real local HTTP tests exercise direct nonowner/missing-setup signup rejection, metadata spoofing rejection, confirmation email/token, verified login, idempotent profile creation, normalized/invalid codes, atomic founding-owner role, duplicate membership prevention, subsequent athlete registration, token refresh, password recovery/reset, persisted admin sessions/RSVPs, RLS and self-promotion denial. Edge checks reject unauthenticated export and incorrect deletion passwords, ignore forged target user IDs, erase only the caller, and preserve honest health setup status.

Early failures were corrected: the preinstalled Supabase CLI selected an upstream PostgreSQL permission-denial crash; the pinned current CLI/image passed the same denied-access tests without weakening grants. Regression tests exposed card/ink rendering and source-deduplication/privacy edge cases; those were fixed. Browser automation was adjusted for Flutter semantic groups, real keyboard input and tab focus. No unsuccessful run is represented as a passing one.

## Browser verification

Chromium/Playwright was used with a configured release against the disposable local backend, desktop 1280×900 and mobile 390×844; Flutter widget layout tests also exercise 320px width. Screenshots were visually inspected and saved under ignored `test-results/`.

Verified through the real public UI: signup, same-browser PKCE email confirmation, genuine profile/session, invalid code rejection, normalized owner club join, empty dashboard/feed/achievements, first admin session creation, RSVP/cancellation and refresh persistence. Mobile checks covered both native bridge instructions, saved phone/onboarding step after refresh, honest missing-Google-configuration status, actual JSON download without credentials and the service worker offline notice.

Cross-tab sign-out was verified: signing out in a second tab closes the first tab’s cached Account route and returns it to sign-in. The final local reset/audit passed. Physical Safari/iPhone/Android testing and hosted email/provider consent are still required; Chromium emulation does not establish those results.

## Resources actually configured

Only the isolated local `runtrack-clean` Docker/Supabase stack was configured: migrations, RLS, local Auth hook, required email confirmation, local Mailpit and local Edge Functions. Disposable email identities were used for tests, including one created through the browser, and are removed by the final local reset. They are not the user's first real account.

No hosted Supabase project was created, linked, migrated, reset or populated. No live administrator email was guessed or committed. Existing `env.json` is preserved locally and ignored by git; its project was not used for writes. No paid infrastructure was provisioned.

Google Health verification is limited to the current official API/schema/scope/mobile-bridge documentation, retrieval of Google's public webhook verification keyset, pure/cryptographic unit tests, service authorization and honest configuration failure. No genuine Google OAuth grant, linked account, workout retrieval, refresh grant, subscriber handshake, webhook delivery or scheduled provider reconciliation was performed.

## Exact remaining deployment actions

1. Create/authorize a fresh dedicated Supabase project and a separate staging project. Apply all five migrations using [database.md](database.md).
2. Privately configure the actual `BOOTSTRAP_OWNER_EMAIL`, activate **Before User Created → public.before_user_created**, require email confirmation, configure real SMTP and exact site/recovery redirect URLs. Verify direct Auth restrictions in staging; SQL function creation alone does not activate a hosted hook.
3. Set the production frontend URL/publishable key, Edge `APP_URL` and deploy all seven functions. Run the read-only launch audit against the untouched production project and review its zero counts. Build with `sh scripts/build_web.sh env.json` and publish `build/web` at the final HTTPS root.
4. Supply Google Cloud OAuth credentials, enable/approve Google Health's read-only scope, set encryption/webhook/scheduler secrets, register the subscriber and schedule reconciliation as detailed in [health.md](health.md). Verify real provider data and both physical phone paths in staging. Health connection remains optional and Setup required until then.
5. Provide the real club/operator privacy contact and retention/rights information before public launch. No legal operator identity has been invented.

Only after those actions should the designated owner create the first production account through the public website, verify email and enter `TBHRTA`. The deployment itself never creates that account.

## Removed obsolete files

The deleted mock database was already marked for deletion when this task started and remains removed. The following obsolete tracked source/test files were removed or retained as deletions:

```text
lib/core/theme/mock_themes.dart
lib/core/widgets/biometric_ring.dart
lib/core/widgets/entry_animation.dart
lib/core/widgets/layout_gaps.dart
lib/data/mock_data/common_utils.dart
lib/data/mock_data/funny_messages.dart
lib/data/mock_data/mock_activity_service.dart
lib/data/mock_data/mock_database.dart
lib/data/mock_data/mock_supabase_db.dart
lib/data/repositories/mock_run_track_repository.dart
lib/data/repositories/time_range_toggle.dart
lib/features/achievements/presentation/view_models/achievements_view_model.dart
lib/features/activity/presentation/view_models/run_track_view_model.dart
lib/features/club_hub/presentation/view_models/club_hub_view_model.dart
lib/features/profile/domain/models/biometric_ui_extensions.dart
lib/features/profile/presentation/view_models/you_view_model.dart
lib/src/core/common_widgets/premium_card.dart
lib/src/core/mock_data/mock_supabase_db.dart
lib/src/core/theme/club_theme_config.dart
lib/utils/common_utils.dart
repomix-output.xml
test/helpers/test_fixtures.dart
test/unit/club_hub/club_hub_view_model_test.dart
test/unit/club_hub/models_test.dart
test/unit/repositories/common_utils.dart
test/unit/repositories/mock_run_track_repository_test.dart
test/unit/utils/common_utils.dart
test/unit/utils/common_utils_test.dart
test/unit/utils/run_track_repository.dart
```

Untracked obsolete duplicates present at the start were also removed: `lib/core/theme/supabase_run_track_repository.dart`, `lib/supabase_run_track_repository.dart`, and the duplicated `activity_processing_utils.dart` files under `lib/utils`, `lib/data/repositories`, and the achievements view directory. One typed production repository replaces those implementations.

## Final clean-state audit

The final guarded local reset applied all five migrations. The standard SQL suite passed **127/127**, and the real HTTP/Auth/database/Edge suite passed **44/44** before its final local reset. The read-only launch audit then passed.

| Entity/state | Audited local value |
| --- | --- |
| Registered Auth users / athlete profiles / memberships | 0 / 0 / 0 |
| Activities / laps / race results | 0 / 0 / 0 |
| Club sessions / RSVPs | 0 / 0 |
| Club challenges / participants | 0 / 0 |
| Health connections / private credentials | 0 / 0 |
| Sync jobs / events / OAuth states | 0 / 0 / 0 |
| Clubs | 1 — Tyne Bridge Harriers, active |
| Joining code | TBHRTA hash validated server-side |
| Bootstrap pending / owner user ID | true / null |
| Real founding-owner email configured | No; requires private deployment configuration |

Earned achievements and leaderboard entries are zero because their source records are empty. All browser/HTTP test identities and their data were removed. The temporary verification database was dropped, the test function server stopped, and the clean local Docker stack remains available. These counts concern the disposable **local** project; no production database was configured or audited.
