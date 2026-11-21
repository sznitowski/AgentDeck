"""Pairing, installation-token auth and hardening tests for the Push Relay."""

import contextlib
import http.client
import io
import json
import logging
import os
from pathlib import Path
import socket
import sqlite3
import sys
import tempfile
import threading
import time
import unittest
from unittest import mock

_server_dir = Path(__file__).resolve().parent.parent
if str(_server_dir) not in sys.path:
    sys.path.insert(0, str(_server_dir))

from push_relay import cli as relay_cli
from push_relay.apns_provider import ApnsPushProvider, FakePushProvider
from push_relay.models import DeviceRegistration
from push_relay.pairing import (
    FailureLimiter,
    generate_installation_token,
    generate_pairing_code,
    normalize_pairing_code,
)
from push_relay.server import PushRelayService, RelayConfigError
from push_relay.store import RelayStore

COMPANION_ID = "cmp_lab"
COMPANION_SECRET = "companion_secret_0123456789"
EVENT = {
    "schemaVersion": 1,
    "eventId": "evt_pair_001",
    "type": "agentWaitingUser",
    "severity": "actionRequired",
    "source": "agent",
    "fingerprint": "fp_1",
    "title": "Agent needs input",
    "message": "Approval requested",
    "serverId": "srv_lab",
    "detectedAt": "2026-09-24T20:00:00Z",
}


def free_port() -> int:
    with socket.socket() as s:
        s.bind(("127.0.0.1", 0))
        return s.getsockname()[1]


def dump_db(store: RelayStore) -> str:
    return "\n".join(store._conn.iterdump())


class TestPairingPrimitives(unittest.TestCase):
    def test_code_shape_and_entropy_source(self):
        code = generate_pairing_code()
        self.assertRegex(code, r"^[A-Z2-7]{4}(-[A-Z2-7]{4}){3}$")
        self.assertEqual(len({generate_pairing_code() for _ in range(200)}), 200)

    def test_normalize_accepts_user_formatting_only(self):
        code = generate_pairing_code()
        self.assertEqual(normalize_pairing_code(code.lower().replace("-", " ")), code.replace("-", ""))
        for bad in ("", "ABC", "A" * 17, "1111-1111-1111-1111", None, 12345):
            self.assertIsNone(normalize_pairing_code(bad))

    def test_token_prefix_and_length(self):
        token = generate_installation_token()
        self.assertTrue(token.startswith("adt_"))
        self.assertGreaterEqual(len(token), 40)

    def test_limiter_blocks_and_recovers(self):
        now = [0.0]
        limiter = FailureLimiter(max_failures=2, window_seconds=10, clock=lambda: now[0])
        limiter.record_failure()
        self.assertFalse(limiter.is_blocked())
        limiter.record_failure()
        self.assertTrue(limiter.is_blocked())
        now[0] = 11.0
        self.assertFalse(limiter.is_blocked())


