#!/usr/bin/env python3
"""Run in the user's Google Cloud Shell. Never prints or persists credentials.

The user explicitly authorizes Cloud Shell before running this reviewed client.
Paste only the narrow 15-minute setup token into its hidden input. The Google IAM
token is captured directly from gcloud and sent over TLS to the temporary RunTrack
bridge, where it is used only for Google subscriber create/list calls.
"""
from __future__ import annotations

import getpass
import json
import re
import subprocess
import sys
import time
import urllib.error
import urllib.request
import warnings

PROJECT_ID = "runtrack-health-cwdhym"
PROJECT_NUMBER = "701191762202"
PROJECT_REF = "cwdhymutbulafmtkfhqf"
BRIDGE_URL = f"https://{PROJECT_REF}.supabase.co/functions/v1/setup-health-bootstrap"


class ClientError(Exception):
    pass


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, request, response, code, message, headers, newurl):
        return None


def validate_nonce(value: str, now: int) -> str:
    match = re.fullmatch(r"rtboot1\.([0-9]{10})\.[A-Za-z0-9_-]{64}", value)
    if not match or not now < int(match[1]) <= now + 900:
        raise ClientError("The setup token is invalid or expired. Start a fresh operator setup session.")
    return value


def gcloud_output(arguments: list[str]) -> str:
    try:
        return subprocess.check_output(["gcloud", *arguments], stderr=subprocess.DEVNULL, timeout=60).decode().strip()
    except (OSError, UnicodeError, subprocess.SubprocessError):
        raise ClientError("Cloud Shell authorization is unavailable. Authorize Cloud Shell for the RunTrack project and retry.") from None


def create_subscriber(nonce: str, google_token: str) -> None:
    request = urllib.request.Request(BRIDGE_URL, method="POST", headers={
        "content-type": "application/json", "authorization": "Bearer " + nonce,
    }, data=json.dumps({"project_ref": PROJECT_REF, "action": "create-subscriber", "google_access_token": google_token}).encode())
    try:
        with urllib.request.build_opener(NoRedirect).open(request, timeout=90) as response:
            body = json.loads(response.read(16384))
        if (not isinstance(body, dict) or body.get("subscriber_active") is not True
                or body.get("webhook_verified") is not True
                or body.get("subscriber_name") != f"projects/{PROJECT_NUMBER}/subscribers/runtrackexercise"):
            raise ClientError("Google subscriber readiness could not be verified; response body was withheld.")
    except urllib.error.HTTPError as error:
        raise ClientError(f"Subscriber setup stopped (HTTP {error.code}); response body and credentials were withheld.") from None
    except (OSError, urllib.error.URLError, UnicodeError, ValueError, TimeoutError):
        raise ClientError("Subscriber setup request failed; response body and credentials were withheld.") from None


def main() -> int:
    try:
        if not sys.stdin.isatty():
            raise ClientError("Run this client interactively in Cloud Shell so the temporary setup token stays hidden.")
        # This is nonsecret project metadata, captured instead of displayed with
        # other gcloud output. No IAM service-account key is created or downloaded.
        number = gcloud_output(["projects", "describe", PROJECT_ID, "--format=value(projectNumber)"])
        if number != PROJECT_NUMBER:
            raise ClientError("Google project identity did not match RunTrack Production.")
        try:
            with warnings.catch_warnings():
                warnings.simplefilter("error", getpass.GetPassWarning)
                nonce = validate_nonce(getpass.getpass("Paste temporary RunTrack setup token (hidden): "), int(time.time()))
        except getpass.GetPassWarning:
            raise ClientError("A hidden terminal prompt is unavailable; the setup token was not read.") from None
        google_token = gcloud_output(["auth", "print-access-token", "--project=" + PROJECT_ID])
        if not re.fullmatch(r"[A-Za-z0-9._~+/=-]{20,4096}", google_token):
            raise ClientError("Cloud Shell did not provide a valid short-lived Google IAM token.")
        create_subscriber(nonce, google_token)
        print("Google exercise subscriber verified ACTIVE. The local operator will remove the temporary setup endpoint and token.")
        return 0
    except (ClientError, EOFError, KeyboardInterrupt) as error:
        print(str(error) if isinstance(error, ClientError) else "Setup interrupted; no credential was printed.", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
