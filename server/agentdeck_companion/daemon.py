"""Autonomous Companion Daemon loop with POSIX locking and error isolation."""

try:
    import fcntl
except ImportError:
    fcntl = None  # Non-POSIX systems (e.g. Windows during development/testing)
import os
from pathlib import Path
import signal
import sys
import time
from typing import Dict, List, Optional, Any

from .models import (
    CompanionConfig,
    CompanionEvent,
    AgentStateObservation,
    GitStateObservation,
    ServerResourceMetrics,
    SCHEMA_VERSION,
    BINARY_VERSION,
    PROTOCOL_VERSION,
    utc_now,
    format_iso,
)
from .journal import EventJournal
from .transition_detector import CompanionTransitionDetector
from .outbox import CompanionOutbox
from .observers.tmux_observer import TmuxObserver
from .observers.git_observer import GitObserver
from .observers.server_metrics import ServerMetricsObserver
from .observers.directory_observer import DirectoryObserver


class CompanionDaemon:
    """Manages continuous server-side observation loops and journal updates."""

    def __init__(self, config: CompanionConfig):
        self.config = config
        self.journal = EventJournal(
            journal_path=config.journal_path,
            max_events=config.retention.max_events,
            max_age_days=config.retention.max_age_days,
        )
        self.transition_detector = CompanionTransitionDetector(
            server_id=config.server_id,
            is_production=config.is_production,
        )
        self.outbox = CompanionOutbox(config.relay)

        self.tmux_observer = TmuxObserver()
        self.git_observer = GitObserver()
        self.server_metrics_observer = ServerMetricsObserver()
        self.directory_observer = DirectoryObserver()

        self._lock_file = None
        self._is_running = False
        self._started_at: Optional[datetime] = None
        self._last_scan_at: Optional[datetime] = None
        self._scan_count = 0
        self._last_error: Optional[str] = None
        self._project_statuses: Dict[str, Dict[str, Any]] = {}

        # Cached observations for snapshot queries
        self._last_server_metrics: Optional[ServerResourceMetrics] = None
        self._last_agent_observations: Dict[str, AgentStateObservation] = {}
        self._last_git_observations: Dict[str, GitStateObservation] = {}
        self._last_dir_observations: Dict[str, bool] = {}

    def acquire_lock(self) -> bool:
        """Acquires an exclusive POSIX lock to enforce a single daemon instance."""
        lock_path = Path(self.config.lock_path)
        if not lock_path.parent.exists():
            lock_path.parent.mkdir(parents=True, exist_ok=True)

        try:
            self._lock_file = open(lock_path, "w")
            if fcntl:
                fcntl.flock(self._lock_file.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
            self._lock_file.write(f"{os.getpid()}\n")
            self._lock_file.flush()
            return True
        except (IOError, OSError):
            if self._lock_file:
                try:
                    self._lock_file.close()
                except Exception:
                    pass
                self._lock_file = None
            return False

    def release_lock(self) -> None:
        """Releases the instance lock file."""
        if self._lock_file:
            try:
                if fcntl:
                    fcntl.flock(self._lock_file.fileno(), fcntl.LOCK_UN)
                self._lock_file.close()
                lock_path = Path(self.config.lock_path)
                if lock_path.exists():
                    lock_path.unlink(missing_ok=True)
            except Exception:
                pass
            self._lock_file = None

    def scan_once(self, is_baseline: bool = False) -> List[CompanionEvent]:
        """Executes a complete observation scan across all registered projects and server metrics."""
        now = utc_now()
        self._last_scan_at = now
        self._scan_count += 1
        new_events: List[CompanionEvent] = []

        # 1. Server metrics observation
        try:
            metrics = self.server_metrics_observer.observe()
            self._last_server_metrics = metrics
            metric_events = self.transition_detector.evaluate_server_metrics(metrics, is_baseline=is_baseline)
            for ev in metric_events:
                saved_ev = self.journal.append(lambda seq, e=ev: self._assign_seq(e, seq))
                self.outbox.enqueue(saved_ev)
                new_events.append(saved_ev)
        except Exception as e:
            self._last_error = f"Server metrics error: {e}"

        # 2. Per-project observation with error isolation
        for project in self.config.projects:
            if not project.enabled:
                continue

            proj_status = {"lastScanAt": format_iso(now), "lastStatus": "ok", "error": None}

            # Directory accessibility
            try:
                dir_exists = self.directory_observer.observe(project.working_directory)
                self._last_dir_observations[project.id] = dir_exists
                dir_events = self.transition_detector.evaluate_directory(project, dir_exists, is_baseline=is_baseline)
                for ev in dir_events:
                    saved_ev = self.journal.append(lambda seq, e=ev: self._assign_seq(e, seq))
                    self.outbox.enqueue(saved_ev)
                    new_events.append(saved_ev)
            except Exception as e:
                proj_status["error"] = f"Directory scan error: {e}"
                proj_status["lastStatus"] = "error"

            # Agent observation
            try:
                agent_obs = self.tmux_observer.observe_for_project(project.id)
                if agent_obs:
                    self._last_agent_observations[project.id] = agent_obs
                    agent_events = self.transition_detector.evaluate_agent(project, agent_obs, is_baseline=is_baseline)
                    for ev in agent_events:
                        saved_ev = self.journal.append(lambda seq, e=ev: self._assign_seq(e, seq))
                        self.outbox.enqueue(saved_ev)
                        new_events.append(saved_ev)
            except Exception as e:
                proj_status["error"] = f"Agent scan error: {e}"
                proj_status["lastStatus"] = "error"

            # Git observation
            try:
                git_obs = self.git_observer.observe(project.working_directory)
                self._last_git_observations[project.id] = git_obs
                git_events = self.transition_detector.evaluate_git(project, git_obs, is_baseline=is_baseline)
                for ev in git_events:
                    saved_ev = self.journal.append(lambda seq, e=ev: self._assign_seq(e, seq))
                    self.outbox.enqueue(saved_ev)
                    new_events.append(saved_ev)
            except Exception as e:
                proj_status["error"] = f"Git scan error: {e}"
                proj_status["lastStatus"] = "error"

            self._project_statuses[project.id] = proj_status

        # 3. Flush outbox to push relay
        if not is_baseline:
            try:
                self.outbox.flush()
            except Exception as e:
                logger.debug(f"Outbox flush error: {e}")

        # Prune journal periodically
        if self._scan_count % 10 == 0:
            try:
                self.journal.prune()
            except Exception:
                pass

        return new_events

    def _assign_seq(self, event: CompanionEvent, sequence: int) -> CompanionEvent:
        event.sequence = sequence
        return event

    def run(self) -> None:
        """Starts the continuous observation loop."""
        if not self.acquire_lock():
            sys.stderr.write("ERROR: Another instance of agentdeck-companion is already running.\n")
            sys.exit(1)

        self._is_running = True
        self._started_at = utc_now()

        def _handle_signal(signum, frame):
            self._is_running = False

        signal.signal(signal.SIGTERM, _handle_signal)
        signal.signal(signal.SIGINT, _handle_signal)

        try:
            # 1. First start: perform initial baseline scan (suppresses historical alert spam)
            self.scan_once(is_baseline=True)

            poll_sec = max(1, self.config.poll_intervals.agents_sec)
            while self._is_running:
                time.sleep(poll_sec)
                if not self._is_running:
                    break
                self.scan_once(is_baseline=False)

        finally:
            self.release_lock()

    def get_health(self) -> Dict[str, Any]:
        """Returns health status."""
        now = utc_now()
        uptime = int((now - self._started_at).total_seconds()) if self._started_at else 0
        return {
            "schemaVersion": SCHEMA_VERSION,
            "status": "ok",
            "version": BINARY_VERSION,
            "startedAt": format_iso(self._started_at) if self._started_at else None,
            "uptimeSeconds": uptime,
            "observedProjects": len([p for p in self.config.projects if p.enabled]),
            "lastScanAt": format_iso(self._last_scan_at) if self._last_scan_at else None,
            "lastError": self._last_error,
            "outbox": {
                "enabled": self.outbox.is_enabled,
                "pendingCount": self.outbox.pending_count,
            },
        }

    def get_status(self) -> Dict[str, Any]:
        """Returns full diagnostic status."""
        health = self.get_health()
        journal_stats = self.journal.stats()

        projects_list = []
        for p in self.config.projects:
            st = self._project_statuses.get(p.id, {})
            projects_list.append({
                "id": p.id,
                "name": p.name,
                "workingDirectory": p.working_directory,
                "enabled": p.enabled,
                "lastScanAt": st.get("lastScanAt"),
                "lastStatus": st.get("lastStatus", "unknown"),
                "error": st.get("error"),
            })

        return {
            "schemaVersion": SCHEMA_VERSION,
            "status": "running" if self._is_running else "ready",
            "pid": os.getpid(),
            "serverId": self.config.server_id,
            "uptimeSeconds": health["uptimeSeconds"],
            "lastScanAt": health["lastScanAt"],
            "scanCount": self._scan_count,
            "projectsCount": len(self.config.projects),
            "journal": journal_stats,
            "outbox": {
                "enabled": self.outbox.is_enabled,
                "pendingCount": self.outbox.pending_count,
            },
            "projects": projects_list,
        }

    def get_snapshot(self) -> Dict[str, Any]:
        """Returns the current active in-memory baseline state of all projects."""
        projects_snap: Dict[str, Any] = {}
        for p in self.config.projects:
            agent = self._last_agent_observations.get(p.id)
            git = self._last_git_observations.get(p.id)
            dir_exists = self._last_dir_observations.get(p.id, True)

            projects_snap[p.id] = {
                "id": p.id,
                "name": p.name,
                "workingDirectory": p.working_directory,
                "directoryExists": dir_exists,
                "agent": agent.to_dict() if agent else None,
                "git": git.to_dict() if git else None,
            }

        return {
            "schemaVersion": SCHEMA_VERSION,
            "observedAt": format_iso(utc_now()),
            "serverId": self.config.server_id,
            "serverHealth": self._last_server_metrics.to_dict() if self._last_server_metrics else None,
            "projects": projects_snap,
        }
