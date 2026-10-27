# Security model

The phone is a loss-prone control surface for sensitive Linux infrastructure. SSH authenticates server and user; `ProjectProfile` provides context; `ExecutionPolicy` guides UI decisions. UI policy does not confine a free shell or remote agent. Production restrictions require least-privilege Linux accounts and server-side authorization.

M1.5 separates storage: `ServerProfile` metadata and credential references in a versioned app-support file; host algorithm, SHA256 fingerprint, timestamps and revocation in a second file; passwords, private-key text and passphrases in platform secure storage behind `SecureCredentialStore`. iOS requests Keychain `unlocked_this_device` with sync disabled. Implementation is present; Keychain/device behavior is PENDING_MACOS_VALIDATION. Metadata/trust files are not encrypted by AgentDeck. App sandbox, file protection and backup/restore effects require device review. Corrupt or unsupported data fails startup closed.

Unknown host keys require user approval with host, algorithm and fingerprint shown. Matching known keys pass; changed and revoked keys block. Normal Connect/Reconnect never replaces trust. Removing a stored key is a separate confirmed action, followed by a new independent fingerprint check. No accept-all host path or secret logging exists. The app does not start an SSH connection if storage initialization fails.

Explicit TCP/handshake/authentication timeouts and bounded cancellable reconnect remain. M1.5's manual lab harness is TEST_ONLY and does not persist secrets. Private-key material exists transiently as Dart strings; reliable memory zeroization is unavailable. iOS background/resume and live SSH interoperability remain pending. Review commands, logs, tunnels, backups and exports before later milestones.

## M2 terminal surface

The free SSH shell can execute any command permitted by the remote Unix account. The PRODUCTION label is persistent text, not an authorization boundary; least-privilege server permissions remain essential. Terminal input, output, commands, prompts, clipboard contents and credentials are not logged or persisted by AgentDeck. Copy requires a selection; Paste requires a button action and may transmit sensitive clipboard text to the remote shell. No password prompt detection, auto-fill or SSH password reuse is implemented. The terminal lab accepts only loopback and disposable credentials. PTY/shell failure never weakens host trust or silently falls back to `exec`. iOS clipboard/keyboard and background network behavior remain PENDING_MACOS_VALIDATION.

## M4 SFTP / remote files surface

1. **Pure SFTP Protocol**: All file and directory operations (list, stat, read, write, mkdir, rename, delete, rmdir) are executed strictly via standard SFTP requests. No remote shell processes (`rm`, `mv`, `cat`, `mkdir`, `scp`) are invoked, completely eliminating shell interpretation and command injection vulnerabilities.
2. **No Sudo or Privilege Escalation**: Operations are governed entirely by the remote user's Unix permissions. If an operation is rejected by the server filesystem, AgentDeck maps the response to a typed `permissionDenied` failure without attempting sudo or privilege escalation.
3. **POSIX Path Sanitization**: All remote file paths are normalized and joined using POSIX rules (`PosixPath`), stripping redundant separators and relative segments while validating against empty names, null bytes, and traversal anomalies.
4. **Atomic Writes**: File creation and edits write to a randomized sibling temporary file (`.agentdeck_tmp_<nonce>_<name>`) before executing an atomic SFTP rename over the target path. If the write fails or is interrupted, the temporary file is purged and the target file remains intact.
5. **Sensitive File Protections**: Known sensitive patterns (`.env`, `*.pem`, `*.key`, `id_rsa`, `id_ed25519`, `credentials*`) trigger a prominent security warning in the viewer. File contents and secret keys are never logged, indexed, cached, or included in activity telemetry.
6. **Production Guardrails**: When connected to a server tagged as `production`, a persistent `PRODUCTION` banner is displayed across all file views. Destructive actions (`delete`, `overwrite`) require explicit dialog confirmation displaying the exact, unabbreviated remote target path.

## M5 Agent orchestration surface

