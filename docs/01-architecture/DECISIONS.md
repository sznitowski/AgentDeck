# Architecture decisions

## ADR-001 — Flutter as primary client framework
Status: Accepted

Context: iPhone is first, iPad and other clients may follow.
Decision: Use Flutter/Dart for the client shell and domain model; add native iOS integration where required.
Consequences: iOS must be tested on macOS/Xcode and a real device. Flutter compatibility does not imply background SSH continuity.
Alternatives considered: Swift-only client, Android-first adaptation.

## ADR-002 — Independent iOS-first product
Status: Accepted

Context: KAMMEL targets Android/Linux and uses Android-specific background behavior.
Decision: Build AgentDeck independently and inspect KAMMEL only as an external reference. Reuse of a specific file needs user approval and provenance.
Consequences: More initial work, less inherited platform debt.
Alternatives considered: full fork, progressive clone, wholesale port.

## ADR-003 — Remote continuity via tmux
Status: Accepted as architectural direction; implementation pending M3

Context: iOS may suspend SSH while a Linux process continues.
Decision: Model mobile connection, remote session, remote process, and agent execution separately. Reconnect and reattach tmux rather than promise a permanent socket.
Consequences: Session discovery and reconciliation are required.
Alternatives considered: relying on a permanent iOS socket.

## ADR-004 — Transport abstraction
Status: Accepted

Context: SSH library choice is not validated on iOS.
Decision: Keep transport interfaces independent of dartssh2. Choose implementation in M1 after license, maintenance, security, and iOS review.
Consequences: Small interface cost now, replaceable adapter later.
Alternatives considered: expose dartssh2 throughout UI and domain.

## ADR-005 — Keychain-backed credentials
Status: Accepted as requirement; implementation pending M1

Context: Server credentials are sensitive.
Decision: Keep secrets behind SecureCredentialStore and use iOS Keychain in the iOS adapter. Store only references in profiles.
Consequences: No credential persistence in M0; device behavior needs macOS validation.
Alternatives considered: preferences or JSON storage, rejected.

## ADR-006 — Structured agent providers
Status: Accepted as interface direction; implementation pending M5

Context: Multiple CLIs have different capabilities and output formats.
Decision: Keep provider identity/capabilities and execution state separate from connection state; do not promise certainty from terminal text alone.
Consequences: M5 will define observation confidence and reconciliation.
Alternatives considered: one UI parser for all agents.

## ADR-007 — Official dartssh2 for SSH transport

Status: Accepted for M1 core, pending iOS device validation

Context: AgentDeck needs password/private-key SSH, strict host identity, future SFTP and PTY, and a replaceable transport. KAMMEL used a patched older dartssh2. Current upstream 4.1.0 exposes OpenSSH SHA256 host fingerprints and fixes the documented channel stall.

Decision: Pin dartssh2 4.1.0 (MIT) as an infrastructure dependency. Always supply onVerifyHostKey; never disable verification. Resolve credentials through SecureCredentialStore, keep SSHClient inside the adapter, and set TCP, handshake, and authentication timeouts. Do not copy KAMMEL's fork.

Consequences: Native iOS behavior and secure persistent stores remain unvalidated. Key material must be obtained from Keychain in a future iOS adapter; test stores are TEST_ONLY. Upstream security changes require review before version upgrades.

Alternatives considered: ssh2 2.2.3 (older native wrappers and key-format limitations), experimental ssh_core, or a custom SSH implementation (unnecessary cryptographic risk).

## ADR-008 — Platform secure credentials

Status: Accepted for M1.5 core; iOS security validation pending.

Context: SSH passwords, private keys and passphrases must persist without entering serializable profiles or plaintext application files. Windows is the development host; iOS is the target. `flutter_secure_storage` 11.2.0 is maintained and lists iOS and Windows support.

