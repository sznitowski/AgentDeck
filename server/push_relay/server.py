"""HTTP server and request handlers for AgentDeck Push Relay.

TLS is terminated by a reverse proxy (Caddy). This process speaks plain HTTP and
must only listen on a loopback address in production.
"""

import hmac
import ipaddress
import json
import logging
from http.server import HTTPServer, BaseHTTPRequestHandler
import socketserver
import time
from typing import Any, Callable, Dict, Optional
from urllib.parse import urlparse

from .models import (
    DeviceRegistration,
    CompanionEventEnvelope,
    format_apns_payload,
    SCHEMA_VERSION,
    RELAY_VERSION,
    format_iso,
)
from .pairing import FailureLimiter, INSTALLATION_ID_RE
from .store import RelayStore
from .apns_provider import PushProvider, FakePushProvider, ApnsPushProvider

logger = logging.getLogger("agentdeck.push_relay")

DEFAULT_MAX_BODY_BYTES = 64 * 1024
_VALID_ENVIRONMENTS = {"sandbox", "production"}
_VALID_PRIVACY_MODES = {"full", "projectOnly", "generic"}
_DEVICE_TOKEN_MIN = 8
_DEVICE_TOKEN_MAX = 256
# Unread request bodies up to this size are drained before an error response so the
# connection closes cleanly (closing with unread data makes TCP send RST and the
# client can lose the response).
_DRAIN_LIMIT_BYTES = 256 * 1024


class RelayConfigError(ValueError):
    """Raised when the relay configuration is unsafe or invalid."""


class HttpError(Exception):
    def __init__(self, status: int, code: str, headers: Optional[Dict[str, str]] = None):
        super().__init__(code)
        self.status = status
        self.code = code
        self.headers = headers or {}


def is_loopback_host(host: str) -> bool:
    if host == "localhost":
        return True
    try:
        return ipaddress.ip_address(host).is_loopback
    except ValueError:
        return False


def validate_relay_security(
    host: str, production: bool, companion_secrets: Dict[str, str]
) -> None:
    """Fails closed on unsafe production configuration."""
    if not production:
        if not is_loopback_host(host):
            raise RelayConfigError("development mode only allows a loopback bind address")
        return
    if not companion_secrets:
        raise RelayConfigError(
            "production mode requires at least one entry in security.companionSecrets"
        )
    if not is_loopback_host(host):
        raise RelayConfigError(
            "relay must bind to a loopback address (127.0.0.1); terminate TLS in Caddy"
        )


