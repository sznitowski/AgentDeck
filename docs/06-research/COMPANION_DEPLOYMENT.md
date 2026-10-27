# AgentDeck Server Companion Deployment & Systemd Hardening Guide

## Overview

This guide outlines the production deployment topology, security sandbox configuration, and lifecycle management for `agentdeck-companion` on Linux servers.

---

## 1. User & Directory Model

The companion runs as an unprivileged service user (e.g. `agentdeck` or the primary SSH operator user). It **never runs as root** and requires no `sudo` privileges.

### Standard File System Paths

| Purpose | Standard Path | Permissions | Ownership |
|---|---|---|---|
| **Executable Binary** | `/usr/local/bin/agentdeck-companion` | `0755` | `root:root` |
| **Configuration Directory** | `/etc/agentdeck/` | `0750` | `agentdeck:agentdeck` |
| **Configuration File** | `/etc/agentdeck/companion.json` | `0640` | `agentdeck:agentdeck` |
| **State / Journal Directory** | `/var/lib/agentdeck/` | `0750` | `agentdeck:agentdeck` |
| **Event Journal** | `/var/lib/agentdeck/events.jsonl` | `0640` | `agentdeck:agentdeck` |
| **Runtime PID / Lock** | `/run/agentdeck/companion.pid` | `0640` | `agentdeck:agentdeck` |

---

## 2. Configuration Schema (`companion.json`)

```json
{
  "schemaVersion": 1,
  "serverId": "srv_prod_1",
  "isProduction": true,
  "journalPath": "/var/lib/agentdeck/events.jsonl",
  "lockPath": "/run/agentdeck/companion.pid",
  "pollIntervals": {
    "agentsSec": 3,
    "gitSec": 15,
    "serverSec": 15,
    "filesSec": 30
  },
  "retention": {
    "maxEvents": 1000,
    "maxAgeDays": 7
  },
  "projects": [
    {
      "id": "proj_portal_proveedores",
      "name": "Portal Proveedores",
      "workingDirectory": "/home/app/portal-proveedores",
      "enabled": true
    }
  ]
}
```

---

## 3. Hardened Systemd Service Unit

File: `/etc/systemd/system/agentdeck-companion.service`

```ini
[Unit]
Description=AgentDeck Server Companion (Remote State Observer)
Documentation=https://github.com/vszni/AgentDeck
After=network.target

[Service]
Type=simple
User=agentdeck
Group=agentdeck
ExecStart=/usr/local/bin/agentdeck-companion run --config /etc/agentdeck/companion.json
Restart=on-failure
RestartSec=5s

# Security Hardening Directives
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=full
ProtectHome=read-only
ProtectControlGroups=true
ProtectKernelModules=true
ProtectKernelTunables=true
RestrictAddressFamilies=AF_UNIX AF_INET AF_INET6
RestrictRealtime=true
RestrictSUIDSGID=true
MemoryDenyWriteExecute=true
CapabilityBoundingSet=

# Resource Limits
LimitNOFILE=1024
MemoryMax=128M
CPUQuota=10%

[Install]
WantedBy=multi-user.target
```

---

## 4. Hardening Trade-Offs & Project Access

- **`ProtectHome=read-only`**: Allows the companion to read Git repositories and inspect tmux sessions under `/home/...` without granting write access to project sources or user directories.
- **`ProtectSystem=full`**: Mounts `/usr`, `/boot`, and `/etc` as read-only for the service process, ensuring the daemon cannot modify system binaries.
- **`CapabilityBoundingSet=` (Empty)**: Strips all Linux capabilities (`CAP_SYS_ADMIN`, `CAP_NET_RAW`, etc.), preventing privilege escalation.
- **`NoNewPrivileges=true`**: Prevents child processes from gaining elevated privileges via setuid/setgid binaries.

---

## 5. Lifecycle Operations

### Installation
```bash
# 1. Create service user and directories
sudo useradd -r -s /usr/sbin/nologin -d /var/lib/agentdeck agentdeck
sudo mkdir -p /etc/agentdeck /var/lib/agentdeck /run/agentdeck
sudo chown -R agentdeck:agentdeck /etc/agentdeck /var/lib/agentdeck /run/agentdeck

# 2. Copy companion executable
sudo cp server/agentdeck-companion /usr/local/bin/agentdeck-companion
sudo chmod 755 /usr/local/bin/agentdeck-companion

# 3. Install configuration
sudo cp server/companion.json /etc/agentdeck/companion.json
sudo chmod 640 /etc/agentdeck/companion.json
sudo chown agentdeck:agentdeck /etc/agentdeck/companion.json

# 4. Install and start systemd service
sudo cp server/agentdeck-companion.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now agentdeck-companion.service
```

### Verification
```bash
# Query status and health via CLI
agentdeck-companion status --json
agentdeck-companion health --json
```

### Uninstallation
```bash
sudo systemctl disable --now agentdeck-companion.service
sudo rm -f /etc/systemd/system/agentdeck-companion.service
sudo rm -f /usr/local/bin/agentdeck-companion
sudo rm -rf /etc/agentdeck /var/lib/agentdeck /run/agentdeck
sudo userdel agentdeck
sudo systemctl daemon-reload
```
