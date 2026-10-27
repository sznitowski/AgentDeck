"""Domain models for AgentDeck Push Relay."""

from dataclasses import dataclass, field, asdict
from datetime import datetime, timezone
import json
from typing import Dict, Optional, Any, List


SCHEMA_VERSION = 1
RELAY_VERSION = "0.1.0"


def utc_now() -> datetime:
    return datetime.now(timezone.utc)


def format_iso(dt: Optional[datetime]) -> Optional[str]:
    if dt is None:
        return None
    return dt.isoformat()


def parse_iso(dt_str: Optional[str]) -> Optional[datetime]:
    if not dt_str:
        return None
    if dt_str.endswith("Z"):
        dt_str = dt_str[:-1] + "+00:00"
    return datetime.fromisoformat(dt_str)


def mask_token(token: str) -> str:
    if not token or len(token) < 12:
        return "***"
    return f"{token[:4]}...{token[-4:]}"


@dataclass
class DeviceRegistration:
    installation_id: str
    device_token: str
    platform: str = "ios"
    bundle_id: str = "com.agentdeck.app"
    environment: str = "sandbox"  # "sandbox" or "production"
    app_version: str = "1.0.0"
    privacy_mode: str = "full"  # "full", "projectOnly", "generic"
    enabled: bool = True
    created_at: datetime = field(default_factory=utc_now)
    updated_at: datetime = field(default_factory=utc_now)

    def to_dict(self) -> Dict[str, Any]:
        return {
            "schemaVersion": SCHEMA_VERSION,
            "installationId": self.installation_id,
            "deviceToken": self.device_token,
            "platform": self.platform,
            "bundleId": self.bundle_id,
            "environment": self.environment,
            "appVersion": self.app_version,
            "privacyMode": self.privacy_mode,
            "enabled": self.enabled,
            "createdAt": format_iso(self.created_at),
            "updatedAt": format_iso(self.updated_at),
        }

    @classmethod
    def from_dict(cls, data: Dict[str, Any]) -> "DeviceRegistration":
        return cls(
            installation_id=data.get("installationId", ""),
            device_token=data.get("deviceToken", ""),
            platform=data.get("platform", "ios"),
            bundle_id=data.get("bundleId", "com.agentdeck.app"),
            environment=data.get("environment", "sandbox"),
            app_version=data.get("appVersion", "1.0.0"),
            privacy_mode=data.get("privacyMode", "full"),
            enabled=data.get("enabled", True),
            created_at=parse_iso(data.get("createdAt")) or utc_now(),
            updated_at=parse_iso(data.get("updatedAt")) or utc_now(),
        )


@dataclass
class CompanionEventEnvelope:
    event_id: str
    type: str
    severity: str
    source: str
    fingerprint: str
    title: str
    message: str
    detected_at: datetime
    server_id: str
    sequence: int = 0
    project_id: Optional[str] = None
    project_name: Optional[str] = None
    server_name: Optional[str] = None
    agent_instance_id: Optional[str] = None
    agent_provider_id: Optional[str] = None
    agent_provider_name: Optional[str] = None
    is_production: bool = False
    action_label: Optional[str] = None
    destination: Optional[Dict[str, Any]] = None
    metadata: Dict[str, Any] = field(default_factory=dict)

    @classmethod
    def from_dict(cls, data: Dict[str, Any]) -> "CompanionEventEnvelope":
        return cls(
            event_id=data.get("eventId") or data.get("id", ""),
            sequence=int(data.get("sequence", 0)),
            type=data.get("type", "agentWaitingUser"),
            severity=data.get("severity", "info"),
            source=data.get("source", "agent"),
            fingerprint=data.get("fingerprint", ""),
            title=data.get("title", ""),
            message=data.get("message", ""),
            detected_at=parse_iso(data.get("detectedAt")) or utc_now(),
            server_id=data.get("serverId", "srv_default"),
            project_id=data.get("projectId"),
            project_name=data.get("projectName"),
            server_name=data.get("serverName"),
            agent_instance_id=data.get("agentInstanceId"),
            agent_provider_id=data.get("agentProviderId"),
            agent_provider_name=data.get("agentProviderName"),
            is_production=bool(data.get("isProduction", False)),
            action_label=data.get("actionLabel"),
            destination=data.get("destination"),
            metadata=data.get("metadata", {}),
        )


def format_apns_payload(
    event: CompanionEventEnvelope,
    privacy_mode: str = "full",
    badge: int = 1,
) -> Dict[str, Any]:
    """Transforms a CompanionEventEnvelope into a standard APNs JSON payload according to the device's privacy mode."""
    # 1. Alert Content based on Privacy Mode
    if privacy_mode == "projectOnly":
        title = f"Action required in {event.project_name}" if event.project_name else "AgentDeck Action Required"
        subtitle = None
        body = f"A remote {event.source} event requires attention."
    elif privacy_mode == "generic":
        title = "AgentDeck Notification"
        subtitle = None
        body = "An action requires your attention."
    else:  # full
        title = event.title or "AgentDeck Alert"
        subtitle = event.project_name
        body = event.message or "Action required."

    alert_dict: Dict[str, Any] = {
        "title": title,
        "body": body,
    }
    if subtitle:
        alert_dict["subtitle"] = subtitle

    # Category for actionable buttons in iOS
    category = "DEFAULT"
    if event.type == "agentWaitingUser":
        category = "AGENT_INTERACTION"
    elif event.type in ("agentFailed", "serverResourceCritical", "gitConflictDetected"):
        category = "CRITICAL_ALERT"

    # 2. Complete APS Dictionary
    payload: Dict[str, Any] = {
        "aps": {
            "alert": alert_dict,
            "sound": "default",
            "badge": badge,
            "category": category,
        },
        "agentdeck": {
            "schemaVersion": SCHEMA_VERSION,
            "eventId": event.event_id,
            "type": event.type,
            "severity": event.severity,
            "serverId": event.server_id,
            "projectId": event.project_id,
            "detectedAt": format_iso(event.detected_at),
            "isProduction": event.is_production,
            "destination": event.destination,
        },
    }

    return payload
