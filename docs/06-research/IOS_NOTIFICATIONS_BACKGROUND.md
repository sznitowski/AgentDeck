# iOS Background Execution & Notification Architecture

## Context & Objectives

AgentDeck is an iPhone-first mobile control surface for Linux servers and remote coding agents.
This document analyzes the fundamental constraints of iOS regarding background execution, continuous network sockets, background tasks, and notifications.

---

## 1. iOS Background Execution Realities

### Continuous SSH Monitoring is Not Feasible
- When the user leaves the AgentDeck app (home screen, app switcher, lock screen), iOS transitions the app to `inactive` and then `background`.
- Within seconds (typically 5–30 seconds), iOS suspends the app process completely unless an explicit background execution entitlement is active (e.g. audio playback, navigation, VoIP).
- Open TCP sockets (including SSH connections maintained by `dartssh2`) are closed or timed out by the OS kernel or the remote SSH server (`ClientAliveInterval`).
- **Conclusion**: Any design that assumes a background Dart `Timer.periodic` or an open SSH socket while the app is suspended will fail.

### BGTaskScheduler Limitations
- iOS provides `BGAppRefreshTask` and `BGProcessingTask` via `BGTaskScheduler`.
- Execution timing is entirely controlled by the operating system based on battery level, charging status, network connectivity, and user app usage patterns.
- iOS does not guarantee exact-time periodic execution (e.g., cannot guarantee polling every 1 minute).
- Background execution time is strictly bounded (typically 30 seconds max per wake-up).
- **Conclusion**: Background tasks can only be used for opportunistic, best-effort catch-up tasks, not for real-time alerting when an agent needs user approval.

### Silent Remote Push (Background Push)
- Apple APNs supports silent push notifications (`content-available: 1`).
- However, silent pushes are heavily rate-limited and throttled by iOS power management. If sent frequently or when battery is low, iOS drops or delays them without notifying the user.
- **Conclusion**: Silent push is suitable only for lightweight background cache warming, not real-time alerting.

---

## 2. Reliable Notification Topology: Client vs Server

| Requirement | Foreground App | Suspended App / Locked Screen |
|---|---|---|
| **Monitoring Mechanism** | Foreground SSH polling / stream observation via `ProjectWorkspaceCoordinator` | Server-side agent monitor / daemon (**AgentDeck Server Companion**) |
| **Notification Engine** | Local `StateTransitionDetector` + In-App notification center | Server-side alert generator -> APNs HTTP/2 Provider |
| **Alert Delivery** | In-app banners, badges, snackbars, and OS local notifications | Apple Push Notification service (APNs) |
| **Network Socket** | Active direct SSH client socket | No mobile socket required |

---

## 3. Milestones Roadmap for Notifications

```
   ┌─────────────────────────────────────────────────────────────┐
   │                    Milestone M8 (Current)                   │
   │ - Structured AgentDeckEvent domain model                    │
   │ - State transition detection (hysteresis, debouncing)       │
   │ - Deduplication engine                                      │
   │ - Atomic, zero-secret local event repository                │
   │ - Notification policy & privacy preview modes               │
   │ - Foreground / App resume Catch-Up transition evaluation    │
   │ - In-App Notification & Activity Center                     │
   └──────────────────────────────┬──────────────────────────────┘
                                  │
                                  ▼
   ┌─────────────────────────────────────────────────────────────┐
   │                  Milestone M8.5 (Companion)                 │
   │ - Lightweight Python/Go/Bash Linux Server Companion         │
   │ - Watches tmux sessions, agent processes, git, & metrics   │
   │ - Zero-install or single-file deployment                    │
   └──────────────────────────────┬──────────────────────────────┘
                                  │
                                  ▼
   ┌─────────────────────────────────────────────────────────────┐
   │                   Milestone M9 (APNs Push)                  │
   │ - APNs HTTP/2 push provider integration                     │
   │ - iOS device token registration & keychain storage          │
   │ - End-to-end background alerts to iPhone lock screen        │
   └─────────────────────────────────────────────────────────────┘
```

---

## 4. Key Rules for Milestone M8

1. **No Fake Backgrounding**: Never implement continuous timers with claims of background monitoring.
2. **Foreground & Catch-Up Polling**: Run polling timers strictly while the app is mounted in the foreground. Upon app resume (`AppLifecycleState.resumed`), trigger an immediate catch-up workspace inspection and state transition evaluation.
3. **Structured Domain Events**: Model events cleanly as `AgentDeckEvent` independent of notification presentation.
4. **Zero-Secret Payload**: Persist only sanitized identifiers and summaries in local event storage.
