# Architecture

The Flutter app has `app/` for startup and navigation, `features/` for user-facing areas, `core/domain/` for platform-independent models and contracts, and `shared/` for shared presentation. Do not add empty domain/application/infrastructure/presentation directories: split a feature when implementation demands it.

The intended dependency direction is UI → application use cases → domain contracts ← infrastructure adapters. Future `dartssh2` or another SSH implementation belongs in infrastructure; Keychain is behind `SecureCredentialStore`. The M0 shell uses mock summary values only and performs no network access.

Connection state and agent execution state are separate. On resume, the app must re-establish SSH, verify the host, discover the remote session, and reattach tmux when possible. Failure to observe an agent is not evidence that it finished. See DOMAIN_MODEL.md and SECURITY_MODEL.md.

## M1 SSH implementation

`ServerProfile` holds only metadata and credential references. `features/connections/domain/ssh_models.dart` defines host identity, known-host and transport contracts, failure categories and policy values. `features/connections/application/ssh_connection_service.dart` coordinates credentials, trust, state and retries. `features/connections/infrastructure/dart_ssh_transport.dart` is the only layer importing dartssh2. `ServersPage` consumes the service interface and never sees `SSHClient`.

Dependency direction remains UI → application → domain ← infrastructure. The transport can later expose separate session capabilities without coupling Projects, Agents, Terminal, SFTP or Git to dartssh2. `RemoteConnection` is an M0 future-facing contract; M1's focused `SshConnectionService` does not yet implement remote sessions. The app shell does not compose the service until secure credential and durable host-trust adapters are available. The in-memory server list is a UI demonstration, not production persistence. Connection state remains separate from agent execution state.

## M1.5 persistence and composition

`AgentDeckServices.bootstrap` composes platform adapters once at startup and injects repositories, credential storage and connection service into Servers. Startup validates both versioned files and fails closed on corrupt data. The UI depends on domain repository interfaces, not files or the secure-storage plugin. `JsonFileStore` serializes writes within an instance; multiple isolates/processes writing the same file are outside this design. `NavigationShell` preserves Servers state across tab changes. The transport remains isolated behind `SshTransport`; no terminal or remote session API is exposed to widgets.
