# AgentDeck Server Companion Protocol (Schema v1)

## Overview

The **AgentDeck Server Companion Protocol** defines the versioned JSON command-line and event interface between the server-side observer (`agentdeck-companion`) and the mobile client (AgentDeck Flutter).

All CLI commands that produce machine-readable output output strictly valid JSON with `schemaVersion: 1`.

---

## 1. CLI Commands & Output Schemas

### `version --json`
Returns binary version and supported protocol schema version.

```json
{
  "schemaVersion": 1,
  "binaryVersion": "0.1.0",
  "protocolVersion": 1
}
```

---

### `health --json`
Returns runtime liveness, daemon status, and observation scan summary.

```json
{
  "schemaVersion": 1,
  "status": "ok",
  "version": "0.1.0",
  "startedAt": "2026-09-20T19:00:00Z",
  "uptimeSeconds": 3600,
  "observedProjects": 2,
  "lastScanAt": "2026-09-20T20:00:00Z",
  "lastError": null
}
```

---

### `status --json`
Returns detailed operational metrics for diagnostics.

```json
{
  "schemaVersion": 1,
  "status": "running",
  "pid": 12345,
  "serverId": "srv_prod_1",
  "uptimeSeconds": 7200,
  "lastScanAt": "2026-09-20T21:00:00Z",
  "scanCount": 1440,
  "projectsCount": 2,
  "journal": {
    "totalEvents": 42,
    "lastSequence": 42,
    "firstSequence": 1,
    "fileSizeBytes": 8420
  },
  "projects": [
    {
      "id": "proj_1",
      "workingDirectory": "/home/lab/workspace",
      "enabled": true,
      "lastScanAt": "2026-09-20T21:00:00Z",
      "lastStatus": "ok"
    }
  ]
}
```

---

### `events --after <sequence> [--limit <N>] --json`
Queries the monotonic event journal for events after a specific cursor sequence.
- `--after`: Integer sequence (e.g. `0` for all events, or last known sequence).
- `--limit`: Maximum number of events to return (default: `100`, max: `500`).

```json
{
  "schemaVersion": 1,
  "events": [
    {
      "sequence": 1,
      "eventId": "evt_srv_prod_1_1_a1b2c3d4",
      "type": "agentWaitingUser",
      "severity": "actionRequired",
      "source": "agent",
      "fingerprint": "agent_waiting:ad_agent_codex_proj_1",
      "title": "Codex is waiting for input",
      "message": "Interactive CLI prompt requires your response.",
      "projectId": "proj_1",
      "serverId": "srv_prod_1",
      "agentInstanceId": "ad_agent_codex_proj_1",
      "detectedAt": "2026-09-20T21:05:00Z",
      "isProduction": true,
      "actionLabel": "Respond",
      "destination": {
        "route": "agent_terminal",
        "projectId": "proj_1",
        "serverId": "srv_prod_1",
        "agentInstanceId": "ad_agent_codex_proj_1"
      },
      "metadata": {
        "providerId": "codex"
      }
    }
  ],
  "cursor": {
    "lastSequence": 1,
    "hasMore": false,
    "totalAvailable": 1
  }
}
```

---

### `snapshot --json`
Returns the current active in-memory baseline state of all observed projects and server resources without modifying or querying the journal.

```json
{
  "schemaVersion": 1,
  "observedAt": "2026-09-20T21:10:00Z",
  "serverId": "srv_prod_1",
  "serverHealth": {
    "cpuPercent": 14.5,
    "memoryPercent": 62.1,
    "diskPercent": 48.0,
    "isHealthy": true
  },
  "projects": {
    "proj_1": {
      "agent": {
        "instanceId": "ad_agent_codex_proj_1",
        "providerId": "codex",
        "state": "waitingUser",
        "observedAt": "2026-09-20T21:05:00Z"
      },
      "git": {
        "conflictCount": 0,
        "isClean": true,
        "observedAt": "2026-09-20T21:09:00Z"
      },
      "directoryExists": true
    }
  }
}
```

---

### `projects --json`
Lists all configured project profiles registered in the companion configuration.

```json
{
  "schemaVersion": 1,
  "projects": [
    {
      "id": "proj_1",
      "workingDirectory": "/home/lab/workspace",
      "enabled": true
    }
  ]
}
```

---

## 2. Event Types & Mappings

The companion produces event types conforming exactly to AgentDeck domain events:

| Companion `type` | Severity | Action Label | Source | Trigger Condition |
|---|---|---|---|---|
| `agentWaitingUser` | `actionRequired` | `Respond` | `agent` | tmux session output matches interactive prompt regex pattern |
| `agentFailed` | `critical` | `Inspect` | `agent` | Process exited non-zero or error regex pattern matched |
| `agentFinished` | `info` | `Open` | `agent` | Process exited cleanly with code 0 or finish regex matched |
| `gitConflictDetected` | `critical` | `View Conflicts` | `git` | `git status --porcelain=v2` reports merge conflict markers ($>0$) |
| `gitConflictResolved` | `info` | `View Git` | `git` | Previous conflict count drops to $0$ |
| `serverResourceCritical` | `critical` | `Server Health` | `server` | CPU/RAM/Disk metric reaches $\ge 90\%$ |
| `serverResourceWarning` | `warning` | `Server Health` | `server` | Metric reaches $\ge 75\%$ from normal |
| `serverResourceRecovered` | `info` | `Server Health` | `server` | Metric falls below hysteresis recovery threshold ($<85\%$ or $<70\%$) |
| `workingDirectoryMissing` | `warning` | `Browse Files` | `files` | Configured working directory inaccessible or deleted |

---

## 3. Monotonic Sequence & Cursor Semantics

1. **Monotonic Sequences**: Each event appended to `events.jsonl` is assigned an incrementing integer `sequence = max_sequence + 1`.
2. **Restart Recovery**: When the companion starts or restarts, it inspects the last line of `events.jsonl` to recover the current maximum sequence. If the file is empty or new, `sequence` starts at `1`.
3. **Cursor Queries**: A client passes `--after <seq>` (e.g. `--after 40`). The companion returns all events where `event.sequence > 40`, sorted in ascending order of `sequence`.
4. **At-Least-Once Delivery**: The client acknowledges receipt by saving the highest `sequence` received. If a network interruption occurs during transmission, the client simply re-queries with the previous cursor, receiving the events again without loss. The mobile client deduplicates using `event.fingerprint` and `event.eventId`.
