# Database, roles and founding owner

The versioned migrations create exactly one active club, Tyne Bridge Harriers, and a salted bcrypt representation of `TBHRTA`. They create **zero Auth users, profiles, memberships, activities, races, sessions, RSVPs or health connections**. There is no data seed script. Running achievements, personal bests and leaderboard values are derived from canonical activity/attendance records rather than populated ranking or earned-award tables.

Only use a new dedicated RunTrack Supabase project. Existing projects or credentials found elsewhere in the repository have not been migrated, reset or deleted. No remote resources are configured by these files.

## Local disposable environment

Use Node/npm, Docker and the pinned current CLI:

```sh
npx --yes supabase@3.1.0 start
npx --yes supabase@3.1.0 test db
```

In another terminal, start the local functions with only the local app origin configured:

```sh
printf '%s\n' 'APP_URL=http://localhost:3000' > /tmp/runtrack-local-functions.env
npx --yes supabase@3.1.0 functions serve --env-file /tmp/runtrack-local-functions.env
```

Then run `python3 scripts/test_local_auth.py` in the first terminal. The script resets only its guarded local database when finished.

The isolated project ID is `runtrack-clean`; API `http://127.0.0.1:56321`, PostgreSQL `56322`, Studio `56323`, local email inbox `56324`. The local configuration enables email confirmation and the Before User Created hook. The hook initially rejects all registrations because no owner email is configured. `test_local_auth.py` refuses a different project or nonlocal endpoint, creates only disposable test identities, verifies actual signup email links and database writes over HTTP, then resets **only the guarded local database** and reruns the clean-state audit. Do not point this test at a hosted project.

