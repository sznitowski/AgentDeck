# Agent Providers Research Register

Investigation of CLI coding agents for remote execution inside managed tmux sessions on Linux servers.

---

## 1. OpenAI Codex CLI

- **Binary Name**: `codex`
- **Candidate Paths**: `['codex']` (e.g. `/usr/local/bin/codex`, `~/.npm-global/bin/codex`)
- **Version Command**: `codex --version`
- **Execution Model**:
  - Interactive REPL mode: `codex` inside project directory.
  - Working directory: Respects working directory where executed or passes directory flags.
  - Authentication: Server-side environment variables or local credentials configured on the server.
  - Prompts requiring user interaction: Interactive prompt inputs, tool confirmation questions, multi-step approval.
- **Output Characteristics**:
  - ANSI formatted rich text / spinners / markdown.
  - Waiting markers: Prompt lines ending with `>` or `?`, questions awaiting input.
- **Tmux Compatibility**: Full PTY / VT100 compatibility.
- **AgentDeck Integration**:
  - Launch inside tmux session with working directory set to project root.
  - Output classifier monitors last lines for interactive prompt symbols and questions without holding full transcript.

---

## 2. Claude Code CLI

- **Binary Name**: `claude`
- **Candidate Paths**: `['claude']`
- **Version Command**: `claude --version`
- **Execution Model**:
  - Interactive mode: `claude` launches the interactive REPL.
  - Working directory: Operates in current working directory.
  - Authentication: Pre-authenticated on remote server via Anthropic setup or environment tokens.
  - Prompts: Interactive question prompts, file edit confirmations, shell execution confirmations.
- **Output Characteristics**:
  - Formatted ANSI terminal output.
  - Prompt markers: `>` prompt symbol, `?` selection prompts, `Allow ...? [y/n]`.
- **Tmux Compatibility**: Full PTY compatibility.
- **AgentDeck Integration**:
  - Launch inside project tmux session.
  - Output classifier identifies question marks and confirmation prompts for `WAITING_USER` state inference.

---

## 3. OpenCode CLI

- **Binary Name**: `opencode`
- **Candidate Paths**: `['opencode']`
- **Version Command**: `opencode --version` (or `opencode -v`)
- **Execution Model**:
  - Interactive mode: `opencode`
  - Session continuation: `--continue` / `-c` or `--session <id>`
  - Working directory: Runs in current project root.
- **Output Characteristics**:
  - Interactive terminal layout.
  - Prompt markers: prompt line indicators, action approvals.
- **Tmux Compatibility**: Full PTY compatibility.

---

## 4. Antigravity CLI

- **Binary Name**: `agy` (with `antigravity` as fallback alias)
- **Candidate Paths**: `['agy', 'antigravity']`
- **Version Command**: `agy --version`
- **Execution Model**:
  - Interactive mode: `agy`
  - Custom flags: `--model`, `--mode`, `--sandbox`
  - TUI session with slash commands (`/config`, `/agents`, `/model`).
- **Output Characteristics**:
  - Rich TUI / ANSI terminal output.
  - Prompt markers: Waiting for user instruction, slash command prompt.
- **Tmux Compatibility**: Full PTY compatibility with dynamic resize.

---

## 5. Generic CLI Provider

- **Binary Name**: Configurable executable name (must match safe identifier `^[a-zA-Z0-9_\-\.]+$`)
- **Execution Model**:
  - Configurable executable with fixed arguments.
  - No free-form unescaped shell strings.
  - Fallback generic prompt classifier.

---

## 6. FakeAgent (Integration Lab Provider)

- **Binary Name**: `agentdeck-fake-agent`
- **Candidate Paths**: `['agentdeck-fake-agent', '/usr/local/bin/agentdeck-fake-agent']`
- **Version Command**: `agentdeck-fake-agent --version` (returns `agentdeck-fake-agent 1.0.0-lab`)
- **Modes**:
  - `agentdeck-fake-agent running`: Emits `[RUNNING]` and stays active with background loop.
  - `agentdeck-fake-agent waiting`: Emits `[WAITING_USER] Please provide instructions: ` and waits for terminal input on stdin.
  - `agentdeck-fake-agent success`: Emits `[FINISHED]` and exits with code `0`.
  - `agentdeck-fake-agent fail`: Emits `[FAILED]` and exits with code `1`.
- **Purpose**: Fully deterministic, reproducible verification of provider discovery, version extraction, tmux launch, running detection, waiting inference, terminal attach/detach, process survival across SSH loss, reconnect discovery, and exit code classification without external APIs or credentials.
