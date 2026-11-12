#!/usr/bin/env python3
"""Validate and optionally install RunTrack provider credentials without logging them.

Dry-run is the default and performs no network/Keychain access. OAuth downloads
must stay outside the repository. SMTP configuration is read only from hidden
interactive input or a pipe; credential values are never command arguments.
"""
from __future__ import annotations

import argparse
import base64
import getpass
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import urllib.error
import urllib.parse
import urllib.request

PROJECT_REF = "cwdhymutbulafmtkfhqf"
PROJECT_NAME = "RunTrack Production"
GOOGLE_PROJECT_ID = "runtrack-health-cwdhym"
REPOSITORY = Path(__file__).resolve().parents[1]
DEFAULT_REDIRECT = f"https://{PROJECT_REF}.supabase.co/functions/v1/health-callback"
ALLOWED_REDIRECTS = {
    DEFAULT_REDIRECT,
    "https://runtrack.tswebdev.co.uk/oauth/google/callback",
}
GOOGLE_KEYS = {
    "GOOGLE_HEALTH_CLIENT_ID", "GOOGLE_HEALTH_CLIENT_SECRET", "GOOGLE_HEALTH_REDIRECT_URI",
}
SMTP_KEYS = {
    "smtp_host", "smtp_port", "smtp_user", "smtp_pass", "smtp_admin_email", "smtp_sender_name",
}
MAX_INPUT = 32768


class SetupError(Exception):
    """Messages must contain no credential or remote response body."""


def validate_target(project_ref: str) -> None:
    if project_ref != PROJECT_REF:
        raise SetupError("Refusing a target other than the dedicated RunTrack Production project.")


def validate_google(data: object, expected_project: str, redirect_uri: str) -> dict[str, str]:
    if redirect_uri not in ALLOWED_REDIRECTS:
        raise SetupError("The selected redirect is not an approved RunTrack callback.")
    if not isinstance(data, dict) or set(data) != {"web"} or not isinstance(data["web"], dict):
        raise SetupError("Use a Google Web application OAuth download, not installed-app or service-account credentials.")
    web = data["web"]
    if not re.fullmatch(r"[a-z][a-z0-9-]{4,28}[a-z0-9]", expected_project or ""):
        raise SetupError("Supply the exact Google Cloud project ID shown in the Console.")
    if web.get("project_id") != expected_project:
        raise SetupError("The OAuth download belongs to a different Google Cloud project.")
    if web.get("auth_uri") not in {
        "https://accounts.google.com/o/oauth2/auth", "https://accounts.google.com/o/oauth2/v2/auth",
    } or web.get("token_uri") != "https://oauth2.googleapis.com/token":
        raise SetupError("The OAuth download has unexpected Google authorization/token endpoints.")
    client_id, client_secret = web.get("client_id"), web.get("client_secret")
    if not isinstance(client_id, str) or not re.fullmatch(r"[A-Za-z0-9._-]+\.apps\.googleusercontent\.com", client_id):
        raise SetupError("The OAuth client ID is invalid.")
    if not isinstance(client_secret, str) or not re.fullmatch(r"[A-Za-z0-9_-]{16,256}", client_secret):
        raise SetupError("The OAuth client secret is missing or malformed.")
    if web.get("redirect_uris") != [redirect_uri]:
        raise SetupError("The production Web client must have exactly the selected RunTrack callback, with no temporary or local redirects.")
    return {
        "GOOGLE_HEALTH_CLIENT_ID": client_id,
        "GOOGLE_HEALTH_CLIENT_SECRET": client_secret,
        "GOOGLE_HEALTH_REDIRECT_URI": redirect_uri,
    }


def load_google(path: Path, expected_project: str, redirect_uri: str) -> dict[str, str]:
    try:
        declared = Path(os.path.abspath(path.expanduser()))
        resolved = path.expanduser().resolve(strict=True)
        if declared.is_relative_to(REPOSITORY) or resolved.is_relative_to(REPOSITORY):
            raise SetupError("Keep the OAuth credentials download outside the repository.")
        if not resolved.is_file() or resolved.stat().st_size > MAX_INPUT:
            raise SetupError("The OAuth download must be a small JSON file outside the repository.")
        data = json.loads(resolved.read_text(encoding="utf-8"))
    except (OSError, ValueError, UnicodeError):
        raise SetupError("The OAuth credentials file could not be read as valid JSON.") from None
    return validate_google(data, expected_project, redirect_uri)