class TestPairingStore(unittest.TestCase):
    def setUp(self):
        self.store = RelayStore(":memory:")

    def tearDown(self):
        self.store.close()

    def test_only_hashes_are_stored(self):
        created = self.store.create_pairing_code()
        code = created["pairingCode"]
        token = self.store.exchange_pairing_code(code, "inst_hash_001")
        dump = dump_db(self.store)
        self.assertNotIn(code, dump)
        self.assertNotIn(code.replace("-", ""), dump)
        self.assertNotIn(token, dump)
        self.assertNotIn(token[4:], dump)

    def test_code_is_single_use(self):
        code = self.store.create_pairing_code()["pairingCode"]
        self.assertIsNotNone(self.store.exchange_pairing_code(code, "inst_once_001"))
        self.assertIsNone(self.store.exchange_pairing_code(code, "inst_once_002"))

    def test_code_expires(self):
        code = self.store.create_pairing_code(60)["pairingCode"]
        from push_relay import store as store_module
        later = store_module.utc_now() + __import__("datetime").timedelta(seconds=61)
        with mock.patch.object(store_module, "utc_now", return_value=later):
            self.assertIsNone(self.store.exchange_pairing_code(code, "inst_exp_0001"))

    def test_ttl_is_clamped(self):
        self.assertEqual(self.store.create_pairing_code(99999)["ttlSeconds"], 15 * 60)
        self.assertEqual(self.store.create_pairing_code(1)["ttlSeconds"], 30)

    def test_concurrent_exchange_has_exactly_one_winner(self):
        code = self.store.create_pairing_code()["pairingCode"]
        results = []
        barrier = threading.Barrier(8)

        def attempt(i: int):
            barrier.wait()
            results.append(self.store.exchange_pairing_code(code, f"inst_race_{i:04d}"))

        threads = [threading.Thread(target=attempt, args=(i,)) for i in range(8)]
        for t in threads:
            t.start()
        for t in threads:
            t.join()
        self.assertEqual(len([r for r in results if r]), 1)

    def test_authenticate_and_garbage(self):
        code = self.store.create_pairing_code()["pairingCode"]
        token = self.store.exchange_pairing_code(code, "inst_auth_001")
        self.assertEqual(self.store.authenticate_installation_token(token), "inst_auth_001")
        for bad in ("", "adt_nope", token + "x", None):
            self.assertIsNone(self.store.authenticate_installation_token(bad))

    def test_repairing_revokes_previous_token(self):
        t1 = self.store.exchange_pairing_code(self.store.create_pairing_code()["pairingCode"], "inst_re_0001")
        t2 = self.store.exchange_pairing_code(self.store.create_pairing_code()["pairingCode"], "inst_re_0001")
        self.assertIsNone(self.store.authenticate_installation_token(t1))
        self.assertEqual(self.store.authenticate_installation_token(t2), "inst_re_0001")

    def test_revocation_disables_token_and_devices(self):
        token = self.store.exchange_pairing_code(self.store.create_pairing_code()["pairingCode"], "inst_rev_001")
        self.store.register_device(DeviceRegistration(installation_id="inst_rev_001", device_token="apns_token_rev_1"))
        self.assertEqual(len(self.store.get_active_devices()), 1)
        self.assertTrue(self.store.revoke_installation("inst_rev_001"))
        self.assertIsNone(self.store.authenticate_installation_token(token))
        self.assertEqual(len(self.store.get_active_devices()), 0)
        self.assertFalse(self.store.revoke_installation("inst_rev_001"))

    def test_device_deactivation_is_scoped_to_owner(self):
        self.store.register_device(DeviceRegistration(installation_id="inst_own_001", device_token="apns_token_own_1"))
        self.assertFalse(self.store.deactivate_device_for_installation("apns_token_own_1", "inst_other_01"))
        self.assertEqual(len(self.store.get_active_devices()), 1)
        self.assertTrue(self.store.deactivate_device_for_installation("apns_token_own_1", "inst_own_001"))


class TestMigration(unittest.TestCase):
    def test_v1_unpaired_devices_are_disabled_once(self):
        with tempfile.TemporaryDirectory() as tmp:
            db = os.path.join(tmp, "relay.db")
            conn = sqlite3.connect(db)
            conn.execute("""CREATE TABLE devices (
                installation_id TEXT PRIMARY KEY, device_token TEXT NOT NULL UNIQUE,
                platform TEXT NOT NULL, bundle_id TEXT NOT NULL, environment TEXT NOT NULL,
                app_version TEXT NOT NULL, privacy_mode TEXT NOT NULL,
                enabled INTEGER NOT NULL DEFAULT 1, created_at TEXT NOT NULL, updated_at TEXT NOT NULL)""")
            conn.execute("INSERT INTO devices VALUES ('inst_legacy_1','tok_legacy_0001','ios','b','sandbox','1','full',1,'2026-01-01T00:00:00+00:00','2026-01-01T00:00:00+00:00')")
            conn.commit()
            conn.close()

            store = RelayStore(db)
            self.assertEqual(len(store.get_active_devices()), 0)
            # A device registered after migration must survive another restart.
            store.register_device(DeviceRegistration(installation_id="inst_new_0001", device_token="tok_new_00001"))
            store.close()
            store = RelayStore(db)
            self.assertEqual([d.installation_id for d in store.get_active_devices()], ["inst_new_0001"])
            store.close()