class PushRelayHandler(BaseHTTPRequestHandler):
    """Processes HTTP requests for the Push Relay API."""

    # HTTP/1.0 (default): one request per connection, so unread bodies on early
    # rejections (401/413) can never be misparsed as a following request.
    timeout = 10  # seconds; protects against slow-loris style clients

    store: RelayStore
    push_provider: PushProvider
    companion_secrets: Dict[str, str]
    production: bool
    max_body_bytes: int
    limiter: FailureLimiter
    started_at: float
    _body_consumed: bool = False

    # -- plumbing -----------------------------------------------------

    def log_message(self, format: str, *args: Any) -> None:  # noqa: A002
        # Request line only; never headers (they carry credentials).
        logger.debug("%s %s", self.command, urlparse(self.path).path)

    def _send_json(
        self, status_code: int, data: Dict[str, Any], headers: Optional[Dict[str, str]] = None
    ) -> None:
        body = json.dumps(data, ensure_ascii=False).encode("utf-8")
        self.send_response(status_code)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        for key, value in (headers or {}).items():
            self.send_header(key, value)
        self.end_headers()
        self.wfile.write(body)

    def _drain_unread_body(self) -> None:
        if self._body_consumed:
            return
        self._body_consumed = True
        try:
            length = int(self.headers.get("Content-Length", 0))
        except ValueError:
            return
        if 0 < length <= _DRAIN_LIMIT_BYTES:
            try:
                self.rfile.read(length)
            except OSError:
                pass

    def _read_json(self) -> Dict[str, Any]:
        if "chunked" in self.headers.get("Transfer-Encoding", "").lower():
            self.close_connection = True
            raise HttpError(411, "length_required")
        raw_length = self.headers.get("Content-Length")
        if raw_length is None:
            self.close_connection = True
            raise HttpError(411, "length_required")
        try:
            length = int(raw_length)
        except ValueError:
            self.close_connection = True
            raise HttpError(400, "invalid_content_length")
        if length < 0:
            self.close_connection = True
            raise HttpError(400, "invalid_content_length")
        if length > self.max_body_bytes:
            self.close_connection = True
            raise HttpError(413, "payload_too_large")
        body = self.rfile.read(length) if length else b""
        self._body_consumed = True
        try:
            data = json.loads(body.decode("utf-8"))
        except (UnicodeDecodeError, ValueError):
            raise HttpError(400, "invalid_json")
        if not isinstance(data, dict):
            raise HttpError(400, "invalid_json")
        return data

    def _dispatch(self, routes: Dict[str, Callable[[], None]]) -> None:
        path = urlparse(self.path).path
        handler = routes.get(path)
        try:
            if handler is None:
                raise HttpError(404, "not_found")
            handler()
        except HttpError as err:
            self._drain_unread_body()
            self._send_json(err.status, {"schemaVersion": SCHEMA_VERSION, "error": err.code}, err.headers)
        except Exception:
            # Details go to the server log only, never to the client.
            logger.exception("Unhandled error processing %s %s", self.command, path)
            self._drain_unread_body()
            self._send_json(500, {"schemaVersion": SCHEMA_VERSION, "error": "internal_error"})

    # -- authentication -----------------------------------------------

    def _authenticate_installation(self) -> str:
        header = self.headers.get("Authorization", "")
        if not header.startswith("Bearer "):
            raise HttpError(401, "unauthorized")
        installation_id = self.store.authenticate_installation_token(header[7:].strip())
        if installation_id is None:
            raise HttpError(401, "unauthorized")
        return installation_id

    def _authenticate_companion(self) -> None:
        if not self.companion_secrets:
            if self.production:
                raise HttpError(401, "unauthorized")
            return  # development mode explicitly allows an unauthenticated lab companion
        comp_id = self.headers.get("X-Companion-Id", "")
        supplied = self.headers.get("X-Companion-Secret", "").encode("utf-8")
        expected = self.companion_secrets.get(comp_id)
        # Always run a constant-time comparison, even for unknown companion ids.
        expected_bytes = (expected if expected is not None else "\x00" * 32).encode("utf-8")
        matches = hmac.compare_digest(supplied, expected_bytes)
        if expected is None or not matches:
            raise HttpError(401, "unauthorized")

    # -- verbs --------------------------------------------------------

    def do_GET(self) -> None:
        self._dispatch({"/v1/health": self._handle_health, "/v1/status": self._handle_status})

    def do_POST(self) -> None:
        self._dispatch({
            "/v1/pairing/exchange": self._handle_pairing_exchange,
            "/v1/devices/register": self._handle_device_register,
            "/v1/companion-events": self._handle_companion_event,
        })

    def do_DELETE(self) -> None:
        self._dispatch({"/v1/devices/by-token": self._handle_device_unregister})

    # -- handlers -----------------------------------------------------

    def _handle_health(self) -> None:
        self._send_json(200, {
            "schemaVersion": SCHEMA_VERSION,
            "status": "ok",
            "version": RELAY_VERSION,
            "apnsConfigured": isinstance(self.push_provider, ApnsPushProvider),
        })

    def _handle_status(self) -> None:
        self._authenticate_companion()
        stats = self.store.get_stats()
        self._send_json(200, {
            "schemaVersion": SCHEMA_VERSION,
            "status": "running",
            "version": RELAY_VERSION,
            "uptimeSeconds": int(time.time() - self.started_at),
            "stats": stats,
        })

    def _handle_pairing_exchange(self) -> None:
        if self.limiter.is_blocked():
            raise HttpError(429, "too_many_attempts", {"Retry-After": "60"})
        data = self._read_json()
        installation_id = data.get("installationId")
        code = data.get("pairingCode")
        if (
            not isinstance(installation_id, str)
            or not INSTALLATION_ID_RE.match(installation_id)
            or not isinstance(code, str)
        ):
            raise HttpError(400, "invalid_request")
        token = self.store.exchange_pairing_code(code, installation_id)
        if token is None:
            self.limiter.record_failure()
            raise HttpError(401, "invalid_pairing_code")
        self._send_json(200, {
            "schemaVersion": SCHEMA_VERSION,
            "status": "paired",
            "installationId": installation_id,
            "installationToken": token,
        })

    def _handle_device_register(self) -> None:
        installation_id = self._authenticate_installation()
        data = self._read_json()
        if data.get("installationId") != installation_id:
            raise HttpError(403, "installation_mismatch")
        token = data.get("deviceToken")
        if (
            not isinstance(token, str)
            or not _DEVICE_TOKEN_MIN <= len(token) <= _DEVICE_TOKEN_MAX
            or any(ch.isspace() for ch in token)
        ):
            raise HttpError(400, "invalid_device_token")
        for key in ("platform", "bundleId", "appVersion"):
            value = data.get(key)
            if value is not None and (not isinstance(value, str) or not 0 < len(value) <= 128):
                raise HttpError(400, "invalid_" + key.lower())
        if data.get("platform", "ios") != "ios":
            raise HttpError(400, "invalid_platform")
        if "enabled" in data and not isinstance(data["enabled"], bool):
            raise HttpError(400, "invalid_enabled")
        if data.get("environment", "sandbox") not in _VALID_ENVIRONMENTS:
            raise HttpError(400, "invalid_environment")
        if data.get("privacyMode", "full") not in _VALID_PRIVACY_MODES:
            raise HttpError(400, "invalid_privacy_mode")
        try:
            device = DeviceRegistration.from_dict(data)
        except (TypeError, ValueError):
            raise HttpError(400, "invalid_request")
        saved = self.store.register_device(device)
        self._send_json(200, {
            "schemaVersion": SCHEMA_VERSION,
            "status": "registered",
            "installationId": saved.installation_id,
            "updatedAt": format_iso(saved.updated_at),
        })

    def _handle_device_unregister(self) -> None:
        installation_id = self._authenticate_installation()
        data = self._read_json()
        token = data.get("deviceToken")
        if not isinstance(token, str) or not token:
            raise HttpError(400, "invalid_device_token")
        if not self.store.deactivate_device_for_installation(token, installation_id):
            raise HttpError(404, "not_found")
        self._send_json(200, {
            "schemaVersion": SCHEMA_VERSION,
            "status": "deactivated",
            "deviceToken": f"{token[:4]}...{token[-4:]}" if len(token) >= 12 else "***",
        })

    def _handle_companion_event(self) -> None:
        self._authenticate_companion()
        data = self._read_json()
        try:
            event = CompanionEventEnvelope.from_dict(data)
        except (KeyError, TypeError, ValueError):
            raise HttpError(400, "invalid_event")
        if not event.event_id:
            raise HttpError(400, "invalid_event")

        # Idempotency / dedup
        if self.store.is_event_processed(event.event_id):
            self._send_json(200, {
                "schemaVersion": SCHEMA_VERSION,
                "status": "accepted",
                "eventId": event.event_id,
                "pushedDevicesCount": 0,
                "deduplicated": True,
            })
            return

        pushed_count = 0
        for dev in self.store.get_active_devices():
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

        self.store.record_event_processed(event.event_id, event.server_id, count=pushed_count)
        self._send_json(200, {
            "schemaVersion": SCHEMA_VERSION,
            "status": "accepted",
            "eventId": event.event_id,
            "pushedDevicesCount": pushed_count,
            "deduplicated": False,
        })


