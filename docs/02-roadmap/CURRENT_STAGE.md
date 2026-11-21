# Current stage

Milestone: **H1.1 — Push Relay hardening: pairing, installation tokens, fail-closed config (incl. H1.1b app integration)**
Status: **H1_1_COMPLETE_LOCALLY_VERIFIED**, 2026-11-21. Codemagic status unchanged: `CODEMAGIC_CONFIG_READY`; `REAL_APNS: PENDING_TESTFLIGHT_VALIDATION`.

Design, review findings, decisions and threat model: `docs/03-stages/H1_RELAY_PAIRING.md` (ADR-019).

Done:
- Relay: one-time pairing code -> per-installation token (SHA-256 only in the relay), revocation CLI, fail-closed production mode, body limit, sanitized errors, real health, loopback bind, atomic exchange and migration with rollback.
- App: Settings is real and opens Push Notification Settings with the bootstrap services; the relay URL is persistent and configurable (empty initially, origin-only, HTTPS except loopback); the token lives only in the Keychain, keyed by relay origin; `InstallationIdentity` is 128-bit `Random.secure()`; production push service is `UnavailablePushNotificationService` (no fake tokens); `crypto` declared as a direct dev dependency.
- Companion/tmux: confirmed by a two-user lab; systemd unit intentionally unchanged.

Executed validation (Windows, 2026-11-21):
- `dart format --output=none --set-exit-if-changed lib test tool`: PASS
- `flutter analyze`: PASS, 0 issues
- `flutter test`: PASS, 240/240
- Python `unittest` (server/tests): PASS, 82 tests on Windows (1 POSIX-only skip) and 82/82 on Linux (WSL Ubuntu)
- `dart run tool/push_lab.dart`: PASS, scenarios A through Q
- `git diff --check`: PASS
- Final strict-loopback fix: format, analyze, flutter test (240/240) and diff check re-run after it; Python tests, WSL and push lab were not re-run (no Python change; last run 82 tests, push lab A-Q).
- Docker labs: NOT RUN (Docker daemon not running). Real VPS, Caddy, APNs, iPhone: NOT RUN.

Not done: native APNs and entitlements; QR pairing; Companion systemd user/`PrivateTmp` fix; VPS provisioning; Caddy validation; silent-notification decision (`UIBackgroundModes`); Codemagic run, signing, TestFlight, physical iPhone. The Settings/pairing flow has not been exercised on a device.

Previous stage summary: Codemagic CI/CD scaffolding (`CODEMAGIC_CONFIG_READY`, 2026-10-27) — see `docs/03-stages/RELEASE_READINESS_REVIEW.md` and `docs/06-research/CODEMAGIC_SETUP.md`.

Next: H1 part 2 (Companion service user/tmux fix verified with a systemd-level test, VPS provisioning scripts), before any native APNs work.
