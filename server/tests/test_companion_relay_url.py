"""Companion must never send relay credentials over remote plain HTTP."""

from pathlib import Path
import sys
import unittest

_server_dir = Path(__file__).resolve().parent.parent
if str(_server_dir) not in sys.path:
    sys.path.insert(0, str(_server_dir))

from agentdeck_companion.models import CompanionRelayConfig, is_secure_relay_url
from agentdeck_companion.outbox import CompanionOutbox


class TestRelayUrlPolicy(unittest.TestCase):
    def test_url_policy(self):
        for ok in ("https://relay.example.com/v1/companion-events",
                   "http://127.0.0.1:8443/v1/companion-events",
                   "http://localhost:8443/x", "http://[::1]:8443/x"):
            self.assertTrue(is_secure_relay_url(ok), ok)
        for bad in ("http://relay.example.com/x", "http://10.0.0.5/x", "ftp://relay/x",
                    "relay.example.com/x", "", "https://"):
            self.assertFalse(is_secure_relay_url(bad), bad)

    def test_config_rejects_remote_http_when_enabled(self):
        with self.assertRaises(ValueError):
            CompanionRelayConfig.from_dict({"enabled": True, "url": "http://relay.example.com/x"})
        CompanionRelayConfig.from_dict({"enabled": True, "url": "https://relay.example.com/x"})
        CompanionRelayConfig.from_dict({"enabled": False, "url": "http://relay.example.com/x"})

    def test_outbox_refuses_insecure_url_even_if_constructed_directly(self):
        config = CompanionRelayConfig(enabled=True, url="http://relay.example.com/x", companion_secret="s")
        with self.assertLogs("agentdeck.companion.outbox", level="ERROR"):
            outbox = CompanionOutbox(config)
        self.assertFalse(outbox.is_enabled)
        self.assertEqual(outbox.flush(), 0)


if __name__ == "__main__":
    unittest.main()