Decision: Pin `flutter_secure_storage` 11.2.0 (BSD-3-Clause) behind `SecureCredentialStore` and a small string backend. Use KeychainAccessibility.unlocked_this_device with synchronization disabled on iOS. Keep opaque references in profiles. Never use SharedPreferences or JSON for secrets.

Consequences: The adapter is implemented, but Keychain entitlements, device lock, backup/restore, reinstall and OS-level persistence have not been validated. Base64 is only a byte/string conversion, not encryption. Key material remains in Dart memory during authentication. The iOS runner will need Keychain capability/entitlement review, followed by a real read/write/restart test.

Alternatives: custom native Keychain bridge (more maintenance and platform work), plaintext preferences/files (rejected), experimental storage packages (unnecessary risk).

## ADR-009 — Versioned files for profile and host trust

Status: Accepted for M1.5 core; platform file protection and restore behavior pending.

Context: Profile metadata and host fingerprints are non-secret but operationally critical; loss or silent replacement of trust can cause unsafe prompts. `shared_preferences` explicitly does not guarantee a write is on disk when its API returns.

Decision: Pin `path_provider` 2.1.6 (BSD-3-Clause) to locate app-support storage. Use separate schema-versioned JSON files behind `ServerProfileRepository` and `KnownHostRepository`. Serialize writes, flush a temporary file, keep a backup during replacement, and fail closed on invalid data. Do not put all metadata into Keychain or add a database for this small dataset.

Consequences: Files are not encrypted by AgentDeck; OS sandbox and file protection, backup/restore and local tampering require device review. Format upgrades must add explicit migrations rather than silently resetting data. Multiple processes/isolates writing the same files are not supported. If data changes outside the app while running, restart/reload is required.

Alternatives: SharedPreferences (rejected for critical trust durability), SQLite/Isar/Hive (unnecessary schema and package weight at this scale), one combined file (unnecessary coupling between profiles and trust).

## ADR-010 — Official xterm terminal emulator for M2

Status: Accepted for M2 core; iOS device validation pending.

Context: AgentDeck needs a VT/ANSI renderer, bounded scrollback, text selection and mobile keyboard input without coupling SSH or application logic to a widget. KAMMEL uses a modified copy of xterm 4 for keyboard suggestions and inline image paste; neither patch is needed for M2.

Decision: Pin `xterm` 4.0.0 (MIT) without overrides. Keep `xterm.Terminal` and `TerminalView` in presentation. `TerminalController` consumes the domain `TerminalSession`, and `DartSshTransport` alone opens the SSH PTY. Use a 2000-line scrollback limit and explicit clipboard paste.

Consequences: The original package is no longer actively maintained. iOS soft/hardware keyboard, touch selection, paste, rotation and lifecycle require real-device validation. A maintained MIT successor may be chosen after evidence. No KAMMEL code was copied.

Alternatives: `xterm2` 5.2.0 (MIT, newer maintained fork), `terminal_view` 0.2.0 (MIT, young mobile fork), `xterm3` 6.3.0 (AGPL obligations), custom emulator (unnecessary parser and security work). See TERMINAL_RESEARCH.md.

## ADR-011 — Pure SFTP & Remote Files Architecture

Status: Accepted for M4 core; iOS document picker and share sheet pending.

Context: AgentDeck requires remote directory browsing, file metadata inspection, streaming download/upload, basic text viewing/editing, directory creation, renaming, and safe deletion. Executing shell commands (`cat`, `rm`, `mv`, `mkdir`, `scp`) introduces severe command injection risks and depends on host binaries.

Decision: Implement remote file management entirely via the SFTP subsystem of `dartssh2` 4.1.0 without invoking any remote shell commands or sudo escalation. Isolate SFTP infrastructure behind `RemoteFileSystem` and `RemoteFileService`. Centralize all remote path manipulation in POSIX-only `PosixPath`. Enforce atomic writes via temporary file upload and SFTP rename. Enforce production safety badges and explicit path confirmations for destructive actions.

