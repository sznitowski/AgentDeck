# Architecture

The Flutter app has `app/` for startup and navigation, `features/` for user-facing areas, `core/domain/` for platform-independent models and contracts, and `shared/` for shared presentation. Do not add empty domain/application/infrastructure/presentation directories: split a feature when implementation demands it.

The intended dependency direction is UI → application use cases → domain contracts ← infrastructure adapters. Future `dartssh2` or another SSH implementation belongs in infrastructure; Keychain is behind `SecureCredentialStore`. The M0 shell uses mock summary values only and performs no network access.

Connection state and agent execution state are separate. On resume, the app must re-establish SSH, verify the host, discover the remote session, and reattach tmux when possible. Failure to observe an agent is not evidence that it finished. See DOMAIN_MODEL.md and SECURITY_MODEL.md.

## M1 SSH implementation

`ServerProfile` holds only metadata and credential references. `features/connections/domain/ssh_models.dart` defines host identity, known-host and transport contracts, failure categories and policy values. `features/connections/application/ssh_connection_service.dart` coordinates credentials, trust, state and retries. `features/connections/infrastructure/dart_ssh_transport.dart` is the only layer importing dartssh2. `ServersPage` consumes the service interface and never sees `SSHClient`.

Dependency direction remains UI → application → domain ← infrastructure. The transport can later expose separate session capabilities without coupling Projects, Agents, Terminal, SFTP or Git to dartssh2. `RemoteConnection` is an M0 future-facing contract; M1's focused `SshConnectionService` does not yet implement remote sessions. The app shell does not compose the service until secure credential and durable host-trust adapters are available. The in-memory server list is a UI demonstration, not production persistence. Connection state remains separate from agent execution state.

## M1.5 persistence and composition

`AgentDeckServices.bootstrap` composes platform adapters once at startup and injects repositories, credential storage and connection service into Servers. Startup validates both versioned files and fails closed on corrupt data. The UI depends on domain repository interfaces, not files or the secure-storage plugin. `JsonFileStore` serializes writes within an instance; multiple isolates/processes writing the same file are outside this design. `NavigationShell` preserves Servers state across tab changes. The transport remains isolated behind `SshTransport`; no terminal or remote session API is exposed to widgets.

## M2 terminal

Servers exposes Open Terminal only after the selected profile has a verified SSH connection. `SshConnectionService.openTerminal` checks connection ownership and dimensions; `SshTerminalTransportHandle` is an optional transport capability so earlier fakes stay compatible. `DartSshTransport` alone imports `dartssh2`, requests a `xterm-256color` PTY and interactive shell, and adapts SSH byte streams to `TerminalSession`. With PTY, stdout is the combined terminal stream; a separate stderr stream is generally absent. A rejected PTY/shell returns a typed `protocol` failure and does not fall back to `exec`.

The Flutter `TerminalPage` owns one `TerminalController` and one xterm view. The application controller owns its terminal channel, incrementally decodes UTF-8, forwards input bytes, debounces and deduplicates resize, and detects stream loss. The page owns only the view/buffer and explicit copy/paste controls. Closing the page closes its channel, not the verified SSH connection. SSH reconnect opens a new channel and shell; the old visual buffer remains on loss, but there is no shell/session recovery before M3. Terminal state is separate from SSH connection and agent execution states.

## M3 tmux implementation

`TmuxService` manages remote tmux processes via `SshTmuxTransportHandle.run` for control commands and `SshTmuxTransportHandle.attachTmux` for interactive PTY attachment over verified SSH. Session references (`ad_<nonce>`) are persisted locally via `FileTmuxSessionRepository`. Formatting uses colon delimiters to prevent control character sanitization. Process execution continues uninterrupted across client disconnects, and detaching cleanly retains the remote tmux session.

## M4 SFTP implementation

The remote files subsystem exposes `RemoteFileSystem` and `RemoteFileService` abstractions. `DartSshSftpAdapter` adapts `dartssh2`'s `SftpClient` to `RemoteFileSystem` without leaking infrastructure types to the presentation layer. All file operations (list, stat, read, write, mkdir, rename, delete, rmdir) execute via native SFTP protocol commands without invoking remote shell processes. Atomic writes utilize nonce-based temporary files and SFTP rename. Paths are handled exclusively via `PosixPath`. Destructive operations on production environments enforce explicit path confirmation and persistent visual badges.