1. **Zero Shell Injection**: `AgentCommandSafety` strictly validates binary candidates (`^[a-zA-Z0-9_\-\.\/]+$`), blocks metacharacters (`;`, `&&`, `|`, `$()`, backticks, newlines), escapes extra arguments using POSIX single quotes (`'arg'`), and sanitizes tmux session names (`ad_agent_<provider>_<project>_<nonce>`).
2. **No Automatic Approvals**: AgentDeck strictly prohibits automated prompt responses, automatic command confirmations, or default "yes" answers to agent CLI prompts. All approval prompts require manual user review and keyboard input through `TerminalPage`.
3. **Zero Agent Credentials Stored**: AgentDeck does not store, request, or persist LLM provider credentials (`OPENAI_API_KEY`, `ANTHROPIC_API_KEY`, etc.) or cloud tokens. The remote CLI agent relies exclusively on existing preconfigured environment/auth files on the Linux server.
4. **Bounded Buffer Observation**: Output classifiers inspect only the most recent ~15–30 lines of terminal output strictly for interaction detection (`WAITING_USER`). Agent conversation logs, code snippets, diff outputs, and terminal streams are never persisted to disk or included in telemetry/logging.
5. **Session Disconnection Resilience**: Mobile network drops or app restarts never terminate remote agent jobs. Execution continues safely within managed tmux sessions.
6. **Production Guardrails**: Running or terminating agent instances on servers designated as `production` requires explicit confirmation dialogues and displays persistent visual badges.

## M6 Git operations surface

1. **Strict Command Isolation**: All Git operations execute via `git -C <workingDirectory>` without subshell spawning or shell operators (`&&`, `;`, `|`).
2. **Path Option Injection Protection**: All file path parameters in `git add`, `git restore`, and `git diff` are prefixed with `--` to prevent filenames starting with `-` from being parsed as CLI options.
3. **No Arbitrary Commands**: UI allows only bounded, whitelisted operations (`status`, `log`, `diff`, `add`, `restore --staged`, `commit`). Arbitrary Git command input is strictly rejected.
4. **No Destructive Commands**: Destructive operations (`reset --hard`, `clean -fd`, `checkout -- .`, `branch -D`) are completely excluded from `GitService`.
5. **No Credential / Token Capture**: AgentDeck does not manage or store Git tokens (GitHub PAT, GitLab token, deploy keys) or alter `credential.helper`.
6. **No Remote Side Effects**: Remote network operations (`push`, `push --force`, `fetch`, `pull`, `rebase`) are explicitly deferred. M6 operations are strictly local to the remote server repository.
7. **No Diff Persistence or Secret Logging**: Diffs are parsed and rendered ephemerally in-memory. Sensitive files (`.env`, `*.key`, `*.pem`, `credentials*`) trigger explicit warning alerts before diff rendering.
8. **Production Guardrails**: Mutating operations (stage, unstage, commit) on projects in `production` require affirmative confirmation dialogues showing the exact project and file path.

## M7 Server operations surface

