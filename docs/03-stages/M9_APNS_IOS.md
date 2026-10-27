# Stage M9 — APNs / iOS Native Integration

**Status:** `IN_PROGRESS` (Core Architecture & Lab: `M9_CORE_DONE`, Physical Apple Validation: `PENDING_MACOS_VALIDATION`)

---

## 1. Goal

Implement the complete, end-to-end Push Notification pipeline for AgentDeck on iOS:

```
Remote state change
      ↓
AgentDeck Companion (Managed Linux Host)
      ↓ Outbound HTTPS POST
AgentDeck Push Relay (Central Service)
      ↓ HTTP/2 Token-Auth (ES256 / .p8)
Apple Push Notification service (APNs)
      ↓
iPhone (iOS)
      ↓ Lock Screen Banner / Badge
User Tap
      ↓ Cold / Warm Start Deep Link
AgentDeck Flutter -> Target Screen (Terminal / Git / Server) + Journal Reconciliation
```

This guarantees that urgent events (e.g. `Codex -> WAITING_USER`, Git merge conflicts, server resource spikes) notify the developer's iPhone lock screen immediately even when:
- The AgentDeck Flutter app is completely terminated.
- The mobile SSH connection is closed.
- The iPhone is suspended or sleeping.

---

## 2. Architecture & Trust Boundaries

```
┌────────────────────────┐         ┌────────────────────────┐
│  Server Companion      │         │   AgentDeck Push Relay │
│  (Managed Linux Host)  │         │   (Central Gateway)    │
│                        │         │                        │
│  - Observes tmux/git   │ Outbound│  - Device Registry     │
│  - Zero secrets/APNs   ├────────►│  - APNs AuthKey (.p8)  │
│  - Outbox retry queue  │  HTTPS  │  - ES256 JWT Generator │
└────────────────────────┘         └───────────┬────────────┘
                                               │
                                               │ HTTP/2 Mutual TLS / Token Auth
                                               ▼
                                   ┌────────────────────────┐
                                   │   Apple APNs Gateway   │
                                   │   (api.push.apple.com) │
                                   └───────────┬────────────┘
                                               │
                                               │ Device-specific secure connection
                                               ▼
                                   ┌────────────────────────┐
                                   │   iPhone (iOS)         │
                                   │   - UserNotifications  │
                                   │   - Lock screen banner │
                                   │   - Deep link tap      │
                                   └────────────────────────┘
```

### Key Principles
1. **No APNs Provider Key on Servers**: The `.p8` key is stored strictly in the Push Relay; never on individual Linux servers or in the mobile application.
2. **Outbound-Only from Companion**: Managed servers make outbound HTTPS requests (`POST /v1/companion-events`) to the relay. Zero open inbound ports.
3. **End-to-End Idempotency**: Relay deduplicates events by `eventId`. At-least-once delivery from companion; idempotent ingestion on relay.
4. **Push is Ephemeral Signal, Journal is Canonical Truth**: Tapping a push notification navigates to the app and triggers an immediate catch-up sync with the companion journal (`events.jsonl`).
5. **Strict Data Privacy**: Push payloads never contain terminal outputs, prompt contents, diff text, or API credentials.

---

## 3. Subsystems & Components

### 1. AgentDeck Push Relay (`server/push_relay/`)
- **Language/Stack**: Python 3 Standard Library with SQLite persistence (`sqlite3`).
- **Endpoints**:
  - `POST /v1/devices/register`: Registers / rotates device tokens for an `installationId`.
  - `DELETE /v1/devices/by-token`: Deactivates uninstalled or rotated device tokens.
  - `POST /v1/companion-events`: Ingests events from authenticated companions, validates deduplication, formats sanitized payloads, and dispatches via `PushProvider`.
  - `GET /v1/health`: Health status, queue depth, active registrations.
- **Provider Abstraction**:
  - `PushProvider` interface.
  - `ApnsPushProvider`: Generates cached ES256 JWT tokens and executes HTTP/2 requests to APNs.
  - `FakePushProvider`: Mock provider for deterministic automated testing and lab validation.

### 2. Companion Outbox & Forwarding (`server/agentdeck_companion/`)
- When an event is detected and written to `events.jsonl`, if relay is enabled in `companion.json`, it is queued in the companion outbox.
- Asynchronously posts to `POST /v1/companion-events` with exponential backoff.
- Never blocks the primary observation loop on network stalls.

### 3. Flutter iOS Push Adapter & UX
- `InstallationIdentity`: UUID-based installation identifier persisted in versioned JSON storage (no hardware UDID, no fake user accounts).
- `PushDeviceRegistration`: Manages token registration and updates with Push Relay.
- `PushNotificationService`: Abstract domain contract for authorization requests, token retrieval, foreground handling, and deep link routing.
- `NotificationSettingsPage`: Contextual permission request banner, event type toggles, and privacy preview mode configuration (`Full`, `Project Only`, `Generic`).
- Cold-start & warm-start deep link dispatching.

---

## 4. Verification Matrix & Quality Gates

| Scenario | Description | Expected Outcome |
|---|---|---|
| **A** | Device registers with Push Relay | Registration stored in SQLite with valid `installationId` |
| **B** | Device token rotates | Existing token updated without creating duplicate device entries |
| **C** | Agent transition event generated | Fake agent enters `WAITING_USER`; transition detected |
| **D** | Companion forwards event to Relay | Event delivered to relay endpoint with companion authentication |
| **E** | Relay deduplicates retransmitted events | Idempotent ingestion; duplicate `eventId` generates zero duplicate pushes |
| **F** | Relay constructs sanitized APNs payload | `aps` alert formatted according to device privacy mode |
| **G** | APNs provider accepts request | Provider reports success (`200 OK`) |
| **H** | APNs `410 Unregistered` response | Relay automatically disables invalid device token |
| **I** | Transient APNs failure | Relay retries with exponential backoff and jitter |
| **J** | Push Relay offline during event | Companion retains event in outbox without data loss |
| **K** | Push Relay restored | Companion flushes pending outbox events successfully |
| **L** | Multiple devices registered | Push Relay fans out notification to all active devices |
| **M** | Generic privacy mode | Payload excludes project names and private identifiers |
| **N** | Privacy & secret scan | Zero `.p8` keys, bearer tokens, or transcripts found in logs or storage |

---

## 5. Exit Criteria & Status

- **Windows Development Status**: `M9_CORE_DONE`
- **Real Apple APNs Status**: `PENDING_MACOS_VALIDATION` (Requires physical iPhone, Xcode signing, and real Apple Developer account credentials).
