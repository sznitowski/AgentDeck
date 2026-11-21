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
    "host": "127.0.0.1",
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
    "mode": "production",
    "companionSecrets": {
      "cmp_srv_prod_1": "<random secret, 32+ chars>"
    }
  }
}
```

Fail-closed rules enforced at startup (the relay exits with code 2 otherwise):

- `security.mode` defaults to `production`; it requires at least one companion secret (>= 16 chars).
- `server.host` must be a loopback address. **TLS is terminated by Caddy**, not by the Python process.
- On POSIX the config file must not be readable by group/others (`chmod 600`).
- `security.mode: "development"` is for local labs only and is loopback-only.

---

## 2b. TLS with Caddy

The relay listens on `127.0.0.1:8443` over plain HTTP. Caddy terminates TLS and proxies `/v1/*` (see `server/caddy/Caddyfile.example`; not validated against a real Caddy in this repository). Both clients refuse `http://` for non-loopback hosts, so the iPhone and any remote Companion must use the `https://` Caddy name. A Companion on the same host may use `http://127.0.0.1:8443` directly.

The app supports **one relay per origin** (`https://relay.example.com` or `https://relay.example.com:8443`; plain HTTP only for loopback labs). Paths, query strings and credentials in the URL are rejected. The relay URL is entered in the app (Settings -> Push Notifications) and stored non-secretly on the phone; it is empty until configured.

## 2c. Pairing and revoking devices

No endpoint creates credentials; an administrator on the relay host does:

```bash
# 1. Generate a one-time code (expires in 10 minutes, shown once, never stored in plaintext)
sudo -u agentdeck agentdeck-push-relay pairing create -c /etc/agentdeck/push-relay.json
# 2. Enter the code in AgentDeck (Notification settings -> Pair with code)
# 3. Inspect / revoke
sudo -u agentdeck agentdeck-push-relay installations list -c /etc/agentdeck/push-relay.json
sudo -u agentdeck agentdeck-push-relay installations revoke <installationId> -c /etc/agentdeck/push-relay.json
```

The app stores the resulting installation token in the iOS Keychain; the relay stores only its SHA-256. Registering, updating and removing APNs tokens requires that token.

Upgrading an existing relay database: devices registered by the old unauthenticated protocol are disabled once at first start and must pair again.

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