## M5 Agent Orchestration implementation

The agent orchestration subsystem is driven by `AgentCoordinator`, `AgentProvider`, `AgentObservation`, and `AgentInstanceRepository`:
- **Provider Decoupling**: Each agent CLI (`CodexProvider`, `ClaudeCodeProvider`, `OpenCodeProvider`, `AntigravityProvider`, `GenericCliProvider`, `FakeAgentProvider`) implements detection, version parsing, typed launch command construction, declared capabilities, and output classification.
- **Managed Tmux Association**: Agent processes run inside managed tmux sessions named `ad_agent_<provider>_<project>_<nonce>`. `AgentCommandSafety` strictly blocks shell injection in binary names, arguments, session names, and working directory paths.
- **State Observation & Confidence**: The coordinator queries `tmux list-panes` (`pane_dead`, `pane_dead_status`, `pane_current_command`) for confirmed process lifecycle state, and uses provider-specific `AgentOutputClassifier` over the most recent 15–30 lines of `capture-pane` output to infer `WAITING_USER` status with ANSI stripping.
- **Resilience & Reconciliation**: Disconnecting or closing AgentDeck leaves remote agents running on the server. On reconnect or refresh, instances reconcile with live remote tmux sessions. If a remote session is missing, the instance is marked `stale`.
- **Zero Credential & Output Persistence**: Only lightweight metadata (`instanceId`, `providerId`, `serverId`, `projectId`, `tmuxSessionName`, timestamps, state) is persisted. No LLM tokens, full terminal histories, or agent conversation logs are ever stored or transmitted.

## M6 Git Operations implementation

The remote Git subsystem provides structured, read-first repository observation and guarded local mutations without cloning repositories locally or storing Git credentials:
- **Layered Structure**: Presentation (`ProjectGitPage`, `GitChangesPage`, `GitDiffViewerPage`, `GitHistoryPage`, `GitCommitDetailPage`) → Application (`GitService` / `RemoteGitService`) → Domain (`GitRepository`, `GitStatus`, `GitFileChange`, `GitCommit`, `GitDiff`, `GitAvailability`, `GitCommandSafety`, `GitCommandExecutor`) ← Infrastructure (`SshGitCommandExecutor` adapting `SshConnectionService`).
- **Command Isolation**: Operates via `git -C <workingDirectory>` without subshells or shell chaining (`&&`). All path arguments are disambiguated with `--` to prevent path-based option injection.
- **Machine-Readable Parsing**: Uses `git status --porcelain=v2 --branch` for deterministic staging state tracking (staged, unstaged, untracked, renamed, deleted, conflicted), ASCII Unit Separator (`\x1f`) for `git log`, and unified diff chunking.
- **Sensitive File Protection & Safety**: Identifies sensitive files (`.env`, `*.key`, `*.pem`, `credentials*`) before rendering diffs, never persists diff bodies to local storage, blocks arbitrary commands from UI, and strictly defers remote push/fetch/rebase operations.

## M7 Server Operations implementation

The server operations and observability subsystem provides structured monitoring and safe service management on remote Linux hosts:
- **Layered Structure**: Presentation (`ServerOperationsPage`, `ServerOverviewTab`, `ServerProcessesTab`, `ServerServicesTab`) → Application (`ServerOperationsService` / `RemoteServerOperationsService`) → Domain (`ServerInfo`, `CpuUsage`, `MemoryUsage`, `DiskUsage`, `RemoteProcess`, `SystemService`, `ServerHealthSnapshot`, `ServerCapabilities`, `ServerCommandExecutor`, `ServerOpsCommandSafety`) ← Infrastructure (`SshServerCommandExecutor` adapting `SshConnectionService`).
- **Machine-Readable Kernels**: Parsers read directly from `/proc/stat` (CPU delta sampling), `/proc/meminfo` (exact available/used RAM & swap), `/proc/loadavg` (1m, 5m, 15m averages), `/proc/uptime`, and `/etc/os-release`.
- **POSIX Filesystem & Process Discovery**: Disks are enumerated via portable `df -P -k` (filtering pseudo-filesystems). Processes are listed via `ps -eo ...` restricted to `comm` (executable name) to safeguard command-line passwords and tokens.
- **Systemd & Capability Awareness**: Dynamically detects `hasSystemd`. Non-systemd systems (Alpine Linux / OpenRC / containers) degrade gracefully and continue reporting resource and process health without errors.
- **Production Guardrails**: Disables arbitrary command execution from UI. Service actions (`start`, `stop`, `restart`) require explicit user confirmation with red `PRODUCTION` badges on production environments. Zero sudo password capture or automated privilege escalation.

