# AgentDeck Server Companion Technology Evaluation

## Context & Purpose

Milestone **M8.5 (Server Companion / Remote Observer)** introduces a server-side background process (`agentdeck-companion`) that observes remote state (tmux sessions, coding agents, Git status, system metrics, project working directories) when the user's mobile device is disconnected or suspended.

This document analyzes the technology stack options for the companion to select the most deterministic, low-resource, secure, and maintainable implementation.

---

## 1. Evaluation Criteria

1. **Single Binary / Packaging**: Simplicity of distribution, single-file deployment, zero external dependencies.
2. **Linux Target Ubiquity**: Out-of-the-box availability across major Linux distributions (Ubuntu, Debian, Alpine, RHEL, CentOS, Arch, Fedora).
3. **Memory Footprint**: Low idle RSS memory consumption (< 30 MB) on constrained VPS instances.
4. **Startup Time & CLI Latency**: Sub-second execution for CLI queries (`status`, `events --after`, `health`).
5. **Cross-Compilation from Windows**: Ease of building/testing Linux artifacts from a Windows development workstation without requiring complex multi-stage cross-compilation toolchains.
6. **Systemd & POSIX File Locking**: Clean integration with systemd service lifecycle and POSIX file locking (`fcntl.flock`) for single-instance enforcement.
7. **JSON Handling & Schema Evolution**: Built-in support for versioned JSON and append-safe JSON Lines (`.jsonl`).
8. **Subprocess Execution**: Secure, non-shell argument array execution of `tmux` and `git` with timeout bounds.
9. **Kernel Metric Interfaces**: Direct parsing of `/proc/stat`, `/proc/meminfo`, and filesystem statistics.
10. **Security & Auditability**: Transparency of source code for system administrators; vulnerability attack surface.
11. **Maintenance & Codebase Ergonomics**: Long-term maintainability and automated testability.
12. **Testing in Disposable Docker Lab**: Ability to execute deterministic integration tests in ephemeral Docker containers.

---

## 2. Technology Comparison Matrix

| Criteria | Dart CLI | Go | Python 3 (Standard Library) |
|---|---|---|---|
| **Packaging & Distribution** | Requires Dart AOT binary (~12MB) or Dart SDK (~100MB) | Single static ELF binary (~8–12MB) | Single Python script or zero-build `.py` module |
| **Linux Ubiquity** | Requires custom binary/SDK install | Single binary works if glibc/musl matches | Pre-installed on ~99% of Linux distros (standard `python3`) |
| **Cross-Compilation (from Win)** | Complex (Dart AOT cross-compilation requires Linux Docker container) | Very easy (`GOOS=linux GOARCH=amd64 go build`) | **Zero compilation required** (identical script runs on all OS/archs) |
| **Idle Memory (RSS)** | ~25–35 MB | ~8–12 MB | ~12–18 MB |
| **Startup / CLI Latency** | ~20–40 ms | < 5 ms | ~15–30 ms |
| **POSIX Locking (`fcntl.flock`)** | Requires Dart FFI to `libc` | Standard library `syscall` | Standard library `fcntl.flock` |
| **JSON & JSON Lines** | `dart:convert` (in-memory) | `encoding/json` | `json` + file streaming |
| **Subprocess Execution** | `Process.run` | `os/exec` | `subprocess.run` with array args |
| **Kernel `/proc` Parsing** | Native file I/O | Native file I/O | Native file I/O |
| **External Dependencies** | Zero or pub packages | Zero (`CGO_ENABLED=0`) | **Strictly ZERO** (Standard library only; no `pip`) |
| **Security Auditability** | Compiled ELF (opaque) | Compiled ELF (opaque) | **Plaintext Python** (fully auditable by sysadmin) |
| **Development & Lab Speed** | Fast in Dart ecosystem | Fast, requires Go compiler | **Instant** across Alpine, Ubuntu, Debian, Docker |

---

## 3. Detailed Technology Analysis

### Option A: Dart CLI
- **Pros**: Direct sharing of model definitions (`events.dart`) and transition logic.
- **Cons**: Dart runtime is not present on typical Linux servers. Building native Linux AOT binaries from a Windows development environment requires running Linux Docker containers for compilation. AOT binaries must be compiled separately for `x86_64` and `aarch64` (ARM64). POSIX file locking requires FFI boilerplate.

### Option B: Go
- **Pros**: Compiles to a single, static binary with minimal memory (~10MB) and instant startup. Excellent concurrency.
- **Cons**: Requires installing the Go toolchain on development machines. Binary distribution requires separate builds for `x86_64`, `aarch64`, `armv7`, etc. Server admins cannot easily inspect the binary source code without decompilation.

### Option C: Python 3 (Standard Library) — Recommended
- **Pros**:
  - **Universal Linux Deployment**: Python 3 is installed by default on almost every modern Linux distribution (Ubuntu 20.04+, Debian 11+, RHEL/CentOS 8+, Arch, Fedora, Alpine `apk add python3`).
  - **Zero Build Matrix**: The exact same `.py` script or module runs natively on `x86_64`, `aarch64` (Raspberry Pi, AWS Graviton), `armv7`, and `riscv64` without compiling separate binaries.
  - **Zero External Dependencies**: Strictly uses the Python standard library (`json`, `subprocess`, `argparse`, `time`, `os`, `signal`, `pathlib`, `fcntl`, `re`). No `pip install` or virtual environment required.
  - **Native POSIX Capabilities**: Includes `fcntl.flock` for robust single-instance daemon locking and stale PID detection.
  - **Security & Transparency**: Sysadmins can inspect the exact code running as the daemon in `/usr/local/bin/agentdeck-companion`.
  - **Low Resource Usage**: Idle memory is ~15 MB RSS with negligible CPU usage (<0.1%).
- **Cons**: Requires Python 3 on the host (addressed by standard distribution packages).

---

## 4. Architectural Decision

**Decision**: Implement `agentdeck-companion` in **Python 3 Standard Library** (`#!/usr/bin/env python3`).

1. **Protocol Contract**: Formalize a versioned JSON schema (`schemaVersion: 1`) shared between Python companion output and the Dart/Flutter client.
2. **Single-File Executable**: Package as a self-contained executable Python script installed to `/usr/local/bin/agentdeck-companion` or run directly from user space.
3. **No Network Ports**: Access strictly through authenticated and host-verified SSH (`agentdeck-companion events --after <cursor>`).
4. **Append-Safe Journaling**: Store events in `/var/lib/agentdeck/events.jsonl` (or user config path) with a monotonic sequence integer.
