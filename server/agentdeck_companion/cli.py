"""CLI entry point for agentdeck-companion."""

import argparse
import json
import os
from pathlib import Path
import sys
from typing import Optional, Dict, Any

from .models import (
    SCHEMA_VERSION,
    BINARY_VERSION,
    PROTOCOL_VERSION,
    CompanionConfig,
    format_iso,
    utc_now,
)
from .journal import EventJournal
from .daemon import CompanionDaemon


DEFAULT_CONFIG_LOCATIONS = [
    "/etc/agentdeck/agentdeck-companion.json",
    "/etc/agentdeck/companion.json",
    os.path.expanduser("~/.config/agentdeck/agentdeck-companion.json"),
    os.path.expanduser("~/.config/agentdeck/companion.json"),
    os.path.expanduser("~/agentdeck-companion.json"),
    os.path.expanduser("~/.agentdeck-companion.json"),
]


def find_default_config_path() -> Optional[str]:
    env_path = os.environ.get("AGENTDECK_CONFIG")
    if env_path and os.path.exists(env_path):
        return env_path
    for p in DEFAULT_CONFIG_LOCATIONS:
        if os.path.exists(p):
            return p
    return None


def load_config(config_path: Optional[str]) -> CompanionConfig:
    if config_path:
        target_path = Path(config_path)
        if not target_path.exists():
            raise FileNotFoundError(f"Configuration file not found: {config_path}")
        with open(target_path, "r", encoding="utf-8") as f:
            data = json.load(f)
        return CompanionConfig.from_dict(data)

    discovered = find_default_config_path()
    if discovered:
        with open(discovered, "r", encoding="utf-8") as f:
            data = json.load(f)
        return CompanionConfig.from_dict(data)

    # Return default empty config
    return CompanionConfig(
        server_id="srv_default",
        journal_path="/var/lib/agentdeck/events.jsonl",
        lock_path="/run/agentdeck/companion.pid",
    )


def print_json(data: Dict[str, Any]) -> None:
    print(json.dumps(data, indent=2, ensure_ascii=False))


def cmd_version(args: argparse.Namespace) -> int:
    payload = {
        "schemaVersion": SCHEMA_VERSION,
        "binaryVersion": BINARY_VERSION,
        "protocolVersion": PROTOCOL_VERSION,
    }
    print_json(payload)
    return 0


def cmd_health(args: argparse.Namespace) -> int:
    try:
        config = load_config(args.config)
        daemon = CompanionDaemon(config)
        health = daemon.get_health()
        print_json(health)
        return 0
    except Exception as e:
        print_json({
            "schemaVersion": SCHEMA_VERSION,
            "status": "error",
            "version": BINARY_VERSION,
            "error": str(e),
        })
        return 1


def cmd_status(args: argparse.Namespace) -> int:
    try:
        config = load_config(args.config)
        daemon = CompanionDaemon(config)
        status = daemon.get_status()
        print_json(status)
        return 0
    except Exception as e:
        print_json({
            "schemaVersion": SCHEMA_VERSION,
            "status": "error",
            "error": str(e),
        })
        return 1


def cmd_events(args: argparse.Namespace) -> int:
    try:
        config = load_config(args.config)
        journal = EventJournal(
            journal_path=config.journal_path,
            max_events=config.retention.max_events,
            max_age_days=config.retention.max_age_days,
        )
        events, last_seq, has_more = journal.query(
            after_sequence=args.after,
            limit=args.limit,
        )
        payload = {
            "schemaVersion": SCHEMA_VERSION,
            "events": [e.to_dict() for e in events],
            "lastSequence": last_seq,
            "hasMore": has_more,
            "count": len(events),
        }
        print_json(payload)
        return 0
    except Exception as e:
        print_json({
            "schemaVersion": SCHEMA_VERSION,
            "events": [],
            "error": str(e),
        })
        return 1


def cmd_snapshot(args: argparse.Namespace) -> int:
    try:
        config = load_config(args.config)
        daemon = CompanionDaemon(config)
        # Perform single scan to capture current state
        daemon.scan_once(is_baseline=True)
        snapshot = daemon.get_snapshot()
        print_json(snapshot)
        return 0
    except Exception as e:
        print_json({
            "schemaVersion": SCHEMA_VERSION,
            "error": str(e),
        })
        return 1


