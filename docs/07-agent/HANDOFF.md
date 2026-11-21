# Handoff

## Completed (2026-11-21, stage H1.1 + H1.1b)

Push Relay hardening and its real integration into the app. Design, review findings and decisions: `docs/03-stages/H1_RELAY_PAIRING.md`, ADR-019.

1. **Relay (`server/push_relay/`)**: `pairing.py`; `store.py` (pairing_codes, installations, schema_meta, atomic exchange and migration with rollback); `server.py` (bearer auth, fail-closed companion auth, 64 KiB limit, sanitized 500, real health, loopback-only production bind, body drain on early errors, field validation); `cli.py` (`pairing create`, `installations list|revoke`, production default).
2. **Companion**: `relay.url` must be `https://` (loopback `http://` allowed).
3. **Flutter**:
   - Settings tab is real (`SettingsPage` -> `NotificationSettingsPage`), wired from `NavigationShell` with the bootstrap services.
   - `RelayConfigRepository` + `FileRelayConfigRepository` (`agentdeck_push_relay_config.json`): relay origin only, empty initially.
   - `RelayUrlPolicy`: origin-only (no path/query/userinfo), HTTPS except loopback. One relay per origin; Keychain reference `push_relay_installation_token@<origin>`.
   - `PushRelayPairingService`: token only in the Keychain; only a 401 deletes the current relay's token.
   - `InstallationIdentity`: 128-bit `Random.secure()`, injectable random, legacy ids kept.
   - Production push service is `UnavailablePushNotificationService` (never registers a fake token).
   - `crypto` is a direct dev dependency (used by `tool/sftp_lab.dart`).
4. **Labs/tests**: `tool/push_lab.dart` (A through Q, production-mode relay with real pairing); Python 20 -> 82; Dart 174 -> 240; two-user tmux lab `tool/companion_tmux_users_lab.sh`.
5. **Docs**: README, PUSH_DEPLOYMENT (Caddy, pairing ops), PUSH_RELAY_PROTOCOL, ARCHITECTURE, DECISIONS (ADR-019), H1_RELAY_PAIRING.

## Validation Results (executed 2026-11-21)

- dart format: PASS; flutter analyze: PASS (0 issues); flutter test: 240/240 PASS
- Python: 82 tests PASS on Windows (1 POSIX-only skip) and on Linux (WSL)
- push lab A through Q: PASS; git diff --check: PASS
- Docker labs: NOT RUN (daemon not running). Real VPS, Caddy, APNs, iPhone: NOT RUN.

## Pending / Next Step

- Nothing is committed; the working tree holds all changes for review.
- H1 part 2: Companion systemd user / `PrivateTmp` fix (confirmed by lab) with a systemd-level test; VPS provisioning scripts; validate `Caddyfile.example` with a real Caddy.
- Decide silent notifications before touching `UIBackgroundModes`.
- Native APNs (needs macOS/Apple), Codemagic runs, TestFlight. QR pairing needs a scanner dependency.
