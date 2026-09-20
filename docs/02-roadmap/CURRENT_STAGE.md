# Current stage

Milestone: **M4 — SFTP**
Status: **M4_DONE (core)**, 2026-09-20

Remote file navigation, metadata inspection, streaming download/upload, atomic save, mkdir, rename, and safe delete implemented via pure SFTP over verified SSH connections using `dartssh2` 4.1.0 without shell commands. Full integration lab Scenarios A–N passed cleanly on disposable Docker OpenSSH + SFTP container. All unit, widget, and quality gates pass. iOS runner/build/iPhone, Keychain, document picker, and file sharing behavior remain: PENDING_MACOS_VALIDATION.

Next milestone: **M5 — Agents** (DO NOT START YET).
