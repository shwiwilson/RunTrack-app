import importlib.util
from pathlib import Path
import unittest

SOURCE = Path(__file__).resolve().parents[2] / "tools" / "setup-health-bootstrap" / "cloud_shell_client.py"
spec = importlib.util.spec_from_file_location("cloud_shell_client", SOURCE)
client = importlib.util.module_from_spec(spec)
spec.loader.exec_module(client)


class CloudShellValidationTests(unittest.TestCase):
    def test_nonce_accepts_only_current_bounded_setup_token(self):
        token = "rtboot1.1800000900." + "n" * 64
        self.assertEqual(client.validate_nonce(token, 1800000000), token)
        for value, now in ((token, 1800000900), (token, 1799999999), (token + "\n", 1800000000), ("short", 1800000000)):
            with self.subTest(length=len(value), now=now), self.assertRaises(client.ClientError):
                client.validate_nonce(value, now)

    def test_client_and_operator_target_same_production(self):
        self.assertEqual(client.PROJECT_ID, "runtrack-health-cwdhym")
        self.assertEqual(client.PROJECT_NUMBER, "701191762202")
        self.assertEqual(client.BRIDGE_URL, "https://cwdhymutbulafmtkfhqf.supabase.co/functions/v1/setup-health-bootstrap")


if __name__ == "__main__":
    unittest.main()
