# Notification Dependencies & Evaluation

## Context & Objectives

AgentDeck requires a structured notification subsystem. This document investigates the dependency options for local alerts, in-app notifications, and future push notifications on Flutter for iOS.

---

## 1. Local Notification Packages Comparison

| Package | Version | License | iOS Support | Foreground Banners | Deep-linking & Actions | Assessment |
|---|---|---|---|---|---|---|
| **`flutter_local_notifications`** | 18.0.1 | BSD-3-Clause | Excellent (`UNUserNotificationCenter`) | Yes (`UNNotificationPresentationOptions`) | Yes (`onDidReceiveNotificationResponse`) | Mature, well-maintained, standard choice for Flutter iOS/Android local alerts. |
| **`awesome_notifications`** | 0.9.3 | BSD-3-Clause | Good | Yes | Yes | Rich layouts, but heavier native overhead and higher maintenance burden. |
| **In-App Pure Dart Delivery** | Custom | MIT / Project | Universal | Yes (In-app snackbars, badges, notification center) | Universal (direct Flutter Navigator / state) | Zero native plugin dependency, ideal for M8 in-app event center. |

---

## 2. Milestone M8 Strategy: Decoupled Delivery Architecture

To maintain strict modularity, testability, and zero unnecessary native plugin dependencies before macOS/Xcode runner verification:

1. **Delivery Abstraction**: Define `NotificationDeliveryService` in Dart with:
   - `InAppNotificationDelivery`: Complete in-memory event bus + UI Activity/Notification Center + badge indicators.
   - `LocalNotificationDelivery`: Decoupled interface wrapping native OS notifications, tagged `PENDING_MACOS_VALIDATION` / `IMPLEMENTED_NOT_DEVICE_VALIDATED`.
   - `RemotePushDelivery`: Abstract contract reserved for Milestone M9 (APNs direct delivery).

2. **iOS Notification Permissions**:
   - Permission requests must not be triggered on cold app startup.
   - A contextual UI banner or Settings switch ("Enable notifications when an agent requests input") initiates permission requests before invoking OS APIs.

3. **Lock Screen Privacy**:
   - OS notifications support `NotificationPrivacyMode`:
     - `full`: Shows project name and sanitized status (`Codex is waiting for input • Portal Proveedores`).
     - `projectOnly`: Shows project name and generic alert (`Agent requires input • Portal Proveedores`).
     - `generic`: Shows completely opaque alert (`AgentDeck requires attention`).
   - Zero terminal outputs, diffs, tokens, or prompt bodies are ever forwarded to the notification subsystem.
