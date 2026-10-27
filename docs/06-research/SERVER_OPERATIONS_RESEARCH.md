# Research: Linux Server Operations & Observability

## 1. Operating System Identification & Uptime

### 1.1 OS Identification (`/etc/os-release` & `uname`)
Linux systems conforming to modern standards expose distribution details in `/etc/os-release` (or `/usr/lib/os-release`).
Format is shell-compatible key-value pairs:
```ini
NAME="Ubuntu"
VERSION="22.04.3 LTS (Jammy Jellyfish)"
ID=ubuntu
ID_LIKE=debian
PRETTY_NAME="Ubuntu 22.04.3 LTS"
VERSION_ID="22.04"
```
Fallback/Kernel info:
`uname -s -r -m -n` outputs in standard order:
- `-s`: Kernel name (`Linux`)
- `-n`: Network node hostname
- `-r`: Kernel release (`5.15.0-89-generic`)
- `-m`: Machine architecture (`x86_64`, `aarch64`)

### 1.2 Uptime & Boot Time (`/proc/uptime`)
`/proc/uptime` contains two floating point numbers separated by a space:
```text
350735.65 2783945.12
```
- First field: System uptime in seconds.
- Second field: Time spent in idle process across all cores in seconds.
Boot timestamp is derived as:
$$\text{bootTime} = \text{currentTime} - \text{uptimeSeconds}$$

---

## 2. CPU Utilization & Sampling (`/proc/stat`)

Reading CPU usage via `top` suffers from locale variations and ANSI terminal control sequences. `/proc/stat` provides stable, kernel-level counter numbers:
```text
cpu  4705 356 584 3699 23 12 21 0 0 0
cpu0 1393 249 158 2116 12 1 11 0 0 0
...
```
The first line aggregates all CPU cores into tick counters:
1. `user`: Normal processes executing in user mode
2. `nice`: Niced processes executing in user mode
3. `system`: Processes executing in kernel mode
4. `idle`: Twiddling thumbs
5. `iowait`: Waiting for I/O to complete
6. `irq`: Servicing interrupts
7. `softirq`: Servicing softirqs
8. `steal`: Involuntary wait in virtualized environments
9. `guest`: Running a normal guest OS
10. `guest_nice`: Running a niced guest OS

### CPU Percentage Delta Calculation:
Single-point readings cannot yield instantaneous usage. We calculate percentage across two samples ($S_1$ and $S_2$):
$$\text{IdleTime} = \text{idle} + \text{iowait}$$
$$\text{NonIdleTime} = \text{user} + \text{nice} + \text{system} + \text{irq} + \text{softirq} + \text{steal}$$
$$\text{TotalTime} = \text{IdleTime} + \text{NonIdleTime}$$
$$\Delta \text{Idle} = \text{IdleTime}_2 - \text{IdleTime}_1$$
$$\Delta \text{Total} = \text{TotalTime}_2 - \text{TotalTime}_1$$
$$\text{CPU \%} = 100 \times \left(1 - \frac{\Delta \text{Idle}}{\Delta \text{Total}}\right)$$

If $\Delta \text{Total} \le 0$, usage is reported as 0.0%.

---

## 3. Memory & Swap Metrics (`/proc/meminfo`)

`/proc/meminfo` provides exact memory metrics in kB:
```text
MemTotal:       16301284 kB
MemFree:         4125820 kB
MemAvailable:   11245800 kB
Buffers:          345612 kB
Cached:          7120400 kB
SwapTotal:       2097148 kB
SwapFree:        2097148 kB
```

### Calculations:
- **Total Memory**: `MemTotal` (converted to bytes: $\text{kB} \times 1024$)
- **Available Memory**: `MemAvailable` (on Linux $\ge 3.14$).
  - Fallback if `MemAvailable` missing: `MemFree + Buffers + Cached`
- **Used Memory**: `MemTotal - MemAvailable`
- **Memory Usage %**: $(\text{Used} / \text{Total}) \times 100$
- **Swap Total**: `SwapTotal`
- **Swap Used**: `SwapTotal - SwapFree`
- **Swap Usage %**: $(\text{SwapUsed} / \text{SwapTotal}) \times 100$ (or 0% if `SwapTotal == 0`)

