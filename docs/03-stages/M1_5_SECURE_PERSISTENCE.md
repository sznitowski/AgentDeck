# M1.5 — Secure Persistence & SSH Lab Validation

## Result

M1_5_DONE (core), 2026-09-19. AgentDeck composes durable server profiles, durable host trust, a platform secure credential adapter and the M1 SSH service at startup. Servers supports create, view, edit, delete, Connect, Disconnect, Reconnect, unknown fingerprint approval and explicit removal of a trusted key. A successful connection displays server, user, authentication method, trusted host status and connection time. No terminal was added.

## Storage boundaries

Server metadata and known-host records are separate schema-versioned JSON files in the OS application-support directory, obtained through `path_provider`. `JsonFileStore` serializes mutations, flushes a temporary file and renames with a backup for interrupted replacement; invalid schema or corrupt data fails startup closed. `FileServerProfileRepository` and `FileKnownHostRepository` hide file details from UI. Records contain only metadata, credential references, and host algorithm/fingerprint/timestamps/revocation status. App sandbox/file protection, backup/restore behavior and tamper resistance need target-device review; these files are not encrypted by this app.

Passwords, private-key PEM/OpenSSH content and optional passphrases go only through `PlatformSecureCredentialStore`, which wraps `flutter_secure_storage`. For iOS, the adapter requests `unlocked_this_device` accessibility with synchronization off: access while unlocked, no migration to a new device by that Keychain class. This is an implementation choice, not yet a device-validated claim. Windows uses the plugin's Windows implementation; no Windows runner or OS storage roundtrip was executed here. The adapter encodes byte values as base64 for the plugin's string API; base64 is not encryption. The plugin supplies OS-backed storage. Private-key text exists briefly in Dart memory for authentication; Dart strings cannot be reliably zeroized. No secret files, clipboard copy, exception content or logging are added.

The UI generates opaque random profile and credential IDs. A failed profile save attempts to remove newly written credentials. Profile deletion removes credential and trust records before profile metadata; interrupted multi-store actions may require retry. Editing does not re-display saved secrets. The private-key entry field is visible while the user pastes it because a multiline obscured Flutter field is unavailable; the saved key is never displayed again. Users should enter it in a private setting.

## Trust and connection

Unknown host identity shows host, algorithm and SHA256 fingerprint and requires explicit approval. Matching records connect automatically. Changed or revoked keys block. The user may explicitly remove a stored key after a warning; the next connection must re-approve a fingerprint through another trusted channel. No ignore/accept-all path exists. `SshConnectionService` still sets explicit timeouts, typed failures and bounded cancellable reconnect. The app's `main` explicitly composes adapters; corrupt metadata/trust prevents app startup rather than silently discarding pins. Navigation retains the Servers state across tabs.

## Dependencies and decisions

`flutter_secure_storage` 11.2.0 (BSD-3-Clause) for credentials, `path_provider` 2.1.6 (BSD-3-Clause) for the application-support directory; `dartssh2` 4.1.0 (MIT) remains the SSH transport. See DEPENDENCIES.md and ADR-008/009. `shared_preferences` was rejected for host trust because its documented writes are not guaranteed durable after returning. No database package was added.

## Validation

`flutter pub get`: PASS. `dart format lib test tool`: PASS. `flutter analyze`: PASS. `flutter test`: PASS (20 tests, 0 failed). Tests cover save/read/update/delete/restart, secure-adapter contract with a fake backend, host trust persistence/mismatch/revocation/removal, app wiring and Servers widget CRUD/approval. No unit test claims OS cryptography. Secret search found only dummy test values and no production secret, accept-all setting or secret print.

The manual `tool/ssh_lab.dart` harness and `docs/06-research/SSH_LAB.md` are prepared. No isolated SSH lab was available or started, and no production infrastructure was accessed. Live TCP/handshake/authentication remain untested.

## Platform status

Secure storage adapter: IMPLEMENTED_BUT_NOT_IOS_VALIDATED. Host verification: CORE_TESTED, DEVICE_PENDING. Keychain behavior, device lock, backup/restore, reinstall, SSH TCP, network changes and background/resume: PENDING_MACOS_VALIDATION. The iOS runner and iPhone build are still absent/unvalidated. M2 Terminal has not started.

