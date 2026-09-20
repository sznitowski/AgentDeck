# M4 — SFTP / Remote Files

## Result

M4_DONE (core), 2026-09-20. AgentDeck can navigate remote file systems, inspect file metadata, stream upload and download files with SHA-256 integrity verification, perform atomic writes and edits, create directories, rename files/directories via pure SFTP, and safely delete files or non-empty directory structures with production protections and permission error handling. iOS runner/build/device, document picker, share sheet, and native sandbox remain PENDING_MACOS_VALIDATION.

## Implementation

The remote files subsystem is structured in strictly decoupled layers:

```text
Presentation (RemoteFilesPage, FileViewerPage)
     ↓
RemoteFilesController (State machine, navigation history, dotfiles toggle)
     ↓
RemoteFileService (Sensitive files detection, binary heuristics, preview limits)
     ↓
RemoteFileSystem (Domain contract: list, stat, read, write, mkdir, rename, delete)
     ↓
DartSshSftpAdapter (Infrastructure adapter over dartssh2 4.1.0 SftpClient)
```

- **Domain Isolation**: Widgets and presentation controllers interact exclusively with `RemoteFileService` and domain models (`RemoteEntry`, `RemoteFilePermissions`, `RemoteFileFailure`). No `dartssh2` types (`SftpClient`, `SftpFile`, `SftpName`) leak into presentation.
- **POSIX Path Manipulation**: Centralized in `PosixPath` (`lib/core/domain/posix_path.dart`) for standard normalization, joining, parent extraction, basename/extension parsing, and path traversal / separator validation.
- **Pure SFTP Operations**: All file operations (list, stat, read, write, mkdir, rename, delete, rmdir) utilize native SFTP protocol commands. No shell commands (`cat`, `rm`, `mv`, `mkdir`, `scp`) are executed, completely eliminating command injection vectors.
- **Atomic Save**: File writing and editing default to atomic mode: writes stream to a temporary sibling file (`.agentdeck_tmp_<nonce>_<name>`), flushes/closes the handle, and atomically renames the temporary file over the target. Failures clean up the temporary file and prevent partial corruption.
- **Streaming Transfer**: Large file uploads and downloads utilize non-blocking chunked byte streams (`writeStream` and `readStream`) with progress reporting and cancellation, avoiding full-file in-memory buffering.
- **Sensitive File Protection**: Sensitive files (`.env`, `*.pem`, `*.key`, `id_rsa`, `id_ed25519`, `credentials*`) are flagged with a security banner in the viewer, never logged or cached, and excluded from telemetry.
- **Production Guardrails**: Servers with `environment == ServerEnvironment.production` display a persistent `PRODUCTION` badge and require explicit confirmation showing the exact target path for destructive actions (`delete`, `overwrite`).
- **Permission & Status Mapping**: SFTP status error codes are cleanly mapped to `RemoteFileFailure` kinds (`permissionDenied`, `notFound`, `alreadyExists`, `directoryNotEmpty`, `fileTooLarge`, `binaryContent`, `connectionLost`, etc.).

## Real Local Lab

A disposable Alpine 3.21/OpenSSH container with internal-sftp subsystem was executed on a dedicated Docker bridge with an unprivileged `lab` user, random credentials, dynamic port binding strictly to `127.0.0.1`, and host key fingerprint validation.

| Scenario | Description | Result |
|---|---|---|
| A | Connect & open SFTP subsystem over verified SSH | PASS |
| B | List directory (`/home/lab`) | PASS |
| C | Create directory (`mkdir /tmp/agentdeck-sftp-test`) | PASS |
| D | Upload UTF-8 text file | PASS |
| E | Stat metadata verification (size, modified time, type) | PASS |
| F | Download & SHA-256 integrity match | PASS |
| G | Non-ASCII / UTF-8 filename handling (`archivo-ñ-漢字.txt`) | PASS |
| H | Rename file via SFTP (`rename`) | PASS |
| I | Permissions error handling (`permissionDenied`) | PASS |
| J | Delete file | PASS |
| K | Non-empty directory delete protection | PASS |
| L | Cleanup test directory | PASS |
| M | Large streaming transfer (25 MB) with SHA-256 match | PASS (`6c944d53befc807099...`) |
| N | 1000-entry directory listing performance & stability | PASS (1000 items in 363ms) |

All disposable container, network, image, and temporary secret resources were cleaned up upon test completion.

## Gates

- `dart format lib test tool`: PASS (0 format violations)
- `flutter analyze`: PASS (0 issues found)
- `flutter test`: PASS (58/58 tests passed)
- `powershell tool/sftp_lab_docker.ps1`: PASS (Scenarios A through N)

## iOS Pending

PENDING_MACOS_VALIDATION: iOS runner/build, physical iPhone validation, iOS Document Picker (`UIDocumentPickerViewController`), Share Sheet (`UIActivityViewController`), app sandbox directories, background transfer interruption, device lock behavior, and resume handling.
