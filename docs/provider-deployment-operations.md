# Production provider activation

These operator tools target only `RunTrack Production`, Supabase project
`cwdhymutbulafmtkfhqf`, Google project `runtrack-health-cwdhym` / `701191762202`.
They do not create paid infrastructure or Google service-account keys. Credential
creation and installation are documented in [provider-credentials.md](provider-credentials.md).

## Deploy the reviewed application changes

Run from the repository root with the existing Supabase CLI authentication. CLI
3.1 uses explicit `--remote=REF`; do not rely on a previously linked project.
The `--skip-vault` flag prevents config-file Vault updates during migration push.

```sh
npx --yes supabase@3.1.0 db push --remote=cwdhymutbulafmtkfhqf --dry-run --skip-vault
```

Review that only migrations `006` consent, `007` webhook batches, `008` consent
locking and `009` schedule provisioning are pending. If the expected list differs,
resolve the difference before applying. Then:

```sh
npx --yes supabase@3.1.0 db push --remote=cwdhymutbulafmtkfhqf --skip-vault --yes
npx --yes supabase@3.1.0 functions deploy delete-account export-data health-connect health-callback health-disconnect health-sync health-webhook --remote=cwdhymutbulafmtkfhqf --use-api --no-verify-jwt --yes
```

Migration009 creates restricted provisioning functions and an RLS-protected table
holding a setup fingerprint and verification time. It activates no job and
contains no credential. The temporary helper lives under `tools/` and is excluded
from the normal function deployment command.

Install the reviewed Web OAuth JSON and dedicated Brevo SMTP configuration with
`scripts/configure_providers.py` before activating delivery. Dry-run is the default;
only `--apply` writes configuration. Existing encryption, webhook and reconciliation
secrets must remain unchanged.

## Activate the scheduler and Google subscriber

First review the nonmutating plan:

```sh
python3 scripts/setup_health_delivery.py --project-ref cwdhymutbulafmtkfhqf --scheduler --subscriber --cloud-shell --copy-bootstrap-to-clipboard
```

For the chosen Cloud Shell handoff, the user explicitly authorizes Cloud Shell for
the RunTrack project and the transfer of its short-lived Google IAM access token to
the temporary Supabase bridge. The token is used only for subscriber create/list
requests. No persistent Google IAM credential is created. The operator explicitly
authorizes replacing the macOS clipboard with a narrow 15-minute setup token using
`--copy-bootstrap-to-clipboard`:

```sh
python3 scripts/setup_health_delivery.py --project-ref cwdhymutbulafmtkfhqf --scheduler --subscriber --cloud-shell --copy-bootstrap-to-clipboard --apply
```

This process verifies the production project and required secret names, creates a
random setup token, deploys only the temporary helper, copies the existing
reconciliation secret directly from Edge memory into Vault and enables a one-minute
Cron job. It then copies the setup token to the clipboard and waits. The Google
webhook and reconciliation secrets never leave Supabase except for the webhook
bearer being sent directly to Google's subscriber API.

In Cloud Shell, download **the reviewed `cloud_shell_client.py` from an exact
public Git commit**, then run it interactively. The operator supplies that immutable
source URL after committing and reviewing the code:

```sh
curl --fail --proto '=https' --tlsv1.2 --location 'REVIEWED_IMMUTABLE_RAW_GITHUB_URL/tools/setup-health-bootstrap/cloud_shell_client.py' --output /tmp/runtrack-health-client.py
python3 /tmp/runtrack-health-client.py
```

The user pastes the temporary setup token into the hidden prompt. The client checks
the exact Google project number, captures `gcloud`'s IAM access token directly in
memory and sends it to the protected bridge over TLS. It never prints the IAM
token, setup token, webhook bearer or provider response body. Google IAM needs
`health.subscribers.create` and `health.subscribers.list`, with the
`https://www.googleapis.com/auth/cloud-platform` OAuth scope.

The bridge first checks authenticated webhook verification returns 201 and
unauthenticated verification returns 401/403. It creates exercise-only automatic
subscriber `projects/701191762202/subscribers/runtrackexercise` and confirms the
actual resource becomes `ACTIVE`. A pre-existing subscriber 409 fails safely for
operator review; the tool cannot read Google's input-only secret and does not
silently replace an unknown registration.

The local process polls nonsecret, session-specific readiness and always attempts
to remove the temporary Edge function and bootstrap secret. The bridge rejects an
expired token using its server UTC clock. Clipboard contents become unusable after
cleanup or expiry. A failed subscriber step leaves an already enabled scheduler
working; it does not rotate or undo existing credentials.

If `gcloud` is already available on the operator's computer, the alternative mode
pipes its captured token directly to the local installer without terminal output:

```sh
gcloud auth print-access-token --project=runtrack-health-cwdhym | python3 scripts/setup_health_delivery.py --project-ref cwdhymutbulafmtkfhqf --subscriber --google-token-stdin --apply
```

Do not run the token-producing command separately or paste a token into chat,
shell arguments, issue comments or repository files.

## Cleanup and verification

If setup was interrupted, use the guarded cleanup command. It removes only
`setup-health-bootstrap` and `RUNTRACK_HEALTH_BOOTSTRAP_TOKEN`, then verifies their
absence. It leaves the actual scheduler, subscriber and existing secrets intact.

```sh
python3 scripts/setup_health_delivery.py --project-ref cwdhymutbulafmtkfhqf --cleanup-only --apply
```

Verify the one-minute Cron job by its name `runtrack-health-reconcile`, active flag
and recent success status. Inspect only job status and safe counters, never Vault
plaintext or `pg_net` request headers. Supabase documents that `pg_net` temporarily
holds decrypted request headers in its internal queue; restrict database login and
schema access accordingly. The job uses the narrow reconciliation bearer, never a
Supabase service-role key, and waits up to 95 seconds for the bounded worker.

A one-minute cadence alone does not establish capacity. Reconciliation throughput
depends on the worker's bounded batch size, provider latency, leases and project
quota. Assess a 100-athlete club against the actual batch budget and observed job
successes; do not claim near-real-time service from one connection per run.

Finally verify a real user's explicit health consent, Google authorization,
exercise import, manual sync and disconnect. Verify ordinary athlete email
delivery separately after SMTP sender verification. Configuration readback and
subscriber activation do not substitute for those end-to-end checks.

References: [Supabase scheduling](https://supabase.com/docs/guides/functions/schedule-functions),
[Vault](https://supabase.com/docs/guides/database/vault),
[Google subscriber creation](https://developers.google.com/health/reference/rest/v4/projects.subscribers/create),
[subscriber listing](https://developers.google.com/health/reference/rest/v4/projects.subscribers/list).
