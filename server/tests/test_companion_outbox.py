"""Unit tests for companion outbox forwarding."""

import json
from pathlib import Path
import tempfile
import threading
import time
import unittest

import sys
_server_dir = Path(__file__).resolve().parent.parent
if str(_server_dir) not in sys.path:
    sys.path.insert(0, str(_server_dir))

from agentdeck_companion.models import (
    CompanionEvent,
    CompanionRelayConfig,
    utc_now,
)
from agentdeck_companion.outbox import CompanionOutbox
from push_relay.store import RelayStore
from push_relay.apns_provider import FakePushProvider
from push_relay.server import PushRelayService


class TestCompanionOutbox(unittest.TestCase):
    def setUp(self):
        self.store = RelayStore(":memory:")
        self.provider = FakePushProvider()
        self.companion_secrets = {"cmp_lab": "secret_lab_pass"}

        self.service = PushRelayService(
            host="127.0.0.1",
            port=19443,
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

    def test_outbox_queue_and_flush(self):
        relay_cfg = CompanionRelayConfig(
            enabled=True,
            url="http://127.0.0.1:19443/v1/companion-events",
            companion_id="cmp_lab",
            companion_secret="secret_lab_pass",
        )
        outbox = CompanionOutbox(relay_cfg)

        ev = CompanionEvent(
            sequence=1,
            event_id="evt_outbox_1",
            type="agentWaitingUser",
            severity="actionRequired",
            source="agent",
            fingerprint="fp_1",
            title="Agent waiting",
            message="Please approve",
            detected_at=utc_now(),
            server_id="srv_1",
        )

        outbox.enqueue(ev)
        self.assertEqual(outbox.pending_count, 1)

        delivered = outbox.flush()
        self.assertEqual(delivered, 1)
        self.assertEqual(outbox.pending_count, 0)
        self.assertTrue(self.store.is_event_processed("evt_outbox_1"))

    def test_outbox_retries_when_relay_offline(self):
        # Point to closed port
        relay_cfg = CompanionRelayConfig(
            enabled=True,
            url="http://127.0.0.1:19999/v1/companion-events",
            companion_id="cmp_lab",
            companion_secret="secret_lab_pass",
            timeout_sec=1,
        )
        outbox = CompanionOutbox(relay_cfg)

        ev = CompanionEvent(
            sequence=2,
            event_id="evt_outbox_2",
            type="agentWaitingUser",
            severity="actionRequired",
            source="agent",
            fingerprint="fp_2",
            title="Agent waiting",
            message="Please approve",
            detected_at=utc_now(),
            server_id="srv_1",
        )

        outbox.enqueue(ev)
        delivered = outbox.flush()
        self.assertEqual(delivered, 0)
        self.assertEqual(outbox.pending_count, 1)  # Stays in queue for retry


if __name__ == "__main__":
    unittest.main()
