# M1 — SSH

## Goal and result

M1_DONE (core), 2026-09-19. AgentDeck now has a replaceable SSH transport, strict host verification, credential references, typed failures, bounded lifecycle and a minimal Servers screen. The app does not enable a real Connect action until secure credential and durable known-host adapters are supplied on the target platform. iOS runner, build and physical device remain PENDING_MACOS_VALIDATION.

## Implementation

`ServerProfile` holds endpoint, environment, authentication method and credential IDs only. `SshConnectionService` obtains password or private-key PEM and optional passphrase through `SecureCredentialStore`, validates configuration, emits disconnected/connecting/connected/reconnecting/failed, and separates mobile connection state from agent execution state. `SshTransport` keeps `dartssh2` confined to infrastructure. The `DartSshTransport` adapter sets TCP (10 s), handshake (15 s) and authentication (15 s) timeouts and maps library/socket exceptions to `SshFailureKind`.

`HostTrustService` compares algorithm and OpenSSH SHA256 fingerprint by hostname and port. Unknown keys require an approval callback and are then recorded. Matching keys pass. Changed and revoked keys block, including during reconnect. Repository replacement is a separate explicit operation; the connection flow cannot replace a key. Known-host and credential fakes are TEST_ONLY. No persistent plaintext secret or trust store has been introduced.

`ReconnectPolicy` defaults disabled. When enabled it allows 1–5 attempts (default 2) with a 2 s delay and can be cancelled by disconnect. Authentication, host trust, missing credential and invalid profile failures stop retries. Socket loss changes connection state; it does not change agent execution state. iOS background/resume integration is pending.

Servers supports an in-memory server list, Add server, detail, PRODUCTION text, state, Connect/Disconnect controls, unknown-key approval and changed-key warning. With no secure runtime stores wired, Connect is disabled and the limitation is visible. Profiles added here are not persisted. This prevents an apparent working connection that would silently forget trust or use plaintext credentials.

## Research and security

Official `dartssh2` 4.1.0 (MIT) is pinned without a fork or dependency override; see `docs/06-research/SSH_RESEARCH.md` and ADR-007. Host verification callback is always supplied. No debug/trace credential logging is configured. Security search found no production secret literal, accept-all host option, or secret print. Test fixtures contain dummy strings only. UI never exposes a changed-key bypass. `KnownHostRepository` and `SecureCredentialStore` need secure, durable target-platform adapters before live use.

## Gates

- `flutter pub get`: PASS
- `dart format lib test`: PASS
- `flutter analyze`: PASS
- `flutter test`: PASS (12 tests, 0 failures)
- iOS runner, compile, iPhone: PENDING_MACOS_VALIDATION
- Live SSH interoperability: not run; no real server was accessed

## iOS follow-up

On macOS/Xcode and a physical iPhone, validate TCP, DNS, handshake, host fingerprints, password and OpenSSH private-key authentication, Keychain accessibility/backup policy, durable host trust, Wi-Fi to cellular changes, background/resume, socket loss and bounded reconnect. Add secure runtime adapters and wire the Servers screen before enabling Connect. Face ID only if introduced later. M2 terminal work has not started.