class RelayHttpBase(unittest.TestCase):
    production = True
    secrets = {COMPANION_ID: COMPANION_SECRET}
    provider = None
    limiter = None

    def setUp(self):
        self.store = RelayStore(":memory:")
        self.port = free_port()
        self.service = PushRelayService(
            host="127.0.0.1",
            port=self.port,
            store=self.store,
            push_provider=self.provider or FakePushProvider(),
            companion_secrets=self.secrets,
            production=self.production,
            limiter=self.limiter,
        )
        threading.Thread(target=self.service.start, daemon=True).start()
        for _ in range(50):
            try:
                socket.create_connection(("127.0.0.1", self.port), timeout=0.2).close()
                break
            except OSError:
                time.sleep(0.05)

    def tearDown(self):
        self.service.stop()
        self.store.close()

    def call(self, method, path, body=None, headers=None, raw_body=None):
        conn = http.client.HTTPConnection("127.0.0.1", self.port, timeout=5)
        hdrs = dict(headers or {})
        payload = raw_body if raw_body is not None else (json.dumps(body).encode() if body is not None else None)
        if payload is not None:
            hdrs.setdefault("Content-Type", "application/json")
        conn.request(method, path, body=payload, headers=hdrs)
        resp = conn.getresponse()
        text = resp.read().decode("utf-8")
        conn.close()
        try:
            return resp.status, json.loads(text)
        except ValueError:
            return resp.status, {"raw": text}

    def pair(self, installation_id="inst_http_0001"):
        code = self.store.create_pairing_code()["pairingCode"]
        status, body = self.call("POST", "/v1/pairing/exchange",
                                 {"installationId": installation_id, "pairingCode": code})
        self.assertEqual(status, 200, body)
        return body["installationToken"]

    @staticmethod
    def bearer(token):
        return {"Authorization": f"Bearer {token}"}

    @staticmethod
    def companion_headers():
        return {"X-Companion-Id": COMPANION_ID, "X-Companion-Secret": COMPANION_SECRET}


class TestPairingHttp(RelayHttpBase):
    def test_exchange_success_and_replay(self):
        code = self.store.create_pairing_code()["pairingCode"]
        payload = {"installationId": "inst_http_0001", "pairingCode": code}
        status, body = self.call("POST", "/v1/pairing/exchange", payload)
        self.assertEqual(status, 200)
        self.assertEqual(body["status"], "paired")
        self.assertTrue(body["installationToken"].startswith("adt_"))
        self.assertNotIn(body["installationToken"], dump_db(self.store))
        status, body = self.call("POST", "/v1/pairing/exchange", payload)
        self.assertEqual((status, body["error"]), (401, "invalid_pairing_code"))

    def test_invalid_expired_and_used_codes_are_indistinguishable(self):
        used = self.store.create_pairing_code()["pairingCode"]
        self.store.exchange_pairing_code(used, "inst_other_001")
        bodies = []
        for code in (generate_pairing_code(), used, "not-a-code-at-all"):
            status, body = self.call("POST", "/v1/pairing/exchange",
                                     {"installationId": "inst_http_0001", "pairingCode": code})
            self.assertEqual(status, 401)
            bodies.append(body)
        self.assertEqual(bodies[0], bodies[1])
        self.assertEqual(bodies[1], bodies[2])

    def test_exchange_validates_request_shape(self):
        for payload in ({}, {"pairingCode": "x"}, {"installationId": "short", "pairingCode": "x"},
                        {"installationId": "inst_http_0001", "pairingCode": 5}):
            status, body = self.call("POST", "/v1/pairing/exchange", payload)
            self.assertEqual((status, body["error"]), (400, "invalid_request"), payload)

    def test_no_open_registration(self):
        status, _ = self.call("POST", "/v1/devices/register",
                              {"installationId": "inst_http_0001", "deviceToken": "apns_token_12345"})
        self.assertEqual(status, 401)
        self.assertEqual(len(self.store.get_active_devices()), 0)

    def test_register_requires_matching_installation(self):
        token = self.pair("inst_http_0001")
        status, body = self.call("POST", "/v1/devices/register",
                                 {"installationId": "inst_http_0002", "deviceToken": "apns_token_12345"},
                                 self.bearer(token))
        self.assertEqual((status, body["error"]), (403, "installation_mismatch"))

    def test_register_update_and_unregister_flow(self):
        token = self.pair("inst_http_0001")
        reg = {"installationId": "inst_http_0001", "deviceToken": "apns_token_12345", "privacyMode": "generic"}
        self.assertEqual(self.call("POST", "/v1/devices/register", reg, self.bearer(token))[0], 200)
        reg["deviceToken"] = "apns_token_67890"  # token rotation = update
        self.assertEqual(self.call("POST", "/v1/devices/register", reg, self.bearer(token))[0], 200)
        devices = self.store.get_active_devices()
        self.assertEqual([d.device_token for d in devices], ["apns_token_67890"])
        status, body = self.call("DELETE", "/v1/devices/by-token", {"deviceToken": "apns_token_67890"},
                                 self.bearer(token))
        self.assertEqual(status, 200)
        self.assertNotIn("apns_token_67890", json.dumps(body))
        self.assertEqual(len(self.store.get_active_devices()), 0)

    def test_unregister_cannot_touch_other_installations(self):
        token_a = self.pair("inst_http_000a")
        token_b = self.pair("inst_http_000b")
        self.call("POST", "/v1/devices/register",
                  {"installationId": "inst_http_000a", "deviceToken": "apns_token_aaaaa"}, self.bearer(token_a))
        status, _ = self.call("DELETE", "/v1/devices/by-token", {"deviceToken": "apns_token_aaaaa"},
                              self.bearer(token_b))
        self.assertEqual(status, 404)
        self.assertEqual(len(self.store.get_active_devices()), 1)
        self.assertEqual(self.call("DELETE", "/v1/devices/by-token", {"deviceToken": "apns_token_aaaaa"})[0], 401)

    def test_revoked_token_is_rejected(self):
        token = self.pair("inst_http_0001")
        self.assertTrue(self.store.revoke_installation("inst_http_0001"))
        status, _ = self.call("POST", "/v1/devices/register",
                              {"installationId": "inst_http_0001", "deviceToken": "apns_token_12345"},
                              self.bearer(token))
        self.assertEqual(status, 401)

    def test_bad_bearer_variants(self):
        for headers in ({}, {"Authorization": "Bearer "}, {"Authorization": "Basic abc"},
                        {"Authorization": "Bearer adt_unknown"}):
            status, _ = self.call("POST", "/v1/devices/register",
                                  {"installationId": "inst_http_0001", "deviceToken": "apns_token_12345"}, headers)
            self.assertEqual(status, 401, headers)

    def test_register_field_validation(self):
        token = self.pair("inst_http_0001")
        base = {"installationId": "inst_http_0001", "deviceToken": "apns_token_12345"}
        for patch in ({"deviceToken": "x"}, {"deviceToken": "has space token"},
                      {"environment": "evil"}, {"privacyMode": "everything"}):
            status, _ = self.call("POST", "/v1/devices/register", {**base, **patch}, self.bearer(token))
            self.assertEqual(status, 400, patch)


