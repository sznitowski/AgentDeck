# Stage M8 — Event & Notification Core

**Status:** `DONE` (`M8_DONE`)

## 1. Goal

Build the core event and notification engine for AgentDeck. Transforms observed remote domain states into structured `AgentDeckEvent` records, evaluates state transitions and hysteresis, applies deduplication and notification policies, persists zero-secret event records with bounded retention, and renders an in-app Activity / Notification Center with deep-action CTAs.

---

## 2. Requirements & Architecture

### Domain Event Model
- `AgentDeckEvent`: Unified event model containing:
  - `id`: unique UUID/nonce string.
  - `type`: `EventType` enum.
  - `projectId`, `serverId`, `agentInstanceId`: entity references.
  - `detectedAt`, `occurredAt`: detection and approximate occurrence timestamps.
  - `severity`: `EventSeverity` (`info`, `warning`, `actionRequired`, `critical`).
  - `source`: `EventSource` (`agent`, `git`, `connection`, `tmux`, `files`, `server`).
  - `fingerprint`: stable deduplication string.
  - `title`, `message`: sanitized, human-readable strings.
  - `metadata`: structured key-value pairs (strictly non-secret).
  - `isProduction`: boolean indicating production environment context.
  - `destination`: structured `NotificationDestination` for deep navigation.
  - `readState`: `EventReadState` (`unread`, `read`, `acknowledged`).

### State Transition Detection Rules
- **Agent**:
  - `running/idle/starting -> waitingUser`: `agentWaitingUser` (`actionRequired`, CTA: `Respond`).
  - `running/starting/waitingUser -> failed`: `agentFailed` (`critical`, CTA: `Inspect`).
  - `running -> finished`: `agentFinished` (`info`).
  - Repeated `waitingUser -> waitingUser` emits **zero** events.
- **Git**:
  - `0 conflicts -> >0 conflicts`: `gitConflictDetected` (`critical`, CTA: `View Conflicts`).
  - `>0 conflicts -> 0 conflicts`: `gitConflictResolved` (`info`).
  - Steady conflict count emits **zero** duplicate events.
- **SSH Connection**:
  - `connected -> disconnected`: `connectionLost` emitted only after sustained disconnect exceeds debounce grace period (default 3s).
  - `disconnected -> connected`: `connectionRestored` emitted only if previous `connectionLost` was alerted.
- **Server Metrics & Hysteresis**:
  - CPU/RAM/Disk:
    - Normal (<75%) -> Warning (>=75%): `serverResourceWarning`.
    - Warning -> Critical (>=90%): `serverResourceCritical` (`warning`/`critical`, CTA: `Server Health`).
    - Recovery: Emits `serverResourceRecovered` only when metric falls below recovery threshold (85% for critical, 70% for warning) to eliminate flapping.
- **Working Directory & tmux**:
  - Working directory missing / inaccessible: `workingDirectoryMissing`.

### Deduplication & Retention
- `EventDeduplicator`: Fingerprint cache keyed by entity + transition state.
- `FileEventRepository`: Atomic JSON store (`agentdeck_events.json`) via `JsonFileStore`. Bounded to 200 latest events with FIFO pruning.

### Notification Policy & Privacy Preview
- `NotificationPolicy`: Filters events against user preferences (`notifyAgentWaiting`, `notifyAgentFailed`, `notifyGitConflict`, `notifyConnectionLost`, etc.) and project overrides.
- `NotificationPrivacyMode`:
  - `full`: Complete project and agent details (`Codex is waiting for input • Portal Proveedores`).
  - `projectOnly`: Project name with generic alert (`Agent requires input • Portal Proveedores`).
  - `generic`: Opaque alert (`AgentDeck requires attention`).

### In-App Notification Center
- Mobile-first `NotificationCenterPage` with unread count, filter tabs, `Mark All Read`, `Clear History`, and 1-tap deep actions (`Respond`, `View Conflicts`, `Inspect Server`, `Reconnect`).
- Dynamic privacy mode preview toggle in UI for immediate verification.

---

## 3. Verification Criteria & Lab Matrix

| Scenario | Description | Expected Outcome | Status |
|---|---|---|---|
| **A** | Agent initial running state | No event generated | **PASS** |
| **B** | Agent transitions to `waitingUser` | 1 `agentWaitingUser` event emitted | **PASS** |
| **C** | Repeated polling while `waitingUser` | 0 duplicate events (dedup verified) | **PASS** |
| **D** | Agent transitions to `failed` | 1 `agentFailed` critical event emitted | **PASS** |
| **E** | Git merge conflict introduced | 1 `gitConflictDetected` event emitted | **PASS** |
| **F** | Repeated polling with conflict | 0 duplicate events | **PASS** |
| **G** | Git conflict resolved | 1 `gitConflictResolved` event emitted | **PASS** |
| **H** | Sustained SSH disconnection | 1 `connectionLost` event emitted | **PASS** |
| **I** | SSH connection restored | 1 `connectionRestored` event emitted | **PASS** |
| **J** | Server metric crosses 90% | 1 `serverResourceCritical` event emitted | **PASS** |
| **K** | Server metric stays at 91% | 0 duplicate events | **PASS** |
| **L** | Server metric drops to 60% (<70% hysteresis) | 1 `serverResourceRecovered` event emitted | **PASS** |
| **M** | Privacy payload verification | JSON store contains zero secrets, tokens, or diffs | **PASS** |
| **N** | Bounded retention pruning | Burst of 250 events pruned strictly to 200 max | **PASS** |

---

## 4. Quality Verification Summary
- `flutter analyze`: **PASS (0 issues)**
- `flutter test`: **PASS (161/161 tests passed)**
- `tool/notifications_lab_docker.ps1`: **PASS (Scenarios A through N: 14/14 PASS)**
