#!/usr/bin/env python3
"""Temporarily bridge existing server secrets to Cron/Vault and Google Health.

Default: print a nonmutating plan. --apply is explicit and production-ref guarded.
No secret is printed, passed in command arguments, or written to a temporary file.
The temporary Edge function and 15-minute bootstrap token are always removed.
"""
from __future__ import annotations

import argparse
import getpass
import json
import os
from pathlib import Path
import re
import secrets
import shutil
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.request

from configure_providers import (
    NoRedirect, PROJECT_NAME, PROJECT_REF, REPOSITORY, SetupError,
    management_request, management_token, validate_target,
)

FUNCTION_NAME = "setup-health-bootstrap"
BOOTSTRAP_KEY = "RUNTRACK_HEALTH_BOOTSTRAP_TOKEN"
PROJECT_URL = f"https://{PROJECT_REF}.supabase.co"
MIGRATION = "202611120009"
SOURCE = REPOSITORY / "tools" / FUNCTION_NAME
CLI_VERSION = "3.1.0"
SUBSCRIBER_NAME = "projects/701191762202/subscribers/runtrackexercise"


def validate_google_token(raw: str) -> str:
    value = raw.strip()
    if not re.fullmatch(r"[A-Za-z0-9._~+/=-]{20,4096}", value):
        raise SetupError("Supply a short-lived Google IAM access token through hidden stdin; no value was logged.")
    return value


def read_google_token() -> str:
    try:
        raw = getpass.getpass("Short-lived Google IAM access token (hidden): ") if sys.stdin.isatty() else sys.stdin.read(4098)
    except (EOFError, OSError):
        raise SetupError("The hidden Google access-token input could not be read.") from None
    return validate_google_token(raw)


def make_nonce(now: int) -> str:
    return f"rtboot1.{now + 900}.{secrets.token_urlsafe(48)}"


def require_project(token: str) -> None:
    project = management_request(token, "GET", f"/v1/projects/{PROJECT_REF}")
    if (not isinstance(project, dict) or project.get("id") != PROJECT_REF
            or project.get("name") != PROJECT_NAME or project.get("status") != "ACTIVE_HEALTHY"):
        raise SetupError("RunTrack Production identity/health check failed; nothing was changed.")


def names_from_rows(rows: object) -> set[str]:
    if not isinstance(rows, list) or any(not isinstance(row, dict) for row in rows):
        raise SetupError("Expected safe metadata could not be validated; response body was withheld.")
    return {row.get("name", "") for row in rows}


def check_ready(token: str, scheduler: bool, subscriber: bool) -> None:
    prefix = f"/v1/projects/{PROJECT_REF}"
    names = names_from_rows(management_request(token, "GET", prefix + "/secrets"))
    if BOOTSTRAP_KEY in names:
        raise SetupError("A temporary bootstrap token already exists. Run --cleanup-only before retrying; it will not be replaced.")
    required = {"GOOGLE_HEALTH_CLIENT_ID", "GOOGLE_HEALTH_CLIENT_SECRET", "GOOGLE_HEALTH_REDIRECT_URI"}
    migrations = management_request(token, "GET", prefix + "/database/migrations")
    if not isinstance(migrations, list) or MIGRATION not in {
        row.get("version") for row in migrations if isinstance(row, dict)
    }:
        raise SetupError("Apply the reviewed migration 202611120009 before delivery activation; nothing was changed.")
    if scheduler:
        required.add("HEALTH_RECONCILE_SECRET")
    if subscriber:
        required.add("GOOGLE_HEALTH_WEBHOOK_SECRET")
    if not required <= names:
        raise SetupError("Required Google/reconciliation/webhook server-secret names are missing; nothing was changed.")
    functions = names_from_rows(management_request(token, "GET", prefix + "/functions"))
    if FUNCTION_NAME in functions:
        raise SetupError("A temporary bootstrap function already exists. Run --cleanup-only before retrying; it will not be replaced.")


def prepare_function(workdir: Path) -> None:
    target = workdir / "supabase" / "functions" / FUNCTION_NAME
    target.mkdir(parents=True)
    for name in ("index.ts", "bridge.ts"):
        shutil.copyfile(SOURCE / name, target / name)
    (workdir / "supabase" / "config.toml").write_text(
        'project_id = "runtrack-health-bootstrap"\n\n[functions.setup-health-bootstrap]\nverify_jwt = false\n',
        encoding="utf-8",
    )


