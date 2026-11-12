# Google Health integration and phone setup

Implemented production code is present. No real OAuth account has been connected, no real workout has been fetched, and no hosted webhook or scheduled job has been configured in this workspace. Missing credentials produce `setup_required`, never a simulated connection. The operator must complete the steps below in separate Google Cloud staging and production projects.

## Documented contract checked on 12 November 2026

The adapter uses the current **v4** Google Health API, not the retired Fitbit Web API or Google Fit REST API:

- [Cloud/OAuth setup](https://developers.google.com/health/setup): enable Google Health API; create a Web application OAuth client; configure consent and test users; register the exact callback URI.
- [Identity endpoint](https://developers.google.com/health/reference/rest/v4/users/getIdentity): `GET https://health.googleapis.com/v4/users/me/identity`. Require a valid `healthUserId`. OAuth login alone is insufficient; `ACCOUNT_NOT_LINKED` remains an error.
- [Workout representation](https://developers.google.com/health/data-types/workouts): `exercise` with documented `RUNNING`, `TRAIL_RUN`, `TREADMILL` types, real UTC timestamps, active duration, summary distance in millimetres, optional metrics and split summaries.
- [Reconciled workouts](https://developers.google.com/health/reference/rest/v4/users.dataTypes.dataPoints/reconcile): `GET /v4/users/me/dataTypes/exercise/dataPoints:reconcile`, page size 25, `nextPageToken`, `dataPointName`. Read the selected [individual data point](https://developers.google.com/health/reference/rest/v4/users.dataTypes.dataPoints/get) for available source/device metadata. Reconciliation selects across sources before RunTrack ingestion.
- Read scope: `https://www.googleapis.com/auth/googlehealth.activity_and_fitness.readonly`. No write, location, sleep or unrelated health scope is requested. Unavailable heart rate or other fields stay null.
- [Webhook documentation](https://developers.google.com/health/webhooks): endpoint authorization secret, verification POST `{"type":"verification"}`, signed notifications, batch size up to 99, user identity `healthUserId`, automatic `exercise` subscriptions.

Browser onboarding uses the native health apps as bridges. It cannot request HealthKit/Health Connect permissions or detect installed apps:

- [Google Health with Apple Health](https://support.google.com/googlehealth/answer/17037331): configure the link in the mobile Google Health app. Historical coverage is limited by Google and the source app.
- [Google Health with Health Connect](https://support.google.com/googlehealth/answer/14506680) and [Android Health Connect setup](https://support.google.com/android/answer/12201227): Android 14+ integrates Health Connect into Settings; earlier supported releases may need its app.
- [Third-party watch compatibility](https://support.google.com/googlehealth/answer/14236613): Google documents Garmin and Apple Watch bridges, but data fields differ between apps. Garmin detailed laps and various metrics may be absent. COROS, Polar, Suunto and other manufacturers must actually share workouts through the selected native bridge; their availability is not assumed.

The wizard saves phone, watch, companion app and step progress locally by genuine user ID and to `profiles.onboarding.health_setup`. User-confirmed setup checkboxes never mark a provider connected. Connection and last sync details always come from the database.

## Backend configuration

Configure these as Supabase **Edge Function secrets**, never Flutter build variables:

| Secret | Value |
| --- | --- |
| `APP_URL` | Exact public HTTPS PWA root, e.g. `https://runtrack.example/` |
| `GOOGLE_HEALTH_CLIENT_ID` | Google Web application OAuth client ID |
| `GOOGLE_HEALTH_CLIENT_SECRET` | Matching confidential client secret |
| `GOOGLE_HEALTH_REDIRECT_URI` | `https://PROJECT_REF.supabase.co/functions/v1/health-callback` |
| `HEALTH_TOKEN_ENCRYPTION_KEY` | Base64 of 32 cryptographically random bytes; back it up securely |
| `GOOGLE_HEALTH_WEBHOOK_SECRET` | Strong random webhook bearer secret, distinct from other secrets |
| `HEALTH_RECONCILE_SECRET` | Strong random scheduler bearer secret, distinct from webhook secret |

Supabase supplies `SUPABASE_URL` and `SUPABASE_SERVICE_ROLE_KEY` to hosted functions. The public PWA receives only its project URL and publishable key. Encryption uses AES-256-GCM with random IVs and connection ID as associated data. Refresh/access tokens are accessible through service-only RPCs and stored in the non-exposed `runtrack_private` schema. OAuth states contain only a hash and an encrypted PKCE verifier, expire after ten minutes, and are consumed atomically once. The callback user ID comes from that saved state; user input cannot substitute a different athlete.

Apply every migration, including `202611120003_health_ingestion.sql`, before deploying:

```sh
supabase functions deploy health-connect
supabase functions deploy health-callback
supabase functions deploy health-sync
supabase functions deploy health-webhook
supabase functions deploy health-disconnect
```

All functions declare `verify_jwt = false` in `supabase/config.toml`: connect/sync/disconnect call `auth.getUser` themselves and require verified email; the callback consumes its one-time state; webhooks require their independent bearer secret and signature; scheduled sync requires its separate secret. This supports current publishable keys/asymmetric user JWTs without disabling application authorization.

Do not rotate `HEALTH_TOKEN_ENCRYPTION_KEY` in place: stored credentials would no longer decrypt. Implement a controlled re-encryption migration or revoke/disconnect existing connections before replacing it. Never copy production credentials into a test database.

## Google Cloud and subscriber setup

1. Create separate Google Cloud projects for staging and production. Enable Google Health API. Configure branding, a real privacy policy, support contact and authorized domains.
2. Create a Web application OAuth client. Register the exact `GOOGLE_HEALTH_REDIRECT_URI` above. Add only the read-only fitness scope to the consent screen. Set the backend secrets.
3. While OAuth is in Testing, explicitly allow your **staging test users** in Google's Audience settings. Do not create any athlete in the clean live RunTrack project. Complete Google's required verification/security review before broader access; the official setup guide documents limits and approval requirements.
4. In staging, sign up and verify an actual test account, create its profile, open the wizard, and prepare its Google Health mobile profile. Test cancellation, unlinked identity, partial scopes, expired state and revocation as well as a genuine workout import. The production owner must later perform their own genuine registration.
5. Deploy `health-webhook` before creating the Google subscriber. Obtain a Google IAM workload/service-account access token using the roles required by the current Google Health documentation. Do not put that credential in the browser.
6. Create a subscriber using `POST https://health.googleapis.com/v4/projects/PROJECT_NUMBER/subscribers?subscriberId=runtrack-exercise` with this JSON body (replace placeholders):

```json
{
  "endpointUri": "https://PROJECT_REF.supabase.co/functions/v1/health-webhook",
  "subscriberConfigs": [
    {"dataTypes": ["exercise"], "subscriptionCreatePolicy": "AUTOMATIC"}
  ],
  "endpointAuthorization": {"secret": "Bearer WEBHOOK_SECRET"}
}
```

Google performs **both** an authorized 200 handshake and an unauthorized 401 challenge. Do not claim subscriber activation until this creation succeeds. Real data notifications additionally require `GOOGLE-HEALTH-API-SIGNATURE`. The receiver fetches Google's rotating [official Tink public keyset](https://www.gstatic.com/googlehealthapi/webhooks/webhooks_public_keyset.json) and verifies the raw body using ECDSA P-256/SHA-256, including the five-byte Tink key prefix and DER signature encoding. This URL was successfully fetched during local work; no real notification was received.

## Scheduled reconciliation

Configure a trusted scheduler to POST `health-sync` with `Authorization: Bearer HEALTH_RECONCILE_SECRET`. Store this secret in a backend vault/scheduler secret store. For example, use Supabase Cron plus Vault/pg_net following [Supabase scheduled Edge Function guidance](https://supabase.com/docs/guides/functions/schedule-functions). Create and verify the schedule only after setting its secret. Start with every five minutes, assess provider quota and workload, and do not enable paid services without approval.

Each call processes the oldest outstanding connection. Normal sync replays seven days for corrections; a full reconciliation runs at least daily or when authenticated notifications are queued. A database lease prevents simultaneous sync/reconnect/disconnect on the same connection. Work is bounded to two 25-record pages per function call; remaining page/filter state is persisted. Partial imports show a continue-sync message and do **not** advance the last-success time. A subsequent call resumes safely. Large first imports may require several calls. Schedule throughput must be adjusted for the real number of connected athletes and Google quotas.

The lightweight webhook persists deduplicated notifications in `sync_events`; reconciliation marks them processed only after successful completion. Unsuccessful responses cause Google to retry. Full reconciliation removes records absent from the provider only after all pages succeed; partial failures never erase history. Provider revocation/deletion events remove server credentials and mark the connection revoked. Refresh tokens renew on demand, not in a mass refresh job. A refused refresh grant clears credentials and asks the user to reconnect.

`upsert_health_activity` keys source records by `(user_id, provider, provider_workout_id)` and preserves athlete visibility settings. It derives no fake measurements. An explicit common origin provider+workout identity can link duplicate source records while retaining provenance; matching distance alone never merges workouts. Google's reconciliation handles duplicates within its available data stream. Future provider adapters must supply stable original identifiers; ambiguous cross-provider matches must remain distinct pending review rather than silently deleting a run.

## Validation and remaining live checks

Run `npx --yes deno test --allow-env supabase/functions/tests` and `npx --yes deno task --config supabase/functions/deno.json check`. Unit tests exercise normalization, DST intervals, absent/zero values, impossible timestamps, encrypted token tampering, token expiry/revocation, unlinked identities, and real generated ECDSA signatures including malformed/spoofed notifications. `supabase/tests/health_security.test.sql` uses rollback-only disposable fixtures to test state expiry/replay, service-only ingestion, token isolation, leases, deduplication and visibility preservation.

These tests do not verify a real Google grant. Still required in staging: real OAuth consent/token exchange; actual linked `getIdentity`; returned workout/lap shapes and device support; provider quota/backoff behavior at load; token refresh/revocation; real subscriber handshake and signed notification delivery; scheduled reconciliation; phone app-to-PWA return behavior on physical iPhone/Android devices. Production remains empty until its owner registers through the public page.

Disconnect disables local access and deletes stored credentials and outstanding OAuth states before remote revocation. If Google cannot confirm revocation, the UI reports that local disconnection succeeded and directs the athlete to Google Account permissions; it never claims remote revocation succeeded.
