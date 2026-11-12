# Production deployment status

12 November 2026. This report records actual hosted configuration and supersedes the earlier local-only status in `verification.md`. No athlete account has been created by the deployment.

## Hosted backend configured and verified

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

## Actual hosted verification

- A direct public Auth request using a nonowner email and forged owner/admin metadata returned **403: RunTrack registration is not open yet**. No identity was created.
- The configured owner was checked against the hook through an identity-free SQL invocation; it is allowed. No signup or verification email was requested on the owner's behalf.
- Public `bootstrap_status()` returns `bootstrap_pending=true` and `setup_required=false`, without exposing the designated address.
- Anonymous requests to the five user functions and the webhook were rejected with **401**. The webhook intentionally returns an empty unauthorized body.
- A callback without valid setup/state returned a safe **303** redirect to the app with `health_result=authorization_failed`; it created no connection.
- Every application/private application table has RLS. Anonymous callers cannot execute owner configuration, and ordinary authenticated roles cannot directly insert memberships.
- The repository's read-only launch audit passed against the new hosted database. The extended hosted audit also passed with the counts below.

| Application data | Final hosted count |
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

The configured production origin is **https://run-track-app.vercel.app**. The public Supabase URL/publishable key have been supplied for the frontend build. Publication and browser verification of the final Vercel release are being completed separately; the backend checks above do not by themselves assert that the new frontend release is live.

## How to register

Once the new frontend release is confirmed live:

1. Open the production URL and choose **Create account**.
2. Register using the privately designated founding administrator address. The deployment has not created this account.
3. Open the confirmation email in the same browser/device, then sign in if prompted.
4. Enter **TBHRTA**. The verified identity and valid code are checked server-side; the one-time transaction grants the founding club administrator membership and completes bootstrap.
5. Your dashboard, feed and running achievements start empty. Open **Club → Create session** to create the club's first real session.
6. Sign out before registering a separate athlete account with a different email. That identity receives ordinary athlete permissions when it joins with **TBHRTA**; it does not receive another founding-owner grant.

**Different-email athlete registration needs custom SMTP first.** See the mail limitation below. Bootstrap can open public signup logically, but it cannot remove Supabase's default sender restrictions.

## Email limitation still requiring operator setup

The designated founder is verified as an Owner/team member of this Supabase organization, so that address is permitted by Supabase's default email service. Actual delivery has not been triggered or verified because the first account must be created by the owner through the website.

The user has no existing SMTP provider, and the old RunTrack project has no custom SMTP configuration to migrate. Supabase's default sender only sends to organization team addresses and is currently limited to two messages per hour. It does not support general athlete registration to different addresses. Email confirmation has not been disabled as a workaround.

To enable normal athletes, configure an SMTP service and a verified sender/domain in [the new project's Auth email settings](https://supabase.com/dashboard/project/cwdhymutbulafmtkfhqf/auth/smtp). Supply its host, port, username, password, sender address and sender name through protected server configuration. Follow [Supabase's official SMTP guidance](https://supabase.com/docs/guides/auth/auth-smtp). Configure any provider plan, domain/DNS and charges explicitly; none were purchased by this deployment.

## Google Health external setup remains

All health backend code and server security secrets are deployed, but real Google Cloud OAuth client credentials, Google Health permission/approval, subscriber registration and real account/workout verification remain unavailable. The app must continue to show an honest **Setup required** state. No Google login, connection or successful sync has been simulated.

The reconciliation secret is configured; no production reconciliation schedule or Google subscriber has been activated while the provider configuration is incomplete. Follow [health.md](health.md) to configure and verify the actual provider and scheduler. Connecting running data remains optional, so the verified founder can use the club and account functions without it.
