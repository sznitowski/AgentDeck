# SSH library research — M1

Date: 2026-09-19. Chosen: official dartssh2 4.1.0, pinned in AgentDeck. Sources:
- https://pub.dev/packages/dartssh2
- https://pub.dev/packages/dartssh2/changelog
- https://pub.dev/packages/dartssh2/license
- https://pub.dev/documentation/dartssh2/latest/dartssh2/SSHClient-class.html
- https://github.com/Jhongdlp/Kammel_ssh/blob/main/pubspec.yaml

## Comparison

| Candidate | Maintenance / maturity | iOS and security fit | Decision |
|---|---|---|---|
| dartssh2 4.1.0 | Published September 2026, active upstream and interop tests; MIT | Pure Dart; iOS listed; password, OpenSSH RSA/ECDSA/Ed25519 private keys, async identity API, SFTP, shell/PTY; SHA256 host callback and explicit handshake/auth timeouts | Select behind our adapter; real iOS validation pending |
| ssh2 2.2.3 | Last published about four years earlier; MIT | Native NMSSH/JSch wrappers, iOS listed, older key-format guidance and larger native surface | Reject for M1 |
| ssh_core 0.1.0-dev.2 | Maintainer labels it experimental and not ready for general use | Promising explicit protocol abstractions but insufficient maturity | Revisit later |

dartssh2's onVerifyHostKey is optional and omission accepts any host. AgentDeck must always pass a rejecting callback. The library validates the host's signature; our repository verifies expected identity. No printDebug or printTrace callbacks are configured. Default algorithms prefer Ed25519, RSA SHA-2, ECDSA, modern KEX and ciphers; legacy SHA-1/CBC algorithms are no longer in default proposals. Web needs a separate transport, outside M1.

## KAMMEL fork relevance

KAMMEL pins dartssh2 2.17.1 plus a local patch to expose raw host keys because upstream then exposed MD5, and another patch for channel receive-window replenishment. Upstream 2.19.0 changed host verification to OpenSSH-style SHA256. Upstream 4.0.1 fixed a channel-window stall. M1 needs the host callback now; it does not need KAMMEL's raw-key patch. M1 does not use SFTP, channels, or tunnels, but M2/M4 should verify upstream interop separately. No KAMMEL code or vendored fork is used.

## Risks and validation

The package's iOS listing is not device evidence. Verify TCP, handshake, modern algorithms, password/key auth, Keychain integration, Wi-Fi/cellular changes, background/resume, and reconnect on macOS/iPhone. Inspect upstream security fixes during upgrades. A dependency update may change host-key semantics; pin and test the adapter. Open GitHub issues were not exhaustively audited; M1 depends on our tests and later live interop.