## M7.5 Project Workspace / Control Center implementation

The Project Workspace coordinates and aggregates modular capabilities around `ProjectProfile`:
- **Layered Structure**: Presentation (`ProjectWorkspacePage`, `WorkspaceAttentionBanner`, `WorkspaceAgentCard`, `WorkspaceGitCard`, `WorkspaceServerCard`, `WorkspaceQuickActions`) → Application (`ProjectWorkspaceCoordinator`) → Domain (`ProjectWorkspaceSnapshot`, `WorkspaceAttentionItem`, `WorkspaceGitSummary`, `WorkspaceAgentSummary`, `WorkspaceTmuxSummary`, `WorkspaceServerSummary`, `WorkspaceFilesSummary`).
- **Composite Observation**: Coordinates status queries across `SshConnectionService`, `AgentCoordinator`, `GitService`, `TmuxService`, `ServerOperationsService`, and `RemoteFileService` concurrently.
- **Actionable Priority Hierarchy**: Automatically derives `WorkspaceAttentionItem` instances, placing urgent events (`WAITING_USER` prompt, merge conflicts, connection drops) at the top of the interface.
- **Partial Failure Isolation**: Each subsystem handles errors in isolation without failing the overall workspace view.
- **Contextual Routing**: Direct navigation to `TerminalPage` (resuming tmux agent or opening shell), `RemoteFilesPage`, `ProjectGitPage`, and `ServerOperationsPage` with full project context preservation.

## M8 Event & Notification Core implementation

The Event & Notification subsystem unifies state observations into structured, deduplicated, privacy-safe domain events and mobile notifications:
- **Layered Structure**: Presentation (`NotificationCenterPage`, `NotificationBadge`) → Application (`NotificationCoordinator`, `StateTransitionDetector`, `EventDeduplicator`, `NotificationDeliveryService`, `AppLifecycleCoordinator`) → Domain (`AgentDeckEvent`, `EventType`, `EventSeverity`, `EventSource`, `EventReadState`, `NotificationDestination`, `NotificationPolicy`, `NotificationPreferences`, `EventRepository`) ← Infrastructure (`FileEventRepository` adapting `JsonFileStore`).
- **State Transition Engine**: Emits events strictly on state changes (`RUNNING -> WAITING_USER`, `0 conflicts -> >0`, sustained disconnects past debounce, server threshold crossings with hysteresis). Steady-state polls emit zero duplicate events.
- **Deduplication & Bounded Retention**: Fingerprint-keyed deduplication prevents duplicate event generation. Local storage in `agentdeck_events.json` is atomically persisted and capped at 200 items max with FIFO pruning.
- **Privacy & Zero Secret Persistence**: Raw command outputs, full prompts, diffs, credentials, and environment tokens are strictly filtered out before event creation and storage. Support for 3 privacy preview modes (`full`, `projectOnly`, `generic`).
- **Lifecycle & Catch-Up**: Automatically pauses foreground timers when app is backgrounded/suspended; triggers catch-up workspace inspection and state transition evaluation upon app resume.
- **Delivery Decoupling**: Implements in-app notifications and provides pluggable abstractions for local OS notifications and future remote push (M8.5/M9 companion).

## M8.5 Server Companion / Remote Observer implementation

