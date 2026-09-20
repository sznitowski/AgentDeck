# Current context

AgentDeck is an independent iPhone-first Flutter client for remote Linux projects and agents. Repository: C:\Users\vszni\repositorios\AgentDeck. SDK: C:\Users\vszni\sdk\flutter (Flutter 3.47.5 / Dart 3.13.4). M0_DONE, M1 SSH core DONE, M1.5 secure persistence core DONE and M1_6_DONE on 2026-09-19. M2 terminal work has not started.

M1.6 validated the real SSH service and official dartssh2 transport against a disposable local Docker/OpenSSH server: unknown and known host, mismatch before auth, password success/failure, private-key success, closed port and same-process recovery all passed. A localized Windows socket error 1225 was mapped to `refused`; regression tests were added. The lab container/image/network and temporary credentials were removed. Pub get, format, analyze and 23/23 tests pass. Encrypted private key/passphrase was NOT_TESTED.

Secure-storage adapter is IMPLEMENTED_BUT_NOT_IOS_VALIDATED. iOS runner/build/iPhone, Keychain, network changes and background/resume remain PENDING_MACOS_VALIDATION. Read AGENTS.md, CURRENT_STAGE.md, M1_6_SSH_INTEGRATION_LAB.md and ARCHITECTURE.md before further work. Do not claim iOS validation or start M2 in this task.
