"""Isolated validation fixtures only; no live API, credential store or email use."""
import contextlib
import copy
import importlib.util
import io
import json
from pathlib import Path
import tempfile
import unittest
from unittest import mock

SPEC = importlib.util.spec_from_file_location(
    "configure_providers", Path(__file__).resolve().parents[2] / "scripts" / "configure_providers.py",
)
provider = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(provider)

GOOGLE = {
    "web": {
        "project_id": "runtrack-health-test",
        "client_id": "123456-testonly.apps.googleusercontent.com",
        "client_secret": "testonly-secret-not-a-real-credential",
        "auth_uri": "https://accounts.google.com/o/oauth2/auth",
        "token_uri": "https://oauth2.googleapis.com/token",
        "redirect_uris": [provider.DEFAULT_REDIRECT],
    },
}
SMTP = {
    "smtp_host": "smtp-relay.brevo.com", "smtp_port": "587",
    "smtp_user": "testonly@smtp-brevo.com", "smtp_pass": "testonly-smtp-credential-not-real",
    "smtp_admin_email": "hello@tswebdev.co.uk", "smtp_sender_name": "RunTrack",
}


class ProviderValidationTests(unittest.TestCase):
    def test_google_validates_project_and_extracts_only_three_permitted_secrets(self):
        values = provider.validate_google(GOOGLE, "runtrack-health-test", provider.DEFAULT_REDIRECT)
        self.assertEqual(set(values), provider.GOOGLE_KEYS)
        self.assertNotIn("HEALTH_TOKEN_ENCRYPTION_KEY", values)
        self.assertNotIn("SUPABASE_SERVICE_ROLE_KEY", values)

    def test_service_accounts_and_desktop_clients_are_rejected(self):
        for value in [{"type": "service_account", "private_key": "testonly"},
                      {"installed": GOOGLE["web"]}, {"web": GOOGLE["web"], "extra": "testonly"}]:
            with self.subTest(value=list(value)):
                with self.assertRaises(provider.SetupError):
                    provider.validate_google(value, "runtrack-health-test", provider.DEFAULT_REDIRECT)

    def test_wrong_google_project_is_rejected(self):
        with self.assertRaises(provider.SetupError):
            provider.validate_google(GOOGLE, "another-test-project", provider.DEFAULT_REDIRECT)

    def test_missing_secret_and_untrusted_token_endpoint_are_rejected(self):
        for field, value in [("client_secret", ""), ("token_uri", "https://example.test/token")]:
            payload = copy.deepcopy(GOOGLE)
            payload["web"][field] = value
            with self.subTest(field=field), self.assertRaises(provider.SetupError):
                provider.validate_google(payload, "runtrack-health-test", provider.DEFAULT_REDIRECT)

    def test_extra_temporary_and_local_redirects_are_rejected(self):
        for uri in ["https://www.google.com", "http://localhost:3000", "https://example.test/callback"]:
            payload = copy.deepcopy(GOOGLE)
            payload["web"]["redirect_uris"].append(uri)
            with self.subTest(uri=uri), self.assertRaises(provider.SetupError):
                provider.validate_google(payload, "runtrack-health-test", provider.DEFAULT_REDIRECT)

    def test_owned_callback_must_match_download_exactly(self):
        callback = "https://runtrack.tswebdev.co.uk/oauth/google/callback"
        payload = copy.deepcopy(GOOGLE)
        payload["web"]["redirect_uris"] = [callback]
        self.assertEqual(provider.validate_google(payload, "runtrack-health-test", callback)
                         ["GOOGLE_HEALTH_REDIRECT_URI"], callback)
        with self.assertRaises(provider.SetupError):
            provider.validate_google(payload, "runtrack-health-test", provider.DEFAULT_REDIRECT)

    def test_smtp_uses_exact_login_without_guessing_account_email(self):
        self.assertEqual(provider.validate_smtp(SMTP)["smtp_user"], "testonly@smtp-brevo.com")
        alternative = dict(SMTP, smtp_user="fixture@example.test", smtp_port="465")
        self.assertEqual(provider.validate_smtp(alternative)["smtp_port"], "465")

    def test_smtp_rejects_api_key_wrong_host_and_header_injection(self):
        for field, value in [("smtp_pass", "xkeysib-testonly-invalid-api-credential"),
                             ("smtp_host", "example.test"),
                             ("smtp_user", "fixture@example.test\r\nBcc: someone@example.test"),
                             ("smtp_admin_email", "someone@example.test"), ("smtp_port", "25")]:
            payload = dict(SMTP, **{field: value})
            with self.subTest(field=field), self.assertRaises(provider.SetupError):
                provider.validate_smtp(payload)

    def test_arbitrary_auth_or_secret_fields_cannot_be_overposted(self):
        for field in ["mailer_autoconfirm", "disable_signup", "HEALTH_TOKEN_ENCRYPTION_KEY"]:
            payload = dict(SMTP, **{field: "testonly"})
            with self.subTest(field=field), self.assertRaises(provider.SetupError):
                provider.validate_smtp(payload)

    def test_credential_download_must_be_outside_repo_including_symlinks(self):
        with tempfile.TemporaryDirectory() as value:
            directory = Path(value).resolve()
            repo = directory / "repository"
            repo.mkdir()
            external = directory / "oauth.json"
            external.write_text(json.dumps(GOOGLE))
            inside = repo / "oauth.json"
            inside.symlink_to(external)
            with mock.patch.object(provider, "REPOSITORY", repo):
                self.assertEqual(set(provider.load_google(external, "runtrack-health-test",
                                                         provider.DEFAULT_REDIRECT)), provider.GOOGLE_KEYS)
                with self.assertRaises(provider.SetupError):
                    provider.load_google(inside, "runtrack-health-test", provider.DEFAULT_REDIRECT)

    def test_dry_run_never_reads_keychain_or_calls_network_and_redacts_credentials(self):
        output = io.StringIO()
        with mock.patch.object(provider.sys, "stdin", io.StringIO(json.dumps(SMTP))), \
                mock.patch.object(provider, "management_token", side_effect=AssertionError("Keychain read")), \
                mock.patch.object(provider, "management_request", side_effect=AssertionError("Network request")), \
                contextlib.redirect_stdout(output):
            result = provider.main(["--project-ref", provider.PROJECT_REF, "--smtp-stdin"])
        self.assertEqual(result, 0)
        self.assertNotIn(SMTP["smtp_pass"], output.getvalue())
        self.assertNotIn(SMTP["smtp_user"], output.getvalue())
        self.assertIn("Dry-run passed", output.getvalue())

    def test_wrong_target_is_denied_before_input_or_network(self):
        output = io.StringIO()
        with mock.patch.object(provider, "read_smtp", side_effect=AssertionError("Input consumed")), \
                mock.patch.object(provider, "management_token", side_effect=AssertionError("Keychain read")), \
                contextlib.redirect_stderr(output):
            result = provider.main(["--project-ref", "other-project", "--smtp-stdin", "--apply"])
        self.assertEqual(result, 1)

    def test_cli_rejects_another_google_cloud_project_before_file_or_network_access(self):
        output = io.StringIO()
        with mock.patch.object(provider, "load_google", side_effect=AssertionError("File read")), \
                mock.patch.object(provider, "management_token", side_effect=AssertionError("Keychain read")), \
                contextlib.redirect_stderr(output):
            result = provider.main(["--project-ref", provider.PROJECT_REF, "--google-json", "/testonly.json",
                                    "--google-project", "another-test-project", "--apply"])
        self.assertEqual(result, 1)

    def test_remote_error_body_is_not_logged(self):
        import urllib.error
        secret = "testonly-sensitive-remote-response"
        failure = urllib.error.HTTPError("https://api.supabase.com/", 400, "invalid", {},
                                        io.BytesIO(secret.encode()))
        opener = mock.Mock()
        opener.open.side_effect = failure
        with mock.patch.object(provider.urllib.request, "build_opener", return_value=opener):
            with self.assertRaises(provider.SetupError) as error:
                provider.management_request("testonly-token", "POST", "/v1/projects/testonly/secrets", [])
        self.assertNotIn(secret, str(error.exception))
        self.assertIn("HTTP 400", str(error.exception))


if __name__ == "__main__":
    unittest.main()