class TestPairingRateLimit(RelayHttpBase):
    limiter = FailureLimiter(max_failures=3, window_seconds=60)

    def test_brute_force_is_throttled_even_for_valid_code(self):
        valid = self.store.create_pairing_code()["pairingCode"]
        for _ in range(3):
            status, _ = self.call("POST", "/v1/pairing/exchange",
                                  {"installationId": "inst_http_0001", "pairingCode": generate_pairing_code()})
            self.assertEqual(status, 401)
        status, body = self.call("POST", "/v1/pairing/exchange",
                                 {"installationId": "inst_http_0001", "pairingCode": valid})
        self.assertEqual((status, body["error"]), (429, "too_many_attempts"))


class TestHardening(RelayHttpBase):
    def test_body_limit_and_framing(self):
        conn = http.client.HTTPConnection("127.0.0.1", self.port, timeout=5)
        conn.putrequest("POST", "/v1/pairing/exchange")
        conn.putheader("Content-Length", str(10 * 1024 * 1024))
        conn.endheaders()
        self.assertEqual(conn.getresponse().status, 413)
        conn.close()
        status, body = self.call("POST", "/v1/pairing/exchange", raw_body=b"x" * (70 * 1024))
        self.assertEqual(status, 413)

    def test_early_rejections_with_unread_bodies_do_not_reset_the_connection(self):
        # 401 happens before the body is parsed; the server must drain it so the
        # client reliably receives the response instead of a TCP reset.
        big = json.dumps({"installationId": "inst_http_0001", "deviceToken": "x" * 100_000}).encode()
        for _ in range(25):
            status, _body = self.call("POST", "/v1/devices/register", raw_body=big)
            self.assertEqual(status, 401)

    def test_invalid_json_and_non_object(self):
        for raw in (b"{not json", b"[1,2,3]", b""):
            status, body = self.call("POST", "/v1/pairing/exchange", raw_body=raw)
            self.assertIn(status, (400,), raw)

    def test_chunked_is_refused(self):
        conn = http.client.HTTPConnection("127.0.0.1", self.port, timeout=5)
        conn.putrequest("POST", "/v1/pairing/exchange")
        conn.putheader("Transfer-Encoding", "chunked")
        conn.endheaders()
        self.assertEqual(conn.getresponse().status, 411)
        conn.close()

    def test_internal_errors_are_sanitized(self):
        with mock.patch.object(self.store, "is_event_processed", side_effect=RuntimeError("secret-internal-detail /etc/passwd")):
            with self.assertLogs("agentdeck.push_relay", level="ERROR"):
                status, body = self.call("POST", "/v1/companion-events", EVENT, self.companion_headers())
        self.assertEqual(status, 500)
        self.assertEqual(body["error"], "internal_error")
        self.assertNotIn("secret-internal-detail", json.dumps(body))

    def test_health_is_real_and_minimal(self):
        status, body = self.call("GET", "/v1/health")
        self.assertEqual(status, 200)
        self.assertFalse(body["apnsConfigured"])
        self.assertNotIn("registeredDevices", body)
        self.assertNotIn("processedEvents", body)

    def test_status_requires_companion_credentials(self):
        self.assertEqual(self.call("GET", "/v1/status")[0], 401)
        self.assertEqual(self.call("GET", "/v1/status", headers=self.companion_headers())[0], 200)

    def test_companion_auth_failures(self):
        self.assertEqual(self.call("POST", "/v1/companion-events", EVENT)[0], 401)
        self.assertEqual(self.call("POST", "/v1/companion-events", EVENT,
                                   {"X-Companion-Id": COMPANION_ID, "X-Companion-Secret": "wrong"})[0], 401)
        self.assertEqual(self.call("POST", "/v1/companion-events", EVENT,
                                   {"X-Companion-Id": "cmp_unknown", "X-Companion-Secret": COMPANION_SECRET})[0], 401)
        self.assertEqual(self.call("POST", "/v1/companion-events", EVENT, self.companion_headers())[0], 200)

    def test_companion_secret_uses_compare_digest(self):
        with mock.patch("push_relay.server.hmac.compare_digest", wraps=__import__("hmac").compare_digest) as spy:
            self.call("POST", "/v1/companion-events", EVENT, self.companion_headers())
            self.call("POST", "/v1/companion-events", EVENT,
                      {"X-Companion-Id": "cmp_unknown", "X-Companion-Secret": "x"})
        self.assertGreaterEqual(spy.call_count, 2)

    def test_non_ascii_secret_does_not_crash(self):
        status, _ = self.call("POST", "/v1/companion-events", EVENT,
                              {"X-Companion-Id": COMPANION_ID, "X-Companion-Secret": "ñandú"})
        self.assertEqual(status, 401)

    def test_unknown_route_and_method(self):
        self.assertEqual(self.call("GET", "/v1/devices/register")[0], 404)
        self.assertEqual(self.call("POST", "/nope", {})[0], 404)

    def test_credentials_never_logged(self):
        records = []

        class Capture(logging.Handler):
            def emit(self, record):
                records.append(record.getMessage())

        handler = Capture(level=logging.DEBUG)
        relay_logger = logging.getLogger("agentdeck.push_relay")
        old_level = relay_logger.level
        relay_logger.addHandler(handler)
        relay_logger.setLevel(logging.DEBUG)
        try:
            code = self.store.create_pairing_code()["pairingCode"]
            _, body = self.call("POST", "/v1/pairing/exchange",
                                {"installationId": "inst_http_0001", "pairingCode": code})
            self.call("GET", "/v1/status", headers=self.companion_headers())
        finally:
            relay_logger.removeHandler(handler)
            relay_logger.setLevel(old_level)
        joined = "\n".join(records)
        self.assertNotIn(code, joined)
        self.assertNotIn(body["installationToken"], joined)
        self.assertNotIn(COMPANION_SECRET, joined)


