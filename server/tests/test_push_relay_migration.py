"""Migration (v1 -> v2), recovery and atomicity tests for the Push Relay store."""

import logging
import os
from pathlib import Path
import sqlite3
import sys
import tempfile
import unittest
from unittest import mock

_server_dir = Path(__file__).resolve().parent.parent
if str(_server_dir) not in sys.path:
    sys.path.insert(0, str(_server_dir))
_tests_dir = Path(__file__).resolve().parent
if str(_tests_dir) not in sys.path:
    sys.path.insert(0, str(_tests_dir))

from push_relay import store as store_module
from push_relay.models import DeviceRegistration
from push_relay.store import RelayStore
from test_push_relay_pairing import RelayHttpBase

# The exact schema the relay shipped before H1.1 (no installations/pairing/meta).
V1_SCHEMA = """
CREATE TABLE devices (
    installation_id TEXT PRIMARY KEY,
    device_token TEXT NOT NULL UNIQUE,
    platform TEXT NOT NULL,
    bundle_id TEXT NOT NULL,
    environment TEXT NOT NULL,
    app_version TEXT NOT NULL,
    privacy_mode TEXT NOT NULL,
    enabled INTEGER NOT NULL DEFAULT 1,
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL
);
CREATE INDEX idx_devices_token ON devices(device_token);
CREATE TABLE processed_events (
    event_id TEXT PRIMARY KEY,
    server_id TEXT NOT NULL,
    received_at TEXT NOT NULL,
    dispatched_count INTEGER NOT NULL DEFAULT 0
);
CREATE TABLE delivery_logs (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    event_id TEXT NOT NULL,
    device_token_masked TEXT NOT NULL,
    status TEXT NOT NULL,
    apns_id TEXT,
    error TEXT,
    created_at TEXT NOT NULL
);
"""
OLD = "2026-01-01T00:00:00+00:00"


def make_v1_db(path: str, devices=("inst_legacy_001", "inst_legacy_002")) -> None:
    conn = sqlite3.connect(path)
    conn.executescript(V1_SCHEMA)
    for i, inst in enumerate(devices):
        conn.execute(
            "INSERT INTO devices VALUES (?,?,?,?,?,?,?,?,?,?)",
            (inst, f"legacy_apns_token_{i:04d}", "ios", "com.agentdeck.app", "sandbox", "1.0.0", "full", 1, OLD, OLD),
        )
    conn.execute("INSERT INTO processed_events VALUES ('evt_old','srv',?,1)", (OLD,))
    conn.execute("INSERT INTO delivery_logs (event_id, device_token_masked, status, created_at) VALUES ('evt_old','lega...0000','delivered',?)", (OLD,))
    conn.commit()
    conn.close()


def raw_query(path: str, sql: str, params=()):
    conn = sqlite3.connect(path)
    try:
        return conn.execute(sql, params).fetchall()
    finally:
        conn.close()


