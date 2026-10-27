# M7 — Server Operations

## Objective
Implement structured, decoupled Linux server observability and safe, guarded operations over verified SSH. Provides real-time metrics for CPU, memory, swap, filesystem disk usage, load averages, uptime, privacy-preserving process inspection, and systemd service discovery and status monitoring without requiring root privileges or turning AgentDeck into an unrestricted administrative shell.

---

## Architectural Principles
1. **Observation First, Guarded Mutation**: Read-only monitoring by default. State-changing actions (`start`, `stop`, `restart`) are strictly gated, require explicit user confirmation, and display persistent `PRODUCTION` warnings on production hosts.
2. **Machine-Readable Sources**: Uses kernel `/proc` files (`/proc/stat`, `/proc/meminfo`, `/proc/loadavg`, `/proc/uptime`), `/etc/os-release`, POSIX portable `df -P -k`, fixed-format `ps`, and `systemctl show` property lists rather than parsing human-formatted command output.
3. **Process Command-Line Privacy**: Discovers processes using `comm` (process/executable name) rather than full command-line arguments to prevent accidental exposure or persistence of credentials, tokens, or passwords passed via CLI flags.
4. **Resilience & Capability Awareness**: Detects host capabilities (`hasProcfs`, `hasSystemd`, `isAlpine`) dynamically. Non-systemd systems (Alpine, OpenRC, containers) continue monitoring resource metrics gracefully without throwing fatal errors.
5. **Zero Sudo / Privileged Auto-Escalation**: AgentDeck never prompts for or stores `sudo` passwords. If a remote operation lacks permission, it fails gracefully with `ServerOperationFailureKind.permissionDenied`.

---

## Deliverables
- **Domain Layer** (`lib/core/domain/server_operations.dart`):
  - `ServerInfo`, `CpuUsage`, `MemoryUsage`, `DiskUsage`, `RemoteProcess`, `SystemService`, `ServerHealthSnapshot`, `ServerCapabilities`, `ServerOperationsService`, `ServerCommandExecutor`, `ServerOperationFailure`.
- **Parsing & Safety Layer** (`lib/features/servers/domain/server_parsers.dart`):
  - `ProcStatParser`, `ProcMeminfoParser`, `ProcLoadavgParser`, `OsReleaseParser`, `DfParser`, `PsParser`, `SystemctlParser`, `ServerOpsCommandSafety`.
- **Infrastructure & Application Layer** (`lib/features/servers/infrastructure/` & `application/`):
  - `SshServerCommandExecutor` adapting `SshConnectionService.runRemoteCommand`.
  - `RemoteServerOperationsService` orchestrating capability discovery, metrics snapshots, and service operations.
- **Presentation Layer** (`lib/features/servers/presentation/`):
  - `ServerOperationsPage` with tabs for Overview, Processes, and Services.
  - `ServerOverviewTab`, `ServerProcessesTab`, `ServerServicesTab`.
  - `ServersPage` action integration.
- **Integration Lab & Tooling** (`tool/server_ops_lab.dart` & `tool/server_ops_lab_docker.ps1`):
  - Scenarios A through N verifying host identity, uptime, load avg, CPU usage delta, memory/swap, disk, process listing/privacy/sorting, systemd detection, non-systemd graceful handling, permission failure mapping, and disconnect/reconnect states.
- **Quality Gates**:
  - `dart format`, `flutter analyze` (0 issues), `flutter test` (100% pass).

---

## Result
M7_DONE (core). Remote server observability, machine-readable procfs/stat/meminfo/loadavg/uptime/df/ps parsing, process privacy protections, systemd discovery & guarded service lifecycle actions, and non-systemd graceful degradation fully implemented and verified via Docker integration lab (Scenarios A through N). iOS device gestures and background polling remain PENDING_MACOS_VALIDATION.

## Follow-up
Next milestone: M8 — Notifications & Background Tasks.