Consequences: SFTP subsystem must be available on the remote SSH server (internal-sftp or sftp-server). Operations are strictly bounded by user permissions without sudo. Native iOS document picker, share sheet, and app sandbox interactions are deferred to iOS platform validation.

Alternatives considered: Shell commands over PTY/SSH exec (rejected for command injection vulnerabilities and inconsistent output parsing), SCP protocol (deprecated and legacy), custom file daemon (rejected to avoid remote agent requirements).

## ADR-012 — Remote Agent Orchestration Architecture

Status: Accepted for M5 core; push notifications and iOS background lifecycle pending.

Context: AgentDeck manages CLI agents (`codex`, `claude`, `opencode`, `agy`, generic CLI) executing on remote Linux servers. The mobile device may disconnect at any time, and agents must persist independently without local LLM execution, credential exposure, or automatic destructive action.

Decision:
1. Run all remote agents inside managed tmux sessions named `ad_agent_<provider>_<project>_<nonce>`.
2. Decouple `AgentExecutionState` (`idle`, `starting`, `running`, `waitingUser`, `finished`, `failed`, `unknown`), `ConnectionState` (SSH), `TmuxSessionState`, and `TerminalState`.
3. Enforce strict shell injection protections in `AgentCommandSafety` (safe binary paths, POSIX single-quote escaping, component sanitization).
4. Classify `WAITING_USER` from bounded recent terminal buffers (~15–30 lines) with ANSI stripping via decoupled `AgentOutputClassifier` instances.
5. Reconcile metadata with live tmux sessions (`list-panes`) on reconnect/refresh; mark missing sessions as `stale` rather than reporting false positive running states.
6. Persist only lightweight metadata without credentials, API tokens, or conversation transcripts.
7. Never perform automatic approvals or automated command execution.

Consequences: Agent state observation relies on process signals (`pane_dead`, `pane_dead_status`, `pane_current_command`) and text pattern heuristics rather than a structured daemon API. The user must attach via `TerminalPage` to respond to interactive prompts. Push notifications and background polling are deferred to iOS platform validation.

Alternatives considered: Local LLM execution (rejected: mobile compute and thermal limits), remote agent companion daemon (deferred: introduces server installation prerequisites), automatic approval engine (rejected: unsafe for production and complex tasks).

## ADR-013 — Remote Git Operations Architecture

Status: Accepted for M6 core; iOS large diff gestures and clipboard integration pending.

Context: AgentDeck users and autonomous agents modify code repositories located on remote Linux servers. The mobile client needs structured visibility into branch, HEAD, staging status, unified diffs, and commit history with bounded, safe mutation capabilities (stage, unstage, commit) without exposing raw Git shell execution or capturing credentials.

Decision:
1. Execute remote Git commands via `git -C <workingDirectory> ...` over verified SSH transport without subshell creation or shell chaining (`&&`).
2. Strictly parse machine-readable outputs: `git status --porcelain=v2 --branch`, `git log --format` with ASCII Unit Separator (`\x1f`), and unified diffs.
3. Enforce option injection protection (`--`) for all path arguments in stage, unstage, and diff commands.
4. Detect sensitive files (`.env`, `*.key`, `*.pem`, `credentials*`) and alert the user before rendering diffs. Never persist diff text or logs.
5. Provide guarded staging (`git add -- <path>`), unstaging (`git restore --staged -- <path>`), and user-driven commit (`git commit -m <msg>`) with mandatory confirmation dialogues in production environments.
6. Explicitly defer remote push (`PUSH_DEFERRED`), automatic pull/rebase (`PULL_DEFERRED`), conflict auto-resolution (`CONFLICT_RESOLUTION_DEFERRED`), and submodule management (`SUBMODULE_MANAGEMENT_DEFERRED`). Block destructive commands (`reset --hard`, `clean -fd`, `checkout -- .`) from the structured UI.

