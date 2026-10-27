"""Unit tests for AgentDeck Server Companion core components."""

import json
import os
from pathlib import Path
import tempfile
import unittest
from datetime import datetime, timezone, timedelta

import sys
_server_dir = Path(__file__).resolve().parent.parent
if str(_server_dir) not in sys.path:
    sys.path.insert(0, str(_server_dir))

from agentdeck_companion.models import (
    CompanionConfig,
    CompanionProjectConfig,
    CompanionEvent,
    AgentStateObservation,
    GitStateObservation,
    ServerResourceMetrics,
    SCHEMA_VERSION,
    utc_now,
)
from agentdeck_companion.journal import EventJournal
from agentdeck_companion.transition_detector import CompanionTransitionDetector
from agentdeck_companion.daemon import CompanionDaemon


class TestEventJournal(unittest.TestCase):
    def setUp(self):
        self.temp_dir = tempfile.TemporaryDirectory()
        self.journal_path = os.path.join(self.temp_dir.name, "events.jsonl")
        self.journal = EventJournal(self.journal_path, max_events=10, max_age_days=7)

    def tearDown(self):
        self.temp_dir.cleanup()

    def test_monotonic_sequence_and_persistence(self):
        # 1. Append 3 events
        for i in range(3):
            self.journal.append(lambda seq: CompanionEvent(
                sequence=seq,
                event_id=f"evt_{seq}",
                type="agentWaitingUser",
                severity="info",
                source="agent",
                fingerprint=f"fp_{seq}",
                title="Agent waiting",
                message="Prompt waiting",
                detected_at=utc_now(),
                server_id="srv_1",
            ))

        self.assertEqual(self.journal.current_sequence, 3)

        # 2. Reopen journal in new instance (simulate daemon restart)
        new_journal = EventJournal(self.journal_path, max_events=10, max_age_days=7)
        self.assertEqual(new_journal.current_sequence, 3)

        # 3. Append 4th event in new instance
        ev4 = new_journal.append(lambda seq: CompanionEvent(
            sequence=seq,
            event_id="evt_4",
            type="agentWaitingUser",
            severity="info",
            source="agent",
            fingerprint="fp_4",
            title="Agent waiting",
            message="Prompt waiting",
            detected_at=utc_now(),
            server_id="srv_1",
        ))
        self.assertEqual(ev4.sequence, 4)
        self.assertEqual(new_journal.current_sequence, 4)

    def test_query_after_cursor(self):
        for i in range(1, 6):
            self.journal.append(lambda seq: CompanionEvent(
                sequence=seq,
                event_id=f"evt_{seq}",
                type="agentWaitingUser",
                severity="info",
                source="agent",
                fingerprint=f"fp_{seq}",
                title=f"Event {seq}",
                message="Test",
                detected_at=utc_now(),
                server_id="srv_1",
            ))

        # Query after sequence 2
        events, last_seq, has_more = self.journal.query(after_sequence=2, limit=2)
        self.assertEqual(len(events), 2)
        self.assertEqual(events[0].sequence, 3)
        self.assertEqual(events[1].sequence, 4)
        self.assertEqual(last_seq, 4)
        self.assertTrue(has_more)

        # Query next batch after sequence 4
        events2, last_seq2, has_more2 = self.journal.query(after_sequence=4, limit=2)
        self.assertEqual(len(events2), 1)
        self.assertEqual(events2[0].sequence, 5)
        self.assertEqual(last_seq2, 5)
        self.assertFalse(has_more2)

    def test_retention_max_events(self):
        # max_events is 10
        for i in range(1, 16):
            self.journal.append(lambda seq: CompanionEvent(
                sequence=seq,
                event_id=f"evt_{seq}",
                type="agentWaitingUser",
                severity="info",
                source="agent",
                fingerprint=f"fp_{seq}",
                title=f"Event {seq}",
                message="Test",
                detected_at=utc_now(),
                server_id="srv_1",
            ))

        self.journal.prune()
        events, _, _ = self.journal.query(after_sequence=0, limit=100)
        self.assertEqual(len(events), 10)
        self.assertEqual(events[0].sequence, 6)
        self.assertEqual(events[-1].sequence, 15)


