# Dependency register

Flutter 3.47.5 / Dart 3.13.4 is installed outside the repository at C:\Users\vszni\sdk\flutter. M1 SSH uses exact `dartssh2` 4.1.0 (MIT) for pure-Dart SSH behind `SshTransport`; see SSH_RESEARCH.md and ADR-007.

| Package | Exact version | License | Purpose and platforms | Security relevance / reason |
|---|---:|---|---|---|
| flutter_secure_storage | 11.2.0 | BSD-3-Clause | Platform credential key/value adapter; pub.dev lists iOS, Android, Windows, macOS, Linux, web | iOS Keychain and Windows implementation; opaque secret references only. iOS device behavior unvalidated. Custom native bridge rejected for maintenance. |
| path_provider | 2.1.6 | BSD-3-Clause | Application-support directory; iOS 13+, Windows 10+, other native platforms | Keeps non-secret profile/trust files in app-specific storage. We implement versioned, flushed file writes rather than using preferences for critical trust. |
| dartssh2 | 4.1.0 | MIT | SSH transport and SFTP subsystem; pure Dart, iOS listed | Host verification callback always supplied; no fork or override. Pure SFTP operations for remote file management. Device handshake pending. |

`shared_preferences` 2.5.5 (BSD-3-Clause) was considered for non-secret records but not added. Its package documentation warns writes are not guaranteed persisted after return, so it is unsuitable for host trust. A database package was not added for this small, bounded dataset. Transitive package versions are recorded in pubspec.lock. Review platform implementation changes and security fixes before upgrades.

Primary package sources: https://pub.dev/packages/flutter_secure_storage , https://pub.dev/packages/flutter_secure_storage/license , https://pub.dev/packages/path_provider , https://pub.dev/packages/path_provider/license , https://pub.dev/packages/shared_preferences .

## M2 terminal addition

| Package | Exact version | License | Purpose and platforms | Security relevance / reason |
|---|---:|---|---|---|
| xterm | 4.0.0 | MIT | Flutter VT terminal emulator; pub.dev lists iOS, Android and desktop/web | Confined to presentation. Scrollback limited to 2000 lines; no input/output logging. Last release is old; iOS keyboard/touch behavior pending device validation. No fork or dependency override. |

See TERMINAL_RESEARCH.md and ADR-010. New transitive dependencies are captured in pubspec.lock. Primary source: https://pub.dev/packages/xterm .

## M4 SFTP addition

No new third-party packages or dependency overrides were added for M4. Existing `dartssh2 4.1.0` provides complete native SFTP v3 client capabilities (`SftpClient`, `SftpFile`, `SftpName`, streaming `read`/`write`, `mkdir`, `rename`, `remove`, `rmdir`, `stat`, `lstat`, `readlink`, `realpath`). See SFTP_RESEARCH.md and ADR-011.