def cmd_projects(args: argparse.Namespace) -> int:
    try:
        config = load_config(args.config)
        payload = {
            "schemaVersion": SCHEMA_VERSION,
            "serverId": config.server_id,
            "projects": [p.to_dict() for p in config.projects],
            "count": len(config.projects),
        }
        print_json(payload)
        return 0
    except Exception as e:
        print_json({
            "schemaVersion": SCHEMA_VERSION,
            "projects": [],
            "error": str(e),
        })
        return 1


def cmd_scan_once(args: argparse.Namespace) -> int:
    try:
        config = load_config(args.config)
        daemon = CompanionDaemon(config)
        events = daemon.scan_once(is_baseline=args.baseline)
        payload = {
            "schemaVersion": SCHEMA_VERSION,
            "scannedAt": format_iso(utc_now()),
            "baseline": args.baseline,
            "eventsGenerated": [e.to_dict() for e in events],
            "count": len(events),
        }
        print_json(payload)
        return 0
    except Exception as e:
        print_json({
            "schemaVersion": SCHEMA_VERSION,
            "eventsGenerated": [],
            "error": str(e),
        })
        return 1


def cmd_run(args: argparse.Namespace) -> int:
    try:
        config = load_config(args.config)
        daemon = CompanionDaemon(config)
        daemon.run()
        return 0
    except KeyboardInterrupt:
        return 0
    except Exception as e:
        sys.stderr.write(f"ERROR: {e}\n")
        return 1


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="agentdeck-companion",
        description="AgentDeck Server Companion & Remote Observer daemon / CLI.",
    )
    subparsers = parser.add_subparsers(dest="command", help="Command to execute")

    # Common options parent parser
    common_parser = argparse.ArgumentParser(add_help=False)
    common_parser.add_argument(
        "--config", "-c",
        type=str,
        default=None,
        help="Path to agentdeck-companion.json config file",
    )
    common_parser.add_argument(
        "--json",
        action="store_true",
        default=True,
        help="Format output as JSON (default: true)",
    )

    # version
    p_version = subparsers.add_parser("version", parents=[common_parser], help="Display version and protocol info")
    p_version.set_defaults(func=cmd_version)

    # health
    p_health = subparsers.add_parser("health", parents=[common_parser], help="Display health information")
    p_health.set_defaults(func=cmd_health)

    # status
    p_status = subparsers.add_parser("status", parents=[common_parser], help="Display full diagnostic status")
    p_status.set_defaults(func=cmd_status)

    # events
    p_events = subparsers.add_parser("events", parents=[common_parser], help="Query journal events")
    p_events.add_argument(
        "--after",
        type=int,
        default=0,
        help="Fetch events strictly after sequence ID (default: 0)",
    )
    p_events.add_argument(
        "--limit",
        type=int,
        default=100,
        help="Max events to return (1-500, default: 100)",
    )
    p_events.set_defaults(func=cmd_events)

    # snapshot
    p_snap = subparsers.add_parser("snapshot", parents=[common_parser], help="Capture current state snapshot")
    p_snap.set_defaults(func=cmd_snapshot)

    # projects
    p_projects = subparsers.add_parser("projects", parents=[common_parser], help="List registered projects")
    p_projects.set_defaults(func=cmd_projects)

    # scan-once
    p_scan = subparsers.add_parser("scan-once", parents=[common_parser], help="Execute a single scan cycle")
    p_scan.add_argument(
        "--baseline",
        action="store_true",
        default=False,
        help="Run as initial baseline without generating historical alert spam",
    )
    p_scan.set_defaults(func=cmd_scan_once)

    # run (daemon)
    p_run = subparsers.add_parser("run", parents=[common_parser], help="Start continuous daemon observation loop")
    p_run.set_defaults(func=cmd_run)

    return parser


def main() -> None:
    parser = build_parser()
    args = parser.parse_args()

    if not hasattr(args, "func"):
        # Default to version if no command given
        cmd_version(args)
        sys.exit(0)

    code = args.func(args)
    sys.exit(code)


if __name__ == "__main__":
    main()