def validate_smtp(data: object) -> dict[str, str]:
    if not isinstance(data, dict) or set(data) != SMTP_KEYS:
        raise SetupError("SMTP JSON must contain exactly the six documented SMTP fields.")
    if any(not isinstance(value, str) or not value or value != value.strip() for value in data.values()):
        raise SetupError("Every SMTP field must be a nonempty string without surrounding whitespace.")
    if any("\r" in value or "\n" in value for value in data.values()):
        raise SetupError("SMTP fields cannot contain line breaks.")
    if data["smtp_host"] != "smtp-relay.brevo.com" or data["smtp_port"] not in {"587", "465"}:
        raise SetupError("Use the official Brevo SMTP host and TLS-capable port 587 or 465.")
    if data["smtp_admin_email"].lower() != "hello@tswebdev.co.uk":
        raise SetupError("Use the confirmed RunTrack sender hello@tswebdev.co.uk after verifying it in Brevo.")
    if not re.fullmatch(r"[^\s@]+@[^\s@]+\.[^\s@]+", data["smtp_user"]):
        raise SetupError("Use the exact SMTP Login address displayed in Brevo.")
    if not 16 <= len(data["smtp_pass"]) <= 512 or data["smtp_pass"].lower().startswith("xkeysib-"):
        raise SetupError("Supply a Brevo SMTP key, not a Brevo API key or account password.")
    if data["smtp_sender_name"] != "RunTrack" or len(data["smtp_user"]) > 254:
        raise SetupError("The sender name must be RunTrack and the SMTP Login must be a valid-length address.")
    return dict(data)


def read_smtp() -> dict[str, str]:
    try:
        if sys.stdin.isatty():
            raw = getpass.getpass("SMTP JSON (input hidden; do not paste into chat): ")
        else:
            raw = sys.stdin.read(MAX_INPUT + 1)
        if len(raw) > MAX_INPUT:
            raise SetupError("SMTP JSON is too large.")
        return validate_smtp(json.loads(raw))
    except (ValueError, UnicodeError, OSError, EOFError):
        raise SetupError("SMTP input must be valid JSON; no input value has been logged.") from None


def management_token() -> str:
    token = os.environ.get("SUPABASE_ACCESS_TOKEN", "").strip()
    if not token and sys.platform == "darwin":
        try:
            stored = subprocess.check_output(
                ["/usr/bin/security", "find-generic-password", "-s", "Supabase CLI", "-a", "supabase", "-w"],
                stderr=subprocess.DEVNULL,
            ).decode().strip()
            token = (base64.b64decode(stored.removeprefix("go-keyring-base64:"), validate=True).decode()
                     if stored.startswith("go-keyring-base64:") else stored)
        except (OSError, subprocess.SubprocessError, ValueError, UnicodeError):
            raise SetupError("Supabase CLI authentication is unavailable. Sign in to the official CLI first.") from None
    if not token or any(char.isspace() for char in token):
        raise SetupError("Supabase management authentication is unavailable.")
    return token


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, request, response, code, message, headers, newurl):
        return None


def management_request(token: str, method: str, path: str, data: object = None) -> object:
    # Paths are generated only from hardcoded endpoints and the guarded ref.
    request = urllib.request.Request(
        "https://api.supabase.com" + path,
        data=None if data is None else json.dumps(data).encode(),
        method=method,
        headers={"Authorization": "Bearer " + token, "Content-Type": "application/json"},
    )
    try:
        with urllib.request.build_opener(NoRedirect).open(request, timeout=30) as response:
            raw = response.read(2 * 1024 * 1024)
            return json.loads(raw) if raw else None
    except urllib.error.HTTPError as error:
        # Never print a response body: remote validators can echo submitted values.
        raise SetupError(f"Supabase management request failed (HTTP {error.code}); its body was withheld.") from None
    except (urllib.error.URLError, TimeoutError, ValueError, UnicodeError, OSError):
        raise SetupError("Supabase management request failed; no credential or response body was logged.") from None


