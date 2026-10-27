# Current context

AgentDeck is an independent iPhone-first Flutter app at `C:\Users\vszni\repositorios\AgentDeck`. Flutter 3.47.5/Dart 3.13.4 is at `C:\Users\vszni\sdk\flutter`. M0 through M9 are complete, and the **Product / Security / iOS Release Readiness Review** is complete with status **`READY_FOR_MACOS_VALIDATION`** as of 2026-09-28.

Summary of Release Readiness Audit:
- **Audit Scope**: Comprehensive evaluation across 88 dimensions covering architecture layering, service lifecycles, cryptographic trust models, credential boundaries, command injection defenses, data persistence, network failure recoveries, mobile UI/UX, and iOS release readiness.
- **Stage Document**: Authored `docs/03-stages/RELEASE_READINESS_REVIEW.md` documenting architecture review, dependency graph, secret storage review, command injection defenses, persistence inventory, feature degradation matrix, and macOS handoff plan.
- **Automated Test Results**:
  - `flutter analyze`: 0 issues found (ran in 70.5s)
  - `flutter test`: 172/172 PASS
  - `python -m unittest`: 20/20 PASS
  - `tool/push_lab.dart`: 14/14 PASS (Scenarios A through N)
  - `dart format`: 100% compliant
  - `git diff --check`: PASS

PENDING_MACOS_VALIDATION: Physical iPhone, native iOS runner generation (`ios/`), Xcode signing, Apple Developer credentials, real APNs device token registration, physical lock-screen notification receipt, background/terminated app tap deep-linking, and canonical companion journal reconciliation on hardware. Do not claim iOS validation on macOS until physical/runner device validation is executed.
