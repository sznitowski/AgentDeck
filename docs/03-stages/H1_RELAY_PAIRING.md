# Stage H1.1 — Push Relay hardening: pairing, installation tokens, fail-closed config

Date: 2026-11-21. Origin: the integral audit of the same date (P0-1, P0-2, P1-3, P3-3, P3-4).

## Corrections to the audit report

1. The "15–20 % of the vision" figure was a rough estimate, not a metric.
2. Historical milestones are **not** reclassified because of today's UI limitations. Two things are kept apart: what each milestone delivered when it closed, and the integration gaps that exist today.
3. `UIBackgroundModes` is **not** added. It first needs a product decision: will AgentDeck use silent/background notifications? (ADR-018 rejected silent pushes for state updates.) Until that is decided, nothing is added to `Info.plist`.
4. The Companion/tmux problem is confirmed by a two-user lab, **before** touching the systemd unit (see "Companion/tmux lab" below). The unit is unchanged in this stage.
5. Git is **not** read-only. `git_service.dart` implements guarded `add`, `reset` (unstage) and `commit`, with production confirmation in the UI. There is no push, pull, fetch or checkout.
6. TLS is terminated in **Caddy**. The Python relay speaks plain HTTP on loopback and does not need TLS support.

## Scope

In: fail-closed production config, `hmac.compare_digest`, request body limit, sanitized internal errors, real health, loopback bind, Caddy as TLS terminator, rejection of remote HTTP in both clients, one-time pairing codes, per-installation tokens, Keychain storage, hashed tokens in the relay, revocation, unit + integration tests.

Out: native APNs, TestFlight, deployment to a real VPS, Apple account changes, multi-agent orchestration, new product features. QR scanning is also out (it needs a new dependency); the code is typed in.

## Protocol

| Endpoint | Auth | Notes |
|---|---|---|
| `POST /v1/pairing/exchange` | pairing code | body `{installationId, pairingCode}` → `{installationToken}`. Failures are a uniform `401 invalid_pairing_code`; `429` after 10 failures/min (global window, because Caddy makes every peer 127.0.0.1) |
| `POST /v1/devices/register` | `Authorization: Bearer` | `installationId` must equal the token's installation (`403 installation_mismatch`). Registering again with a new APNs token is the update path |
| `DELETE /v1/devices/by-token` | Bearer | only deletes tokens owned by the caller's installation (`404` otherwise) |
| `POST /v1/companion-events` | `X-Companion-Id` + `X-Companion-Secret` | fail-closed in production |
| `GET /v1/health` | none | `status`, `version`, real `apnsConfigured` only (no counters) |
| `GET /v1/status` | companion credentials | previously public |

Admin operations have **no HTTP surface**; they run on the relay host against SQLite:

```
agentdeck-push-relay pairing create [--ttl-minutes 10] -c /etc/agentdeck/push-relay.json
agentdeck-push-relay installations list -c ...
agentdeck-push-relay installations revoke <installationId> -c ...
```

### Credentials

- Pairing code: 80 bits from `secrets`, base32 `ABCD-EFGH-IJKL-MNOP`, TTL 10 min (max 15), single use, atomic consume (`UPDATE ... WHERE used_at IS NULL AND expires_at > now`). Shown once on stdout; only its SHA-256 is stored.
- Installation token: `adt_` + 256 bits (`secrets.token_urlsafe(32)`). The relay stores only SHA-256 and compares with `hmac.compare_digest`. Re-pairing an installation revokes its previous token.
- App side: token stored in the iOS Keychain through `SecureCredentialStore` under `push_relay_installation_token@<relay authority>`; it is never written to JSON/preferences or logged, and it is only ever sent to the relay it was issued by. Redirects are not followed. A `401` wipes the local token.

### Other hardening

- Production is the default mode. No `companionSecrets` ⇒ the relay refuses to start. `security.mode: "development"` is explicit, loopback-only, and still requires installation tokens.
- Non-loopback bind is refused; config readable by group/others is refused on POSIX; companion secrets must be ≥ 16 chars.
- Request body ≤ 64 KiB, `Content-Length` required, chunked refused, 10 s socket timeout, HTTP/1.0 (one request per connection).
- Unhandled errors return `{"error":"internal_error"}`; details only in the server log. Logs never include headers.
- Clients (Dart `RelayUrlPolicy`, Python `is_secure_relay_url`) accept `https://` or loopback `http://` only.

## Threats considered

Brute force of codes (80 bits + rate limit); replay of a used code; expired code; concurrent exchange race (one winner, covered by a thread test); stolen relay database (hashes only); a token of one installation used for another; oversized/invalid bodies; internal detail leakage; relay or Companion over remote plain HTTP; Companion without a secret; timing side channels on secrets. Accepted: an attacker able to burn the global rate limit can delay pairing for a minute.

## Migration

The store gains `pairing_codes`, `installations` and `schema_meta` (version 2) on startup. Devices registered by the old unauthenticated protocol have no installation and are disabled once (logged). Impact today is nil: native APNs never existed, so no real device was registered. Existing relays must add `security.companionSecrets` (the old default of "no secrets" no longer starts).

## Companion/tmux lab (finding confirmed)

`tool/companion_tmux_users_lab.sh` (WSL Ubuntu, tmux 3.4, disposable users, cleaned up) result:

| Case | Result |
|---|---|
| dev user, own session (control) | session visible |
| other user, default socket | `error connecting to /tmp/tmux-<uid>/default (No such file or directory)` |
| other user, pointing at dev's socket | `Permission denied` |
| same user + private `/tmp` (as `PrivateTmp=true`) | `No such file or directory` |
| same user, shared `/tmp` | session visible |

