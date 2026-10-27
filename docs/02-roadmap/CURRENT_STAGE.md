# Current stage

Milestone: **Product / Security / iOS Release Readiness Review**
Status: **READY_FOR_MACOS_VALIDATION** (M0 through M9 comprehensively audited, hardened, verified; `REAL_APNS: PENDING_MACOS_VALIDATION`), 2026-09-28

Completed comprehensive, systematic audit across 88 dimensions of AgentDeck:
- **Architecture & Purity**: Strict layered architecture, domain purity, clean third-party isolation (dartssh2, xterm, secure storage), zero leaks.
- **Security & Boundaries**: 4 non-overlapping trust zones, strict host key pinning (TOFU/SHA256), zero plaintext credential persistence in JSON/Git, safe argument construction, command injection defenses across Git, SFTP, systemctl, tmux, and agents.
- **Lifecycle & Continuity**: Full disposal audit, background/foreground boundary verification, fail-closed persistence, corruption recovery, feature degradation matrix.
- **Verification Matrix**: All automated suites passing with 100% success rate:
  - Flutter analyze: `0 issues found`
  - Flutter tests: `172 / 172 PASS`
  - Python server tests: `20 / 20 PASS`
  - Push integration lab: `14 / 14 PASS` (Scenarios A through N)
  - Dart format & Git diff check: `PASS`
- **Release Readiness Document**: `docs/03-stages/RELEASE_READINESS_REVIEW.md` authored with exhaustive findings, persistence inventory, threat model alignment, and macOS handoff plan.

Next Milestone: **macOS + Xcode + Physical iPhone Validation** (Runner generation, Apple Developer signing, physical device APNs receipt, Keychain verification).