Use CLI 3.1.0 or later with compatible local configuration. The preinstalled CLI 2.101.0 selected a PostgreSQL 17.6.1.106 image with an upstream [permission-denial crash](https://github.com/supabase/postgres/issues/2112). The fixed current CLI uses PostgreSQL 17.11.0.018. Do not weaken grants to work around an old database image. CLI 3 uses `[local_smtp]` instead of `[inbucket]`.

## Fresh hosted project setup

1. Create a dedicated Supabase project; check its Auth and application tables contain no pre-existing data. Do not reuse/reset an unrelated project. Pick the required region and approve any plan charges yourself.
2. From this repository, link the **new** project and apply migrations:

   ```sh
   npx --yes supabase@3.1.0 login
   npx --yes supabase@3.1.0 link --project-ref YOUR_NEW_PROJECT_REF
   npx --yes supabase@3.1.0 db push
   ```

   Review the target before the push. Never use a production reset command.
3. Configure the private founding owner setting named `BOOTSTRAP_OWNER_EMAIL`. With a secure administrative PostgreSQL connection, run `scripts/configure_bootstrap_owner.sql`; it prompts for the actual email and stores it in `runtrack_private.application_settings`, which browser roles cannot read or change. Alternatively execute `select public.configure_bootstrap_owner('YOUR_ACTUAL_OWNER_EMAIL');` privately in the Supabase SQL editor. No owner value belongs in Dart defines, public environment files or git. Calling this function creates **no account**.
4. In **Authentication → Hooks**, enable **Before User Created**, select the PostgreSQL function `public.before_user_created`. This is essential: migration creation alone does not activate hosted Auth hooks. Its SQL URI is `pg-functions://postgres/public/before_user_created`. The migration grants execution only to `supabase_auth_admin`. See [Supabase hook documentation](https://supabase.com/docs/guides/auth/auth-hooks/before-user-created-hook).
5. In Auth settings, enable email/password signups, **Confirm email**, secure email changes on both addresses, refresh-token rotation, minimum password length 12 and appropriate rate limits. Disable anonymous sign-ins and unused OAuth/phone providers. Configure a real SMTP sender with SPF/DKIM as required by the email provider. Local Mailpit does not deliver production email.
6. Set the Auth **Site URL** to the final HTTPS PWA origin. Add exact allowed callback/reset URLs, e.g. `https://YOUR_RUNTRACK_DOMAIN/`; use the same URL as `APP_URL` in the app and backend. Avoid a wildcard production redirect allowlist. See [redirect URL documentation](https://supabase.com/docs/guides/auth/redirect-urls).
7. Deploy server functions and health configuration using the main deployment/health guide. Only the frontend Supabase URL and publishable key go in the web build. The service key, token-encryption key and Google secrets remain server-side.
8. Verify the hook on a **separate staging project** through direct Auth API signup: missing configuration must reject, nonowner email and forged metadata must reject, designated email must receive confirmation; unverified users must not bootstrap; a verified owner and correct normalized code must atomically become the sole founding admin; subsequent verified users become athletes. Use disposable accounts only in staging. Do not claim the hosted registration restriction is active until that verification succeeds.
9. On the untouched launch project, run `scripts/verify_clean_database.sql` over an administrative connection. It is read-only and raises if user/activity/session data exists or the one-club/code requirement is violated. Check `bootstrap_owner_configured=true`, `bootstrap_pending=true`, `owner_user_id=null`. Hook activation and SMTP delivery require separate dashboard/API verification; they cannot be inferred from these database counts.

## Trusted APIs and boundaries

- `bootstrap_status()` exposes only pending/setup flags; it never exposes the designated email.
- `ensure_profile(p_display_name)` requires an authenticated, email-confirmed Auth identity and inserts idempotently. A profile trigger is not attached to signup, so profile errors cannot silently prevent Auth registration.
- `update_onboarding(p_patch)` merges bounded JSON into only the signed-in profile. Onboarding metadata never controls roles.
- `join_club(p_code)` normalizes input, enforces ten attempts per fifteen minutes, checks the salted hash server-side and locks the singleton bootstrap row. Invalid attempts return `{ok:false,code,error}` instead of raising, so their rate-limit counters commit. Success returns `{ok:true,club_id,user_id,role,status}`. The frontend must check `ok`. Joining cannot directly set a role; only the verified designated owner during pending bootstrap gains admin. Removed members cannot rejoin through the same code.
- Membership insert/update/delete are not granted to browsers. `update_membership` checks current club admin membership, serializes role changes and prevents removing/demoting the last admin. `rotate_join_code` revokes the old code and stores a new bcrypt hash. `record_attendance` is admin-only; RSVP status does not prove attendance.
- All application tables have RLS. Private activities, laps, profile onboarding, health metadata and sync jobs are visible only to their owner. Club admin membership grants **no private health access**. `shared_activity_feed` exposes a limited projection only for activities explicitly shared to a current club, excluding heart rate, provenance and provider workout identifiers (it returns an opaque activity ID instead). `club_member_profiles` exposes only club roster IDs/names; club administrators can also see pending/removed members’ names to manage them. Removing a membership stops that runner’s previous club shares appearing in the club feed. Athletes retain access to their own RSVP/confirmed-attendance records after leaving, without access to former club session details or other members’ records.
- Service-only health RPCs read/write encrypted credential blobs in a non-API schema. OAuth state consumption is atomic, single-use and expiry checked. Browser roles cannot read ciphertext or OAuth state tables. Exact-origin duplicate groups are rebuilt after source corrections and deletions, preserving each source record while choosing exactly one surviving canonical workout. Full provider deletions run through the same athlete lock as ingestion. Every security-definer function fixes its search path and has explicit execution grants. See [Supabase RLS](https://supabase.com/docs/guides/database/postgres/row-level-security) and [function security](https://supabase.com/docs/guides/database/functions).
- Deleting an Auth identity cascades personal profiles, memberships, activities/laps, race results, RSVP/participation records, health connections, credentials, states and sync logs. Club sessions retain their content with `created_by=null`. Bootstrap remains complete even if its original owner later deletes their account; deletion never reopens privilege claiming.

## Verification status

Actual local results are recorded in `docs/verification.md` by the implementation report. Hosted migration, Auth hook, SMTP and live signup verification remain deployment tasks until performed against authorized fresh projects. No claim of hosted activation is implied by passing local tests.