class ThreadedPushRelayServer(socketserver.ThreadingMixIn, HTTPServer):
    daemon_threads = True
    allow_reuse_address = True


class PushRelayService:
    """Manages lifecycle of the Push Relay HTTP daemon.

    ``production=True`` (the default) fails closed: it requires companion secrets and a
    loopback bind address. ``production=False`` is for local labs and tests only.
    """

    def __init__(
        self,
        host: str = "127.0.0.1",
        port: int = 8443,
        store: Optional[RelayStore] = None,
        push_provider: Optional[PushProvider] = None,
        companion_secrets: Optional[Dict[str, str]] = None,
        production: bool = True,
        max_body_bytes: int = DEFAULT_MAX_BODY_BYTES,
        limiter: Optional[FailureLimiter] = None,
    ):
        secrets_map = dict(companion_secrets or {})
        validate_relay_security(host, production, secrets_map)
        self.host = host
        self.port = port
        self.store = store or RelayStore()
        self.push_provider = push_provider or FakePushProvider()
        self.companion_secrets = secrets_map
        self.production = production
        self.max_body_bytes = max_body_bytes
        self.limiter = limiter or FailureLimiter()
        self.server: Optional[ThreadedPushRelayServer] = None
        self.started_at: float = 0.0

    def start(self) -> None:
        self.started_at = time.time()
        # Per-service handler subclass: no shared mutable class state between instances.
        handler_class = type("BoundPushRelayHandler", (PushRelayHandler,), {
            "store": self.store,
            "push_provider": self.push_provider,
            "companion_secrets": self.companion_secrets,
            "production": self.production,
            "max_body_bytes": self.max_body_bytes,
            "limiter": self.limiter,
            "started_at": self.started_at,
        })
        self.server = ThreadedPushRelayServer((self.host, self.port), handler_class)
        self.server.serve_forever()

    def stop(self) -> None:
        if self.server:
            self.server.shutdown()
            self.server.server_close()
            self.server = None
