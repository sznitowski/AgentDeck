"""SQLite-backed persistent store for AgentDeck Push Relay."""

from datetime import datetime, timedelta, timezone
import hmac
import logging
from pathlib import Path
import sqlite3
import threading
from typing import Dict, List, Optional, Any

from .models import (
    DeviceRegistration,
    utc_now,
    format_iso,
    parse_iso,
    mask_token,
)
from .pairing import (
    DEFAULT_PAIRING_TTL_SECONDS,
    MAX_PAIRING_TTL_SECONDS,
    generate_installation_token,
    generate_pairing_code,
    hash_secret,
    normalize_pairing_code,
)

logger = logging.getLogger("agentdeck.push_relay.store")

STORE_SCHEMA_VERSION = 2


class RelayStore:
    """Manages SQLite storage for device tokens, event dedup, and delivery history."""

    def __init__(self, db_path: str = ":memory:"):
        self.db_path = db_path
        self._lock = threading.Lock()
        if db_path != ":memory:":
            p = Path(db_path)
            if not p.parent.exists():
                p.parent.mkdir(parents=True, exist_ok=True)
        self._conn = sqlite3.connect(self.db_path, check_same_thread=False)
        self._conn.row_factory = sqlite3.Row
        try:
            self._init_schema()
        except BaseException:
            # A failed open/migration must not leak the connection. The database
            # file is never replaced or emptied; the error propagates (fail closed).
            self._conn.close()
            self._conn = None
            raise

    def close(self) -> None:
        with self._lock:
            if self._conn:
                self._conn.close()
                self._conn = None

    def _init_schema(self) -> None:
        with self._lock:
            try:
                self._init_schema_locked()
            except BaseException:
                self._conn.rollback()
                raise

    def _init_schema_locked(self) -> None:
        # 1. Devices table
        self._conn.execute("""
            CREATE TABLE IF NOT EXISTS devices (
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
            )
        """)

        # Index for fast token lookups
        self._conn.execute("""
            CREATE INDEX IF NOT EXISTS idx_devices_token ON devices(device_token)
        """)

        # 2. Processed events table (Idempotency & Dedup)
        self._conn.execute("""
            CREATE TABLE IF NOT EXISTS processed_events (
                event_id TEXT PRIMARY KEY,
                server_id TEXT NOT NULL,
                received_at TEXT NOT NULL,
                dispatched_count INTEGER NOT NULL DEFAULT 0
            )
        """)

        # 3. Delivery logs table
        self._conn.execute("""
            CREATE TABLE IF NOT EXISTS delivery_logs (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                event_id TEXT NOT NULL,
                device_token_masked TEXT NOT NULL,
                status TEXT NOT NULL,
                apns_id TEXT,
                error TEXT,
                created_at TEXT NOT NULL
            )
        """)

        # 4. Pairing codes (hash only, single use, short expiry)
        self._conn.execute("""
            CREATE TABLE IF NOT EXISTS pairing_codes (
                code_hash TEXT PRIMARY KEY,
                created_at TEXT NOT NULL,
                expires_at TEXT NOT NULL,
                used_at TEXT
            )
        """)

        # 5. Installations (hash of the opaque installation token only)
        self._conn.execute("""
            CREATE TABLE IF NOT EXISTS installations (
                installation_id TEXT PRIMARY KEY,
                token_hash TEXT NOT NULL UNIQUE,
                created_at TEXT NOT NULL,
                last_used_at TEXT,
                revoked_at TEXT
            )
        """)

        # 6. Schema metadata + one-time migration
        self._conn.execute("""
            CREATE TABLE IF NOT EXISTS schema_meta (
                key TEXT PRIMARY KEY,
                value TEXT NOT NULL
            )
        """)
        row = self._conn.execute(
            "SELECT value FROM schema_meta WHERE key = 'version'"
        ).fetchone()
        current = int(row["value"]) if row else 1
        if current < 2:
            # v1 devices registered without authentication and have no paired
            # installation. Disable them; they must pair again.
            cur = self._conn.execute(
                "UPDATE devices SET enabled = 0 WHERE installation_id NOT IN "
                "(SELECT installation_id FROM installations)"
            )
            if cur.rowcount:
                logger.warning(
                    "Disabled %d legacy unpaired device registration(s)", cur.rowcount
                )
        self._conn.execute(
            "INSERT INTO schema_meta (key, value) VALUES ('version', ?) "
            "ON CONFLICT(key) DO UPDATE SET value = excluded.value",
            (str(STORE_SCHEMA_VERSION),),
        )
        self._conn.commit()

    # ------------------------------------------------------------------
    # Pairing and installation credentials
    # ------------------------------------------------------------------

    def create_pairing_code(self, ttl_seconds: int = DEFAULT_PAIRING_TTL_SECONDS) -> Dict[str, Any]:
        """Creates a one-time pairing code. The plaintext is returned once and not stored."""
        ttl = max(30, min(int(ttl_seconds), MAX_PAIRING_TTL_SECONDS))
        code = generate_pairing_code()
        now = utc_now()
        expires = now + timedelta(seconds=ttl)
        normalized = normalize_pairing_code(code)
        with self._lock:
            self._conn.execute(
                "INSERT INTO pairing_codes (code_hash, created_at, expires_at) VALUES (?, ?, ?)",
                (hash_secret(normalized), format_iso(now), format_iso(expires)),
            )
            self._conn.commit()
        return {"pairingCode": code, "expiresAt": format_iso(expires), "ttlSeconds": ttl}

    def exchange_pairing_code(self, code: Any, installation_id: str) -> Optional[str]:
        """Atomically consumes a pairing code and issues an installation token.

        Returns the plaintext token once, or None for any invalid/expired/used code.
        Re-pairing an existing installation revokes its previous token.
        """
        normalized = normalize_pairing_code(code)
        if normalized is None:
            return None
        code_hash = hash_secret(normalized)
        now = utc_now()
        token = generate_installation_token()
        with self._lock:
            try:
                cur = self._conn.execute(
                    "UPDATE pairing_codes SET used_at = ? "
                    "WHERE code_hash = ? AND used_at IS NULL AND expires_at > ?",
                    (format_iso(now), code_hash, format_iso(now)),
                )
                if cur.rowcount != 1:
                    self._conn.rollback()
                    return None
                self._conn.execute(
                    """
                    INSERT INTO installations (installation_id, token_hash, created_at)
                    VALUES (?, ?, ?)
                    ON CONFLICT(installation_id) DO UPDATE SET
                        token_hash = excluded.token_hash,
                        created_at = excluded.created_at,
                        last_used_at = NULL,
                        revoked_at = NULL
                    """,
                    (installation_id, hash_secret(token), format_iso(now)),
                )
                self._conn.commit()
            except BaseException:
                # Consuming the code and issuing the token are one atomic step:
                # if issuing fails, the code stays usable.
                self._conn.rollback()
                raise
        return token

    def authenticate_installation_token(self, token: str) -> Optional[str]:
        """Returns the installation_id bound to a valid, non-revoked token."""
        if not isinstance(token, str) or not token:
            return None
        token_hash = hash_secret(token)
        with self._lock:
            row = self._conn.execute(
                "SELECT installation_id, token_hash, revoked_at FROM installations "
                "WHERE token_hash = ?",
                (token_hash,),
            ).fetchone()
            if row is None:
                return None
            if not hmac.compare_digest(row["token_hash"], token_hash):
                return None
            if row["revoked_at"] is not None:
                return None
            self._conn.execute(
                "UPDATE installations SET last_used_at = ? WHERE installation_id = ?",
                (format_iso(utc_now()), row["installation_id"]),
            )
            self._conn.commit()
            return row["installation_id"]

    def revoke_installation(self, installation_id: str) -> bool:
        """Revokes the installation token and disables its device registrations."""
        now = format_iso(utc_now())
        with self._lock:
            cur = self._conn.execute(
                "UPDATE installations SET revoked_at = ? "
                "WHERE installation_id = ? AND revoked_at IS NULL",
                (now, installation_id),
            )
            self._conn.execute(
                "UPDATE devices SET enabled = 0, updated_at = ? WHERE installation_id = ?",
                (now, installation_id),
            )
            self._conn.commit()
            return cur.rowcount > 0

    def list_installations(self) -> List[Dict[str, Any]]:
        with self._lock:
            rows = self._conn.execute(
                "SELECT installation_id, created_at, last_used_at, revoked_at "
                "FROM installations ORDER BY created_at DESC"
            ).fetchall()
            return [
                {
                    "installationId": r["installation_id"],
                    "createdAt": r["created_at"],
                    "lastUsedAt": r["last_used_at"],
                    "revokedAt": r["revoked_at"],
                }
                for r in rows
            ]

    def deactivate_device_for_installation(self, token: str, installation_id: str) -> bool:
        """Deactivates a device token only if it belongs to the given installation."""
        with self._lock:
            cursor = self._conn.execute(
                "UPDATE devices SET enabled = 0, updated_at = ? "
                "WHERE device_token = ? AND installation_id = ?",
                (format_iso(utc_now()), token, installation_id),
            )
            self._conn.commit()
            return cursor.rowcount > 0

    def register_device(self, device: DeviceRegistration) -> DeviceRegistration:
        """Inserts or updates a device registration. Replaces token if installation_id exists."""
        now = utc_now()
        device.updated_at = now

        with self._lock:
            # Check if token exists on another installation (token rotation or reinstall)
            self._conn.execute(
                "DELETE FROM devices WHERE device_token = ? AND installation_id != ?",
                (device.device_token, device.installation_id),
            )

            self._conn.execute(
                """
                INSERT INTO devices (
                    installation_id, device_token, platform, bundle_id,
                    environment, app_version, privacy_mode, enabled,
                    created_at, updated_at
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(installation_id) DO UPDATE SET
                    device_token = excluded.device_token,
                    platform = excluded.platform,
                    bundle_id = excluded.bundle_id,
                    environment = excluded.environment,
                    app_version = excluded.app_version,
                    privacy_mode = excluded.privacy_mode,
                    enabled = excluded.enabled,
                    updated_at = excluded.updated_at
                """,
                (
                    device.installation_id,
                    device.device_token,
                    device.platform,
                    device.bundle_id,
                    device.environment,
                    device.app_version,
                    device.privacy_mode,
                    1 if device.enabled else 0,
                    format_iso(device.created_at),
                    format_iso(device.updated_at),
                ),
            )
            self._conn.commit()
        return device

    def get_active_devices(self) -> List[DeviceRegistration]:
        """Returns all currently enabled device registrations."""
        with self._lock:
            cursor = self._conn.execute(
                "SELECT * FROM devices WHERE enabled = 1 ORDER BY updated_at DESC"
            )
            rows = cursor.fetchall()
            devices: List[DeviceRegistration] = []
            for r in rows:
                devices.append(
                    DeviceRegistration(
                        installation_id=r["installation_id"],
                        device_token=r["device_token"],
                        platform=r["platform"],
                        bundle_id=r["bundle_id"],
                        environment=r["environment"],
                        app_version=r["app_version"],
                        privacy_mode=r["privacy_mode"],
                        enabled=bool(r["enabled"]),
                        created_at=parse_iso(r["created_at"]) or utc_now(),
                        updated_at=parse_iso(r["updated_at"]) or utc_now(),
                    )
                )
            return devices

    def deactivate_device_by_token(self, token: str) -> bool:
        """Deactivates a device registration when APNs returns 410 Unregistered."""
        with self._lock:
            cursor = self._conn.execute(
                "UPDATE devices SET enabled = 0, updated_at = ? WHERE device_token = ?",
                (format_iso(utc_now()), token),
            )
            self._conn.commit()
            return cursor.rowcount > 0

    def is_event_processed(self, event_id: str) -> bool:
        """Checks if an event has already been ingested and processed."""
        with self._lock:
            cursor = self._conn.execute(
                "SELECT 1 FROM processed_events WHERE event_id = ?",
                (event_id,),
            )
            return cursor.fetchone() is not None

    def record_event_processed(self, event_id: str, server_id: str, count: int = 1) -> None:
        """Records an event as processed for idempotency."""
        with self._lock:
            self._conn.execute(
                """
                INSERT INTO processed_events (event_id, server_id, received_at, dispatched_count)
                VALUES (?, ?, ?, ?)
                ON CONFLICT(event_id) DO UPDATE SET
                    dispatched_count = dispatched_count + excluded.dispatched_count
                """,
                (event_id, server_id, format_iso(utc_now()), count),
            )
            self._conn.commit()

    def log_delivery(
        self,
        event_id: str,
        device_token: str,
        status: str,
        apns_id: Optional[str] = None,
        error: Optional[str] = None,
    ) -> None:
        """Appends a masked delivery entry to the delivery log."""
        masked = mask_token(device_token)
        with self._lock:
            self._conn.execute(
                """
                INSERT INTO delivery_logs (event_id, device_token_masked, status, apns_id, error, created_at)
                VALUES (?, ?, ?, ?, ?, ?)
                """,
                (event_id, masked, status, apns_id, error, format_iso(utc_now())),
            )
            self._conn.commit()

    def get_stats(self) -> Dict[str, Any]:
        """Returns statistics for health and diagnostics."""
        with self._lock:
            total_devs = self._conn.execute("SELECT COUNT(*) FROM devices").fetchone()[0]
            active_devs = self._conn.execute("SELECT COUNT(*) FROM devices WHERE enabled = 1").fetchone()[0]
            total_evts = self._conn.execute("SELECT COUNT(*) FROM processed_events").fetchone()[0]
            total_logs = self._conn.execute("SELECT COUNT(*) FROM delivery_logs").fetchone()[0]

            return {
                "totalDevices": total_devs,
                "activeDevices": active_devs,
                "processedEvents": total_evts,
                "deliveryLogEntries": total_logs,
            }
