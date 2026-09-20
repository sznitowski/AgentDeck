# M1.6 — SSH Integration Lab

## Result

M1_6_DONE, 2026-09-19. A disposable Docker/OpenSSH server on this Windows host validated the real Dart SSH path: `tool/ssh_lab.dart` → `SshConnectionService` → `DartSshTransport` → TCP → SSH handshake → host verification → password/private-key authentication → connect/disconnect. No production host or credential was used. No terminal functionality was added.

## Lab boundary

Docker Desktop 29.1.3, Linux daemon. Disposable image: Alpine 3.21 with OpenSSH 9.9p2. One unprivileged `lab` account, disposable random password, LAB_ONLY Ed25519 key and freshly generated host keys. A dedicated Docker bridge and `127.0.0.1:60351` host binding exposed only the local loopback port; no project mount, real key, Docker socket or privileged mode. The image build downloaded Alpine/OpenSSH packages. The host fingerprint was obtained independently inside the container with `ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub`: algorithm `ssh-ed25519`, public fingerprint `SHA256:ZgJZHm92Gn+dRFifM1hdPyNUjAaDJP+fYoj7CGbX+Zs`. The port and fingerprint were specific to this discarded run.

The first attempted `--internal` Docker network did not publish a host port on this setup. That container/network were removed, then the lab was recreated on a dedicated bridge with the host binding still limited to `127.0.0.1`.

## Scenario matrix

| Scenario | Expected | Actual | Result |
|---|---|---|---|
| Unknown host | Show host/algorithm/fingerprint; approve only after independent comparison | Harness showed `ssh-ed25519` and the exact fingerprint obtained through Docker; manual `yes`; `CONNECTED`, `DISCONNECTED` | PASS |
| Known fingerprint | Connect without prompt | Pinned expected fingerprint; `CONNECTED`, `DISCONNECTED` without prompt | PASS |
| Mismatch | Block before authentication | `hostMismatch`; sshd logged closure `[preauth]`, no accepted authentication for that attempt | PASS |
| Bad password | Authentication category, no secret output | `authentication`; no password/key/passphrase value in harness output | PASS |
| Closed localhost port | Bounded connection failure | After adapter fix, `refused` for Windows error 1225; no retry loop | PASS |
| LAB_ONLY private key | Authenticate with key | `CONNECTED`, `DISCONNECTED`; sshd logged accepted Ed25519 public key | PASS |
| Failure then connection in same process | Cleanup and recover without restarting service | `FIRST_ATTEMPT: authentication failure`, then `CONNECTED`, `DISCONNECTED` using the same `SshConnectionService` | PASS |
| Encrypted private key/passphrase | Optional | Not run | NOT_TESTED |

## Issue and correction

A closed local port initially surfaced as generic `network` because Windows returned OS error 1225 with a localized refusal message. The adapter previously matched English text. `classifySocketException` now maps Windows 1225/10061 to `refused`, 10060 to `timeout`, and POSIX 111/110 accordingly, with DNS handling retained. Three regression tests cover these codes. The lab closed-port scenario was rerun and returned `refused`. No dartssh2 fork or dependency override was introduced.

## Cleanup and security

The harness was reviewed: it accepts only loopback targets, prints only public host identity/state/failure category, never prints password/key/passphrase, does not persist secrets, and its `yes` applies only to the currently shown unknown identity. Disposable password and key stayed outside Git in a temporary directory; environment variables were removed after each invocation. Environment variables can be visible to local processes, so this approach remains suitable only for disposable lab credentials. An interactive secret prompt could be considered in a later harness revision.

After testing, only the sshd listener remained; 0 established lab TCP connections and 0 harness Dart processes were observed. The exact lab container, network and image were removed, the verified temporary directory was recursively deleted, and absence of those resources was checked. No lab secret was found in the repository scan.

## Gates and platform status

`flutter pub get`, `dart format lib test tool`, `flutter analyze` and `flutter test`: PASS; 23 tests, 0 failed. Host verification and SSH handshake/password/key transport were validated on this Windows-to-local-Docker setup. Keychain, SSH on iOS, network changes, background/resume and physical iPhone remain PENDING_MACOS_VALIDATION. M2 Terminal has not started.
