# Handoff

## Completed

M4_DONE (core). Servers offers "Browse Files" on any server with a verified SSH connection. The files subsystem implements pure SFTP (via `dartssh2` 4.1.0) without invoking remote shell processes (`cat`, `rm`, `mv`, `mkdir`, `scp`) or sudo escalation. Features include:
- `PosixPath` centralized manipulation and traversal sanitization.
- `RemoteFileSystem` / `RemoteFileService` layered contracts.
- Directory listing with directory-first ordering and dotfile toggle.
- Metadata inspection (type, size, modifiedAt, permissions).
- Monospace text viewer and basic editor (<=5MB threshold) with sensitive file security warnings.
- Atomic file writes via sibling temporary files (`.agentdeck_tmp_<nonce>_<name>`) and SFTP rename.
- Streaming upload and download (`writeStream`, `readStream`) with progress reporting.
- Directory creation (`mkdir`), renaming (`rename`), and safe deletion (`delete`/`rmdir`) rejecting non-empty directories without explicit cascade.
- Persistent `PRODUCTION` badge and explicit path confirmation dialogues for destructive operations.

## Validation

- `flutter pub get`: PASS
- `dart format lib test tool`: PASS (0 format violations)
- `flutter analyze`: PASS (0 issues found)
- `flutter test`: PASS (58/58 unit & widget tests passed)
- Disposable local Docker/OpenSSH + SFTP lab: PASS (Scenarios A through N: connect, list, mkdir, upload, stat, download SHA-256 integrity, UTF-8 filename `archivo-ñ-漢字.txt`, rename, permissions error mapping, delete, non-empty directory rejection, cleanup, 25MB streaming transfer, 1000-entry directory listing in 363ms).
- All disposable container, network, image, and temporary secret resources were cleaned up.

## Pending

iOS Document Picker (`UIDocumentPickerViewController`), Share Sheet (`UIActivityViewController`), native app sandbox directories, physical iPhone runner/build, Keychain, touch selection, rotation, background network drops and transfer resumption: PENDING_MACOS_VALIDATION.

Next milestone: **M5 — Agents** (DO NOT START YET).

The reproducible local lab entry point is `tool/sftp_lab_docker.ps1`; the Dart assertions are in `tool/sftp_lab.dart`.