---

## 4. Load Averages (`/proc/loadavg`)

`/proc/loadavg` exposes 5 space-delimited tokens:
```text
0.15 0.20 0.25 1/140 12345
```
1. `1m`: 1-minute exponential moving average of runnable tasks
2. `5m`: 5-minute load average
3. `15m`: 15-minute load average
4. `runnable/total`: Number of currently runnable kernel scheduling entities / total kernel scheduling entities
5. `last_pid`: Most recently created process ID

---

## 5. Filesystem & Disk Usage (`df -P -k`)

POSIX specifies `df -P -k` for portable, single-line, 1024-byte block reporting:
```text
Filesystem     1024-blocks      Used Available Capacity Mounted on
/dev/sda1        102626244  42150820  55215836      44% /
/dev/sdb1        512340000 125000000 361200000      26% /data
tmpfs              8150640         0   8150640       0% /dev/shm
```

### Filtering Pseudo-Filesystems:
We filter out virtual, memory-only, or driver mounts:
- Filesystems starting with `tmpfs`, `devtmpfs`, `udev`, `none`, `cgroup`, `overlay`, `shm`, `squashfs`
- Retain physical or network block mounts and root `/`.

---

## 6. Process Listing & Privacy (`ps`)

### Privacy Concern:
CLI arguments (`args` / `cmdline`) frequently contain sensitive parameters (`--db-password=xxx`, `--api-key=yyy`, `--secret=zzz`).
To prevent accidental credential exfiltration, M7 default process listings use:
```bash
ps -eo pid,ppid,user,%cpu,%mem,stat,comm --sort=-%cpu
```
- `comm`: Executable name only (e.g. `nginx`, `python3`, `node`, `postgres`).
- Output is formatted with whitespace-delimited columns for reliable parsing.

---

## 7. Systemd Service Discovery & Non-Systemd Environments

### 7.1 Detection
1. Check executable: `command -v systemctl`
2. Check running status: Verify `/run/systemd/system` directory or `systemctl is-system-running`.
3. If absent or not running under systemd, flag `hasSystemd = false`.

### 7.2 Unit Listing
```bash
systemctl list-units --type=service --all --no-pager --no-legend --plain
```
Output columns:
`UNIT LOAD ACTIVE SUB DESCRIPTION...`
Example:
`nginx.service loaded active running A high performance web server and reverse proxy`
`portal-api.service loaded failed failed Portal Backend Daemon`

### 7.3 Unit Properties (`systemctl show`)
```bash
systemctl show <unit> --property=Id,Description,LoadState,ActiveState,SubState,UnitFileState,MainPID
```
Output is key-value lines:
```ini
Id=nginx.service
Description=A high performance web server
LoadState=loaded
ActiveState=active
SubState=running
UnitFileState=enabled
MainPID=1234
```

### 7.4 Non-Systemd Hosts (Alpine Linux, OpenRC, Containers)
On Alpine Linux or lightweight Docker containers running OpenRC or bare processes:
- `ServerCapabilities.hasSystemd` is set to `false`.
- Host resource observability (CPU, RAM, Disk, Load, Processes) continues to function seamlessly.
- The Services tab renders a non-systemd information card rather than a failure state.

---

## 8. Security & Injection Defenses

1. **Whitelisted Commands**: Only structured, non-destructive discovery commands are permitted (`cat /proc/...`, `uname`, `df -P -k`, `ps -eo ...`, `systemctl list-units`, `systemctl show`).
2. **Service Name Validation**: Service identifiers must match `^[a-zA-Z0-9_\.\-@]+$`. Shell metacharacters (`;`, `&`, `|`, `` ` ``, `$`, `\n`, spaces) are strictly rejected.
3. **Guarded Mutations**: `start`, `stop`, `restart` require explicit user confirmation dialogs and persistent `PRODUCTION` warnings on production profiles. Sudo is never invoked silently.