class TestTransitionDetector(unittest.TestCase):
    def setUp(self):
        self.detector = CompanionTransitionDetector(server_id="srv_test", is_production=False)
        self.proj = CompanionProjectConfig(id="proj_1", name="Test Project", working_directory="/tmp/p1")

    def test_baseline_prevents_historical_spam(self):
        obs = AgentStateObservation(
            instance_id="inst_1",
            provider_id="codex",
            state="waitingUser",
            tmux_session_name="agentdeck-agent-1",
            observed_at=utc_now(),
        )
        # Scan with is_baseline=True
        events = self.detector.evaluate_agent(self.proj, obs, is_baseline=True)
        self.assertEqual(len(events), 0)

        # Second scan in same state with is_baseline=False -> no new event
        events2 = self.detector.evaluate_agent(self.proj, obs, is_baseline=False)
        self.assertEqual(len(events2), 0)

    def test_agent_state_transition_and_dedup(self):
        # 1. Start in running
        obs_running = AgentStateObservation(
            instance_id="inst_1",
            provider_id="codex",
            state="running",
            tmux_session_name="agentdeck-agent-1",
            observed_at=utc_now(),
        )
        self.detector.evaluate_agent(self.proj, obs_running, is_baseline=False)

        # 2. Transition to waitingUser -> produces event
        obs_waiting = AgentStateObservation(
            instance_id="inst_1",
            provider_id="codex",
            state="waitingUser",
            tmux_session_name="agentdeck-agent-1",
            observed_at=utc_now(),
        )
        events = self.detector.evaluate_agent(self.proj, obs_waiting, is_baseline=False)
        self.assertEqual(len(events), 1)
        self.assertEqual(events[0].type, "agentWaitingUser")
        self.assertEqual(events[0].severity, "actionRequired")

        # 3. Repeat waitingUser -> deduplicated (0 events)
        events_dup = self.detector.evaluate_agent(self.proj, obs_waiting, is_baseline=False)
        self.assertEqual(len(events_dup), 0)

        # 4. Transition to finished -> produces event
        obs_finished = AgentStateObservation(
            instance_id="inst_1",
            provider_id="codex",
            state="finished",
            tmux_session_name="agentdeck-agent-1",
            observed_at=utc_now(),
        )
        events_fin = self.detector.evaluate_agent(self.proj, obs_finished, is_baseline=False)
        self.assertEqual(len(events_fin), 1)
        self.assertEqual(events_fin[0].type, "agentFinished")

    def test_git_conflict_detection_and_resolution(self):
        # 1. Clean repo
        obs_clean = GitStateObservation(conflict_count=0, is_clean=True, branch="main", observed_at=utc_now())
        self.detector.evaluate_git(self.proj, obs_clean, is_baseline=False)

        # 2. Conflict detected (2 conflicting files)
        obs_conflict = GitStateObservation(conflict_count=2, is_clean=False, branch="main", observed_at=utc_now())
        events_conf = self.detector.evaluate_git(self.proj, obs_conflict, is_baseline=False)
        self.assertEqual(len(events_conf), 1)
        self.assertEqual(events_conf[0].type, "gitConflictDetected")
        self.assertEqual(events_conf[0].severity, "critical")

        # 3. Conflict resolved
        events_res = self.detector.evaluate_git(self.proj, obs_clean, is_baseline=False)
        self.assertEqual(len(events_res), 1)
        self.assertEqual(events_res[0].type, "gitConflictResolved")
        self.assertEqual(events_res[0].severity, "info")

    def test_server_metrics_thresholds(self):
        # Normal metric: 50%
        m_normal = ServerResourceMetrics(cpu_percent=50.0, memory_percent=60.0, disk_percent=50.0, observed_at=utc_now())
        self.detector.evaluate_server_metrics(m_normal, is_baseline=False)

        # Warning metric: 85%
        m_warn = ServerResourceMetrics(cpu_percent=85.0, memory_percent=60.0, disk_percent=50.0, observed_at=utc_now())
        events_warn = self.detector.evaluate_server_metrics(m_warn, is_baseline=False)
        self.assertEqual(len(events_warn), 1)
        self.assertEqual(events_warn[0].type, "serverResourceWarning")
        self.assertEqual(events_warn[0].severity, "warning")

        # Critical metric: 95%
        m_crit = ServerResourceMetrics(cpu_percent=95.0, memory_percent=60.0, disk_percent=50.0, observed_at=utc_now())
        events_crit = self.detector.evaluate_server_metrics(m_crit, is_baseline=False)
        self.assertEqual(len(events_crit), 1)
        self.assertEqual(events_crit[0].type, "serverResourceCritical")
        self.assertEqual(events_crit[0].severity, "critical")

        # Recovery back to 60%
        events_rec = self.detector.evaluate_server_metrics(m_normal, is_baseline=False)
        self.assertEqual(len(events_rec), 1)
        self.assertEqual(events_rec[0].type, "serverResourceRecovered")


class TestProjectIsolation(unittest.TestCase):
    def setUp(self):
        self.temp_dir = tempfile.TemporaryDirectory()
        self.journal_path = os.path.join(self.temp_dir.name, "events.jsonl")
        self.lock_path = os.path.join(self.temp_dir.name, "companion.pid")

        self.p1 = CompanionProjectConfig(id="p1", name="Project 1", working_directory="/nonexistent/path/p1")
        self.p2 = CompanionProjectConfig(id="p2", name="Project 2", working_directory="/nonexistent/path/p2")

        self.config = CompanionConfig(
            server_id="srv_iso",
            journal_path=self.journal_path,
            lock_path=self.lock_path,
            projects=[self.p1, self.p2],
        )
        self.daemon = CompanionDaemon(self.config)

    def tearDown(self):
        self.daemon.release_lock()
        self.temp_dir.cleanup()

    def test_project_isolation_on_failure(self):
        # Scan should run cleanly without raising unhandled exception even if directories do not exist
        events = self.daemon.scan_once(is_baseline=False)
        status = self.daemon.get_status()
        self.assertEqual(status["projectsCount"], 2)
        self.assertIn("projects", status)
        self.assertEqual(len(status["projects"]), 2)


if __name__ == "__main__":
    unittest.main()
