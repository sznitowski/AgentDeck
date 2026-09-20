# Session log

| Date | Milestone | Task | Result | Decision | Tests | Next action |
|---|---|---|---|---|---|---|
| 2026-09-19 | M0 | Bootstrap harness and shell | Source and documentation authored | Independent iOS-first app, no KAMMEL code | Not then available | Audit M0 |
| 2026-09-19 | M0 | Repository audit | Physical files, documents, models, and navigation verified statically | Keep M0 blocked until Flutter gates | Toolchain absent; iOS pending | Prepare SDK |
| 2026-09-19 | M0 | Local Flutter toolchain and core gates | Flutter 3.47.5/Dart 3.13.4 outside repo; M0_DONE | Leave iOS runner for macOS; no M1 in this session | pub get PASS; format PASS; analyze PASS; test 3/3 PASS | M1 SSH in a separate task; iOS validation pending |
| 2026-09-19 | M1 | SSH foundation | M1_DONE core; default Connect disabled until secure persistent stores | Official dartssh2 4.1.0, strict host trust, no fork | pub get/format/analyze PASS; test 12/12 PASS; no live server | macOS/iPhone adapters and validation, then M2 |
| 2026-09-19 | M1.5 | Secure persistence, Servers wiring and lab harness | M1_5_DONE core; live lab/iOS pending | Secure credentials via flutter_secure_storage; versioned app-support files for metadata/trust | pub get/format/analyze PASS; test 20/20 PASS; no live server | Isolated lab and macOS/iPhone validation, then M2 |

| 2026-09-19 | M1.6 | Local Docker/OpenSSH integration | M1_6_DONE; lab passed and cleaned | Windows 1225 refusal mapped by OS code; harness loopback only | pub get/format/analyze PASS; test 23/23; real SSH matrix PASS | iOS/macOS device validation, then M2 |
