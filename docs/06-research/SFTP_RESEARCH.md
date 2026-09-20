# SFTP Research & Capabilities in `dartssh2` 4.1.0

## 1. Overview & Protocol Version

AgentDeck uses `dartssh2` 4.1.0 (MIT), which includes a pure-Dart implementation of the SSH File Transfer Protocol (SFTP) Version 3 (`SSH_FXP_INIT`, `_kVersion = 3`), alongside OpenSSH protocol extensions.

SFTP channels run over the established SSH transport via `client.sftp()`, which requests an `sftp` subsystem session channel (`SSH_MSG_CHANNEL_OPEN` with `subsystem` = `sftp`).

## 2. API Capabilities

`dartssh2`'s `SftpClient` and `SftpFile` provide:

- **Directory Listing (`listdir` / `readdir`)**:
  - `readdir(path)` streams chunks of `SftpName` items (`filename`, `longname`, `attrs`).
  - `listdir(path)` provides a consolidated list of entries.
  - Returns `SftpFileAttrs` with file type (regular, directory, symlink, pipe, socket, character/block device), byte size, modification/access timestamps, owner UID/GID, and UNIX permissions bitmask.
- **Attributes & Metadata (`stat` / `lstat` / `setStat`)**:
  - `stat(path, {bool followLink = true})`: retrieves metadata following symlinks (`SSH_FXP_STAT`) or target link info (`SSH_FXP_LSTAT`).
  - `setStat(path, attrs)`: modifies file permissions or timestamps.
- **File Read & Streaming (`open`, `read`, `readBytes`, `downloadTo`, `download`)**:
  - `SftpFile.read()` streams chunks (`Uint8List`) with configurable `chunkSize` (default 16 KB) and pipelined pending requests (default 64) to maximize throughput over high-latency links.
  - `SftpClient.download()` streams remote file content into a `StreamSink<List<int>>` with progress callbacks (`onProgress: (bytesRead)`).
- **File Write & Streaming (`open`, `write`, `writeBytes`, `uploadFrom`)**:
  - `SftpFile.write()` accepts a stream of bytes and pipelines `SSH_FXP_WRITE` packets.
  - `SftpFileOpenMode`: supports `read`, `write`, `create`, `truncate`, `append`, `exclusive`.
- **Directory & File Manipulation**:
  - `mkdir(path, [attrs])`: creates remote directory (`SSH_FXP_MKDIR`).
  - `remove(filename)`: removes regular file (`SSH_FXP_REMOVE`).
  - `rmdir(dirname)`: removes empty directory (`SSH_FXP_RMDIR`). Fails with `SSH_FX_FAILURE` if directory is non-empty.
  - `rename(oldPath, newPath)`: OpenSSH extension `posix-rename@openssh.com` (version 1) is automatically used if supported by the remote OpenSSH server, providing atomic replacement semantics. If unavailable, falls back to standard `SSH_FXP_RENAME`.
- **Symlinks (`readlink`, `link`)**:
  - `readlink(path)` reads target path.
  - `link(linkPath, targetPath)` creates symbolic links.
- **Filesystem Stats (`statvfs`)**:
  - Supports `statvfs@openssh.com` extension for remote free disk space and inode inspection.

## 3. Error Model

`dartssh2` surfaces `SftpStatusError` containing `statusCode` and server error message:
- `SftpStatusCode.noSuchFile` (2): file or directory does not exist (`notFound`).
- `SftpStatusCode.permissionDenied` (3): insufficient filesystem permissions (`permissionDenied`).
- `SftpStatusCode.failure` (4): generic failure, including removing non-empty directories (`directoryNotEmpty` / `failure`).
- `SftpStatusCode.badMessage` (5): malformed protocol packet.
- `SftpStatusCode.noConnection` (6) / `connectionLost` (7): connection dropped.
- `SftpStatusCode.opUnsupported` (8): unsupported operation.

## 4. Security & Architecture Considerations

1. **Pure SFTP — No Shell Execution**: All file operations are executed via binary SFTP packets, completely avoiding shell command execution (`rm`, `mv`, `mkdir`, `cat`) and eliminating command injection risks.
2. **Path Traversal Protection**: Paths are strictly validated and normalized as POSIX paths (`/`). Embedded null bytes, arbitrary delimiters, and `..` traversals are trapped before invoking SFTP calls.
3. **Atomic Save Strategy**: For editing and saving files, write to a temporary file (`<target>.agentdeck.tmp.<nonce>`) in the same directory, verify successful closure, and execute atomic rename. This prevents partial writes or file truncation on network disconnect.
4. **Streaming & Memory Bounds**: Large file downloads and uploads stream in chunks without loading entire files into memory. Text previews are capped (e.g. 5 MB limit) with binary content heuristics.
5. **Sensitive File Protection**: Dotfiles and credential files (`.env`, `*.pem`, `*.key`, `id_rsa`) are treated as sensitive: no automatic background previews, no content in telemetry or logs, and confirmation prompts on modifications.
6. **Channel Independence**: SFTP runs on its own dedicated SSH subsystem channel (`SSHChannel`) separate from interactive PTY/terminal and tmux channels. Closing the SFTP client does not affect active terminal sessions.

## 5. iOS Implications (PENDING_MACOS_VALIDATION)

- **Sandbox & Local Files**: On iOS, local file import/export must interface with the iOS Document Picker (`UIDocumentPickerViewController`), app sandbox directories (`Documents/`, `tmp/`), and the system Share Sheet.
- **Background Transfers**: Large transfers interrupted by iOS app suspension require lifecycle handling (`beginBackgroundTaskWithExpirationHandler` or user notification).
