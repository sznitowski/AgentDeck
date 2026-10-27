# Codemagic iOS CI/CD Architecture & Research

## 1. Context & Objectives

AgentDeck is developed on Windows 11 without a physical local macOS workstation.
To establish end-to-end verification, compilation, and distribution to a physical iPhone, AgentDeck leverages **Codemagic Cloud CI/CD** as its macOS and Xcode build host:

```text
Windows Development (Local)
       │ (git push)
       ▼
GitHub Repository (main)
       │ (webhook trigger)
       ▼
Codemagic macOS Runner (mac_mini_m2 / Apple Silicon)
       │ (Flutter 3.47.5, Xcode latest, CocoaPods default)
       ▼
Gate 1: Unsigned iOS Build (`flutter build ios --debug --no-codesign`)
       │
       ▼ (Future: Apple Developer Program credentials configured)
Gate 2: Signed Production IPA (`flutter build ipa --release`)
       │ (App Store Connect API)
       ▼
Apple TestFlight
       │
       ▼ (Install & Runtime verification)
Physical iPhone Runtime (Keychain, APNs, Companion sync)
```

---

## 2. Official Documentation & Sources Consulted

This specification and implementation are based on current official Codemagic documentation:
1. **Building Flutter apps with codemagic.yaml**: [https://docs.codemagic.io/yaml-quick-start/building-a-flutter-app/](https://docs.codemagic.io/yaml-quick-start/building-a-flutter-app/)
2. **Flutter Version Management**: [https://docs.codemagic.io/flutter-configuration/flutter-version-management/](https://docs.codemagic.io/flutter-configuration/flutter-version-management/)
3. **iOS Code Signing in YAML**: [https://docs.codemagic.io/yaml-code-signing/signing-ios/](https://docs.codemagic.io/yaml-code-signing/signing-ios/)
4. **Publishing to App Store Connect / TestFlight**: [https://docs.codemagic.io/yaml-publishing/app-store-connect/](https://docs.codemagic.io/yaml-publishing/app-store-connect/)
5. **Dependency Caching**: [https://docs.codemagic.io/yaml-basic-configuration/yaml-getting-started/#cache](https://docs.codemagic.io/yaml-basic-configuration/yaml-getting-started/#cache)

---

## 3. Toolchain & Version Pinning Strategy

### Flutter & Dart Version
- **Local Certified Baseline**: Flutter `3.47.5` (channel `stable`, revision `6a19cca564`), Dart `3.13.4`.
- **Codemagic Configuration**: `flutter: 3.47.5`.
- **Rationale**: Avoids `flutter: latest` drift across builds. If a runner instance does not have the exact patch pre-cached, Codemagic automatically provisions the specified version.

### macOS Host & Xcode
- **Instance Type**: `mac_mini_m2` (M2 Apple Silicon, 8 CPU cores, 16 GB RAM).
- **Xcode Version**: `latest` (Xcode 15 / 16 on macOS Sonoma / Sequoia).
- **CocoaPods**: `default` (matches macOS system gem).

---

## 4. Dependencies & iOS Native Plugin Audit

AgentDeck maintains a minimal, pure dependency footprint:

| Package | Version | iOS Native Plugin | Minimum iOS | Native Frameworks / Notes |
| :--- | :--- | :--- | :--- | :--- |
| `dartssh2` | 4.1.0 | **No** (Pure Dart) | N/A | Zero iOS native code; uses Dart `dart:io` sockets. |
| `xterm` | 4.0.0 | **No** (Pure Dart) | N/A | Canvas/CustomPainter terminal emulator; zero native pods. |
| `flutter_secure_storage` | 11.2.0 | **Yes** (`flutter_secure_storage_darwin`) | iOS 12.0+ | Apple `Security.framework` (iOS Keychain wrapper). |
| `path_provider` | 2.1.6 | **Yes** (`path_provider_foundation`) | iOS 12.0+ | Apple `Foundation.framework` (Standard app sandboxed dirs). |
| `flutter` | 3.47.5 | **Core** | iOS 12.0+ | Engine, Metal rendering pipeline. |

### Minimum iOS Target
The project's Xcode configuration in `ios/Runner.xcodeproj/project.pbxproj` is pinned to:
```text
IPHONEOS_DEPLOYMENT_TARGET = 15.0;
```
Both `flutter_secure_storage_darwin` and `path_provider_foundation` require iOS 12.0+, which is fully satisfied by iOS 15.0+.

---

## 5. CocoaPods Behavior & `Podfile` Generation

- **Local Status**: `ios/Podfile` is intentionally **not** generated on Windows because CocoaPods is a Ruby gem native to macOS/Darwin.
- **macOS CI Behavior**: When `flutter build ios` executes on a macOS runner with CocoaPods installed, Flutter detects that native plugins exist in `pubspec.yaml` (`flutter_secure_storage_darwin`, `path_provider_foundation`) and that `ios/Podfile` is absent.
- **Deterministic Synthesis**: Flutter synthesizes `ios/Podfile` from its embedded engine template (`packages/flutter_tools/templates/app/ios.tmpl/Podfile`), links the plugin pods into `ios/Pods/`, and generates `ios/Runner.xcworkspace`.
- **No Manual Intervention**: We do not commit an artificial or handcrafted `Podfile` from Windows, preserving deterministic generation by Flutter on the target platform.

---

## 6. Two-Workflow Architecture

### Workflow 1: `ios-unsigned-validation` (Gate 1 - Immediate)
- **Goal**: Verify complete compilation on macOS without code signing or Apple credentials.
- **Trigger**: Every push or pull request to `main`.
- **Quality Gates**:
  1. `flutter pub get`
  2. `dart format --output=none --set-exit-if-changed lib test tool`
  3. `flutter analyze` (0 issues threshold)
  4. `flutter test` (172 unit/widget tests)
  5. `python3 -m unittest discover -s server/tests` (20 companion/relay tests)
  6. `dart run tool/push_lab.dart` (14 integration scenarios)
  7. `git --no-pager diff --check` (0 whitespace errors)
- **Build Step**: `flutter build ios --debug --no-codesign`
- **Output Artifacts**: `build/ios/iphoneos/**/*.app`, build logs.

### Workflow 2: `ios-testflight` (Gate 2 - Future)
- **Goal**: Automated signing with App Store distribution certificate, generation of production IPA, and upload to TestFlight.
- **Trigger**: Git version tags (`v*`).
- **Signing Mechanism**: Codemagic automatic code signing via App Store Connect API:
  - Fetches certificates and provisioning profiles for `com.agentdeck.app`.
  - Injects signing profiles into Xcode.
  - Builds `--release` IPA using `flutter build ipa --release`.
- **Publishing**: `app_store_connect` section configured with TestFlight internal testing groups.

---

## 7. Security & Credential Boundary

- **Zero Apple Secrets in Git**: No `.p8`, `.p12`, or certificates stored in repository.
- **APNs `.p8` vs App Store Connect API Key**:
  - The Push Relay's APNs AuthKey (`AuthKey_<KEY_ID>.p8`) belongs **only** to the Push Relay server daemon. It is **never** required for building or signing the iOS app and is strictly excluded from CI.
  - The App Store Connect API key is used strictly by Codemagic for certificate management and TestFlight upload, configured as a masked secret in Codemagic's web UI.