class TestHealthWithApns(RelayHttpBase):
    provider = mock.create_autospec(ApnsPushProvider, instance=True)

    def test_apns_configured_reflects_provider(self):
        self.assertTrue(self.call("GET", "/v1/health")[1]["apnsConfigured"])


class TestFailClosedConfig(unittest.TestCase):
    def make(self, **kwargs):
        store = RelayStore(":memory:")
        self.addCleanup(store.close)
        return PushRelayService(store=store, **kwargs)

    def test_production_requires_companion_secrets(self):
        with self.assertRaises(RelayConfigError):
            self.make(companion_secrets={})
        with self.assertRaises(RelayConfigError):
            self.make(companion_secrets=None)

    def test_production_requires_loopback_bind(self):
        for host in ("0.0.0.0", "192.168.1.5", "example.com", "::"):
            with self.assertRaises(RelayConfigError, msg=host):
                self.make(host=host, companion_secrets={"c": "s" * 20})
        self.make(host="127.0.0.1", companion_secrets={"c": "s" * 20})
        self.make(host="::1", companion_secrets={"c": "s" * 20})

    def test_development_mode_is_explicit_and_loopback_only(self):
        self.make(host="127.0.0.1", production=False)
        with self.assertRaises(RelayConfigError):
            self.make(host="0.0.0.0", production=False)