The Server Companion (`agentdeck-companion`) operates as an autonomous, headless, read-first server-side observer on managed Linux hosts:
- **Topology**: Daemon running on Linux host observing tmux sessions, active coding agents, Git status, server resource pressure, and working directories independently of mobile app lifecycle.
- **Layered Structure**:
  - Companion Core (`agentdeck-companion` in Python 3 stdlib): Configuration (`companion.json`), Observers (`tmux`, `git`, `server_metrics`, `directories`), Transition Detector, Monotonic Journal (`events.jsonl`), POSIX single-instance lock (`fcntl.flock`), and CLI commands (`version`, `health`, `status`, `events`, `snapshot`, `projects`, `run`, `scan-once`).
  - Mobile Integration: Presentation (`NotificationCenterPage`, `ProjectWorkspacePage`) → Application (`NotificationCoordinator`) → Domain (`RemoteCompanionClient`, `CompanionAvailability`, `CompanionEventBatch`, `CompanionCursorRepository`) ← Infrastructure (`SshCompanionClient`, `FileCompanionCursorRepository`).
- **CLI-over-SSH Transport**: Exposes zero open TCP ports. Synchronization occurs strictly via authenticated, host-verified SSH commands (`agentdeck-companion events --after <sequence>`).
- **Monotonic Sequence & Journal**: Appends versioned JSON Lines with strictly increasing sequence numbers surviving daemon restarts. Automatic FIFO retention pruning (1,000 events / 7 days).
- **First-Start Baseline**: Initial daemon startup captures baseline observations to prevent historical alert spam.
- **Strict Privacy**: Zero transcript or diff logging, non-root execution, and strict argument sanitization against shell injection.

## M9 APNs / iOS Native Integration implementation

The APNs push notification pipeline enables real-time lock-screen alerts when remote agents need user input, even when the mobile app is terminated and SSH connections are closed:
- **Topology & Trust Boundaries**:
  - `Remote Linux Hosts`: Run `agentdeck-companion` with zero open inbound ports. On state transitions, the Companion Outbox pushes event envelopes outbound via `POST /v1/companion-events` over HTTPS/TLS to the central Push Relay.
  - `AgentDeck Push Relay` (`server/push_relay/`): Central daemon in Python 3 managing device registrations, rotating ES256 JWT provider tokens (50-minute cache), APNs HTTP/2 requests, and deduplication.
  - `Apple APNs`: Direct Apple Push Notification service.
  - `iOS Mobile App`: Presentation (`NotificationSettingsPage`, deep link routing) → Application (`PushNotificationService`) → Domain (`PushDeviceRegistration`, `InstallationIdentity`, `PushRelayClient`) ← Infrastructure (`HttpPushRelayClient`, `FileInstallationIdentityRepository`, `FilePushRegistrationRepository`).
- **Direct APNs (No Third-Party Intermediaries)**: Eliminates Firebase Cloud Messaging (FCM) and external push vendors to maximize iOS battery efficiency, minimize SDK bloat, and maintain direct trust boundaries.
- **Provider Key Isolation**: The `.p8` Apple private key is stored exclusively in the Push Relay. It is never copied to remote Linux hosts, mobile apps, or git repositories.
- **Device Registration & Rotation**: Mobile generates an application-level random UUID `InstallationIdentity` (no hardware UDIDs) and registers its APNs device token. Reinstalls or token rotations gracefully overwrite prior token registrations.
- **Idempotency & Dedup**: Push Relay deduplicates incoming events by `eventId` in a thread-safe SQLite database (`processed_events`).
- **APNs Response Handling**: HTTP 200 logs delivery; HTTP 410 (`Unregistered`) automatically deactivates invalid device tokens in the registry; transient errors (429/503) trigger exponential backoff.
- **Notification Privacy**: Payloads are formatted according to user-selected privacy modes (`full`, `projectOnly`, `generic`), masking sensitive project names and terminal text.
- **Signal vs Truth Separation**: Push notification serves strictly as a wake-up signal. Opening a push notification deep-links to the target view and triggers canonical SSH catch-up synchronization with the Server Companion Journal (`events.jsonl`).