So `User=agentdeck` **and** `PrivateTmp=true` in `server/agentdeck-companion.service` each prevent the Companion from seeing the SSH user's tmux sessions. The existing Docker labs run the Companion as the same user and hide this. **The unit is not changed in this stage**; the fix (run as the dev user, drop `PrivateTmp`) belongs to the VPS stage and needs a systemd-level test.

## Open decisions

- Silent notifications / `UIBackgroundModes` (see correction 3).
- QR pairing (needs a camera/scanner dependency).
- Whether to move the Companion service user (see lab).

## Validation

See `CURRENT_STAGE.md` for the executed results of this stage.

## H1.1b — App integration and technical closure (2026-11-21)

H1.1 was not functional from the app: Settings was still an M0 placeholder, the relay URL defaulted to `http://127.0.0.1:8443` (the phone itself), and the bootstrap composed a *fake* push service that would have registered a mock APNs token with a real relay. H1.1b fixes that and closes the review findings.

### Review findings (all fixed)

| # | Finding | Fix |
|---|---|---|
| 1 | `exchange_pairing_code` and the v1->v2 migration had no explicit rollback; a failure mid-way could leave a consumed code without a token, or a half-applied migration, in the open transaction | explicit rollback in both; the connection is closed if opening fails; a mutation test proves the exchange test fails without the rollback |
| 2 | Keychain reference used `authority` but `RelayUrlPolicy` accepted paths, so two relays with different paths shared one token | origin-only policy, reference = `push_relay_installation_token@<origin>` |
| 3 | `platform`/`bundleId`/`appVersion`/`enabled` were not type-checked and could produce a 500 | validated, `400 invalid_*` |
| 4 | `getIdentity()` accepted an empty or malformed id | valid ids (current or legacy) are kept, anything else is replaced |
| 5 | The bootstrap default was `FakePushNotificationService`; exposing Settings would register a mock token with a real relay | production default is `UnavailablePushNotificationService` (never authorizes, never returns a token) |
| 6 | `InstallationIdentity.generate` hashed the timestamp (not random, comment claimed otherwise) | 128 bits from `Random.secure()`, injectable `Random` for tests |
| 7 | Default relay URL pointed at loopback | URL is empty until the user configures it; nothing is contacted while empty |
| 8 | `crypto` was used without being declared | `tool/sftp_lab.dart` still uses it, so it is now a direct dev dependency (`crypto: 3.0.7`); `lib/` no longer imports it |

Reviewed and accepted (documented, not changed): anyone holding a valid pairing code can pair *any* installation id, including an existing one (this revokes that installation's old token). The code is the administrator's authorization, it is single-use and short-lived, so this is a deliberate property of re-pairing. The relay rate limiter is global because every request arrives from Caddy at 127.0.0.1.

Protocol regressions versus the old (unauthenticated) protocol are intentional: device endpoints without a bearer are `401`; deleting a token that is not yours is `404` instead of always `200`; `/v1/status` needs companion credentials.

### Final fix: strict loopback check

`RelayUrlPolicy` first used `^127(\.\d{1,3}){3}$`, which classified invalid hosts such as `127.999.999.999` as loopback and so allowed plain HTTP to them. Loopback is now strict: `localhost`, `::1`, or 127.0.0.0/8 with exactly four decimal octets, each 0-255 and without leading zeros (ambiguous octal notation, e.g. `127.00.0.1`, is rejected too). Tests cover the accepted (`127.0.0.1`, `127.1.2.3`, `localhost`, `[::1]`) and rejected (`127.999.999.999`, `127.0.0.256`, `127.0.0`, `127.0.0.1.2`, `128.0.0.1`, `localhost.example.com`, leading-zero and non-numeric octets) cases. The Python side already used `ipaddress` and was unaffected.

**H1.1b is closed.** H1.2 has not been started.

### Decisions

- **One relay per origin.** Only origin URLs are accepted: `https://relay.example.com`, `https://relay.example.com:8443`, and `http://127.0.0.1:8443` for labs. A trailing `/` and explicit default ports are normalized away, so equivalent spellings share one Keychain reference. Rejected: userinfo, query, fragment, any path other than empty or `/`, other schemes, empty host, invalid ports, and plain HTTP to non-loopback hosts. The relay URL is stored in `agentdeck_push_relay_config.json` (versioned, atomic, non-secret); tokens stay only in the Keychain.
- Changing the URL never deletes or sends another relay's token; switching back finds the earlier pairing intact.
- Only a `401` deletes the token of the *current* relay. Network failures, `403`, `429` and other rejections keep it.
- Settings now hosts the real flow: Settings tab -> Push Notifications -> relay URL, pairing, permission, privacy. Services come from `AgentDeckServices` (injected, never created in widgets).

### Tests added

Dart: URL policy (accepted/normalized/rejected/insecure), token isolation across hosts, ports, remote HTTP and invalid URLs, which statuses delete a token, relay config repository (persistence, corruption, tampering, no secrets in the file), identity (format, uniqueness, determinism with an injected `Random`, legacy kept, malformed replaced, corrupt file untouched), settings page (empty URL contacts nothing, validation messages, switching relays), navigation with real bootstrap services (Settings in the nav, opens Push settings, receives the bootstrap instances, pairing dialog opens, back keeps tab state).
Python: v1 database fixture with the exact pre-H1.1 schema (migration, idempotent second open, re-activation after pairing + authenticated registration, failed migration rolls back and is recoverable, corrupt database never replaced), atomic exchange, field validation, re-pair and revocation over HTTP.

### Still pending after H1.1b

Native APNs and entitlements; QR pairing; the Companion systemd user / `PrivateTmp` fix (unit untouched); VPS provisioning; real Caddy validation; silent-notification decision; Codemagic run, signing, TestFlight, iPhone. The Settings flow is verified by widget tests with fakes and a loopback relay, not on a device.
