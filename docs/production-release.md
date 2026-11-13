# Production deployment status

13 November 2026. The current status below was checked against the live service. The launch audit later in this report is historical: its zero counts and pending bootstrap describe the initial deployment, before the owner registered. The deployment did not create an athlete account.

## Current onboarding status

- The founder has registered and completed bootstrap. The live public status reports `bootstrap_pending=false` and `setup_required=false`, and the club has one active administrator membership. Do not register the founder again or run a clean-database reset on production.
- The website is live at [run-track-app.vercel.app](https://run-track-app.vercel.app). Its public `/privacy.html` serves the actual TSWebDev privacy notice.
- Ordinary athlete email registration is enabled through the existing Brevo account. The domain is authenticated and `hello@tswebdev.co.uk` is a verified sender. The owner created a dedicated SMTP key and saved it directly in Supabase. Safe configuration readback passed, an Auth recovery-email request returned HTTP 200, and the owner confirmed receipt from that sender. Email confirmation remains required; the current Auth limit is 30 emails per hour.
- Google Health API is enabled in the dedicated `runtrack-health-cwdhym` Cloud project. Its External consent configuration has the read-only activity/fitness scope and one permitted test user. The owner created the Web OAuth client; the guarded installer validated its downloaded JSON and exact callback, then installed its credentials only as protected Edge secrets. A real Google grant and workout import are still unverified.
- Production has all nine migrations through `202611120009` and seven active version-3 Edge Functions. Consent, atomic OAuth completion, transactional webhook delivery and bounded/resumable synchronization are deployed. All six protected endpoints still reject anonymous requests with HTTP 401. One-minute reconciliation is enabled with the existing secret transferred directly from Edge runtime to Vault. Subscriber activation and a real authorized workout import are the remaining live checks.
- Google branding now includes the public app and privacy URLs, with both app/callback domains saved. Google's Verification Centre confirms no verification is required while the app remains in Testing; this is not public approval. Testing grants expire after seven days and only listed accounts can link. Other runners can register and skip linking.

Runners can register with email and use the club without connecting Google Health. Google Testing access requires each intended Google account to be allowed; public verification is a separate provider process. The initial group is at most ten runners, and Google linking is optional. See [provider-credentials.md](provider-credentials.md).

## Initial hosted backend configuration

| Resource | Actual state |
| --- | --- |
| Supabase project | **RunTrack Production** |
| Project reference | `cwdhymutbulafmtkfhqf` |
| Region / plan | London (`eu-west-2`) / verified Free organization |
| API URL | `https://cwdhymutbulafmtkfhqf.supabase.co` |
| Project dashboard | [Supabase dashboard](https://supabase.com/dashboard/project/cwdhymutbulafmtkfhqf) |
| Database migrations | All five versioned RunTrack migrations applied successfully |
| Initial club | Exactly one active **Tyne Bridge Harriers** record; protected `TBHRTA` hash validated |
| Founding owner | Privately designated address configured only in protected backend settings |
| Bootstrap | Pending; owner user ID remains null |
| Before User Created hook | Enabled and read back as `pg-functions://postgres/public/before_user_created` |
| Auth | Email/password enabled; email confirmation required; 12-character minimum; refresh-token rotation enabled; anonymous/phone sign-in disabled |
| Site / recovery URLs | `https://run-track-app.vercel.app`, with exact `/` and `/?flow=recovery` redirect entries |
| Edge Functions | All seven deployed, active, version 1 |
| Server secrets | App origin, provider callback URI, token-encryption key and distinct webhook/reconciliation secrets configured server-side |

The old paused RunTrack project and the unrelated TSLeagues project were not resumed, modified, migrated, deleted or populated. No paid plan or add-on was enabled. The new project used the available second active Free project slot.

The seven active functions are `delete-account`, `export-data`, `health-connect`, `health-callback`, `health-sync`, `health-webhook` and `health-disconnect`. Gateway JWT checking is disabled deliberately; user functions verify the bearer identity with Supabase Auth, callbacks use one-time state and webhooks/scheduled reconciliation use their separate protected authentication.

## Historical launch verification — 12 November 2026

- A direct public Auth request using a nonowner email and forged owner/admin metadata returned **403: RunTrack registration is not open yet**. No identity was created.
- The configured owner was checked against the hook through an identity-free SQL invocation; it is allowed. No signup or verification email was requested on the owner's behalf.
- Public `bootstrap_status()` returns `bootstrap_pending=true` and `setup_required=false`, without exposing the designated address.
- Anonymous requests to the five user functions and the webhook were rejected with **401**. The webhook intentionally returns an empty unauthorized body.
- A callback without valid setup/state returned a safe **303** redirect to the app with `health_result=authorization_failed`; it created no connection.
- Every application/private application table has RLS. Anonymous callers cannot execute owner configuration, and ordinary authenticated roles cannot directly insert memberships.
- The repository's read-only launch audit passed against the new hosted database. The extended hosted audit also passed with the counts below.

| Application data | Count at initial launch audit |
| --- | --- |
| Auth users / profiles / memberships | 0 / 0 / 0 |
| Activities / laps / race results | 0 / 0 / 0 |
| Club sessions / RSVPs | 0 / 0 |
| Challenges / participants | 0 / 0 |
| Health connections / private credentials | 0 / 0 |
| Sync jobs / sync events / OAuth states | 0 / 0 / 0 |
| Clubs | 1 |

Achievements and leaderboard entries are projections of the empty source records and therefore have zero earned/ranking entries. No production test athlete or fabricated activity was inserted.

## Frontend deployment

The release is **live at [https://run-track-app.vercel.app](https://run-track-app.vercel.app)** on the existing Vercel Hobby project. Source commit `448280273f9c58170e42e9ee5cedca235ddc5204` adds the revised phone/watch guide and explicit skip action. Hosted artifact checks confirm this guidance, the current project's URL and the updated Brevo privacy disclosure are served in production.

The pinned Flutter build uses only the fresh production project's URL and publishable key from Vercel configuration. It overrides the old dashboard build settings using `vercel.json`. No bootstrap email or server credentials are in the public source or browser bundle.

Actual production checks passed: root, manifest, service worker, JavaScript bundle and password-recovery URL all returned 200 with the expected content types; the bundle targets the new Supabase project; frame and location-permission protections were present. Chrome rendered the genuine prebootstrap welcome screen and Create account form, including accessible name/email/password controls and the 12-character requirement. No registration form was submitted, so no owner identity or verification message was created by these checks.

## How registration works

The founder has already completed the first-account process below. These steps explain bootstrap; they are not an instruction to recreate that account:

1. Open the production URL and choose **Create account**.
2. Register using the privately designated founding administrator address. The deployment has not created this account.
3. Open the confirmation email in the same browser/device, then sign in if prompted.
4. Enter **TBHRTA**. The verified identity and valid code are checked server-side; the one-time transaction grants the founding club administrator membership and completes bootstrap.
5. Your dashboard, feed and running achievements start empty. Open **Club → Create session** to create the club's first real session.
6. Sign out before registering a separate athlete account with a different email. That identity receives ordinary athlete permissions when it joins with **TBHRTA**; it does not receive another founding-owner grant.

New athletes use their own email address, verify the account message, then join with **TBHRTA**. They receive athlete permissions. They can skip Google Health and connect later from the app's health setup.

## Email delivery verified

The initial deployment used Supabase's limited default sender. This has now been replaced with the existing Brevo SMTP relay: `smtp-relay.brevo.com:587`, sender **RunTrack <hello@tswebdev.co.uk>**. The existing business/Gmail key was not rotated or reused.

The owner confirmed the real recovery message arrived. This verifies the hosted Auth-to-Brevo delivery path; it is not a claim that a second athlete account has already registered. No demo athlete was created. The Auth limit is 30 account messages per hour, including recovery/resend messages, which is adequate for the stated initial group of up to ten runners. Existing provider quotas also apply.

Manage credentials only in [the project's protected SMTP settings](https://supabase.com/dashboard/project/cwdhymutbulafmtkfhqf/auth/smtp). No provider plan, domain or paid service was purchased.

## Google Health external setup remains

Google Cloud OAuth client credentials are installed, the exact callback is registered and the backend upgrades are deployed. Scheduled reconciliation is active. Subscriber registration and real account/workout verification are being completed. Saved credentials alone do not mean any runner is connected. No successful connection or sync has been simulated.

The live `runtrack-health-reconcile` Cron job is active every minute; its command reads the existing reconciliation credential from Vault. The token-encryption, webhook and reconciliation secrets were not rotated. Google subscriber creation is in progress through a temporary operator bridge. Follow [health.md](health.md) for the provider behavior and limits. Connecting running data remains optional, so verified athletes can use the club and account functions without it.