1. **Strict Command Isolation**: Only whitelisted, non-destructive discovery and systemd management commands are executed (`cat /proc/...`, `uname`, `df -P -k`, `ps -eo ...`, `systemctl list-units`, `systemctl show`, `systemctl start/stop/restart`). Arbitrary shell execution from UI is strictly blocked.
2. **Process Command-Line Privacy**: Process enumeration is restricted to executable basename (`comm`) rather than full argument strings (`args`) to prevent accidental discovery, display, or persistence of secrets, database credentials, or tokens passed via CLI flags.
3. **Zero Sudo / Privileged Auto-Escalation**: AgentDeck never requests, intercepts, auto-fills, or stores `sudo` passwords. Operations lacking adequate permissions fail closed with `ServerOperationFailureKind.permissionDenied`.
4. **Service Name Injection Defense**: Service identifiers must match `^[a-zA-Z0-9_\.\-@]+$`. Shell control characters (`;`, `&&`, `|`, `` ` ``, `$()`, newlines, spaces) are rejected before command construction.
5. **Production Guardrails**: Service mutations (`start`, `stop`, `restart`) on `production` servers display persistent `PRODUCTION` warning badges and require explicit dialog confirmation with the exact service name and host before execution.
6. **Ephemeral Metrics & No Secret Dumps**: Kernel metrics snapshots and process tables reside strictly in ephemeral memory and are never persisted to disk or included in log telemetry. Commands dumping environment variables (`env`, `printenv`, `/proc/<pid>/environ`) are strictly excluded.

## M8 Event & Notification Core surface

1. **Zero Secret Persistence**: Event storage in `agentdeck_events.json` strictly records sanitized identifiers, timestamps, and high-level summaries. Terminal outputs, prompt bodies, full diffs, command arguments, tokens, and credentials are completely excluded.
2. **Lock Screen Privacy Modes**: Notifications support 3 privacy modes (`full`, `projectOnly`, `generic`). In `generic` mode, all project and agent identifiers are masked on the lock screen (e.g. "AgentDeck requires your attention").
3. **No Automated Remote Mutation from Notifications**: Deep actions (`Respond`, `View Conflicts`, `Inspect Server`, `Reconnect`) navigate the user to interactive UI screens with proper confirmations and human review; no remote execution or agent approvals are triggered automatically.
4. **Bounded Event Retention**: The event store automatically enforces a strict cap of 200 events, discarding the oldest entries via FIFO rotation to prevent unlimited storage growth or accidental historical footprint accumulation on device.

## M8.5 Server Companion surface

1. **Non-Root / Least Privilege Execution**: The companion runs as an unprivileged service user (`agentdeck` or the SSH operator user) with empty Linux capabilities (`CapabilityBoundingSet=`). It requires no `sudo` privileges, `CAP_SYS_ADMIN`, or access to `docker.sock`.
2. **Zero Network Port Exposure**: The companion does not listen on any public or loopback TCP ports (no HTTP/gRPC server). All communication is conducted via authenticated, host-verified SSH command execution (`agentdeck-companion events --after <sequence>`).
3. **Read-Only / No Auto-Approval**: The companion strictly observes server state. It never sends input (`yes`, `approve`, `continue`) to active agent CLI prompts and never executes mutating Git commands (`git add`, `git commit`, `git push`, `git reset`).
4. **Command Injection Defense**: All internal process executions (`tmux`, `git`) use explicit argument arrays via `subprocess.run(..., shell=False)`. CLI argument parsing strictly validates integer sequences, project IDs, and paths.
5. **No Secret / Environment Dumping**: The companion never reads or logs environment variables (`OPENAI_API_KEY`, `ANTHROPIC_API_KEY`, etc.), process environments (`/proc/<pid>/environ`), or full terminal transcripts. The journal records only high-level transition events.
6. **Bounded Journal & Single-Instance Lock**: The journal file (`events.jsonl`) is constrained by count (1,000 events) and age (7 days). Single-instance locking via `fcntl.flock` prevents concurrent execution and duplicate sequence collisions.

## M9 Push Relay & APNs Security Surface

1. **Four Explicit Trust Boundaries**:
   - **Mobile Client**: Generates and stores its own `InstallationIdentity` (UUID). Keeps SSH credentials in iOS Keychain. Never receives APNs `.p8` private keys.
   - **Server Companion**: Operates on managed Linux hosts with zero open inbound TCP ports. Never accesses APNs `.p8` keys. Sends sanitized event envelopes outbound to the Push Relay over TLS.
   - **Push Relay**: Central service that holds the APNs `.p8` key and signs short-lived ES256 JWT tokens. Maintains an isolated SQLite database for device tokens and dedup records. Never executes SSH commands or accesses remote server code.
   - **Apple APNs**: Direct Apple infrastructure receiving HTTP/2 push requests authenticated with provider JWTs.
2. **APNs Private Key (.p8) Isolation**:
   - `.p8` keys must never be committed to git, copied to Docker images, stored in client code, or placed on managed Linux hosts.
   - Push Relay reads `.p8` keys only from an external, restricted-permission path (e.g. `chmod 0600`) specified at runtime via environment variable or secure config.
3. **Device Token Privacy**:
   - APNs device tokens are sensitive routing identifiers. They are never printed in plain text, logged in application telemetry, or exposed in public logs.
   - Push Relay logs only 8-character masked tokens (`f40f...78ad`).
4. **Zero Transcript / Secret Leakage in Push Payloads**:
   - Push notification alert payloads strictly follow user privacy policies (`full`, `projectOnly`, `generic`).
   - Terminal outputs, agent prompt bodies, diff chunks, code paths, and command lines are strictly stripped before payload creation.
5. **Deduplication & Idempotency**:
   - Ingested events are recorded in `processed_events` by `eventId`. Duplicate transmissions from companions retrying over network drops are acknowledged without triggering double push alerts to devices.
6. **Automatic Token Invalidation (410 Cleanup)**:
   - When APNs responds with HTTP 410 (`Unregistered`) or `BadDeviceToken`, the Push Relay immediately deactivates the device registration in the database, preventing stale token accumulation or retry storms.