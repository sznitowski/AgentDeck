# M0 — Bootstrap

## Goal
Create a reproducible documentation harness, domain contracts, mock navigation shell, and test baseline.

## Why this milestone exists
Future agents need a stable project memory and a validated starting point before SSH work begins.

## Scope
Harness, architecture decisions, server/project/agent models, security baseline, five-destination shell, and core tests.

## Out of scope
Live SSH, Docker, agents, APNs, destructive actions, deploy, and native iOS runner generation from Windows.

## Requirements
Independent iOS-first product; no secrets in source; no KAMMEL code copied; separate connection and agent execution states.

## Architecture impact
Established app/, core/domain/, features/, and shared/ boundaries.

## Tasks
Documentation, models, shell, tests, SDK preparation, formatting, analysis, and verification completed.

## Tests
2026-09-19: flutter pub get PASS; dart format PASS; flutter analyze PASS with no issues; flutter test PASS with 3 tests and 0 failures.

## Security considerations
No network or secret storage in M0. Basic source scan found no credential material. Production enforcement remains future work.

## Risks
ios/ runner, iOS build, simulator, and physical iPhone behavior are PENDING_MACOS_VALIDATION.

## Exit criteria
Documentation and structure verified; five destinations covered by widget test; analyze and test pass; iOS pending status explicit. Met for M0 core validation.

## Result
M0_DONE. Flutter 3.47.5 / Dart 3.13.4 used from C:\Users\vszni\sdk\flutter outside the repository.

## Follow-up
M1 — SSH in a later task. Generate and validate the iOS runner on macOS/Xcode when available.
