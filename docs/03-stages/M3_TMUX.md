# M3 — tmux

## Result

M3_DONE (core), 2026-09-20. AgentDeck can detect remote tmux capabilities, create isolated managed sessions, list active/detached/stale sessions, attach interactive PTY streams over SSH, survive network loss while background processes continue, reattach, detach cleanly without terminating processes, and terminate managed sessions. iOS runner/build/device remain PENDING_MACOS_VALIDATION.

## Implementation

The `TmuxService` application layer executes remote tmux commands via `SshTmuxTransportHandle.run` and attaches interactive sessions via `SshTmuxTransportHandle.attachTmux` (backed by `dartssh2` 4.1.0).

- **Format & Delimiter**: `tmux list-sessions` outputs formatted session data using colon `:` delimiters (`#{session_name}:#{session_attached}:#{session_created}`) to prevent control character sanitization (such as tab replacement to underscores in tmux 3.5a).
- **UTF-8 Support**: Commands and attach sessions invoke `tmux -u` with container `LANG=C.UTF-8` and `LC_ALL=C.UTF-8` to ensure multi-byte characters (Japanese Kanji, Spanish accents, emoji) are rendered without encoding loss.
- **PTY & Detach Lifecycle**: Closing the terminal session cleanly transmits the tmux detach escape sequence before channel close, allowing the remote tmux server to keep the session alive with detached state (`attachedClients = 0`).
- **Process Continuity**: When the SSH connection or mobile link drops unexpectedly, remote processes running inside tmux continue executing uninterrupted. Upon reconnecting, the session reference is retained and the user can reattach directly.
- **Session Reference Storage**: Managed session references (`ad_[a-f0-9]{16}`) are persisted locally via `FileTmuxSessionRepository` with atomic write and corruption detection.

## Real local lab

A disposable Alpine 3.21/OpenSSH + tmux container was executed on a dedicated Docker bridge with an unprivileged `lab` user, random credentials, dynamic port binding strictly to `127.0.0.1`, and host fingerprint validation. Unrelated containers and images were unaffected.

| Scenario | Description | Result |
|---|---|---|
| A | Detect remote tmux capability & version | PASS (`tmux 3.5a`) |
| B | Create & list managed session | PASS (session `ad_*` created and listed) |
| C | Attach PTY and echo roundtrip | PASS (`LAB_ECHO` verified) |
| D | Working directory initialization | PASS (`/home/lab` verified) |
| E | UTF-8 multi-byte & emoji stream | PASS (`ñ漢字🧪` preserved) |
| F | Dynamic PTY resize | PASS (80x24 -> 120x40 with status bar offset) |
| G | Interactive signal handling (Ctrl+C) | PASS (`sleep 30` interrupted cleanly) |
| H | SSH drop, process continuity & persistence | PASS (file written by background sleep during disconnect; persisted reference intact) |
| I | Reconnect & reattach | PASS (resumed session in new SSH connection) |
| J | Detach client & retain session | PASS (session state transitioned to `detached`) |
| K | Session termination & cleanup | PASS (session removed from remote & storage) |

All disposable container, network, image, and temporary secret resources were cleaned up upon test completion.

## Gates

- `dart format .`: PASS (0 format violations)
- `flutter analyze`: PASS (0 issues found)
- `flutter test`: PASS (32/32 tests passed)

## iOS pending

PENDING_MACOS_VALIDATION: iOS runner/build, physical iPhone validation, Keychain integration, touch selection, rotation, background network drops on iOS device.
