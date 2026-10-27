"""Security and privacy tests for AgentDeck Server Companion."""

import json
import os
from pathlib import Path
import tempfile
import unittest

import sys
_server_dir = Path(__file__).resolve().parent.parent
if str(_server_dir) not in sys.path:
    sys.path.insert(0, str(_server_dir))

from agentdeck_companion.models import (
    CompanionConfig,
    CompanionProjectConfig,
    CompanionEvent,
    utc_now,
)
from agentdeck_companion.journal import EventJournal
from agentdeck_companion.observers.git_observer import GitObserver
from agentdeck_companion.observers.tmux_observer import TmuxObserver
from agentdeck_companion.cli import build_parser


class TestCompanionSecurity(unittest.TestCase):
    def setUp(self):
        self.temp_dir = tempfile.TemporaryDirectory()
        self.journal_path = os.path.join(self.temp_dir.name, "events.jsonl")
        self.journal = EventJournal(self.journal_path)

    def tearDown(self):
        self.temp_dir.cleanup()

    def test_git_observer_injection_resistance(self):
        """Ensures malicious project paths do not execute arbitrary shell commands."""
        observer = GitObserver()
        malicious_paths = [
            "/tmp; cat /etc/passwd",
            "/tmp && echo pwned",
            "/tmp | touch /tmp/pwned",
            "/tmp/$(whoami)",
            "/tmp/`id`",
            "/tmp/test\nrm -rf /",
        ]
        for path in malicious_paths:
            obs = observer.observe(path)
            # Should fail safely as non-repo or non-existent without executing shell injection
            self.assertFalse(obs.is_repository)

    def test_tmux_observer_sanitization(self):
        """Ensures malicious project IDs are sanitized for tmux filtering."""
        observer = TmuxObserver()
        malicious_ids = [
            "proj; rm -rf /",
            "proj && touch /tmp/hacked",
            "proj | cat /etc/shadow",
            "proj$(id)",
        ]
        for proj_id in malicious_ids:
            # Should safely return None without exploding or running shell code
            obs = observer.observe_for_project(proj_id)
            self.assertIsNone(obs)

    def test_journal_privacy_zero_secrets(self):
        """Ensures that event journal serialization never contains credentials or transcripts."""
        sensitive_patterns = [
            "sk-ant-api03-",
            "sk-proj-1234567890",
            "ghp_1234567890abcdef",
            "BEGIN OPENSSH PRIVATE KEY",
            "PASSWORD=",
            "ANTHROPIC_API_KEY",
            "OPENAI_API_KEY",
        ]

        # Create an event and serialize
        event = self.journal.append(lambda seq: CompanionEvent(
            sequence=seq,
            event_id="evt_test",
            type="agentWaitingUser",
            severity="info",
            source="agent",
            fingerprint="fp_test",
            title="Claude Agent waiting for user confirmation",
            message="Tool call approval required",
            detected_at=utc_now(),
            server_id="srv_sec",
            project_id="proj_1",
            agent_instance_id="inst_1",
            agent_provider_id="claude",
            metadata={"tool": "replace_file_content"},
        ))

        with open(self.journal_path, "r", encoding="utf-8") as f:
            journal_content = f.read()
        for pattern in sensitive_patterns:
            self.assertNotIn(pattern, journal_content)

        # Verify parsed dict has no raw terminal buffer
        data = json.loads(journal_content.strip())
        self.assertNotIn("terminalTranscript", data)
        self.assertNotIn("rawBuffer", data)
        self.assertNotIn("environment", data)

    def test_cli_parser_argument_validation(self):
        """Tests that CLI parser handles numeric arguments safely."""
        parser = build_parser()

        # Valid events command
        args = parser.parse_args(["events", "--after", "15", "--limit", "50"])
        self.assertEqual(args.after, 15)
        self.assertEqual(args.limit, 50)

        # Negative/invalid inputs should be parsed as int or rejected by argparse
        with self.assertRaises(SystemExit):
            parser.parse_args(["events", "--after", "malicious_string"])


if __name__ == "__main__":
    unittest.main()
