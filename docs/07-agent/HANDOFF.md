# Handoff

## Completed

**Release Readiness Review Completed** (`READY_FOR_MACOS_VALIDATION`, 2026-09-28).
Systematic product, security, architecture, lifecycle, persistence, and iOS readiness audit completed across M0 through M9:
- `docs/03-stages/RELEASE_READINESS_REVIEW.md`: Comprehensive audit report covering 88 dimensions, architectural layering, dependency graphs, credential lifecycles, command injection protections, persistence inventory, failure recovery matrices, and macOS handoff plan.
- Architecture verified: Strict layering, domain purity, clean third-party isolation (dartssh2, xterm, secure storage), zero leaks.
- Security verified: 4 non-overlapping trust zones, TOFU host key pinning, zero credentials in Git/JSON/logs, POSIX command escaping, pure SFTP, process privacy (`comm` only).
- Verified failure modes: Fail-closed JSON persistence, outbox recovery, headless companion degradation.

## Validation Results

- `flutter pub get`: PASS
- `dart format --output=none --set-exit-if-changed lib test tool`: PASS (0 format changes needed)
- `flutter analyze`: PASS (0 issues found, ran in 70.5s)
- `flutter test`: PASS (172/172 unit & widget tests passed)
- `Python Server Tests`: PASS (`server/tests/`: 20/20 PASS)
- `Push Relay Lab` (`tool/push_lab.dart`): PASS (Scenarios A through N: 14/14 PASS).
- `git diff --check`: PASS

## Pending / Next Step

- Milestone: **macOS + Xcode + Physical iPhone Validation**
- Execution Scope:
  1. Generate native `ios/` workspace via `flutter create --platforms=ios .` on macOS.
  2. Configure Apple Developer Team ID, Bundle ID (`com.agentdeck.app`), and Push Notification capabilities.
  3. Validate Keychain roundtrip, real APNs token registration, physical lock-screen notification display, background wake-up, terminated app cold-start deep linking, and companion journal catch-up on physical iPhone.