class TestDevelopmentModeCompanion(RelayHttpBase):
    production = False
    secrets = {}

    def test_dev_mode_allows_lab_companion_without_secret(self):
        self.assertEqual(self.call("POST", "/v1/companion-events", EVENT)[0], 200)

    def test_dev_mode_still_requires_installation_auth(self):
        status, _ = self.call("POST", "/v1/devices/register",
                              {"installationId": "inst_http_0001", "deviceToken": "apns_token_12345"})
        self.assertEqual(status, 401)


class TestCli(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.db = os.path.join(self.tmp.name, "relay.db")

    def tearDown(self):
        self.tmp.cleanup()

    def write_config(self, **overrides):
        cfg = {
            "server": {"host": "127.0.0.1", "port": free_port(), "databasePath": self.db},
            "apns": {"enabled": False},
            "security": {"mode": "production", "companionSecrets": {"cmp": "x" * 24}},
        }
        for key, value in overrides.items():
            cfg[key].update(value)
        path = os.path.join(self.tmp.name, "relay.json")
        with open(path, "w", encoding="utf-8") as f:
            json.dump(cfg, f)
        if os.name != "nt":
            os.chmod(path, 0o600)
        return path

    def run_cli(self, argv):
        out, err = io.StringIO(), io.StringIO()
        parser = relay_cli.build_parser()
        args = parser.parse_args(argv)
        with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
            code = args.func(args)
        return code, out.getvalue(), err.getvalue()

    def test_run_refuses_default_config(self):
        code, _, err = self.run_cli(["run"])
        self.assertEqual(code, 2)
        self.assertIn("companionSecrets", err)

    def test_run_refuses_weak_secret_and_public_bind(self):
        weak = self.write_config(security={"companionSecrets": {"cmp": "short"}})
        self.assertEqual(self.run_cli(["run", "-c", weak])[0], 2)
        public = self.write_config(server={"host": "0.0.0.0"})
        self.assertEqual(self.run_cli(["run", "-c", public])[0], 2)

    def test_run_refuses_unknown_mode(self):
        cfg = self.write_config(security={"mode": "yolo"})
        self.assertEqual(self.run_cli(["run", "-c", cfg])[0], 2)

    @unittest.skipIf(os.name == "nt", "POSIX permission bits")
    def test_config_must_not_be_group_or_world_readable(self):
        cfg = self.write_config()
        os.chmod(cfg, 0o644)
        self.assertEqual(self.run_cli(["run", "-c", cfg])[0], 2)

    def test_pairing_create_list_and_revoke(self):
        cfg = self.write_config()
        code, out, _ = self.run_cli(["pairing", "create", "-c", cfg])
        self.assertEqual(code, 0)
        created = json.loads(out)
        store = RelayStore(self.db)
        try:
            self.assertNotIn(created["pairingCode"], dump_db(store))
            token = store.exchange_pairing_code(created["pairingCode"], "inst_cli_0001")
            self.assertIsNotNone(token)
        finally:
            store.close()
        listed = json.loads(self.run_cli(["installations", "list", "-c", cfg])[1])
        self.assertEqual(listed["installations"][0]["installationId"], "inst_cli_0001")
        self.assertNotIn("token", json.dumps(listed).lower().replace("installationid", ""))
        self.assertEqual(self.run_cli(["installations", "revoke", "inst_cli_0001", "-c", cfg])[0], 0)
        self.assertEqual(self.run_cli(["installations", "revoke", "inst_cli_0001", "-c", cfg])[0], 1)
        store = RelayStore(self.db)
        try:
            self.assertIsNone(store.authenticate_installation_token(token))
        finally:
            store.close()

    def test_admin_commands_need_a_database_file(self):
        self.assertEqual(self.run_cli(["pairing", "create"])[0], 2)


if __name__ == "__main__":
    unittest.main()
