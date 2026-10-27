# Codemagic CI/CD Setup Guide for AgentDeck

This guide walks through configuring Codemagic to build AgentDeck on macOS runners from GitHub, enabling iPhone testing without owning a physical Mac.

---

## Part 1: Gate 1 — Unsigned iOS Validation (Immediate)

### 1. Create a Codemagic Account
- Navigate to [https://codemagic.io/signup](https://codemagic.io/signup).
- Sign up using your **GitHub account** where `AgentDeck` is hosted.
- Codemagic provides free monthly build minutes on macOS Apple Silicon runners.

### 2. Connect Your GitHub Repository
1. In the Codemagic dashboard, click **Add application**.
2. Select **Git provider: GitHub**.
3. Locate `AgentDeck` (or grant access to the repository if prompted).
4. Select **Flutter App** as the project type and click **Finish: Add application**.

### 3. Select Configuration File (`codemagic.yaml`)
1. On the application settings page, switch to the **codemagic.yaml** tab (if not already selected).
2. Codemagic will automatically detect the `codemagic.yaml` file present in the repository root.

### 4. Execute the First Unsigned Build
1. In the top right corner, click **Start new build**.
2. Select:
   - **Branch**: `main`
   - **Workflow**: `ios-unsigned-validation`
3. Click **Start build**.

### 5. Monitor Logs and Status
- Codemagic allocates a `mac_mini_m2` runner and begins execution.
- Live logs will display each step in real time:
  1. `Display Host & Toolchain Info`: macOS, Xcode, Flutter, CocoaPods versions.
  2. `Run AgentDeck CI Quality Gates`: executes `tool/ci_verify.sh` (pub get, format check, analyze, Flutter tests, Python tests, push lab, git diff check).
  3. `Build Unsigned iOS Runner`: executes `flutter build ios --debug --no-codesign`.

### 6. Inspect Artifacts
Upon completion, the build overview page displays:
- **Build Status**: Green checkmark (`SUCCESS`).
- **Artifacts Tab**: Downloadable `Runner.app` archive and compilation logs.

---

## Part 2: Gate 2 — TestFlight Signed Release (Future)

> [!NOTE]
> Execute these steps only after acquiring Apple Developer Program membership.

### 7. Generate App Store Connect API Key
1. Go to [App Store Connect](https://appstoreconnect.apple.com/) > **Users and Access** > **Integrations** > **App Store Connect API**.
2. Click **+** to generate a new key:
   - **Name**: `Codemagic CI Key`
   - **Access**: `App Manager` or `Admin`.
3. Note down:
   - **Issuer ID** (displayed at the top).
   - **Key ID** (e.g., `ABC1234567`).
   - Download the `.p8` file (e.g., `AuthKey_ABC1234567.p8`). *Note: Apple only allows downloading this once.*

### 8. Configure Codemagic Environment Group
1. In Codemagic, open your application > **Environment variables**.
2. Add a new variable group named: **`app_store_credentials`**.
3. Add the following variables (marked as **Secret**):
   - `APP_STORE_CONNECT_ISSUER_ID`: Your Apple Issuer ID UUID.
   - `APP_STORE_CONNECT_KEY_IDENTIFIER`: Your 10-character Key ID.
   - `APP_STORE_CONNECT_PRIVATE_KEY`: The entire content of the downloaded `.p8` file.
   - `CERTIFICATE_PRIVATE_KEY`: A generated RSA/ECDSA private key for the iOS distribution certificate (or let Codemagic generate one automatically).
4. Update `APP_STORE_APPLE_ID` in `codemagic.yaml` with the numerical App ID from your App Store Connect app record.

### 9. Trigger TestFlight Build
1. Create and push a version tag:
   ```powershell
   git tag v0.1.0
   git push origin v0.1.0
   ```
2. Codemagic will automatically trigger the `ios-testflight` workflow:
   - Runs full quality gates.
   - Automatically provisions certificates and profiles.
   - Compiles `AgentDeck.ipa`.
   - Uploads to TestFlight for distribution to your physical iPhone!
