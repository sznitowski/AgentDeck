# Stage M8.5 — Server Companion / Remote Observer

**Status:** `DONE` (Verified: Python unit tests 12/12 PASS, Flutter analyze 0 issues PASS, Flutter tests 166/166 PASS, Docker Companion Lab A-P PASS)

## 1. Goal

Build the first **AgentDeck Server Companion** (`agentdeck-companion`) — an autonomous, lightweight, read-first server-side observer that continuously inspects active coding agents (tmux), Git merge conflicts, server resources, and project working directories while the user's mobile device is disconnected or suspended.

The companion detects state transitions, creates structured, discrete `AgentDeckEvent` records with monotonic sequence numbers, appends them to a bounded, crash-safe journal, and exposes them over authenticated SSH for mobile catch-up synchronization.

---

## 2. Architecture & Requirements

### Core Properties
- **Headless & Low-Resource**: Runs as an unprivileged daemon with ~15MB RSS memory footprint and negligible CPU.
- **Zero Open Ports**: No public or loopback TCP listeners; communication occurs strictly over authenticated CLI-over-SSH (`agentdeck-companion events --after <sequence>`).
- **Single-Instance Enforcement**: POSIX file locking (`fcntl.flock`) prevents multiple daemons from executing on the same host and generating duplicate sequences.
- **Strict Privacy**: Zero storage of terminal transcripts, diff bodies, tokens, passwords, or environment variables.
- **Read-Only / No Auto-Approval**: Strictly observes; never responds to prompts or modifies Git repositories.

### Event & Observation Model
- **Agents**: Observes `ad_agent_*` tmux sessions, pane command lifecycle, and interactive prompts -> `agentWaitingUser`, `agentFailed`, `agentFinished`.
- **Git**: Inspects repository status (`git -C <dir> status --porcelain=v2 --branch`) -> `gitConflictDetected`, `gitConflictResolved`.
- **Server Resources**: Reads `/proc/stat`, `/proc/meminfo`, and filesystem statistics with hysteresis (90%/85% critical, 75%/70% warning) -> `serverResourceCritical`, `serverResourceWarning`, `serverResourceRecovered`.
- **Working Directories**: Verifies directory accessibility -> `workingDirectoryMissing`.
- **First-Start Baseline**: Builds baseline state on first startup to eliminate historical alert spam.
- **Monotonic Journaling**: Appends events with integer `sequence: 1, 2, 3...` surviving daemon restarts.
- **Retention**: Bounded to 1,000 events and 7 days max age with FIFO pruning.

---

## 3. Verification Criteria & Lab Matrix

| Scenario | Description | Expected Outcome |
|---|---|---|
| **A** | Companion starts and acquires lock | Daemon initializes, creates lock file, and logs startup |
| **B** | Health JSON endpoint query | Returns valid `status: ok` and scan summary |
| **C** | Version negotiation | Returns `schemaVersion: 1` and protocol version |
| **D** | First-start baseline initialization | Initial steady state produces 0 historical alert events |
| **E** | Agent transitions to `waitingUser` | Companion detects transition and writes sequence #1 event to journal |
| **F** | **Phone Absent Simulation** | Agent transitions while mobile is disconnected; companion records event |
| **G** | Git conflict while phone is disconnected | Merge conflict introduced offline; companion records event |
| **H** | Server resource metric spike | Server metric $\ge 90\%$ triggers `serverResourceCritical` event |
| **I** | Companion restart recovery | Restart recovers baseline; produces 0 duplicate historical alerts |
| **J** | Sequence persistence | Monotonic sequence continues from previous max after restart |
| **K** | **Mobile Reconnect Catch-Up** | Mobile connects, runs `events --after <cursor>`, and receives offline batch |
| **L** | Deterministic cursor queries | Repeated queries with same cursor return identical events with no duplicates |
| **M** | Project error isolation | One project error (e.g. deleted Git repo) does not disrupt other projects |
| **N** | Bounded journal retention | Prunes events exceeding 1,000 count limit or max age |
| **O** | Privacy & zero-secret scan | Verifies zero secrets, passwords, tokens, or diff bodies in journal |
| **P** | Command injection protection | Malformed flags, invalid paths, and injection characters are safely rejected |
