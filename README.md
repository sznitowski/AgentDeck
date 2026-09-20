# AgentDeck

AgentDeck is an iPhone-first control center for Linux servers, projects and remote coding agents. Agents run on the server; the mobile app connects, observes and reconnects. The product is independent of KAMMEL SSH.

**Current milestone:** M1.6 SSH Integration Lab complete. A disposable Docker/OpenSSH server bound to localhost validated AgentDeck's real SSH handshake, host identity approval/pinning, password and LAB_ONLY private-key authentication, error handling, disconnect and same-process recovery. The lab and temporary credentials were removed. Servers retains the M1.5 persistent profile/trust/credential workflow. No terminal, SFTP, live agents or server operations have started.

Flutter 3.47.5 / Dart 3.13.4 is installed at C:\Users\vszni\sdk\flutter, outside this repository. Runtime packages include dartssh2 4.1.0, flutter_secure_storage 11.2.0 and path_provider 2.1.6. Run the SDK tools by absolute path. See docs/02-roadmap/CURRENT_STAGE.md and docs/03-stages/M1_6_SSH_INTEGRATION_LAB.md.

The iOS runner is absent. On macOS with Flutter/Xcode, create and review it, configure Keychain capability/entitlements as needed, and validate simulator and physical iPhone. iOS build, Keychain security and device behavior remain PENDING_MACOS_VALIDATION.
