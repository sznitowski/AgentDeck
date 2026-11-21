"""CLI entry point for agentdeck-push-relay."""

import argparse
import json
import os
import stat
import sys
from typing import Dict, Any, Optional

from .models import SCHEMA_VERSION, RELAY_VERSION
from .pairing import DEFAULT_PAIRING_TTL_SECONDS
from .store import RelayStore
from .server import PushRelayService, RelayConfigError, validate_relay_security
from .apns_provider import FakePushProvider, ApnsPushProvider
from .jwt_helper import JwtTokenManager

MIN_COMPANION_SECRET_LENGTH = 16


def print_json(data: Dict[str, Any]) -> None:
    print(json.dumps(data, indent=2, ensure_ascii=False))


def load_relay_config(config_path: Optional[str]) -> Dict[str, Any]:
    """Loads config. Without a file the defaults are production + no secrets,
    which ``run`` rejects (fail closed)."""
    if config_path and os.path.exists(config_path):
        if os.name != "nt":
            mode = stat.S_IMODE(os.stat(config_path).st_mode)
            if mode & 0o077:
                raise RelayConfigError(
                    f"{config_path} is accessible by group/others (mode {mode:o}); chmod 600 it"
                )
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
            "mode": "production",
            "companionSecrets": {},
        },
    }


def is_production(config: Dict[str, Any]) -> bool:
    mode = config.get("security", {}).get("mode", "production")
    if mode not in ("production", "development"):
        raise RelayConfigError("security.mode must be 'production' or 'development'")
    return mode == "production"


def cmd_version(args: argparse.Namespace) -> int:
    print_json({
        "schemaVersion": SCHEMA_VERSION,
        "binaryVersion": RELAY_VERSION,
        "service": "agentdeck-push-relay",
    })
    return 0


def _open_store(args: argparse.Namespace, config: Dict[str, Any]) -> RelayStore:
    db_path = args.db or config.get("server", {}).get("databasePath", ":memory:")
    if db_path == ":memory:":
        raise RelayConfigError("this command needs a database file (server.databasePath or --db)")
    return RelayStore(db_path)


def cmd_run(args: argparse.Namespace) -> int:
    try:
        config = load_relay_config(args.config)
        production = is_production(config)
        server_cfg = config.get("server", {})
        host = args.host or server_cfg.get("host", "127.0.0.1")
        port = args.port or server_cfg.get("port", 8443)
        db_path = args.db or server_cfg.get("databasePath", ":memory:")
        companion_secrets = config.get("security", {}).get("companionSecrets", {})

        validate_relay_security(host, production, companion_secrets)
        if production:
            weak = [k for k, v in companion_secrets.items()
                    if not isinstance(v, str) or len(v) < MIN_COMPANION_SECRET_LENGTH]
            if weak:
                raise RelayConfigError(
                    f"companion secrets must be at least {MIN_COMPANION_SECRET_LENGTH} characters"
                )
    except RelayConfigError as e:
        sys.stderr.write(f"CONFIG ERROR: {e}\n")
        return 2

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

    service = PushRelayService(
        host=host,
        port=port,
        store=store,
        push_provider=provider,
        companion_secrets=companion_secrets,
        production=production,
    )

    mode_label = "production" if production else "DEVELOPMENT"
    sys.stderr.write(
        f"AgentDeck Push Relay v{RELAY_VERSION} ({mode_label}) listening on http://{host}:{port} "
        "(plain HTTP; terminate TLS in Caddy)\n"
    )
    try:
        service.start()
        return 0
    except KeyboardInterrupt:
        service.stop()
        return 0
    except Exception as e:
        sys.stderr.write(f"ERROR: {type(e).__name__}: {e}\n")
        return 1


def cmd_pairing_create(args: argparse.Namespace) -> int:
    try:
        config = load_relay_config(args.config)
        store = _open_store(args, config)
    except RelayConfigError as e:
        sys.stderr.write(f"CONFIG ERROR: {e}\n")
        return 2
    try:
        result = store.create_pairing_code(args.ttl_minutes * 60)
    finally:
        store.close()
    # The code is shown once here and never stored in plaintext or logged.
    print_json(result)
    return 0


def cmd_installations_list(args: argparse.Namespace) -> int:
    try:
        store = _open_store(args, load_relay_config(args.config))
    except RelayConfigError as e:
        sys.stderr.write(f"CONFIG ERROR: {e}\n")
        return 2
    try:
        print_json({"installations": store.list_installations()})
    finally:
        store.close()
    return 0


def cmd_installations_revoke(args: argparse.Namespace) -> int:
    try:
        store = _open_store(args, load_relay_config(args.config))
    except RelayConfigError as e:
        sys.stderr.write(f"CONFIG ERROR: {e}\n")
        return 2
    try:
        revoked = store.revoke_installation(args.installation_id)
    finally:
        store.close()
    print_json({"installationId": args.installation_id, "revoked": revoked})
    return 0 if revoked else 1


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="agentdeck-push-relay",
        description="AgentDeck Push Relay central daemon & CLI.",
    )
    subparsers = parser.add_subparsers(dest="command", help="Command to execute")

    common_parser = argparse.ArgumentParser(add_help=False)
    common_parser.add_argument("--config", "-c", type=str, default=None, help="Path to push-relay.json")
    common_parser.add_argument("--db", type=str, default=None, help="Database path")
    common_parser.add_argument("--json", action="store_true", default=True, help="JSON output")

    p_ver = subparsers.add_parser("version", parents=[common_parser])
    p_ver.set_defaults(func=cmd_version)

    p_run = subparsers.add_parser("run", parents=[common_parser])
    p_run.add_argument("--host", type=str, default=None, help="Bind host (loopback only in production)")
    p_run.add_argument("--port", type=int, default=None, help="Bind port")
    p_run.set_defaults(func=cmd_run)

    p_pair = subparsers.add_parser("pairing", help="Manage pairing codes")
    pair_sub = p_pair.add_subparsers(dest="pairing_command", required=True)
    p_pair_create = pair_sub.add_parser("create", parents=[common_parser])
    p_pair_create.add_argument(
        "--ttl-minutes", type=int, default=DEFAULT_PAIRING_TTL_SECONDS // 60,
        help="Code lifetime in minutes (max 15)",
    )
    p_pair_create.set_defaults(func=cmd_pairing_create)

    p_inst = subparsers.add_parser("installations", help="Manage paired installations")
    inst_sub = p_inst.add_subparsers(dest="installations_command", required=True)
    p_inst_list = inst_sub.add_parser("list", parents=[common_parser])
    p_inst_list.set_defaults(func=cmd_installations_list)
    p_inst_revoke = inst_sub.add_parser("revoke", parents=[common_parser])
    p_inst_revoke.add_argument("installation_id", type=str)
    p_inst_revoke.set_defaults(func=cmd_installations_revoke)

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
