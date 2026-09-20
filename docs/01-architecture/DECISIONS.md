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
