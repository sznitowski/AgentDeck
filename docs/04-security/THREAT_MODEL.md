# Threat Model & Risk Analysis

## 1. Assets

1. **Host & Authentication Credentials**: SSH passwords, OpenSSH/PEM private keys, and key passphrases.
2. **Host Trust Integrity**: Known host keys, SHA256 fingerprints, and revocation records.
3. **APNs Provider Credentials**: Apple `.p8` private authentication key, Team ID, and Key ID.
4. **Device Routing Identifiers**: APNs device tokens and installation UUIDs.
5. **Companion-to-Relay Ingestion Secrets**: Shared pre-shared keys (PSK) between Server Companions and Push Relay.
6. **Remote Infrastructure & Code**: Managed Linux server environments, git repositories, project working directories, and production services.
7. **Session Data & Privacy**: Terminal streams, agent prompt interactions, merge conflict diffs, process tables, and lock-screen notification alerts.

---

## 2. Threat Actors & Adversary Capabilities

- **Network Impostor / MITM**: Positioned between mobile client and SSH host, or between Server Companion and Push Relay, or between Push Relay and APNs. Can intercept, replay, modify, or drop packets.
- **Malicious / Compromised SSH Server**: Controlled by an attacker. Attempts to impersonate known hosts, return malicious escape sequences, manipulate filesystem hierarchies, or probe client vulnerabilities.
- **Malicious Repository / Path Injection**: Contains filenames or paths engineered to exploit shell expansion or argument injection (e.g., `-rf`, `; rm -rf /`, `$(whoami)`).
- **Physical Device Attacker (Lost / Stolen iPhone)**: Possesses physical access to an unlocked or locked device. Attempts to inspect local storage, dump memory, or extract Keychain secrets.
- **Compromised Server Companion Host**: Attacker with local user access on a managed server attempts to spoof events, inject false alerts, or access companion state.
- **Compromised Push Relay Gateway**: Attacker with access to central relay host attempts to intercept push contents or send fraudulent APNs alerts.

---

## 3. Threat Scenarios & Mitigations

| Threat | Risk | Mitigation in AgentDeck | Residual Risk |
|---|---|---|---|
| **Host Impersonation (MITM on SSH)** | High | Strict host fingerprint verification via `HostTrustService`. Known hosts pinned by hostname/port/algo/SHA256. Changed or revoked fingerprints fail closed immediately without bypass options. | First-time trust requires user to verify fingerprint out-of-band. |
| **Credential Theft from Storage** | High | Passwords and private keys stored strictly in OS Keychain (`unlocked_this_device`, no cloud sync). Profiles contain only opaque UUID references. No plaintext JSON storage. | Transient key strings in Dart process memory during active authentication handshake. |
| **APNs Provider Key Compromise** | Critical | `.p8` signing key resides exclusively in Push Relay deployment; never committed to git, never sent to mobile, never deployed to managed Linux servers. | Requires secure filesystem permissions (`chmod 0600`) and environment mounting on relay host. |
| **Command & Argument Injection** | High | Pure SFTP file operations (no `rm`, `cat`, `mkdir` shell calls). `AgentCommandSafety`, `GitCommandSafety`, and `ServerOpsCommandSafety` enforce strict regex validation, argument array execution (`shell=False`), and POSIX single-quote escaping. | Free interactive shell in `TerminalPage` operates with full permissions of the remote SSH user. |
| **Lock-Screen Privacy Leakage** | Medium | `NotificationPolicy` provides 3 privacy preview modes (`Full`, `Project Only`, `Generic`). Payloads exclude terminal output, prompt bodies, diff chunks, environment variables, and passwords. | Full preview mode displays project name and sanitized summary. |
| **Event Spoofing & Replay** | Medium | Push Relay validates companion shared secrets over TLS. End-to-end deduplication keyed by `eventId` prevents alert spam or replay loops. | Central relay availability required for real-time push ingestion. |
| **Unregistered Device Accumulation** | Low | Push Relay parses APNs HTTP 410 (`Unregistered`) responses and immediately deactivates invalid device tokens in SQLite registry. | Initial notification dispatch before APNs registers token revocation. |
| **Accidental Production Destruction** | High | Persistent red `PRODUCTION` banners on production environments. Destructive operations (file delete, process kill, service restart, agent termination) require affirmative dialog confirmation showing exact unabbreviated target paths. | User can intentionally confirm destructive actions. |
| **Stale Push State Desynchronization** | Medium | Push notification acts strictly as an ephemeral wake-up signal. Tapping a notification opens AgentDeck and triggers canonical catch-up synchronization with Server Companion journal (`events.jsonl`). | Delay between push display and mobile network reconnection. |
| **Companion Daemon Starvation / Loop** | Low | Single-instance lock via `fcntl.flock`. Non-blocking outbox queue with exponential backoff retry. Read-only observation never writes to managed repositories. | Host-level resource exhaustion if host is severely degraded. |

---

## 4. Trust Boundaries & Separation

```
[ Mobile App (iOS) ]
       │ Authenticated SSH (Verified Fingerprint)
       ▼
[ Remote Linux Host ] ──── (Outbound HTTPS POST) ────► [ Push Relay (Central) ]
  - Companion Daemon (Non-root)                           - .p8 Provider Key
  - Monotonic Journal (events.jsonl)                      - Device Token Registry
  - Zero Inbound Ports                                    - ES256 JWT Generator
                                                                 │
                                                                 ▼ (HTTP/2 TLS)
                                                          [ Apple APNs Gateway ]
```

1. **Mobile Secure Zone**: Key material in iOS Keychain, profiles in app sandbox.
2. **Server Execution Zone**: Read-only companion running as unprivileged user; zero inbound TCP listening ports.
3. **Relay Ingestion Zone**: Dedicated central gateway for APNs token signing and device token dispatch.
4. **Transport Channels**: All traffic conducted over SSH (port 22) or HTTPS/TLS (port 443).
