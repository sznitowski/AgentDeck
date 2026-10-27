# iOS Native Validation & Real Device Checklist

## Overview

This checklist defines the physical device validation steps required to advance Milestone M9 from `M9_CORE_DONE` to final `M9_DONE` on a macOS workstation with Xcode and a connected physical iPhone.

---

## 1. Prerequisites (macOS Environment)

- [ ] macOS Sequoia (15.x) or macOS Sonoma (14.x)
- [ ] Xcode 16.x with Command Line Tools
- [ ] Apple Developer Program enrollment (Team ID with Push Notification entitlement)
- [ ] Registered App ID `com.agentdeck.app` with Push Notifications capability enabled
- [ ] Generated APNs Provider Key (`AuthKey_<KEY_ID>.p8`)
- [ ] Physical iPhone running iOS 18.x or iOS 17.x connected via USB / Wi-Fi debugging

---

## 2. macOS Validation Gates

### Gate 1: Flutter Toolchain & iOS Build
```bash
flutter doctor -v
flutter pub get
cd ios && pod install && cd ..
flutter build ios --no-codesign
```
- **Validation Criteria**: Zero build errors, clean Swift compilation, correct minimum deployment target (iOS 16.0+).

---

### Gate 2: Xcode Code Signing & Entitlements
1. Open `ios/Runner.xcworkspace` in Xcode.
2. Under **Signing & Capabilities**:
   - Select your Apple Developer Team.
   - Verify Bundle Identifier matches `com.agentdeck.app`.
   - Add **Push Notifications** capability.
   - Add **Background Modes** (Remote notifications) if background fetch is enabled.
3. Deploy to physical iPhone via Xcode or `flutter run -d <iPhone_Device_ID>`.

---

### Gate 3: Contextual Permission Request UX
1. Open AgentDeck on the physical iPhone.
2. Navigate to **Settings -> Notifications**.
3. Verify contextual pre-prompt dialog: "Stay informed when remote agents need you..."
4. Tap **Enable Notifications**.
5. Verify native iOS system prompt (`UNUserNotificationCenter.requestAuthorization`):
   - Tap **Allow**.
   - Verify status transitions to `authorized`.
   - Toggle to denied in iOS Settings app and verify status transitions to `denied` with an "Open iOS Settings" action.

---

### Gate 4: Device Token Generation & Registration
1. Verify device token is received via `didRegisterForRemoteNotificationsWithDeviceToken`.
2. Confirm device registration payload sent to Push Relay:
   - Device token (64-char hex).
   - Platform: `ios`.
   - Environment: `production` or `sandbox`.
   - Installation ID (UUID).
3. Confirm token is not printed in plaintext to application console or public logs.

---

### Gate 5: Real APNs End-to-End Test (Primary Gate)

#### Test Scenario A: App Terminated (Cold Start)
1. Terminate AgentDeck on the iPhone (swipe up from App Switcher).
2. Ensure SSH connections from mobile are closed.
3. On the remote test server, trigger fake agent transition:
   ```bash
   agentdeck-fake-agent waiting
   ```
4. Observe pipeline:
   - `agentdeck-companion` detects `WAITING_USER` transition.
   - Companion forwards event to Push Relay (`POST /v1/companion-events`).
   - Push Relay sends ES256-signed HTTP/2 request to `api.push.apple.com`.
   - APNs returns HTTP 200 OK.
5. **Physical Lock Screen Verification**:
   - iPhone wakes and displays alert banner: **"Codex is waiting for input in Portal Proveedores"**.
6. **Tap & Deep Link Routing**:
   - Tap notification on lock screen.
   - AgentDeck launches from cold start.
   - App automatically navigates to **TerminalPage** (attached to the agent's tmux session) or **ProjectWorkspacePage**.
   - Companion journal catch-up sync reconciles event as read in Notification Center.

#### Test Scenario B: App in Background
1. Put AgentDeck in background (return to iOS home screen).
2. Trigger remote Git conflict or agent failure.
3. Banner appears at top of screen.
4. Tap banner -> AgentDeck resumes in foreground and navigates to the conflict/failure view.

#### Test Scenario C: App in Foreground
1. AgentDeck open in foreground.
2. Event arrives -> Notification badge updates live; in-app banner/snackbar appears without intrusive lock screen duplicate.

---

## 3. Current Status

```text
Core Architecture & Lab:           PASS (M9_CORE_DONE)
macOS Build Toolchain:             PENDING_MACOS_VALIDATION
Physical iPhone Signing:           PENDING_MACOS_VALIDATION
APNs Device Token Generation:      PENDING_MACOS_VALIDATION
Lock Screen Visual Alert:          PENDING_MACOS_VALIDATION
Cold-Start Deep Link Tap:          PENDING_MACOS_VALIDATION
```
