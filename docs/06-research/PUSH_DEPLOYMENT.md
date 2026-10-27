# AgentDeck Push Relay Deployment Guide

## Overview

The **AgentDeck Push Relay** is a standalone, lightweight daemon responsible for maintaining the iOS device registry, caching Apple provider authentication tokens (JWT / ES256), and forwarding notifications to APNs over HTTP/2.

---

## 1. Directory Structure & Permissions

| Path | Purpose | Recommended Mode | Owner |
|---|---|---|---|
| `/usr/local/bin/agentdeck-push-relay` | Executable entry point | `0755` | `root:root` |
| `/etc/agentdeck/push-relay.json` | Configuration file | `0600` | `agentdeck:agentdeck` |
| `/etc/agentdeck/secrets/AuthKey.p8` | Apple APNs Provider Key | `0400` | `agentdeck:agentdeck` |
| `/var/lib/agentdeck/push-relay.db` | SQLite Database | `0600` | `agentdeck:agentdeck` |
| `/run/agentdeck/push-relay.pid` | Single-instance lock file | `0644` | `agentdeck:agentdeck` |

---

## 2. Configuration (`push-relay.json`)

```json
{
  "schemaVersion": 1,
  "server": {
    "host": "0.0.0.0",
    "port": 8443,
    "databasePath": "/var/lib/agentdeck/push-relay.db",
    "lockPath": "/run/agentdeck/push-relay.pid"
  },
  "apns": {
    "enabled": true,
    "environment": "production",
    "teamId": "ABCDE12345",
    "keyId": "KEY9876543",
    "bundleId": "com.agentdeck.app",
    "privateKeyPath": "/etc/agentdeck/secrets/AuthKey.p8"
  },
  "security": {
    "companionSecrets": {
      "cmp_srv_prod_1": "secret_token_1234567890abcdef",
      "cmp_srv_prod_2": "secret_token_0987654321fedcba"
    },
    "rateLimits": {
      "maxRequestsPerMinutePerDevice": 30,
      "maxCompanionEventsPerMinute": 120
    }
  }
}
```

---

## 3. Systemd Service Unit

File: `/etc/systemd/system/agentdeck-push-relay.service`

```ini
[Unit]
Description=AgentDeck Push Relay Daemon
Documentation=https://github.com/vszni/AgentDeck
After=network.target

[Service]
Type=simple
User=agentdeck
Group=agentdeck
ExecStart=/usr/local/bin/agentdeck-push-relay run --config /etc/agentdeck/push-relay.json
Restart=on-failure
RestartSec=5s

# Security Hardening
NoNewPrivileges=true
ProtectSystem=full
ProtectHome=true
PrivateTmp=true
ProtectKernelModules=true
ProtectKernelTunables=true
RestrictAddressFamilies=AF_UNIX AF_INET AF_INET6
MemoryDenyWriteExecute=true

# Resource Limits
LimitNOFILE=4096
MemoryMax=256M
CPUQuota=20%

[Install]
WantedBy=multi-user.target
```
