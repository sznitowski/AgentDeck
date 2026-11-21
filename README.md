# AgentDeck

AgentDeck is an iPhone-first control center for Linux servers, projects and remote coding agents. Agents run on the server (inside tmux); the mobile app connects over SSH, observes and reconnects. The product is independent of KAMMEL SSH.

**Current status:** M0–M9 implemented at the code level; Codemagic configured (`CODEMAGIC_CONFIG_READY`). Real APNs, signed builds, TestFlight, physical iPhone validation, a real VPS deployment and App Store submission are all still **pending**. See `docs/02-roadmap/CURRENT_STAGE.md` and `docs/03-stages/RELEASE_READINESS_REVIEW.md`.

Implemented: SSH with host key pinning and Keychain-backed credentials, terminal, tmux persistent sessions, SFTP file management, agent launch/observation (Codex, Claude Code, OpenCode, Antigravity, generic CLI), Git operations, server operations, project workspace, server Companion (Python) and Push Relay (Python).

Push Relay (H1.1, 2026-11-21): device operations require a per-installation token obtained by pairing with a one-time code; the relay fails closed and listens only on loopback behind Caddy (TLS). Settings -> Push Notifications configures the relay URL and pairing. Known gaps: native iOS APNs registration is not implemented (production uses an unavailable-push placeholder, never a fake token), QR pairing, and no real VPS/Caddy/iPhone validation yet.

Flutter 3.47.5 / Dart 3.13.4 is installed at C:\Users\vszni\sdk\flutter, outside this repository (not on PATH). Runtime packages: dartssh2 4.1.0, flutter_secure_storage 11.2.0, path_provider 2.1.6, xterm 4.0.0.

Quality gates: `tool/ci_verify.sh` (Codemagic) or `tool/pre_ci_check.ps1` (Windows).