def apply_configuration(google: dict[str, str], smtp: dict[str, str], *, replace_google: bool,
                        email_limit: int | None) -> None:
    token = management_token()
    prefix = f"/v1/projects/{PROJECT_REF}"
    project = management_request(token, "GET", prefix)
    if not isinstance(project, dict) or project.get("id") != PROJECT_REF or project.get("name") != PROJECT_NAME:
        raise SetupError("The live project identity did not match RunTrack Production; nothing was written.")
    if project.get("status") != "ACTIVE_HEALTHY":
        raise SetupError("RunTrack Production is not healthy; nothing was written.")
    if google:
        existing = management_request(token, "GET", prefix + "/secrets")
        if not isinstance(existing, list):
            raise SetupError("Could not validate existing server-secret metadata; nothing was written.")
        names = {row.get("name") for row in existing if isinstance(row, dict)}
        if names & {"GOOGLE_HEALTH_CLIENT_ID", "GOOGLE_HEALTH_CLIENT_SECRET"} and not replace_google:
            raise SetupError("Google OAuth credentials already exist. An intentional replacement needs --replace-existing-google.")
    if smtp:
        auth = management_request(token, "GET", prefix + "/config/auth")
        if not isinstance(auth, dict) or auth.get("mailer_autoconfirm") is not False:
            raise SetupError("Required email confirmation could not be verified; nothing was written.")
    if google:
        if set(google) != GOOGLE_KEYS:
            raise SetupError("Unexpected server-secret names; nothing was written.")
        management_request(token, "POST", prefix + "/secrets",
                           [{"name": name, "value": value} for name, value in google.items()])
        metadata = management_request(token, "GET", prefix + "/secrets")
        if not isinstance(metadata, list) or not GOOGLE_KEYS <= {
            item.get("name") for item in metadata if isinstance(item, dict)
        }:
            raise SetupError("Google secrets were submitted but metadata verification failed; check the dashboard before retrying.")
        print("Applied Google OAuth client ID, client secret and callback URI; server-secret names verified.")
    if smtp:
        patch: dict[str, str | int] = dict(smtp)
        if email_limit is not None:
            patch["rate_limit_email_sent"] = email_limit
        management_request(token, "PATCH", prefix + "/config/auth", patch)
        auth = management_request(token, "GET", prefix + "/config/auth")
        fields = SMTP_KEYS - {"smtp_pass"}
        if (not isinstance(auth, dict) or auth.get("mailer_autoconfirm") is not False
                or any(str(auth.get(name)) != smtp[name] for name in fields)):
            raise SetupError("SMTP settings were submitted but safe readback failed; inspect the dashboard before retrying.")
        print("Applied Brevo SMTP settings; sender/host/login readback and required email confirmation verified.")
        print("Actual email delivery still requires a deliberate verification-email test; none was sent.")


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--project-ref", required=True, help="Must name the dedicated RunTrack Production project")
    parser.add_argument("--google-json", type=Path, help="Downloaded Web OAuth JSON outside the repository")
    parser.add_argument("--google-project", help="Exact Google Cloud project ID to match against the download")
    parser.add_argument("--redirect-uri", default=DEFAULT_REDIRECT)
    parser.add_argument("--smtp-stdin", action="store_true", help="Read SMTP JSON from hidden terminal input or a pipe")
    parser.add_argument("--email-limit", type=int, help="Explicit optional hourly Auth email limit, 1–300")
    parser.add_argument("--replace-existing-google", action="store_true")
    parser.add_argument("--apply", action="store_true", help="Write the reviewed values to the guarded production project")
    args = parser.parse_args(argv)
    try:
        validate_target(args.project_ref)
        if not args.google_json and not args.smtp_stdin:
            raise SetupError("Supply a Google OAuth download or SMTP hidden input to validate.")
        if args.google_json and not args.google_project:
            raise SetupError("Supply --google-project to guard the downloaded client's project identity.")
        if args.google_json and args.google_project != GOOGLE_PROJECT_ID:
            raise SetupError("Refusing OAuth credentials outside the dedicated RunTrack Google Cloud production project.")
        if args.email_limit is not None and (not args.smtp_stdin or not 1 <= args.email_limit <= 300):
            raise SetupError("An explicit hourly email limit requires SMTP input and must be between 1 and 300.")
        google = load_google(args.google_json, args.google_project, args.redirect_uri) if args.google_json else {}
        smtp = read_smtp() if args.smtp_stdin else {}
        print(f"Target: {PROJECT_NAME} ({PROJECT_REF})")
        if google:
            print(f"Google project: {args.google_project}; Web OAuth download and exact callback validated.")
            print(f"Callback: {args.redirect_uri}")
            print("Secret changes: GOOGLE_HEALTH_CLIENT_ID, GOOGLE_HEALTH_CLIENT_SECRET, GOOGLE_HEALTH_REDIRECT_URI [values withheld]")
        if smtp:
            print("SMTP: Brevo, requested sender hello@tswebdev.co.uk (verify it in Brevo first), RunTrack sender name [login/key withheld]")
            if args.email_limit is not None:
                print(f"Requested hourly Auth email limit: {args.email_limit}")
        if args.apply:
            apply_configuration(google, smtp, replace_google=args.replace_existing_google, email_limit=args.email_limit)
        else:
            print("Dry-run passed. No network, Keychain access, emails, secrets or server settings were changed.")
        return 0
    except SetupError as error:
        print("Configuration stopped: " + str(error), file=sys.stderr)
        return 1


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except KeyboardInterrupt:
        print("Stopped. Review completed steps before retrying.", file=sys.stderr)
        raise SystemExit(130) from None
