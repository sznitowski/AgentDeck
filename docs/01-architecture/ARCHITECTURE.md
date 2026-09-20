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