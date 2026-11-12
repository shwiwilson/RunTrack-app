# Installing provider credentials securely

This is an operator runbook, not evidence that Google OAuth, SMTP delivery or a
subscriber is configured. The current live project is **RunTrack Production**,
`cwdhymutbulafmtkfhqf`. The installer below is deliberately restricted to that
project and never creates an athlete, sends an email or downloads health data.

## Google Web OAuth client

Use the dedicated RunTrack Google Cloud project `runtrack-health-cwdhym`
(project number `701191762202`). Enable **Google Health API**
(`health.googleapis.com`), configure its External consent screen, and request
only `https://www.googleapis.com/auth/googlehealth.activity_and_fitness.readonly`.
Use a **Web application** client for the confidential server authorization-code
flow, rather than a service-account key or desktop client.

The current deployed callback is:

```text
https://cwdhymutbulafmtkfhqf.supabase.co/functions/v1/health-callback
```

If an owned-domain callback is configured, the installer also permits the exact
`https://runtrack.tswebdev.co.uk/oauth/google/callback` endpoint. Do not select
that option until its DNS/TLS/proxy route is genuinely deployed and verified.
The Google client's redirect list must contain only the one selected callback;
temporary `google.com` and localhost redirects are rejected for production.
JavaScript origins are not required for this server flow.

