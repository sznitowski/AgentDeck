# Current stage

Milestone: **Product / Security / iOS Release Readiness Review & Codemagic CI Setup**
Status: **CODEMAGIC_CONFIG_READY** (M0 through M9 audited and verified; `REAL_APNS: PENDING_TESTFLIGHT_VALIDATION`), 2026-10-27

Completed comprehensive audit and cloud CI pipeline scaffolding:
- **Architecture & Purity**: Strict layered architecture, domain purity, clean third-party isolation (dartssh2, xterm, secure storage), zero leaks.
- **Security & Boundaries**: 4 non-overlapping trust zones, strict host key pinning (TOFU/SHA256), zero plaintext credential persistence in JSON/Git, safe argument construction, command injection defenses across Git, SFTP, systemctl, tmux, and agents.
- **Codemagic CI/CD Pipeline**: Configured `codemagic.yaml` with dual workflows:
  - `ios-unsigned-validation`: Automated quality gates (`tool/ci_verify.sh`) + `flutter build ios --debug --no-codesign` on macOS Apple Silicon (`mac_mini_m2`).
  - `ios-testflight`: Scaffolded release workflow with App Store Connect automated signing and TestFlight distribution.
- **Verification Matrix**: All automated suites passing with 100% success rate:
  - Flutter analyze: `0 issues found`
  - Flutter tests: `174 / 174 PASS` (including `codemagic_config_test.dart`)
  - Python server tests: `20 / 20 PASS`
  - Push integration lab: `14 / 14 PASS` (Scenarios A through N)
  - Dart format & Git diff check: `PASS`
- **Documentation**: `CODEMAGIC_IOS_RESEARCH.md` and `CODEMAGIC_SETUP.md` authored.

Next Milestone: **Codemagic Cloud Build Execution & Physical iPhone TestFlight Validation** (Gate 1: `ios-unsigned-validation`; Gate 2: Apple Developer signing & TestFlight delivery to user's iPhone).