def deploy_command(workdir: Path) -> list[str]:
    return ["npx", "--yes", f"supabase@{CLI_VERSION}", "functions", "deploy", FUNCTION_NAME,
            f"--remote={PROJECT_REF}", "--use-api", "--no-verify-jwt", "--yes", "--workdir", str(workdir)]


def deploy_bridge(token: str) -> None:
    # Only reviewed source/config enters this temporary directory. Authentication
    # stays in child environment memory and never appears in its command line.
    with tempfile.TemporaryDirectory(prefix="runtrack-health-bootstrap-") as path:
        workdir = Path(path)
        prepare_function(workdir)
        environment = dict(os.environ)
        environment["SUPABASE_ACCESS_TOKEN"] = token
        try:
            result = subprocess.run(deploy_command(workdir), env=environment, capture_output=True,
                                    timeout=180, check=False)
        except (OSError, subprocess.SubprocessError):
            raise SetupError("Temporary function deployment failed; command output was withheld.") from None
        if result.returncode != 0:
            raise SetupError("Temporary function deployment failed; command output was withheld.")


def bridge_request(nonce: str, action: str, google_token: str = "") -> dict:
    body = {"project_ref": PROJECT_REF, "action": action}
    if google_token:
        body["google_access_token"] = google_token
    request = urllib.request.Request(
        PROJECT_URL + "/functions/v1/" + FUNCTION_NAME,
        method="POST", data=json.dumps(body).encode(),
        headers={"content-type": "application/json", "authorization": "Bearer " + nonce},
    )
    try:
        with urllib.request.build_opener(NoRedirect).open(request, timeout=90) as response:
            result = json.loads(response.read(16384))
        if not isinstance(result, dict):
            raise ValueError()
        return result
    except urllib.error.HTTPError as error:
        raise SetupError(f"Temporary provisioning request failed (HTTP {error.code}); its body was withheld.") from None
    except (urllib.error.URLError, OSError, ValueError, UnicodeError, TimeoutError):
        raise SetupError("Temporary provisioning request failed; its body was withheld.") from None


def cleanup(token: str) -> None:
    prefix = f"/v1/projects/{PROJECT_REF}"
    failures = []
    try:
        functions = names_from_rows(management_request(token, "GET", prefix + "/functions"))
        if FUNCTION_NAME in functions:
            management_request(token, "DELETE", prefix + "/functions/" + FUNCTION_NAME)
    except SetupError:
        failures.append("temporary function")
    try:
        names = names_from_rows(management_request(token, "GET", prefix + "/secrets"))
        if BOOTSTRAP_KEY in names:
            management_request(token, "DELETE", prefix + "/secrets", [BOOTSTRAP_KEY])
    except SetupError:
        failures.append("temporary token")
    try:
        functions = names_from_rows(management_request(token, "GET", prefix + "/functions"))
        names = names_from_rows(management_request(token, "GET", prefix + "/secrets"))
        if FUNCTION_NAME in functions or BOOTSTRAP_KEY in names:
            failures.append("removal verification")
    except SetupError:
        failures.append("removal verification")
    if failures:
        raise SetupError("Cleanup needs attention: " + ", ".join(failures) +
                         ". The bootstrap token expires after 15 minutes. Run --cleanup-only.")
    print("Verified removal of temporary bootstrap function and token.")


def copy_nonce_to_clipboard(nonce: str) -> None:
    if sys.platform != "darwin":
        raise SetupError("Clipboard handoff requires macOS. Use hidden IAM token input on another system.")
    try:
        subprocess.run(["/usr/bin/pbcopy"], input=nonce.encode(), stdout=subprocess.DEVNULL,
                       stderr=subprocess.DEVNULL, timeout=10, check=True)
    except (OSError, subprocess.SubprocessError):
        raise SetupError("The temporary setup token could not be copied to the clipboard; no value was printed.") from None


def wait_for_cloud_shell(nonce: str) -> None:
    copy_nonce_to_clipboard(nonce)
    print("Copied the narrow 15-minute setup token to the macOS clipboard. Paste it only into the Cloud Shell client's hidden prompt.", flush=True)
    print("Waiting for Cloud Shell to verify the Google subscriber; no IAM credential is required on this computer.", flush=True)
    deadline = int(nonce.split(".")[1]) - 5
    while int(time.time()) < deadline:
        status = bridge_request(nonce, "status")
        if status.get("subscriber_active") is True:
            print("Verified ACTIVE Google exercise subscriber through this setup session.", flush=True)
            return
        time.sleep(5)
    raise SetupError("Cloud Shell setup did not complete before the temporary token expired. No existing credential was replaced.")


