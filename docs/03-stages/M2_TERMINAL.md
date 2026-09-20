# M2 — Terminal

## Result

M2_DONE (core), 2026-09-19. AgentDeck can open a raw interactive SSH shell with PTY from a previously verified Servers connection. No tmux/session persistence or M3 feature was added. iOS runner/build/device remain PENDING_MACOS_VALIDATION.

## Implementation

The transport opens `SSHClient.shell(pty: SSHPtyConfig(type: 'xterm-256color', width: columns, height: rows))`; PTY denial/shell failure becomes a `protocol` category and no `exec` fallback occurs. `TerminalSession` streams bytes, accepts input, resize and close. The application `TerminalController` decodes UTF-8 across chunks, forwards input, debounces resize by 100 ms, and owns channel cleanup. It exposes opening/active/failed/lost/closed independently of SSH and agent execution state. `TerminalPage` owns xterm 4.0.0 (MIT), a 2000-line scrollback, selection/copy, explicit paste, hideable mobile key row, one-shot Ctrl, and a persistent PRODUCTION label for production servers. ANSI/VT parsing remains in xterm. Physical keys use xterm input; soft-key behavior awaits iPhone testing.

On connection loss the view retains its buffer and displays CONNECTION LOST. Reconnect verifies SSH again and opens a new shell. It does not resume the prior remote process. Leaving the page closes the PTY channel while the SSH connection remains available in Servers. Clipboard input/output and terminal content are never logged or stored by the app.

## Real local lab

Disposable Alpine 3.21/OpenSSH on a dedicated Docker bridge, unprivileged `lab` account, random LAB_ONLY password and key outside the repository, freshly generated host key, pinned independent SHA256 fingerprint, and a host port bound only to 127.0.0.1. No production host or credential, project mount, Docker socket mount or privileged container. All disposable container/network/image/temp resources were removed; unrelated Docker containers remained running.

| Scenario | Result |
|---|---|
| A PTY + interactive shell + TERM=xterm-256color | PASS (`tty` returned `/dev/pts/*`) |
| B echo roundtrip | PASS |
| C pwd | PASS (`/home/lab`) |
| D UTF-8 | PASS (ñ, Han characters, emoji) |
| E resize | PASS (`stty size`: 24 80 → 40 120) |
| F Ctrl+C | PASS (`sleep 30` interrupted; subsequent marker received) |
| Large output | PASS (`seq 1 2000`, end observed) |
| G cleanup | PASS (channel closed, SSH stayed connected until explicit disconnect; no lab shell process afterward) |

The first lab attempts exposed a CRLF password fixture issue, a `dartssh2` channel exception triggered by explicit `SSHSession.flush()`, and markers seen in PTY echo before command execution. The fixture now uses LF, input uses `SSHSession.write()` without explicit flush, and the harness disables echo before marker assertions. Channel close wait is bounded to 2 seconds because the library can leave `session.done` pending; disconnect still closes the SSH client. Final lab run passed all scenarios.

## Gates

`flutter pub get`, `dart format lib test tool`, `flutter analyze`, `flutter test`: PASS (26 tests, 0 failed). Controller unit tests cover UTF-8 chunk boundaries, input, resize, channel close and stream loss; widget test covers production label, toolbar action/toggle and loss banner. Security scan found no production input/output/secret logging or host-key bypass. Original xterm package maintenance is a known risk; see research and ADR-010.

## iOS pending

PENDING_MACOS_VALIDATION: virtual keyboard, hardware keyboard, safe area, rotation and PTY resize on rotation, touch selection, copy/paste, background/resume, network loss, Keychain, iOS SSH, runner/build and physical iPhone. M3 — tmux is next and has not started.

Reproduce the loopback lab with `pwsh -NoProfile -File tool/terminal_lab_docker.ps1` from this repository while Docker Desktop is running. The script creates uniquely named disposable resources and verifies cleanup; it does not stop unrelated containers.
