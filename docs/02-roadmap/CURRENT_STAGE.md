# Current stage

Milestone: **M1.6 — SSH Integration Lab**
Status: **M1_6_DONE**, 2026-09-19

A local disposable Docker/OpenSSH server validated the real AgentDeck SSH stack. Unknown-host approval, known fingerprint, mismatch blocking before auth, password success/failure, private-key success, closed-port handling, disconnect and same-process recovery passed. A Windows 1225 localized refusal mapping bug was fixed and covered by regression tests. The lab container, image, network and temporary credentials were removed. Pub get, format, analyze and 23/23 tests pass.

Encrypted private key/passphrase: NOT_TESTED. iOS Keychain, SSH/device behavior, network changes and background/resume: PENDING_MACOS_VALIDATION. M2 — Terminal is next but has not started.
