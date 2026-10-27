"""SQLite-backed persistent store for AgentDeck Push Relay."""

from datetime import datetime, timezone
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
        self._init_schema()

    def close(self) -> None:
        with self._lock:
            if self._conn:
                self._conn.close()
                self._conn = None

    def _init_schema(self) -> None:
        with self._lock:
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
            self._conn.commit()

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