Consequences: Git operations are strictly repo-local on the remote server. Network push/pull operations remain deferred until remote credential and branch policy controls are established in future milestones.

Alternatives considered: Local repository mirroring (rejected: excessive mobile bandwidth and storage consumption), arbitrary Git CLI execution from UI (rejected: unsafe and prone to injection), Git library / libgit2 native bindings (rejected: unnecessary complexity and native compilation overhead).

## ADR-014 — Linux Server Operations & Observability Architecture

Status: Accepted for M7 core; iOS background polling and push notifications pending.

Context: AgentDeck needs to observe remote Linux server resource health (CPU, memory, swap, disk, load average, uptime), inspect active processes, and discover/monitor systemd services without requiring root/sudo privileges, leaking process command-line secrets, or turning the mobile app into an unrestricted administrative shell.

Decision:
1. Adopt an Observation-First architecture: Read-only monitoring by default. State mutations (systemd service start/stop/restart) are guarded behind explicit confirmation dialogs and persistent `PRODUCTION` banners.
2. Rely on machine-readable kernel interfaces (`/proc/stat`, `/proc/meminfo`, `/proc/loadavg`, `/proc/uptime`), `/etc/os-release`, POSIX-standard `df -P -k`, and `systemctl show` property lists.
3. Protect process privacy by listing processes via executable name (`comm`) rather than full command-line arguments (`args`), preventing leakage of database passwords, API tokens, or secrets passed via CLI flags.
4. Calculate CPU usage from `/proc/stat` counter deltas across consecutive samples.
5. Dynamically detect host capabilities (`hasProcfs`, `hasSystemd`, `isAlpine`) via `ServerCapabilities`. Gracefully display capability notes on non-systemd hosts (e.g. Alpine Linux, OpenRC, Docker containers) without throwing fatal errors.
6. Strictly disallow automatic sudo escalation or sudo password storage. Operations lacking permissions fail gracefully with `ServerOperationFailureKind.permissionDenied`.

Consequences: Observability requires standard Linux procfs and POSIX utilities. Non-Linux servers are classified as `unsupportedPlatform`. Full journal logs and arbitrary process killing are deferred to future milestones.

Alternatives considered: Custom monitoring daemon (rejected: requires server-side installation prerequisites), raw `top`/`htop` screen scraping (rejected: locale-dependent, brittle, and terminal-control heavy), Webmin/Cockpit API integration (rejected: unnecessary third-party server dependency).

## ADR-015 — Project Workspace / Control Center Composition

Status: Accepted for M7.5; background push notifications pending.

Context: Prior to M7.5, AgentDeck possessed strong remote capabilities (SSH, Terminal, tmux, Files, Agents, Git, Server Operations) operated in relative isolation. Users managing a software project on a remote server had to navigate across separate screens to determine if a background agent needed attention, if files were modified, if merge conflicts existed, or if the server was experiencing resource pressure.

Decision:
1. Compose a unified `ProjectWorkspacePage` centered around `ProjectProfile`.
2. Introduce an ephemeral `ProjectWorkspaceSnapshot` and `ProjectWorkspaceCoordinator` that aggregate subsystem summaries without duplicating underlying state or maintaining parallel polling daemons.
3. Establish an Actionable Priority Hierarchy: Events requiring immediate human intervention (`WAITING_USER` agent status, Git merge conflicts, SSH disconnection, failed jobs) are prominently rendered at the top of the mobile interface.
4. Enforce Partial Failure Isolation: Subsystem queries run concurrently with isolated error handling; an unconfigured Git repository or non-systemd server does not crash or invalidate the rest of the workspace snapshot.
5. Provide contextual navigation to existing subsystem views (`TerminalPage`, `RemoteFilesPage`, `ProjectGitPage`, `ServerOperationsPage`) preserving project context.

