"""CLI entry point for agentdeck-push-relay."""

import argparse
import json
import os
from pathlib import Path
import sys
from typing import Dict, Any, Optional

from .models import (
    SCHEMA_VERSION,
    RELAY_VERSION,
    DeviceRegistration,
    utc_now,
    format_iso,
)
from .store import RelayStore
from .server import PushRelayService
from .apns_provider import FakePushProvider, ApnsPushProvider
from .jwt_helper import JwtTokenManager


def print_json(data: Dict[str, Any]) -> None:
    print(json.dumps(data, indent=2, ensure_ascii=False))


def load_relay_config(config_path: Optional[str]) -> Dict[str, Any]:
    if config_path and os.path.exists(config_path):
        with open(config_path, "r", encoding="utf-8") as f:
            return json.load(f)
    return {
        "server": {
            "host": "127.0.0.1",
            "port": 8443,
            "databasePath": ":memory:",
        },
        "apns": {
            "enabled": False,
        },
        "security": {
            "companionSecrets": {},
        },
    }


def cmd_version(args: argparse.Namespace) -> int:
    print_json({
        "schemaVersion": SCHEMA_VERSION,
        "binaryVersion": RELAY_VERSION,
        "service": "agentdeck-push-relay",
    })
    return 0


def cmd_run(args: argparse.Namespace) -> int:
    config = load_relay_config(args.config)
    server_cfg = config.get("server", {})
    host = args.host or server_cfg.get("host", "127.0.0.1")
    port = args.port or server_cfg.get("port", 8443)
    db_path = args.db or server_cfg.get("databasePath", ":memory:")


    store = RelayStore(db_path)
    apns_cfg = config.get("apns", {})

    if apns_cfg.get("enabled", False):
        jwt_mgr = JwtTokenManager(
            team_id=apns_cfg.get("teamId", ""),
            key_id=apns_cfg.get("keyId", ""),
            private_key_path=apns_cfg.get("privateKeyPath"),
        )
        provider = ApnsPushProvider(
            jwt_manager=jwt_mgr,
            bundle_id=apns_cfg.get("bundleId", "com.agentdeck.app"),
            environment=apns_cfg.get("environment", "sandbox"),
        )
    else:
        provider = FakePushProvider()

    companion_secrets = config.get("security", {}).get("companionSecrets", {})

    service = PushRelayService(
        host=host,
        port=port,
        store=store,
        push_provider=provider,
        companion_secrets=companion_secrets,
    )

    sys.stderr.write(f"AgentDeck Push Relay v{RELAY_VERSION} listening on http://{host}:{port}\n")
    try:
        service.start()
        return 0
    except KeyboardInterrupt:
        service.stop()
        return 0
    except Exception as e:
        sys.stderr.write(f"ERROR: {e}\n")
        return 1


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="agentdeck-push-relay",
        description="AgentDeck Push Relay central daemon & CLI.",
    )
    subparsers = parser.add_subparsers(dest="command", help="Command to execute")

    common_parser = argparse.ArgumentParser(add_help=False)
    common_parser.add_argument("--config", "-c", type=str, default=None, help="Path to push-relay.json")
    common_parser.add_argument("--json", action="store_true", default=True, help="JSON output")

    # version
    p_ver = subparsers.add_parser("version", parents=[common_parser])
    p_ver.set_defaults(func=cmd_version)

    # run
    p_run = subparsers.add_parser("run", parents=[common_parser])
    p_run.add_argument("--host", type=str, default=None, help="Bind host")
    p_run.add_argument("--port", type=int, default=None, help="Bind port")
    p_run.add_argument("--db", type=str, default=None, help="Database path")
    p_run.set_defaults(func=cmd_run)


    return parser


def main() -> None:
    parser = build_parser()
    args = parser.parse_args()

    if not hasattr(args, "func"):
        cmd_version(args)
        sys.exit(0)

    sys.exit(args.func(args))


if __name__ == "__main__":
    main()
