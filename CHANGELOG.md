# Changelog

## Unreleased

- Completed M0 Flutter/Dart bootstrap and M1 SSH core using official dartssh2 4.1.0.
- Added M1.5 versioned server-profile and known-host persistence, platform secure credentials, explicit app wiring and Servers CRUD/connection UI.
- M1.6 validated the real SSH stack against a disposable local Docker/OpenSSH lab: host trust, password and LAB_ONLY key authentication, failures, disconnect and same-process recovery. The lab was removed.
- Classified localized Windows socket error 1225 as connection refused, with regression tests; restricted the manual lab harness to loopback.
- Windows gates passed: pub get, format, analyze and 23 tests.
- iOS runner, Keychain behavior, build and device validation remain PENDING_MACOS_VALIDATION.