Consequences: The mobile workspace functions as an integrated control surface. Each underlying service remains the single source of truth for its domain. Background push alerts remain deferred to M8.

Alternatives considered: Heavyweight monolithic project daemon (rejected: violates zero-server-install principle), tightly coupled mega-service (rejected: degrades modularity and testability), separate independent views only (rejected: poor mobile user experience).

## ADR-016 — Event and Notification Core Architecture

Status: Accepted for M8 core; APNs push provider and server companion deferred to M8.5/M9.

Context: AgentDeck needs to inform users when remote state transitions occur (e.g. agent needs user input, git conflicts arise, connection is lost, or server resources exceed limits). Polling repeatedly without state transition detection produces alert spam. Background execution on iOS suspends the app and closes SSH sockets, making local background monitoring impossible.

Decision:
1. Model events strictly as `AgentDeckEvent` domain records decoupled from presentation notifications.
2. Implement `StateTransitionDetector` to emit events only on actual state delta transitions (e.g. `RUNNING -> WAITING_USER`), applying debounce grace periods to SSH drops and hysteresis bands (90% critical / 85% recovery) to server resource metrics.
3. Apply `EventDeduplicator` using stable entity fingerprints.
4. Persist events atomically in `agentdeck_events.json` using `JsonFileStore`, enforcing a 200-event FIFO retention limit and strictly blocking secret data (passwords, tokens, command outputs, prompt bodies, diff chunks).
5. Filter notifications through `NotificationPolicy` supporting user preferences, project overrides, and 3 privacy preview modes (`full`, `projectOnly`, `generic`).
6. Enforce lifecycle awareness via `AppLifecycleCoordinator`: foreground-only polling timers; catch-up workspace inspection and state transition detection triggered on app resume.
7. Decouple notification delivery into `InAppNotificationDelivery`, `LocalNotificationDelivery` (pluggable, pending macOS validation), and future `RemotePushDelivery`.

Consequences: The app delivers accurate, deduplicated, zero-spam in-app notifications and activity history while foregrounded. True background alerts while the app is suspended require the server-side companion and APNs provider planned for M8.5 and M9.

Alternatives considered: Continuous background SSH socket (rejected: impossible on iOS), spamming notifications on every observation snapshot (rejected: degraded user experience), storing full terminal streams or agent prompts in event store (rejected: severe privacy and security violation).

## ADR-017 — Server Companion Architecture, Stack Decision, and CLI-over-SSH Event Protocol

Status: Accepted for M8.5; APNs remote push provider deferred to M9.

Context: While M8 implemented the client-side event and notification core, iOS background execution suspends the mobile app process and terminates SSH sockets within seconds of the user switching apps or locking the phone. To reliably observe agent transitions, Git conflicts, and server resources when the iPhone is disconnected or asleep, state observation must execute locally on the remote Linux host.

Decision:
1. Implement the first **AgentDeck Server Companion** (`agentdeck-companion`) as a lightweight, autonomous, read-first daemon written in **Python 3 Standard Library** (`#!/usr/bin/env python3`) with strictly zero external dependencies (no pip required).
2. Execute companion as an unprivileged service user without root/sudo or elevated capabilities.
3. Expose zero open network ports (no public or loopback HTTP listeners). Mobile event synchronization operates strictly through authenticated, host-verified SSH (`agentdeck-companion events --after <sequence>`).
4. Maintain an append-safe, bounded, versioned JSON Lines event journal (`events.jsonl`) with monotonic sequence integers (`sequence: 1, 2, 3...`) surviving daemon restarts. Enforce FIFO pruning (1,000 events / 7 days).
5. Enforce single-instance execution on the host using POSIX file locking (`fcntl.flock`).
6. Perform an initial baseline scan upon first start to capture steady state and prevent historical alert storms.
7. Strictly scrub sensitive data (zero terminal transcripts, diff bodies, tokens, passwords, or environment dumps).
8. Integrate with mobile app via `SshCompanionClient` and `NotificationCoordinator`, tracking confirmed cursor sequence per server profile for catch-up synchronization.

