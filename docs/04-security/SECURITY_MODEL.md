# Security model

The phone is a loss-prone control surface for sensitive Linux infrastructure. SSH authenticates server and user; `ProjectProfile` provides context; `ExecutionPolicy` guides UI decisions. UI policy does not confine a free shell or remote agent. Production restrictions require least-privilege Linux accounts and server-side authorization.

M1.5 separates storage: `ServerProfile` metadata and credential references in a versioned app-support file; host algorithm, SHA256 fingerprint, timestamps and revocation in a second file; passwords, private-key text and passphrases in platform secure storage behind `SecureCredentialStore`. iOS requests Keychain `unlocked_this_device` with sync disabled. Implementation is present; Keychain/device behavior is PENDING_MACOS_VALIDATION. Metadata/trust files are not encrypted by AgentDeck. App sandbox, file protection and backup/restore effects require device review. Corrupt or unsupported data fails startup closed.

Unknown host keys require user approval with host, algorithm and fingerprint shown. Matching known keys pass; changed and revoked keys block. Normal Connect/Reconnect never replaces trust. Removing a stored key is a separate confirmed action, followed by a new independent fingerprint check. No accept-all host path or secret logging exists. The app does not start an SSH connection if storage initialization fails.

Explicit TCP/handshake/authentication timeouts and bounded cancellable reconnect remain. M1.5's manual lab harness is TEST_ONLY and does not persist secrets. Private-key material exists transiently as Dart strings; reliable memory zeroization is unavailable. iOS background/resume and live SSH interoperability remain pending. Review commands, logs, tunnels, backups and exports before later milestones.