def activate(token: str, scheduler: bool, subscriber: bool, google_token: str, cloud_shell: bool = False) -> None:
    check_ready(token, scheduler, subscriber)
    nonce = make_nonce(int(time.time()))
    try:
        management_request(token, "POST", f"/v1/projects/{PROJECT_REF}/secrets",
                           [{"name": BOOTSTRAP_KEY, "value": nonce}])
        deploy_bridge(token)
        probe = bridge_request(nonce, "status")
        expected = ["project_verified", "google_oauth_configured"]
        if scheduler:
            expected.append("scheduler_secret_present")
        if subscriber:
            expected.append("webhook_secret_present")
        if any(probe.get(name) is not True for name in expected):
            raise SetupError("Temporary runtime configuration check failed; response body was withheld.")
        if scheduler:
            installed = bridge_request(nonce, "install-scheduler")
            if (installed.get("scheduler_enabled") is not True or installed.get("vault_secret_present") is not True
                    or installed.get("schedule") != "* * * * *"):
                raise SetupError("Scheduler activation could not be verified.")
            print("Enabled one-minute health reconciliation using the existing secret copied directly into Vault.")
        if subscriber and cloud_shell:
            wait_for_cloud_shell(nonce)
        elif subscriber:
            installed = bridge_request(nonce, "create-subscriber", google_token)
            if (installed.get("subscriber_active") is not True or installed.get("webhook_verified") is not True
                    or installed.get("subscriber_name") != SUBSCRIBER_NAME):
                raise SetupError("Google subscriber activation could not be verified.")
            print("Verified ACTIVE Google exercise subscriber, authenticated 201 and unauthenticated 401/403 webhook checks.")
    finally:
        # If a later step fails, an already activated schedule/subscriber remains
        # valid. Never undo it or rotate its existing secret while cleaning up.
        cleanup(token)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--project-ref", required=True)
    parser.add_argument("--scheduler", action="store_true")
    parser.add_argument("--subscriber", action="store_true")
    parser.add_argument("--google-token-stdin", action="store_true")
    parser.add_argument("--cloud-shell", action="store_true", help="Wait for the Cloud Shell client; IAM token stays in Cloud Shell")
    parser.add_argument("--copy-bootstrap-to-clipboard", action="store_true", help="Explicitly authorize copying only the narrow 15-minute setup token")
    parser.add_argument("--cleanup-only", action="store_true")
    parser.add_argument("--apply", action="store_true")
    args = parser.parse_args(argv)
    try:
        validate_target(args.project_ref)
        if args.cleanup_only:
            if args.scheduler or args.subscriber or args.google_token_stdin or args.cloud_shell or args.copy_bootstrap_to_clipboard:
                raise SetupError("Use --cleanup-only independently of activation options.")
        elif not args.scheduler and not args.subscriber:
            raise SetupError("Choose --scheduler, --subscriber, or --cleanup-only.")
        if args.cloud_shell != args.copy_bootstrap_to_clipboard:
            raise SetupError("Cloud Shell mode requires explicit --copy-bootstrap-to-clipboard.")
        if args.subscriber != (args.google_token_stdin or args.cloud_shell) or (args.google_token_stdin and args.cloud_shell):
            raise SetupError("Subscriber activation requires exactly one of hidden IAM stdin or Cloud Shell mode; never put a token in an argument.")
        print(f"Target: {PROJECT_NAME} ({PROJECT_REF})")
        if not args.apply:
            print("Dry run: no network, Keychain access, token input, clipboard access, deployment or remote changes.")
            if args.scheduler:
                print("Plan: require migration009, reuse existing reconciliation secret in Vault, enable one-minute Cron.")
            if args.subscriber:
                if args.cloud_shell:
                    print("Plan: explicitly copy a narrow 15-minute setup token to clipboard; Cloud Shell captures its own short-lived IAM token in memory.")
                else:
                    print("Plan: accept a short-lived IAM token through hidden stdin, reuse existing webhook secret, verify ACTIVE subscriber.")
            print("Temporary bridge/token are removed after apply; existing provider/encryption/webhook/reconciliation secrets are untouched.")
            return 0
        google_token = read_google_token() if args.google_token_stdin else ""
        token = management_token()
        require_project(token)
        if args.cleanup_only:
            cleanup(token)
        else:
            activate(token, args.scheduler, args.subscriber, google_token, args.cloud_shell)
        return 0
    except SetupError as error:
        print("Setup stopped: " + str(error), file=sys.stderr)
        return 1
    except KeyboardInterrupt:
        print("Setup interrupted. If provisioning began, run --cleanup-only --apply; the token expires after 15 minutes.", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
