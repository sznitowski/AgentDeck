"""State transition detector and event generator with hysteresis and baseline support."""

from typing import Dict, List, Optional, Any
import uuid

from .models import (
    CompanionEvent,
    CompanionProjectConfig,
    AgentStateObservation,
    GitStateObservation,
    ServerResourceMetrics,
    NotificationDestination,
    utc_now,
)


class CompanionTransitionDetector:
    """Detects discrete state transitions from remote observations."""

    def __init__(
        self,
        server_id: str,
        is_production: bool = False,
        critical_metric_threshold: float = 90.0,
        warning_metric_threshold: float = 75.0,
        critical_recovery_threshold: float = 85.0,
        warning_recovery_threshold: float = 70.0,
    ):
        self.server_id = server_id
        self.is_production = is_production
        self.critical_metric_threshold = critical_metric_threshold
        self.warning_metric_threshold = warning_metric_threshold
        self.critical_recovery_threshold = critical_recovery_threshold
        self.warning_recovery_threshold = warning_recovery_threshold

        self._last_agent_states: Dict[str, str] = {}
        self._last_git_conflicts: Dict[str, int] = {}
        self._last_server_alert_states: Dict[str, str] = {}  # "normal", "warning", "critical"
        self._last_dir_states: Dict[str, bool] = {}

    def _generate_event_id(self) -> str:
        nonce = uuid.uuid4().hex[:8]
        return f"evt_{self.server_id}_{nonce}"

    def evaluate_agent(
        self,
        project: CompanionProjectConfig,
        observation: Optional[AgentStateObservation],
        is_baseline: bool = False,
    ) -> List[CompanionEvent]:
        """Evaluates agent execution state transitions."""
        if not observation:
            return []

        agent_key = observation.instance_id or project.id
        prev_state = self._last_agent_states.get(agent_key)
        curr_state = observation.state
        self._last_agent_states[agent_key] = curr_state

        if is_baseline:
            return []

        events: List[CompanionEvent] = []
        now = observation.observed_at

        if prev_state != curr_state:
            if curr_state == "waitingUser" and prev_state != "waitingUser":
                events.append(
                    CompanionEvent(
                        sequence=0,  # Assigned by EventJournal
                        event_id=self._generate_event_id(),
                        type="agentWaitingUser",
                        severity="actionRequired",
                        source="agent",
                        fingerprint=f"agent_waiting:{agent_key}",
                        title=f"{observation.provider_id.title()} is waiting for input",
                        message="Interactive CLI prompt requires your response.",
                        detected_at=now,
                        server_id=self.server_id,
                        project_id=project.id,
                        project_name=project.name,
                        agent_instance_id=observation.instance_id,
                        agent_provider_id=observation.provider_id,
                        agent_provider_name=observation.provider_id.title(),
                        is_production=self.is_production,
                        action_label="Respond",
                        destination=NotificationDestination(
                            route="agent_terminal",
                            project_id=project.id,
                            server_id=self.server_id,
                            agent_instance_id=observation.instance_id,
                            tmux_session_name=observation.tmux_session_name,
                        ),
                        metadata={"detail": observation.detail or ""},
                    )
                )
            elif curr_state == "failed" and prev_state != "failed":
                events.append(
                    CompanionEvent(
                        sequence=0,
                        event_id=self._generate_event_id(),
                        type="agentFailed",
                        severity="critical",
                        source="agent",
                        fingerprint=f"agent_failed:{agent_key}",
                        title=f"{observation.provider_id.title()} execution failed",
                        message="Agent process terminated with an error state.",
                        detected_at=now,
                        server_id=self.server_id,
                        project_id=project.id,
                        project_name=project.name,
                        agent_instance_id=observation.instance_id,
                        agent_provider_id=observation.provider_id,
                        agent_provider_name=observation.provider_id.title(),
                        is_production=self.is_production,
                        action_label="Inspect",
                        destination=NotificationDestination(
                            route="agent_details",
                            project_id=project.id,
                            server_id=self.server_id,
                            agent_instance_id=observation.instance_id,
                        ),
                        metadata={"detail": observation.detail or ""},
                    )
                )
            elif curr_state == "finished" and prev_state != "finished":
                events.append(
                    CompanionEvent(
                        sequence=0,
                        event_id=self._generate_event_id(),
                        type="agentFinished",
                        severity="info",
                        source="agent",
                        fingerprint=f"agent_finished:{agent_key}",
                        title=f"{observation.provider_id.title()} finished execution",
                        message="Agent task completed successfully.",
                        detected_at=now,
                        server_id=self.server_id,
                        project_id=project.id,
                        project_name=project.name,
                        agent_instance_id=observation.instance_id,
                        agent_provider_id=observation.provider_id,
                        agent_provider_name=observation.provider_id.title(),
                        is_production=self.is_production,
                        action_label="Open",
                        destination=NotificationDestination(
                            route="workspace",
                            project_id=project.id,
                            server_id=self.server_id,
                            agent_instance_id=observation.instance_id,
                        ),
                        metadata={"detail": observation.detail or ""},
                    )
                )

        return events

    def evaluate_git(
        self,
        project: CompanionProjectConfig,
        observation: Optional[GitStateObservation],
        is_baseline: bool = False,
    ) -> List[CompanionEvent]:
        """Evaluates Git conflict transitions."""
        if not observation or not observation.is_repository:
            return []

        git_key = project.id
        prev_conflicts = self._last_git_conflicts.get(git_key, 0)
        curr_conflicts = observation.conflict_count
        self._last_git_conflicts[git_key] = curr_conflicts

        if is_baseline:
            return []

        events: List[CompanionEvent] = []
        now = observation.observed_at or utc_now()

        if prev_conflicts == 0 and curr_conflicts > 0:
            events.append(
                CompanionEvent(
                    sequence=0,
                    event_id=self._generate_event_id(),
                    type="gitConflictDetected",
                    severity="critical",
                    source="git",
                    fingerprint=f"git_conflict:{project.id}:{curr_conflicts}",
                    title="Git Merge Conflicts Detected",
                    message=f"{curr_conflicts} file(s) contain unresolved merge conflicts.",
                    detected_at=now,
                    server_id=self.server_id,
                    project_id=project.id,
                    project_name=project.name,
                    is_production=self.is_production,
                    action_label="View Conflicts",
                    destination=NotificationDestination(
                        route="git",
                        project_id=project.id,
                        server_id=self.server_id,
                    ),
                    metadata={"conflictCount": curr_conflicts, "branch": observation.branch or ""},
                )
            )
        elif prev_conflicts > 0 and curr_conflicts == 0:
            events.append(
                CompanionEvent(
                    sequence=0,
                    event_id=self._generate_event_id(),
                    type="gitConflictResolved",
                    severity="info",
                    source="git",
                    fingerprint=f"git_conflict_resolved:{project.id}",
                    title="Git Merge Conflicts Resolved",
                    message="All repository merge conflicts have been resolved.",
                    detected_at=now,
                    server_id=self.server_id,
                    project_id=project.id,
                    project_name=project.name,
                    is_production=self.is_production,
                    action_label="View Git",
                    destination=NotificationDestination(
                        route="git",
                        project_id=project.id,
                        server_id=self.server_id,
                    ),
                    metadata={"branch": observation.branch or ""},
                )
            )

        return events

    def evaluate_server_metrics(
        self,
        metrics: Optional[ServerResourceMetrics],
        is_baseline: bool = False,
    ) -> List[CompanionEvent]:
        """Evaluates server resource pressure transitions with hysteresis."""
        if not metrics:
            return []

        srv_key = self.server_id
        max_pct = metrics.max_percent()
        prev_alert = self._last_server_alert_states.get(srv_key, "normal")
        next_alert = prev_alert

        events: List[CompanionEvent] = []
        now = metrics.observed_at or utc_now()

        if max_pct >= self.critical_metric_threshold:
            next_alert = "critical"
            if not is_baseline and prev_alert != "critical":
                events.append(
                    CompanionEvent(
                        sequence=0,
                        event_id=self._generate_event_id(),
                        type="serverResourceCritical",
                        severity="critical",
                        source="server",
                        fingerprint=f"srv_crit:{self.server_id}",
                        title="Critical Server Resource Pressure",
                        message=f"Server resource utilization reached {max_pct:.1f}%.",
                        detected_at=now,
                        server_id=self.server_id,
                        is_production=self.is_production,
                        action_label="Server Health",
                        destination=NotificationDestination(
                            route="server",
                            server_id=self.server_id,
                        ),
                        metadata={
                            "maxPercent": max_pct,
                            "cpuPercent": metrics.cpu_percent or 0.0,
                            "memoryPercent": metrics.memory_percent or 0.0,
                            "diskPercent": metrics.disk_percent or 0.0,
                        },
                    )
                )
        elif max_pct >= self.warning_metric_threshold:
            if prev_alert == "critical":
                # Apply hysteresis: only step down from critical to warning if below recovery threshold
                if max_pct < self.critical_recovery_threshold:
                    next_alert = "warning"
            elif prev_alert == "normal":
                next_alert = "warning"
                if not is_baseline:
                    events.append(
                        CompanionEvent(
                            sequence=0,
                            event_id=self._generate_event_id(),
                            type="serverResourceWarning",
                            severity="warning",
                            source="server",
                            fingerprint=f"srv_warn:{self.server_id}",
                            title="Server Resource Warning",
                            message=f"Server resource utilization reached {max_pct:.1f}%.",
                            detected_at=now,
                            server_id=self.server_id,
                            is_production=self.is_production,
                            action_label="Server Health",
                            destination=NotificationDestination(
                                route="server",
                                server_id=self.server_id,
                            ),
                            metadata={
                                "maxPercent": max_pct,
                                "cpuPercent": metrics.cpu_percent or 0.0,
                                "memoryPercent": metrics.memory_percent or 0.0,
                                "diskPercent": metrics.disk_percent or 0.0,
                            },
                        )
                    )
        else:
            # Below warning threshold: check recovery hysteresis
            if prev_alert == "warning" and max_pct < self.warning_recovery_threshold:
                next_alert = "normal"
                if not is_baseline:
                    events.append(
                        CompanionEvent(
                            sequence=0,
                            event_id=self._generate_event_id(),
                            type="serverResourceRecovered",
                            severity="info",
                            source="server",
                            fingerprint=f"srv_recov:{self.server_id}",
                            title="Server Resources Normal",
                            message=f"Server resource utilization recovered to {max_pct:.1f}%.",
                            detected_at=now,
                            server_id=self.server_id,
                            is_production=self.is_production,
                            action_label="Server Health",
                            destination=NotificationDestination(
                                route="server",
                                server_id=self.server_id,
                            ),
                            metadata={"maxPercent": max_pct},
                        )
                    )
            elif prev_alert == "critical" and max_pct < self.warning_recovery_threshold:
                next_alert = "normal"
                if not is_baseline:
                    events.append(
                        CompanionEvent(
                            sequence=0,
                            event_id=self._generate_event_id(),
                            type="serverResourceRecovered",
                            severity="info",
                            source="server",
                            fingerprint=f"srv_recov:{self.server_id}",
                            title="Server Resources Normal",
                            message=f"Server resource utilization recovered to {max_pct:.1f}%.",
                            detected_at=now,
                            server_id=self.server_id,
                            is_production=self.is_production,
                            action_label="Server Health",
                            destination=NotificationDestination(
                                route="server",
                                server_id=self.server_id,
                            ),
                            metadata={"maxPercent": max_pct},
                        )
                    )
            elif prev_alert == "normal":
                next_alert = "normal"

        self._last_server_alert_states[srv_key] = next_alert
        return events

    def evaluate_directory(
        self,
        project: CompanionProjectConfig,
        exists: bool,
        is_baseline: bool = False,
    ) -> List[CompanionEvent]:
        """Evaluates project working directory accessibility."""
        dir_key = project.id
        prev_exists = self._last_dir_states.get(dir_key, True)
        self._last_dir_states[dir_key] = exists

        if is_baseline:
            return []

        events: List[CompanionEvent] = []
        if prev_exists and not exists:
            events.append(
                CompanionEvent(
                    sequence=0,
                    event_id=self._generate_event_id(),
                    type="workingDirectoryMissing",
                    severity="warning",
                    source="files",
                    fingerprint=f"dir_missing:{project.id}",
                    title="Working Directory Inaccessible",
                    message=f"Project working directory {project.working_directory} could not be found.",
                    detected_at=utc_now(),
                    server_id=self.server_id,
                    project_id=project.id,
                    project_name=project.name,
                    is_production=self.is_production,
                    action_label="Browse Files",
                    destination=NotificationDestination(
                        route="files",
                        project_id=project.id,
                        server_id=self.server_id,
                    ),
                    metadata={"workingDirectory": project.working_directory},
                )
            )
        return events
