"""HTTP server and request handlers for AgentDeck Push Relay."""

import json
import logging
from http.server import HTTPServer, BaseHTTPRequestHandler
import socketserver
import time
from typing import Dict, Any, Optional
from urllib.parse import urlparse

from .models import (
    DeviceRegistration,
    CompanionEventEnvelope,
    format_apns_payload,
    SCHEMA_VERSION,
    RELAY_VERSION,
    utc_now,
    format_iso,
)
from .store import RelayStore
from .apns_provider import PushProvider, FakePushProvider, ApnsPushProvider
from .jwt_helper import JwtTokenManager

logger = logging.getLogger("agentdeck.push_relay")


class PushRelayHandler(BaseHTTPRequestHandler):
    """Processes HTTP requests for the Push Relay API."""

    store: RelayStore
    push_provider: PushProvider
    companion_secrets: Dict[str, str]
    started_at: float

    def _send_json(self, status_code: int, data: Dict[str, Any]) -> None:
        body = json.dumps(data, ensure_ascii=False).encode("utf-8")
        self.send_response(status_code)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _read_json(self) -> Optional[Dict[str, Any]]:
        length = int(self.headers.get("Content-Length", 0))
        if length > 0:
            body = self.rfile.read(length)
            return json.loads(body.decode("utf-8"))
        if self.headers.get("Transfer-Encoding", "").lower() == "chunked":
            chunks = []
            while True:
                line = self.rfile.readline().strip()
                if not line:
                    break
                chunk_len = int(line, 16)
                if chunk_len == 0:
                    self.rfile.readline()
                    break
                chunk = self.rfile.read(chunk_len)
                chunks.append(chunk)
                self.rfile.readline()
            return json.loads(b"".join(chunks).decode("utf-8"))
        return None


    def do_GET(self) -> None:
        parsed = urlparse(self.path)
        path = parsed.path

        if path == "/v1/health":
            stats = self.store.get_stats()
            uptime = int(time.time() - self.started_at)
            self._send_json(200, {
                "schemaVersion": SCHEMA_VERSION,
                "status": "ok",
                "version": RELAY_VERSION,
                "uptimeSeconds": uptime,
                "apnsConfigured": True,
                "registeredDevices": stats["activeDevices"],
                "processedEvents": stats["processedEvents"],
            })
            return

        if path == "/v1/status":
            stats = self.store.get_stats()
            uptime = int(time.time() - self.started_at)
            self._send_json(200, {
                "schemaVersion": SCHEMA_VERSION,
                "status": "running",
                "version": RELAY_VERSION,
                "uptimeSeconds": uptime,
                "stats": stats,
            })
            return

        self._send_json(404, {"schemaVersion": SCHEMA_VERSION, "error": "Not Found"})

    def do_POST(self) -> None:
        parsed = urlparse(self.path)
        path = parsed.path

        if path == "/v1/devices/register":
            self._handle_device_register()
            return

        if path == "/v1/companion-events":
            self._handle_companion_event()
            return

        self._send_json(404, {"schemaVersion": SCHEMA_VERSION, "error": "Not Found"})

    def do_DELETE(self) -> None:
        parsed = urlparse(self.path)
        path = parsed.path

        if path == "/v1/devices/by-token":
            try:
                data = self._read_json() or {}
                token = data.get("deviceToken")
                if not token:
                    self._send_json(400, {"schemaVersion": SCHEMA_VERSION, "error": "deviceToken required"})
                    return
                self.store.deactivate_device_by_token(token)
                self._send_json(200, {
                    "schemaVersion": SCHEMA_VERSION,
                    "status": "deactivated",
                    "deviceToken": f"{token[:4]}...{token[-4:]}" if len(token) >= 8 else "***",
                })
            except Exception as e:
                self._send_json(500, {"schemaVersion": SCHEMA_VERSION, "error": str(e)})
            return

        self._send_json(404, {"schemaVersion": SCHEMA_VERSION, "error": "Not Found"})

    def _handle_device_register(self) -> None:
        try:
            data = self._read_json()
            if not data or "deviceToken" not in data or "installationId" not in data:
                self._send_json(400, {
                    "schemaVersion": SCHEMA_VERSION,
                    "error": "Missing required fields: deviceToken, installationId",
                })
                return

            device = DeviceRegistration.from_dict(data)
            saved = self.store.register_device(device)
            self._send_json(200, {
                "schemaVersion": SCHEMA_VERSION,
                "status": "registered",
                "installationId": saved.installation_id,
                "updatedAt": format_iso(saved.updated_at),
            })
        except Exception as e:
            self._send_json(500, {"schemaVersion": SCHEMA_VERSION, "error": str(e)})

    def _handle_companion_event(self) -> None:
        # 1. Authenticate companion if secrets configured
        if self.companion_secrets:
            comp_id = self.headers.get("X-Companion-Id", "")
            comp_secret = self.headers.get("X-Companion-Secret", "")
            expected_secret = self.companion_secrets.get(comp_id)
            if not expected_secret or comp_secret != expected_secret:
                self._send_json(401, {
                    "schemaVersion": SCHEMA_VERSION,
                    "error": "Unauthorized: Invalid companion credentials",
                })
                return

        try:
            data = self._read_json()
            if not data:
                self._send_json(400, {"schemaVersion": SCHEMA_VERSION, "error": "Empty payload"})
                return

            event = CompanionEventEnvelope.from_dict(data)

            # 2. Idempotency / Dedup Check
            if self.store.is_event_processed(event.event_id):
                self._send_json(200, {
                    "schemaVersion": SCHEMA_VERSION,
                    "status": "accepted",
                    "eventId": event.event_id,
                    "pushedDevicesCount": 0,
                    "deduplicated": True,
                })
                return

            # 3. Retrieve active devices
            devices = self.store.get_active_devices()
            pushed_count = 0

            # 4. Dispatch APNs push to all registered devices
            for dev in devices:
                payload = format_apns_payload(event, privacy_mode=dev.privacy_mode)
                collapse_id = f"agent:{event.agent_instance_id}" if event.agent_instance_id else None

                # Priority: 10 for interactive prompt / critical error; 5 for info
                priority = 10 if event.severity in ("actionRequired", "critical") else 5

                result = self.push_provider.send_push(
                    device=dev,
                    payload=payload,
                    collapse_id=collapse_id,
                    priority=priority,
                )

                if result.is_unregistered:
                    self.store.deactivate_device_by_token(dev.device_token)

                self.store.log_delivery(
                    event_id=event.event_id,
                    device_token=dev.device_token,
                    status="delivered" if result.success else "failed",
                    apns_id=result.apns_id,
                    error=result.reason,
                )
                if result.success:
                    pushed_count += 1

            # 5. Record processed
            self.store.record_event_processed(event.event_id, event.server_id, count=pushed_count)

            self._send_json(200, {
                "schemaVersion": SCHEMA_VERSION,
                "status": "accepted",
                "eventId": event.event_id,
                "pushedDevicesCount": pushed_count,
                "deduplicated": False,
            })
        except Exception as e:
            self._send_json(500, {"schemaVersion": SCHEMA_VERSION, "error": str(e)})


class ThreadedPushRelayServer(socketserver.ThreadingMixIn, HTTPServer):
    daemon_threads = True
    allow_reuse_address = True


class PushRelayService:
    """Manages lifecycle of the Push Relay HTTP daemon."""

    def __init__(
        self,
        host: str = "127.0.0.1",
        port: int = 8443,
        store: Optional[RelayStore] = None,
        push_provider: Optional[PushProvider] = None,
        companion_secrets: Optional[Dict[str, str]] = None,
    ):
        self.host = host
        self.port = port
        self.store = store or RelayStore()
        self.push_provider = push_provider or FakePushProvider()
        self.companion_secrets = companion_secrets or {}
        self.server: Optional[ThreadedPushRelayServer] = None
        self.started_at: float = 0.0

    def start(self) -> None:
        handler_class = PushRelayHandler
        handler_class.store = self.store
        handler_class.push_provider = self.push_provider
        handler_class.companion_secrets = self.companion_secrets
        self.started_at = time.time()
        handler_class.started_at = self.started_at

        self.server = ThreadedPushRelayServer((self.host, self.port), handler_class)
        self.server.serve_forever()

    def stop(self) -> None:
        if self.server:
            self.server.shutdown()
            self.server.server_close()
            self.server = None
