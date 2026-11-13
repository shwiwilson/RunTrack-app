import contextlib
import importlib.util
import io
from pathlib import Path
import sys
import tempfile
import unittest

SCRIPTS = Path(__file__).resolve().parents[2] / "scripts"
sys.path.insert(0, str(SCRIPTS))
spec = importlib.util.spec_from_file_location("setup_health_delivery", SCRIPTS / "setup_health_delivery.py")
setup = importlib.util.module_from_spec(spec)
spec.loader.exec_module(setup)


class SetupDeliveryValidationTests(unittest.TestCase):
    def test_google_token_validation_rejects_malformed_values(self):
        self.assertEqual(setup.validate_google_token("ya29.fixtureGoogleTokenForUnitTest\n"), "ya29.fixtureGoogleTokenForUnitTest")
        for raw in ("short", "x" * 4097, "x" * 25 + " other", "{\"token\":\"fixture\"}"):
            with self.subTest(raw_length=len(raw)), self.assertRaises(setup.SetupError):
                setup.validate_google_token(raw)

    def test_nonce_is_random_expiring_and_not_a_persistent_provider_secret(self):
        first = setup.make_nonce(1800000000)
        second = setup.make_nonce(1800000000)
        self.assertRegex(first, r"^rtboot1\.1800000900\.[A-Za-z0-9_-]{64}$")
        self.assertNotEqual(first, second)

    def test_deployment_directory_contains_source_and_fixed_config_only(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            setup.prepare_function(root)
            files = sorted(str(path.relative_to(root)) for path in root.rglob("*") if path.is_file())
            self.assertEqual(files, ["supabase/config.toml", "supabase/functions/setup-health-bootstrap/bridge.ts", "supabase/functions/setup-health-bootstrap/index.ts"])
            config = (root / "supabase/config.toml").read_text()
            self.assertIn("verify_jwt = false", config)
            self.assertNotIn("SUPABASE_ACCESS_TOKEN", config)

    def test_deployment_command_is_explicit_project_and_temporary_function(self):
        command = setup.deploy_command(Path("/tmp/unit-test-source"))
        self.assertIn("--remote=cwdhymutbulafmtkfhqf", command)
        self.assertIn("setup-health-bootstrap", command)
        self.assertIn("supabase@3.1.0", command)
        self.assertNotIn("--prune", command)
        self.assertNotIn("secrets", command)

    def test_dry_run_does_not_need_authentication_or_google_token(self):
        with contextlib.redirect_stdout(io.StringIO()) as output:
            code = setup.main(["--project-ref", setup.PROJECT_REF, "--scheduler", "--subscriber", "--google-token-stdin"])
        self.assertEqual(code, 0)
        self.assertIn("no network, Keychain access, token input, clipboard access", output.getvalue())

    def test_cloud_shell_dry_run_requires_explicit_clipboard_flag(self):
        with contextlib.redirect_stdout(io.StringIO()) as output:
            code = setup.main(["--project-ref", setup.PROJECT_REF, "--subscriber", "--cloud-shell", "--copy-bootstrap-to-clipboard"])
        self.assertEqual(code, 0)
        self.assertIn("short-lived IAM token in memory", output.getvalue())

    def test_wrong_target_and_ambiguous_actions_rejected_before_authentication(self):
        cases = [
            ["--project-ref", "other", "--scheduler"],
            ["--project-ref", setup.PROJECT_REF],
            ["--project-ref", setup.PROJECT_REF, "--subscriber"],
            ["--project-ref", setup.PROJECT_REF, "--scheduler", "--google-token-stdin"],
            ["--project-ref", setup.PROJECT_REF, "--scheduler", "--cleanup-only"],
            ["--project-ref", setup.PROJECT_REF, "--subscriber", "--cloud-shell"],
            ["--project-ref", setup.PROJECT_REF, "--subscriber", "--cloud-shell", "--copy-bootstrap-to-clipboard", "--google-token-stdin"],
        ]
        for args in cases:
            with self.subTest(args=args), contextlib.redirect_stderr(io.StringIO()):
                self.assertEqual(setup.main(args), 1)


if __name__ == "__main__":
    unittest.main()
