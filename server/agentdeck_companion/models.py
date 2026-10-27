"""Domain models and schemas for AgentDeck Server Companion (schemaVersion: 1)."""

from dataclasses import dataclass, field, asdict
from datetime import datetime, timezone
from typing import Dict, List, Optional, Any
import json
import uuid


SCHEMA_VERSION = 1
BINARY_VERSION = "0.1.0"
PROTOCOL_VERSION = 1


def utc_now() -> datetime:
    return datetime.now(timezone.utc)


def format_iso(dt: datetime) -> str:
    return dt.astimezone(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def parse_iso(dt_str: str) -> datetime:
    return datetime.fromisoformat(dt_str.replace("Z", "+00:00"))


@dataclass
class CompanionProjectConfig:
    id: str
    name: str
    working_directory: str
    enabled: bool = True

    @classmethod
    def from_dict(cls, data: Dict[str, Any]) -> "CompanionProjectConfig":
        return cls(
            id=str(data["id"]),
            name=str(data.get("name", data["id"])),
            working_directory=str(data["workingDirectory"]),
            enabled=bool(data.get("enabled", True)),
        )

    def to_dict(self) -> Dict[str, Any]:
        return {
            "id": self.id,
            "name": self.name,
            "workingDirectory": self.working_directory,
            "enabled": self.enabled,
        }


@dataclass
class CompanionPollIntervals:
    agents_sec: int = 3
    git_sec: 15 = 15
    server_sec: int = 15
    files_sec: int = 30

    @classmethod
    def from_dict(cls, data: Dict[str, Any]) -> "CompanionPollIntervals":
        return cls(
            agents_sec=int(data.get("agentsSec", 3)),
            git_sec=int(data.get("gitSec", 15)),
            server_sec=int(data.get("serverSec", 15)),
            files_sec=int(data.get("filesSec", 30)),
        )

    def to_dict(self) -> Dict[str, Any]:
        return {
            "agentsSec": self.agents_sec,
            "gitSec": self.git_sec,
            "serverSec": self.server_sec,
            "filesSec": self.files_sec,
        }


@dataclass
class CompanionRetention:
    max_events: int = 1000
    max_age_days: int = 7

    @classmethod
    def from_dict(cls, data: Dict[str, Any]) -> "CompanionRetention":
        return cls(
            max_events=int(data.get("maxEvents", 1000)),
            max_age_days=int(data.get("maxAgeDays", 7)),
        )

    def to_dict(self) -> Dict[str, Any]:
        return {
            "maxEvents": self.max_events,
            "maxAgeDays": self.max_age_days,
        }


@dataclass
class CompanionRelayConfig:
    enabled: bool = False
    url: str = "http://127.0.0.1:8443/v1/companion-events"
    companion_id: str = "cmp_default"
    companion_secret: str = ""
    timeout_sec: int = 5
    max_retries: int = 3

    @classmethod
    def from_dict(cls, data: Dict[str, Any]) -> "CompanionRelayConfig":
        return cls(
            enabled=bool(data.get("enabled", False)),
            url=str(data.get("url", "http://127.0.0.1:8443/v1/companion-events")),
            companion_id=str(data.get("companionId", "cmp_default")),
            companion_secret=str(data.get("companionSecret", "")),
            timeout_sec=int(data.get("timeoutSec", 5)),
            max_retries=int(data.get("maxRetries", 3)),
        )

    def to_dict(self) -> Dict[str, Any]:
        return {
            "enabled": self.enabled,
            "url": self.url,
            "companionId": self.companion_id,
            "companionSecret": self.companion_secret,
            "timeoutSec": self.timeout_sec,
            "maxRetries": self.max_retries,
        }


@dataclass
class CompanionConfig:
    server_id: str
    is_production: bool = False
    journal_path: str = "/var/lib/agentdeck/events.jsonl"
    lock_path: str = "/run/agentdeck/companion.pid"
    poll_intervals: CompanionPollIntervals = field(default_factory=CompanionPollIntervals)
    retention: CompanionRetention = field(default_factory=CompanionRetention)
    relay: CompanionRelayConfig = field(default_factory=CompanionRelayConfig)
    projects: List[CompanionProjectConfig] = field(default_factory=list)

    @classmethod
    def from_dict(cls, data: Dict[str, Any]) -> "CompanionConfig":
        projects_data = data.get("projects", [])
        projects = [CompanionProjectConfig.from_dict(p) for p in projects_data]
        return cls(
            server_id=str(data.get("serverId", "srv_default")),
            is_production=bool(data.get("isProduction", False)),
            journal_path=str(data.get("journalPath", "/var/lib/agentdeck/events.jsonl")),
            lock_path=str(data.get("lockPath", "/run/agentdeck/companion.pid")),
            poll_intervals=CompanionPollIntervals.from_dict(data.get("pollIntervals", {})),
            retention=CompanionRetention.from_dict(data.get("retention", {})),
            relay=CompanionRelayConfig.from_dict(data.get("relay", {})),
            projects=projects,
        )

    def to_dict(self) -> Dict[str, Any]:
        return {
            "schemaVersion": SCHEMA_VERSION,
            "serverId": self.server_id,
            "isProduction": self.is_production,
            "journalPath": self.journal_path,
            "lockPath": self.lock_path,
            "pollIntervals": self.poll_intervals.to_dict(),
            "retention": self.retention.to_dict(),
            "relay": self.relay.to_dict(),
            "projects": [p.to_dict() for p in self.projects],
        }


@dataclass
class NotificationDestination:
    route: str
    project_id: Optional[str] = None
    server_id: Optional[str] = None
    agent_instance_id: Optional[str] = None
    tmux_session_name: Optional[str] = None

    def to_dict(self) -> Dict[str, Any]:
        d: Dict[str, Any] = {"route": self.route}
        if self.project_id:
            d["projectId"] = self.project_id
        if self.server_id:
            d["serverId"] = self.server_id
        if self.agent_instance_id:
            d["agentInstanceId"] = self.agent_instance_id
        if self.tmux_session_name:
            d["tmuxSessionName"] = self.tmux_session_name
        return d


@dataclass
class CompanionEvent:
    sequence: int
    event_id: str
    type: str
    severity: str
    source: str
    fingerprint: str
    title: str
    message: str
    detected_at: datetime
    server_id: str
    project_id: Optional[str] = None
    project_name: Optional[str] = None
    agent_instance_id: Optional[str] = None
    agent_provider_id: Optional[str] = None
    agent_provider_name: Optional[str] = None
    is_production: bool = False
    action_label: Optional[str] = None
    destination: Optional[NotificationDestination] = None
    metadata: Dict[str, Any] = field(default_factory=dict)

    def to_dict(self) -> Dict[str, Any]:
        d: Dict[str, Any] = {
            "sequence": self.sequence,
            "eventId": self.event_id,
            "type": self.type,
            "severity": self.severity,
            "source": self.source,
            "fingerprint": self.fingerprint,
            "title": self.title,
            "message": self.message,
            "detectedAt": format_iso(self.detected_at),
            "serverId": self.server_id,
            "isProduction": self.is_production,
            "metadata": self.metadata,
        }
        if self.project_id:
            d["projectId"] = self.project_id
        if self.project_name:
            d["projectName"] = self.project_name
        if self.agent_instance_id:
            d["agentInstanceId"] = self.agent_instance_id
        if self.agent_provider_id:
            d["agentProviderId"] = self.agent_provider_id
        if self.agent_provider_name:
            d["agentProviderName"] = self.agent_provider_name
        if self.action_label:
            d["actionLabel"] = self.action_label
        if self.destination:
            d["destination"] = self.destination.to_dict()
        return d

    @classmethod
    def from_dict(cls, data: Dict[str, Any]) -> "CompanionEvent":
        dest_data = data.get("destination")
        dest = None
        if dest_data:
            dest = NotificationDestination(
                route=dest_data["route"],
                project_id=dest_data.get("projectId"),
                server_id=dest_data.get("serverId"),
                agent_instance_id=dest_data.get("agentInstanceId"),
                tmux_session_name=dest_data.get("tmuxSessionName"),
            )
        return cls(
            sequence=int(data["sequence"]),
            event_id=str(data["eventId"]),
            type=str(data["type"]),
            severity=str(data["severity"]),
            source=str(data["source"]),
            fingerprint=str(data["fingerprint"]),
            title=str(data["title"]),
            message=str(data["message"]),
            detected_at=parse_iso(data["detectedAt"]),
            server_id=str(data["serverId"]),
            project_id=data.get("projectId"),
            project_name=data.get("projectName"),
            agent_instance_id=data.get("agentInstanceId"),
            agent_provider_id=data.get("agentProviderId"),
            agent_provider_name=data.get("agentProviderName"),
            is_production=bool(data.get("isProduction", False)),
            action_label=data.get("actionLabel"),
            destination=dest,
            metadata=dict(data.get("metadata", {})),
        )


@dataclass
class ServerResourceMetrics:
    cpu_percent: Optional[float] = None
    memory_percent: Optional[float] = None
    disk_percent: Optional[float] = None
    observed_at: Optional[datetime] = None

    def max_percent(self) -> float:
        values = [v for v in [self.cpu_percent, self.memory_percent, self.disk_percent] if v is not None]
        return max(values) if values else 0.0

    def to_dict(self) -> Dict[str, Any]:
        return {
            "cpuPercent": self.cpu_percent,
            "memoryPercent": self.memory_percent,
            "diskPercent": self.disk_percent,
            "observedAt": format_iso(self.observed_at) if self.observed_at else None,
            "isHealthy": self.max_percent() < 90.0,
        }


@dataclass
class AgentStateObservation:
    instance_id: str
    provider_id: str
    state: str  # "running", "waitingUser", "failed", "finished", "unknown"
    tmux_session_name: str
    observed_at: datetime
    detail: Optional[str] = None

    def to_dict(self) -> Dict[str, Any]:
        return {
            "instanceId": self.instance_id,
            "providerId": self.provider_id,
            "state": self.state,
            "tmuxSessionName": self.tmux_session_name,
            "observedAt": format_iso(self.observed_at),
            "detail": self.detail,
        }


@dataclass
class GitStateObservation:
    conflict_count: int = 0
    is_clean: bool = True
    branch: Optional[str] = None
    is_repository: bool = True
    error: Optional[str] = None
    observed_at: Optional[datetime] = None

    def to_dict(self) -> Dict[str, Any]:
        return {
            "conflictCount": self.conflict_count,
            "isClean": self.is_clean,
            "branch": self.branch,
            "isRepository": self.is_repository,
            "error": self.error,
            "observedAt": format_iso(self.observed_at) if self.observed_at else None,
        }
