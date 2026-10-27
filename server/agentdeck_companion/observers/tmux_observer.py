"""Tmux and Agent process observer for AgentDeck Server Companion."""

import re
import subprocess
from typing import Dict, List, Optional, Tuple, Any
from ..models import AgentStateObservation, utc_now

ANSI_ESCAPE_PATTERN = re.compile(
    r"(\x1B\[[0-?]*[ -/]*[@-~])|(\x1B\][^\x07\x1B]*(\x07|\x1B\\))|(\x1B[@-Z\\-_])",
    re.IGNORECASE,
)

WAITING_PATTERNS = [
    re.compile(r"\[WAITING_USER\]", re.IGNORECASE),
    re.compile(r"\?\s+[^\n]+", re.IGNORECASE),
    re.compile(r"\[y/n\]", re.IGNORECASE),
    re.compile(r"\(y/n\)", re.IGNORECASE),
    re.compile(r"approve\s+(command|edit|file|action)", re.IGNORECASE),
    re.compile(r"allow\s+(command|execution|edit)", re.IGNORECASE),
    re.compile(r"(›|>)\s*$", re.MULTILINE),
    re.compile(r"enter\s+to\s+continue", re.IGNORECASE),
    re.compile(r"what\s+would\s+you\s+like\s+to\s+do", re.IGNORECASE),
    re.compile(r"confirm\s+action", re.IGNORECASE),
    re.compile(r"waiting\s+for\s+instructions", re.IGNORECASE),
]

FAILED_PATTERNS = [
    re.compile(r"\[FAILED\]", re.IGNORECASE),
]

FINISHED_PATTERNS = [
    re.compile(r"\[FINISHED\]", re.IGNORECASE),
]


def strip_ansi(text: str) -> str:
    return ANSI_ESCAPE_PATTERN.sub("", text)


class TmuxObserver:
    """Inspects tmux sessions and classifies agent execution states."""

    def __init__(self, timeout_sec: int = 5):
        self.timeout_sec = timeout_sec

    def is_tmux_available(self) -> bool:
        try:
            res = subprocess.run(
                ["tmux", "-V"],
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                timeout=self.timeout_sec,
            )
            return res.returncode == 0
        except Exception:
            return False

    def list_agent_sessions(self) -> List[Dict[str, Any]]:
        """Queries all tmux panes belonging to AgentDeck agent sessions."""
        if not self.is_tmux_available():
            return []

        try:
            res = subprocess.run(
                [
                    "tmux",
                    "list-panes",
                    "-a",
                    "-F",
                    "#{session_name}:#{pane_pid}:#{pane_current_command}:#{pane_dead}:#{pane_dead_status}",
                ],
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                timeout=self.timeout_sec,
            )
            if res.returncode != 0:
                return []

            sessions = []
            for line in res.stdout.strip().split("\n"):
                line = line.strip()
                if not line:
                    continue
                parts = line.split(":")
                session_name = parts[0] if len(parts) > 0 else ""
                if not (session_name.startswith("ad_") or session_name.startswith("agentdeck") or "agent" in session_name):
                    continue

                pane_pid = parts[1] if len(parts) > 1 else ""
                current_cmd = parts[2] if len(parts) > 2 else ""
                is_dead = len(parts) > 3 and parts[3] == "1"
                dead_status = int(parts[4]) if len(parts) > 4 and parts[4].isdigit() else (1 if is_dead else 0)

                sessions.append({
                    "session_name": session_name,
                    "pane_pid": pane_pid,
                    "current_cmd": current_cmd,
                    "is_dead": is_dead,
                    "dead_status": dead_status,
                })
            return sessions
        except Exception:
            return []

    def capture_pane(self, session_name: str, lines: int = 30) -> str:
        """Captures recent terminal output from a tmux session."""
        try:
            res = subprocess.run(
                [
                    "tmux",
                    "capture-pane",
                    "-t",
                    session_name,
                    "-p",
                    "-S",
                    f"-{lines}",
                ],
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                timeout=self.timeout_sec,
            )
            if res.returncode == 0:
                return res.stdout
            return ""
        except Exception:
            return ""

    def classify_output(self, raw_output: str) -> Tuple[str, Optional[str]]:
        """Classifies terminal output into an AgentExecutionState."""
        clean = strip_ansi(raw_output).strip()
        if not clean:
            return ("running", None)

        for pattern in FAILED_PATTERNS:
            if pattern.search(clean):
                return ("failed", "Agent output indicates failure signal")

        for pattern in FINISHED_PATTERNS:
            if pattern.search(clean):
                return ("finished", "Agent output indicates completion signal")

        for pattern in WAITING_PATTERNS:
            if pattern.search(clean):
                return ("waitingUser", "Agent output waiting on user prompt/approval")

        return ("running", None)

    def observe_session(self, session_info: Dict[str, Any]) -> AgentStateObservation:
        """Derives an AgentStateObservation from tmux pane info and captured output."""
        session_name = session_info["session_name"]
        now = utc_now()

        # Parse provider_id and project_id from session name: ad_agent_<provider>_<project>_<nonce>
        parts = session_name.split("_")
        provider_id = parts[2] if len(parts) > 2 else "generic"

        if session_info["is_dead"]:
            exit_code = session_info["dead_status"]
            state = "finished" if exit_code == 0 else "failed"
            detail = f"Agent process exited with code {exit_code}"
            return AgentStateObservation(
                instance_id=session_name,
                provider_id=provider_id,
                state=state,
                tmux_session_name=session_name,
                observed_at=now,
                detail=detail,
            )

        # Active pane: capture output
        captured = self.capture_pane(session_name, lines=30)
        state, detail = self.classify_output(captured)

        return AgentStateObservation(
            instance_id=session_name,
            provider_id=provider_id,
            state=state,
            tmux_session_name=session_name,
            observed_at=now,
            detail=detail,
        )

    def observe_for_project(self, project_id: str) -> Optional[AgentStateObservation]:
        """Observes the primary active agent for a given project ID."""
        sessions = self.list_agent_sessions()
        # Find sessions matching this project
        project_sessions = [
            s for s in sessions
            if f"_{project_id}_" in s["session_name"]
            or f"-{project_id}-" in s["session_name"]
            or s["session_name"].endswith(f"_{project_id}")
            or s["session_name"].endswith(f"-{project_id}")
            or f"_{project_id}" in s["session_name"]
            or f"-{project_id}" in s["session_name"]
        ]
        if not project_sessions:
            return None

        # Prioritize dead or waiting sessions
        observations = [self.observe_session(s) for s in project_sessions]
        waiting = [o for o in observations if o.state == "waitingUser"]
        if waiting:
            return waiting[0]
        failed = [o for o in observations if o.state == "failed"]
        if failed:
            return failed[0]
        running = [o for o in observations if o.state == "running"]
        if running:
            return running[0]
        return observations[0]