Consequences: The companion runs universally across any modern Linux distribution without compilation toolchains or custom runtimes. The iPhone catches up on offline events upon reconnecting. Real-time out-of-app background push notifications to the iPhone lock screen will build upon this journal in M9.

Alternatives considered: Dart CLI companion (rejected: requires Dart SDK or Linux AOT cross-compilation pipeline), Go companion (rejected: requires Go compiler and separate multi-arch binary matrix), SQLite database for journal (rejected: unnecessary complexity vs atomic JSON Lines), opening local HTTP port with SSH tunnel (rejected: adds unnecessary port forwarding management compared to direct CLI-over-SSH execution).

## ADR-018 — Push Relay Architecture, Direct APNs, and Device Identity

Status: Accepted for M9 core; physical Apple APNs delivery pending macOS/Xcode validation.

Context: In M8.5, Server Companion reliably observed state transitions and recorded them in a persistent journal on the Linux host. However, when the iPhone is locked or the app is terminated, the user cannot receive real-time alerts without Apple Push Notification service (APNs). Connecting every managed Linux server directly to APNs is a severe security violation (would require distributing Apple `.p8` private keys across all managed servers).

Decision:
1. **Central Push Relay Architecture**: Introduce a standalone central service `AgentDeck Push Relay` (`server/push_relay/`) responsible exclusively for device registration, token rotation, ES256 JWT provider token management, HTTP/2 APNs dispatch, and 410 Unregistered token cleanup.
2. **Direct APNs (Zero Third-Party Push Intermediaries)**: Interact directly with official Apple APNs HTTP/2 endpoints without Firebase Cloud Messaging (FCM), OneSignal, or AWS SNS. This eliminates third-party SDK bloat, improves battery efficiency, and minimizes attack surfaces.
3. **Strict Secret Boundary**: The `.p8` APNs private key lives exclusively inside the Push Relay environment (mounted securely via filesystem). Never copy `.p8` keys to managed Linux servers, Flutter client code, or git.
4. **Outbound-Only Companion Forwarding**: Server Companion maintains zero inbound listening ports and uses an asynchronous `CompanionOutbox` to push event envelopes outbound over HTTPS/TLS (`POST /v1/companion-events`) with exponential backoff retry.
5. **Application-Level Device Identity**: The mobile app generates a random UUID `InstallationIdentity` (persisted locally) rather than relying on hardware UDIDs or cloud accounts. Device registration links `installationId` with `deviceToken`.
6. **Token-Based APNs Authentication**: Push Relay signs ES256 JWT provider tokens using Apple Team ID and Key ID, caching and reusing tokens with conservative 50-minute rotation.
7. **APNs Response Lifecycle**: Push Relay parses APNs responses: HTTP 200 logs delivery; HTTP 410 (`Unregistered`) or `BadDeviceToken` automatically deactivates the device token in the SQLite store; transient errors (429/503) trigger retry.
8. **Signal vs Truth Decoupling**: Push notifications serve strictly as ephemeral wake-up signals. Tapping a notification opens the target view in AgentDeck and triggers canonical catch-up synchronization with the Server Companion journal (`events.jsonl`).

Consequences: The entire push pipeline is cleanly decoupled across four explicit trust boundaries (Companion, Push Relay, APNs, Mobile App). Complete automated unit and lab tests (Scenarios A through N) validate all components in headless environments without Apple dependencies. Physical iPhone lock-screen verification is gated on macOS/Xcode environment.

Alternatives considered: Direct APNs connection from every Linux host (rejected: severe private key exposure risk), Firebase Cloud Messaging (rejected: unnecessary third-party dependency for iOS-first architecture), Silent pushes for state updates (rejected: unreliable and aggressively throttled on iOS; visible alerts required for user action).