class TestV1Migration(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.db = os.path.join(self.tmp.name, "relay.db")
        make_v1_db(self.db)

    def tearDown(self):
        self.tmp.cleanup()

    def test_first_open_migrates_and_disables_legacy_devices(self):
        with self.assertLogs("agentdeck.push_relay.store", level="WARNING") as logs:
            store = RelayStore(self.db)
        self.assertIn("2 legacy unpaired", "\n".join(logs.output))
        self.assertEqual(store.get_active_devices(), [])
        stats = store.get_stats()
        self.assertEqual(stats["totalDevices"], 2)  # rows are kept, only disabled
        self.assertEqual(stats["processedEvents"], 1)  # history preserved
        self.assertEqual(stats["deliveryLogEntries"], 1)
        store.close()
        self.assertEqual(raw_query(self.db, "SELECT value FROM schema_meta WHERE key='version'"), [("2",)])

    def test_second_open_is_idempotent(self):
        RelayStore(self.db).close()
        before = raw_query(self.db, "SELECT installation_id, enabled, updated_at FROM devices ORDER BY 1")
        # A device re-enabled after migration (authenticated registration) must survive.
        conn = sqlite3.connect(self.db)
        conn.execute("UPDATE devices SET enabled = 1 WHERE installation_id = 'inst_legacy_001'")
        conn.commit()
        conn.close()
        # (assertNoLogs needs Python 3.10; CI runners may ship 3.9.)
        records = []

        class Capture(logging.Handler):
            def emit(self, record):
                records.append(record)

        handler = Capture(level=logging.WARNING)
        store_logger = logging.getLogger("agentdeck.push_relay.store")
        store_logger.addHandler(handler)
        try:
            store = RelayStore(self.db)
        finally:
            store_logger.removeHandler(handler)
        store.close()
        self.assertEqual(records, [])
        after = raw_query(self.db, "SELECT installation_id, enabled, updated_at FROM devices ORDER BY 1")
        self.assertEqual(after[0][1], 1)  # not re-disabled
        self.assertEqual(after[1], before[1])  # untouched
        self.assertEqual(raw_query(self.db, "SELECT COUNT(*) FROM schema_meta"), [(1,)])

    def test_pairing_then_authenticated_registration_reactivates(self):
        store = RelayStore(self.db)
        try:
            self.assertEqual(store.get_active_devices(), [])
            code = store.create_pairing_code()["pairingCode"]
            token = store.exchange_pairing_code(code, "inst_legacy_001")
            self.assertEqual(store.authenticate_installation_token(token), "inst_legacy_001")
            store.register_device(DeviceRegistration(installation_id="inst_legacy_001", device_token="legacy_apns_token_0000"))
            active = store.get_active_devices()
            self.assertEqual([d.installation_id for d in active], ["inst_legacy_001"])
            # The other legacy device stays disabled until it pairs too.
            self.assertEqual(store.get_stats()["activeDevices"], 1)
        finally:
            store.close()

    def test_failed_migration_rolls_back_and_is_recoverable(self):
        conn = sqlite3.connect(self.db)
        conn.execute("CREATE TRIGGER block_update BEFORE UPDATE ON devices BEGIN SELECT RAISE(ABORT, 'boom'); END")
        conn.commit()
        conn.close()
        with self.assertRaises(sqlite3.Error):
            RelayStore(self.db)
        # Nothing half-applied: devices untouched and no version marker written.
        self.assertEqual(raw_query(self.db, "SELECT COUNT(*) FROM devices WHERE enabled = 1"), [(2,)])
        self.assertEqual(raw_query(self.db, "SELECT COUNT(*) FROM schema_meta WHERE key='version'"), [(0,)])
        # Once the cause is fixed, the next start migrates normally.
        conn = sqlite3.connect(self.db)
        conn.execute("DROP TRIGGER block_update")
        conn.commit()
        conn.close()
        store = RelayStore(self.db)
        self.assertEqual(store.get_active_devices(), [])
        store.close()
        self.assertEqual(raw_query(self.db, "SELECT value FROM schema_meta WHERE key='version'"), [("2",)])


class TestCorruptionAndAtomicity(unittest.TestCase):
    def test_corrupt_database_is_never_replaced_or_emptied(self):
        with tempfile.TemporaryDirectory() as tmp:
            db = os.path.join(tmp, "relay.db")
            garbage = b"this is definitely not a sqlite database\n" * 50
            Path(db).write_bytes(garbage)
            with self.assertRaises(sqlite3.DatabaseError):
                RelayStore(db)
            self.assertEqual(Path(db).read_bytes(), garbage)
            self.assertEqual(sorted(os.listdir(tmp)), ["relay.db"])  # no journal/backup/new db

    def test_failed_token_issue_does_not_burn_the_pairing_code(self):
        store = RelayStore(":memory:")
        try:
            code = store.create_pairing_code()["pairingCode"]
            real = store_module.hash_secret
            calls = {"n": 0}

            def flaky(value):
                calls["n"] += 1
                if calls["n"] == 2:  # the token hash, after the code was marked used
                    raise RuntimeError("disk full")
                return real(value)

            with mock.patch.object(store_module, "hash_secret", side_effect=flaky):
                with self.assertRaises(RuntimeError):
                    store.exchange_pairing_code(code, "inst_atomic_001")
            self.assertEqual(store.list_installations(), [])
            # Rolled back: the code is still valid and can be exchanged.
            self.assertIsNotNone(store.exchange_pairing_code(code, "inst_atomic_001"))
        finally:
            store.close()

    def test_unknown_code_leaves_no_open_transaction(self):
        store = RelayStore(":memory:")
        try:
            self.assertIsNone(store.exchange_pairing_code("AAAA-BBBB-CCCC-DDDD", "inst_atomic_001"))
            self.assertFalse(store._conn.in_transaction)
        finally:
            store.close()


class TestRegisterFieldValidation(RelayHttpBase):
    def test_malformed_optional_fields_are_400_not_500(self):
        token = self.pair("inst_http_0001")
        base = {"installationId": "inst_http_0001", "deviceToken": "apns_token_12345"}
        bad_patches = [
            {"platform": "android"},
            {"platform": 5},
            {"bundleId": ["x"]},
            {"bundleId": "x" * 200},
            {"appVersion": {"a": 1}},
            {"enabled": "yes"},
            {"enabled": 1},
        ]
        for patch in bad_patches:
            status, body = self.call("POST", "/v1/devices/register", {**base, **patch}, self.bearer(token))
            self.assertEqual(status, 400, patch)
            self.assertNotEqual(body.get("error"), "internal_error")
        self.assertEqual(self.store.get_active_devices(), [])

    def test_valid_optional_fields_still_register(self):
        token = self.pair("inst_http_0001")
        status, _ = self.call("POST", "/v1/devices/register", {
            "installationId": "inst_http_0001", "deviceToken": "apns_token_12345",
            "platform": "ios", "bundleId": "com.agentdeck.app", "appVersion": "0.1.0",
            "enabled": True, "environment": "production", "privacyMode": "projectOnly",
        }, self.bearer(token))
        self.assertEqual(status, 200)

    def test_re_pair_invalidates_old_token_and_revocation_disables_devices_over_http(self):
        old = self.pair("inst_http_0001")
        reg = {"installationId": "inst_http_0001", "deviceToken": "apns_token_12345"}
        self.assertEqual(self.call("POST", "/v1/devices/register", reg, self.bearer(old))[0], 200)
        new = self.pair("inst_http_0001")
        self.assertEqual(self.call("POST", "/v1/devices/register", reg, self.bearer(old))[0], 401)
        self.assertEqual(self.call("POST", "/v1/devices/register", reg, self.bearer(new))[0], 200)
        self.store.revoke_installation("inst_http_0001")
        self.assertEqual(self.store.get_active_devices(), [])
        self.assertEqual(self.call("POST", "/v1/devices/register", reg, self.bearer(new))[0], 401)


if __name__ == "__main__":
    unittest.main()
