# Domain model

`ServerProfile` holds id, display name, host, port, user, and a credential reference; it never holds a password or private key. `ProjectProfile` holds server id, working directory, optional repository, environment, runtime, preferred agent id, capabilities, and `ExecutionPolicy`. `Environment` distinguishes development, staging, and production.

`AgentProvider` describes identity and supported capabilities. `AgentExecutionState` is idle, starting, running, waitingUser, finished, or failed. `ConnectionState` is disconnected, connecting, connected, reconnecting, or failed. A disconnected connection does not modify agent state. `PolicyDecision` is allowed, confirmationRequired, or denied.

`RemoteConnection`, `RemoteSession`, `TerminalSession`, `FileTransferClient`, and `SecureCredentialStore` are future-facing interfaces. M0 contains signatures, not transports or persistence.
