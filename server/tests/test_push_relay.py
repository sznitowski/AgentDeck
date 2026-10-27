"""Unit and integration tests for AgentDeck Push Relay."""

from datetime import datetime, timezone
import json
import os
from pathlib import Path
import tempfile
import threading
import time
import unittest
import urllib.request
import urllib.error

import sys
_server_dir = Path(__file__).resolve().parent.parent
if str(_server_dir) not in sys.path:
    sys.path.insert(0, str(_server_dir))

from push_relay.models import (
    DeviceRegistration,
    CompanionEventEnvelope,
    format_apns_payload,
    SCHEMA_VERSION,
    RELAY_VERSION,
    utc_now,
)
from push_relay.store import RelayStore
from push_relay.apns_provider import FakePushProvider
from push_relay.server import PushRelayService


class TestPushRelayStore(unittest.TestCase):
    def setUp(self):
        self.temp_dir = tempfile.TemporaryDirectory()
        self.db_path = os.path.join(self.temp_dir.name, "relay.db")
        self.store = RelayStore(self.db_path)

    def tearDown(self):
        self.store.close()
        self.temp_dir.cleanup()

    def test_device_registration_and_token_rotation(self):
        dev1 = DeviceRegistration(
            installation_id="inst_1",
            device_token="token_aaa_111",
            platform="ios",
            environment="sandbox",
            privacy_mode="full",
        )
        self.store.register_device(dev1)

        active = self.store.get_active_devices()
        self.assertEqual(len(active), 1)
        self.assertEqual(active[0].installation_id, "inst_1")
        self.assertEqual(active[0].device_token, "token_aaa_111")

        # Token rotation: new token for same installation
        dev1_rotated = DeviceRegistration(
            installation_id="inst_1",
            device_token="token_bbb_222",
            platform="ios",
            environment="production",
            privacy_mode="projectOnly",
        )
        self.store.register_device(dev1_rotated)

        active_after = self.store.get_active_devices()
        self.assertEqual(len(active_after), 1)
        self.assertEqual(active_after[0].device_token, "token_bbb_222")
        self.assertEqual(active_after[0].privacy_mode, "projectOnly")

    def test_deactivate_unregistered_token(self):
        dev = DeviceRegistration(
            installation_id="inst_2",
            device_token="token_invalid",
            platform="ios",
        )
        self.store.register_device(dev)
        self.assertEqual(len(self.store.get_active_devices()), 1)

        self.store.deactivate_device_by_token("token_invalid")
        self.assertEqual(len(self.store.get_active_devices()), 0)

    def test_event_idempotency(self):
        self.assertFalse(self.store.is_event_processed("evt_100"))
        self.store.record_event_processed("evt_100", "srv_1", count=1)
        self.assertTrue(self.store.is_event_processed("evt_100"))


class TestPushRelayHttpService(unittest.TestCase):
    def setUp(self):
        self.store = RelayStore(":memory:")
        self.provider = FakePushProvider()
        self.companion_secrets = {"cmp_lab": "secret_lab_pass"}

        self.service = PushRelayService(
            host="127.0.0.1",
            port=18443,
            store=self.store,
            push_provider=self.provider,
            companion_secrets=self.companion_secrets,
        )
        self.server_thread = threading.Thread(target=self.service.start, daemon=True)
        self.server_thread.start()
        time.sleep(0.1)

    def tearDown(self):
        self.service.stop()
        self.store.close()

    def _post(self, path: str, data: dict, headers: dict = None) -> tuple[int, dict]:
        url = f"http://127.0.0.1:18443{path}"
        req_headers = {"Content-Type": "application/json"}
        if headers:
            req_headers.update(headers)
        body = json.dumps(data).encode("utf-8")
        req = urllib.request.Request(url, data=body, headers=req_headers, method="POST")
        try:
            with urllib.request.urlopen(req) as resp:
                return resp.status, json.loads(resp.read().decode("utf-8"))
        except urllib.error.HTTPError as e:
            return e.code, json.loads(e.read().decode("utf-8"))

    def test_device_register_endpoint(self):
        status, resp = self._post("/v1/devices/register", {
            "schemaVersion": 1,
            "installationId": "inst_http_1",
            "deviceToken": "token_http_12345",
            "platform": "ios",
            "privacyMode": "full",
        })
        self.assertEqual(status, 200)
        self.assertEqual(resp["status"], "registered")
        self.assertEqual(len(self.store.get_active_devices()), 1)

    def test_companion_event_dispatch_and_dedup(self):
        # 1. Register device
        self.store.register_device(DeviceRegistration(
            installation_id="inst_target",
            device_token="target_token_999",
            privacy_mode="full",
        ))

        # 2. Companion posts event
        event_data = {
            "schemaVersion": 1,
            "eventId": "evt_test_001",
            "type": "agentWaitingUser",
            "severity": "actionRequired",
            "source": "agent",
            "fingerprint": "agent_waiting:codex_1",
            "title": "Codex needs your input",
            "message": "Tool execution approval requested",
            "projectId": "proj_portal",
            "projectName": "Portal Proveedores",
            "serverId": "srv_lab",
            "isProduction": True,
            "detectedAt": "2026-09-24T20:00:00Z",
        }

        # Auth headers
        headers = {
            "X-Companion-Id": "cmp_lab",
            "X-Companion-Secret": "secret_lab_pass",
        }

        status, resp = self._post("/v1/companion-events", event_data, headers=headers)
        self.assertEqual(status, 200)
        self.assertEqual(resp["status"], "accepted")
        self.assertEqual(resp["pushedDevicesCount"], 1)
        self.assertFalse(resp["deduplicated"])

        # Check provider received push
        self.assertEqual(len(self.provider.dispatched_pushes), 1)
        dispatched = self.provider.dispatched_pushes[0]
        self.assertEqual(dispatched["device"].device_token, "target_token_999")
        self.assertEqual(dispatched["payload"]["aps"]["alert"]["title"], "Codex needs your input")
        self.assertEqual(dispatched["payload"]["aps"]["alert"]["subtitle"], "Portal Proveedores")

        # 3. Duplicate POST with same eventId -> deduplicated
        status2, resp2 = self._post("/v1/companion-events", event_data, headers=headers)
        self.assertEqual(status2, 200)
        self.assertTrue(resp2["deduplicated"])
        self.assertEqual(len(self.provider.dispatched_pushes), 1)  # No second push

    def test_privacy_modes(self):
        event = CompanionEventEnvelope.from_dict({
            "eventId": "evt_priv_1",
            "type": "agentWaitingUser",
            "severity": "actionRequired",
            "source": "agent",
            "fingerprint": "fp_1",
            "title": "Codex waiting for approval",
            "message": "Command confirmation required",
            "projectName": "Secret Client Alpha",
            "serverId": "srv_secret",
            "detectedAt": "2026-09-24T20:00:00Z",
        })

        # Generic mode
        p_generic = format_apns_payload(event, privacy_mode="generic")
        self.assertNotIn("Secret Client Alpha", json.dumps(p_generic["aps"]))
        self.assertNotIn("Codex", json.dumps(p_generic["aps"]))
        self.assertEqual(p_generic["aps"]["alert"]["title"], "AgentDeck Notification")

        # ProjectOnly mode
        p_proj = format_apns_payload(event, privacy_mode="projectOnly")
        self.assertIn("Secret Client Alpha", json.dumps(p_proj["aps"]))
        self.assertNotIn("Codex waiting for approval", json.dumps(p_proj["aps"]))


if __name__ == "__main__":
    unittest.main()