Google now shows the client secret only immediately after creation. The account
owner should complete credential creation, then download the JSON to a private
location **outside this repository**, such as Downloads or a password manager's
secure storage. Never paste the secret into chat, Flutter defines, Git, shell
arguments or a public page. [Google's Web OAuth instructions](https://developers.google.com/identity/protocols/oauth2/web-server)

Validate the downloaded file first; substitute its actual path and exact Google
Cloud project ID (the project ID is not the project number):

```sh
python3 scripts/configure_providers.py \
  --project-ref cwdhymutbulafmtkfhqf \
  --google-json /ABSOLUTE/PRIVATE/PATH/client_secret.json \
  --google-project runtrack-health-cwdhym
```

The default dry-run performs **no network or Keychain access**. It checks that
the download belongs to the stated project, is a Google Web client, has the
expected Google endpoints and exact callback, and has usable credential fields.
Output contains metadata and secret names only, never credential values.

After reviewing that result, repeat the same command with `--apply`. The helper
uses the existing Supabase CLI management login from the process environment or
macOS Keychain, verifies the live project identity/health, and writes only:

```text
GOOGLE_HEALTH_CLIENT_ID
GOOGLE_HEALTH_CLIENT_SECRET
GOOGLE_HEALTH_REDIRECT_URI
```

Existing Google ID/secret fields require the deliberate
`--replace-existing-google` flag. The helper never rotates the existing token
encryption key, webhook secret or reconciliation secret. In particular, do not
replace `HEALTH_TOKEN_ENCRYPTION_KEY` while encrypted provider tokens exist.
Supabase's server-secret API returns metadata rather than the old plaintext;
keep an operator-controlled secure backup of credentials when they are issued.

These are the official management endpoints used:
[bulk server-secret creation](https://supabase.com/docs/reference/api/v1-bulk-create-secrets)
and [Auth configuration updates](https://supabase.com/docs/reference/api/v1-update-auth-service-config).
The helper uses HTTPS, refuses redirects and suppresses response bodies that
could echo submitted secrets. It writes no credential file or shell argument.

## Existing Brevo sender

Public DNS already contains Brevo authentication records for `tswebdev.co.uk`;
this does not prove that its current Brevo account or sender is active. Check
the existing account's sender/domain verification before enabling SMTP.

Open [Brevo SMTP settings](https://app.brevo.com/settings/keys/smtp) and use the
displayed **SMTP Login**, which can differ from the account sign-in email.
Supabase needs a **Brevo SMTP key**, not a Brevo API key or account password.
Use a dedicated RunTrack SMTP key without revealing, reusing or rotating keys
used by other business services. The account owner should perform credential creation.
[Brevo's SMTP credential guidance](https://help.brevo.com/hc/en-us/articles/7924908994450-Send-transactional-emails-using-Brevo-SMTP)

The reviewed configuration for the confirmed RunTrack contact is:

| Setting | Value |
| --- | --- |
| Sender address | `hello@tswebdev.co.uk`, after confirming it is verified in Brevo |
| Sender name | `RunTrack` |
| Host | `smtp-relay.brevo.com` |
| Port | `587` with STARTTLS, or `465` with TLS |
| User | Exact SMTP Login shown in Brevo |
| Password | SMTP key held privately by the operator |

The operator may enter these directly in the protected
[Supabase SMTP settings](https://supabase.com/dashboard/project/cwdhymutbulafmtkfhqf/auth/smtp).
For scripted installation, run the helper in a private terminal with
`--smtp-stdin`. Interactive input is hidden; otherwise it accepts a pipe from a
secure credential source. The required JSON shape is shown with placeholders:

```json
{
  "smtp_host": "smtp-relay.brevo.com",
  "smtp_port": "587",
  "smtp_user": "EXACT_SMTP_LOGIN",
  "smtp_pass": "PRIVATE_BREVO_SMTP_KEY",
  "smtp_admin_email": "hello@tswebdev.co.uk",
  "smtp_sender_name": "RunTrack"
}
```

```sh
python3 scripts/configure_providers.py \
  --project-ref cwdhymutbulafmtkfhqf --smtp-stdin
```

Repeat with `--apply` after validation. An optional explicit `--email-limit 30`
sets the hourly Auth email limit; omit it to preserve the existing setting.
Choose a limit consistent with the actual Brevo plan. The script changes no
billing, DNS, account roles, email confirmation, bootstrap or Auth-hook settings.
It requires email confirmation to be enabled before writing SMTP fields and
checks that this remains enabled afterward.

Google-secret and SMTP updates are separate API operations, so a combined apply
is not transactional. Completed steps are reported without their values. If a
later step fails, inspect the protected dashboard before retrying. No failure is
reported as a successful provider connection or email delivery.

## Verify actual behaviour

1. SMTP: intentionally request an Auth email for an authorized real account,
   then verify arrival and Brevo's transactional log. Do not create a demo
   athlete in production. Configuration readback alone does not prove delivery.
2. Health: the real runner consents in RunTrack, completes Google OAuth, and the
   server verifies the linked Health identity before fetching real workouts.
   A linked account may have no available workouts. Check actual sync state;
   a Google login or saved credential is not a successful activity import.
3. Google Testing mode requires explicit test users; authorizations and refresh
   tokens expire after seven days. Public OAuth availability and Google Health
   review are separate steps, as described in [health.md](health.md).
4. Subscriber: after the receiver is ready, create
   `POST https://health.googleapis.com/v4/projects/701191762202/subscribers?subscriberId=runtrackexercise`.
   Use the numeric Cloud project number, `exercise`/`AUTOMATIC`, the verified
   `health-webhook` endpoint, and the existing server-held bearer secret. The
   authorized verification request must return **201**, while the unauthorized
   challenge must be rejected. Do not activate paid infrastructure to work
   around a missing IAM role or provider approval.
5. Reconciliation: configure a trusted scheduler to call `health-sync` using
   the existing protected reconciliation secret. Start only after OAuth and
   real ingestion are verified. Do not assume the old secret can be retrieved
   through the secret-metadata API. If installing Supabase Cron/Vault, transfer
   the existing value through a protected server-side path; never paste it in
   a committed SQL file or rotate it silently. [Supabase scheduling guide](https://supabase.com/docs/guides/functions/schedule-functions)

No Google subscriber, schedule, real account grant or email test is activated by
the credential installer itself.

Run its isolated validation/security tests with:

```sh
python3 -m unittest discover -s test/python -v
```
