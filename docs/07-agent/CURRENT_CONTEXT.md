# Current context

AgentDeck is an independent iPhone-first Flutter app at `C:\Users\vszni\repositorios\AgentDeck`. Flutter 3.47.5/Dart 3.13.4 is at `C:\Users\vszni\sdk\flutter`. M0 through M9 are complete, Release Readiness is complete, and Codemagic CI/CD is configured with status **`CODEMAGIC_CONFIG_READY`** (`REAL_APNS: PENDING_TESTFLIGHT_VALIDATION`) as of 2026-10-27.

Summary of CI/CD Pipeline & Release Architecture:
- **Build & CI Strategy**: Windows local development -> GitHub -> Codemagic macOS Runner (`mac_mini_m2`, Apple Silicon, Flutter 3.47.5, Xcode latest, CocoaPods default). Eliminates the need for a local Mac workstation.
- **Workflow 1 (`ios-unsigned-validation`)**: Executes full quality gates (`tool/ci_verify.sh`) and `flutter build ios --debug --no-codesign`. Verifies complete iOS toolchain, pods, and Swift compilation in the cloud.
- **Workflow 2 (`ios-testflight`)**: Scaffolded production signing pipeline targeting Apple TestFlight for real physical iPhone delivery.
- **Automated Test Results**:
  - `flutter analyze`: 0 issues found
  - `flutter test`: 174/174 PASS (including `codemagic_config_test.dart`)
  - `python -m unittest`: 20/20 PASS
  - `tool/push_lab.dart`: 14/14 PASS (Scenarios A through N)
  - `dart format`: 100% compliant
  - `git diff --check`: PASS
- **Repository Hygiene**: Accidental Python `__pycache__` and `.pyc` files scrubbed from working tree and ignored via `.gitignore`. `.gitattributes` enforces LF across platforms. Zero secrets in source control.

PENDING_TESTFLIGHT_VALIDATION: Execution of Codemagic cloud workflow, Apple Developer Program account setup, App Store Connect API keys, signed IPA build, TestFlight distribution, and physical iPhone runtime verification (real APNs receipt, hardware Keychain, and Companion sync). Do not claim iOS or APNs hardware validation until physical TestFlight execution is confirmed.
