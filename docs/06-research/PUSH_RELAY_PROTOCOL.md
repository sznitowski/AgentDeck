# AgentDeck Push Relay Protocol (Schema v1)

## Overview

The **AgentDeck Push Relay Protocol** specifies the HTTP/JSON interface for:
1. **Device Registration & Management** (Mobile App ↔ Push Relay).
2. **Companion Event Ingestion** (Server Companion ↔ Push Relay).
3. **APNs Message Formatting & Dispatch** (Push Relay ↔ APNs).

All request and response bodies utilize `schemaVersion: 1`.

---

## 1. Device Registration Endpoints

### `POST /v1/devices/register`
Registers a new device token or updates an existing token for an `installationId`.

**Request Body:**
```json
{
  "schemaVersion": 1,
  "installationId": "inst_9b8f2c3d-1a2b-4c5d-8e9f-0a1b2c3d4e5f",
  "deviceToken": "740f4707bebcf74f9b7c25d48e3358945f6aa01da5ddb387462c7eaf61bb78ad",
  "platform": "ios",
  "bundleId": "com.agentdeck.app",
  "environment": "sandbox",
  "appVersion": "1.0.0",
  "privacyMode": "full",
  "enabled": true
}
```

**Response (`200 OK` / `201 Created`):**
```json
{
  "schemaVersion": 1,
  "status": "registered",
  "registrationId": "reg_a1b2c3d4",
  "installationId": "inst_9b8f2c3d-1a2b-4c5d-8e9f-0a1b2c3d4e5f",
  "updatedAt": "2026-09-24T20:00:00Z"
}
```

---

### `DELETE /v1/devices/by-token`
Deactivates or unregisters a device token upon user logout, notification disablement, or APNs `410 Unregistered` response.

**Request Body:**
```json
{
  "schemaVersion": 1,
  "deviceToken": "740f4707bebcf74f9b7c25d48e3358945f6aa01da5ddb387462c7eaf61bb78ad"
}
```

**Response (`200 OK`):**
```json
{
  "schemaVersion": 1,
  "status": "deactivated",
  "deviceToken": "740f4707...78ad"
}
```

---

## 2. Companion Event Ingestion Endpoint

### `POST /v1/companion-events`
Receives state transition events forwarded by an active `agentdeck-companion` daemon.

**Headers:**
```http
Content-Type: application/json
X-Companion-Id: cmp_srv_prod_1
X-Companion-Secret: <pre_shared_secret_token>
```

**Request Body:**
```json
{
  "schemaVersion": 1,
  "eventId": "evt_srv_prod_1_42_a1b2c3d4",
  "sequence": 42,
  "type": "agentWaitingUser",
  "severity": "actionRequired",
  "source": "agent",
  "fingerprint": "agent_waiting:ad_agent_codex_proj_1",
  "title": "Codex is waiting for input",
  "message": "Interactive CLI prompt requires your response.",
  "projectId": "proj_1",
  "projectName": "Portal Proveedores",
  "serverId": "srv_prod_1",
  "serverName": "UNIBER-FENIX",
  "agentInstanceId": "ad_agent_codex_proj_1",
  "agentProviderId": "codex",
  "agentProviderName": "Codex",
  "detectedAt": "2026-09-24T20:05:00Z",
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
```

**Response (`200 OK` / `202 Accepted`):**
```json
{
  "schemaVersion": 1,
  "status": "accepted",
  "eventId": "evt_srv_prod_1_42_a1b2c3d4",
  "pushedDevicesCount": 1,
  "deduplicated": false
}
```

If the event was already received and processed, `deduplicated: true` is returned with `200 OK`, executing zero duplicate APNs dispatches.

---

## 3. APNs Alert Payload Transformation

When the relay dispatches an event, it renders an `aps` dictionary formatted according to the target device's `privacyMode`:

### 1. Full Privacy Mode (`full`)
```json
{
  "aps": {
    "alert": {
      "title": "Codex is waiting for input",
      "subtitle": "Portal Proveedores",
      "body": "Interactive CLI prompt requires your response."
    },
    "sound": "default",
    "badge": 1,
    "category": "AGENT_INTERACTION"
  },
  "agentdeck": {
    "schemaVersion": 1,
    "eventId": "evt_srv_prod_1_42_a1b2c3d4",
    "type": "agentWaitingUser",
    "serverId": "srv_prod_1",
    "projectId": "proj_1",
    "destination": {
      "route": "agent_terminal",
      "projectId": "proj_1",
      "serverId": "srv_prod_1",
      "agentInstanceId": "ad_agent_codex_proj_1"
    }
  }
}
```

### 2. Project Only Mode (`projectOnly`)
```json
{
  "aps": {
    "alert": {
      "title": "Action required in Portal Proveedores",
      "body": "A remote agent requires your input."
    },
    "sound": "default"
  },
  "agentdeck": { ... }
}
```

### 3. Generic Mode (`generic`)
```json
{
  "aps": {
    "alert": {
      "title": "AgentDeck Notification",
      "body": "An action requires your attention."
    },
    "sound": "default"
  },
  "agentdeck": { ... }
}
```

---

## 4. Health & Diagnostics Endpoints

### `GET /v1/health`
```json
{
  "schemaVersion": 1,
  "status": "ok",
  "version": "0.1.0",
  "uptimeSeconds": 14400,
  "apnsConfigured": true,
  "registeredDevices": 3,
  "activeCompanions": 2,
  "queueDepth": 0
}
```
