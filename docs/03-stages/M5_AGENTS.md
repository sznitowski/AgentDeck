# M5 — Agents (Remote Agent Orchestration)

## Result

M5_DONE (core), 2026-09-20. AgentDeck can discover, launch, observe, detach, reconnect, resume, and terminate remote CLI agents (`codex`, `claude`, `opencode`, `agy`, generic CLI, and fake agent for automated lab validation) running inside persistent, managed tmux sessions on remote Linux servers. The agent process lifecycle is decoupled from the mobile client connection, with zero secret leakage, safe argument encapsulation, bounded buffer observation, and no automatic approvals. iOS lifecycle, APNs, background polling, and physical iPhone execution remain PENDING_MACOS_VALIDATION.

## Implementation

The Agent Orchestration subsystem is structured in strictly decoupled layers:

```text
Presentation (AgentsPage, AgentDetailPage, ProjectAgentsView)
     ↓
AgentCoordinator (Launch, observe, refresh, reconcile stale sessions, terminate)
     ↓
AgentProvider (Contract: id, displayName, detect, version, buildLaunchCommand, capabilities, outputClassifier)
  ├── CodexProvider
  ├── ClaudeCodeProvider
  ├── OpenCodeProvider
  ├── AntigravityProvider
  ├── GenericCliProvider
  └── FakeAgentProvider
     ↓
TmuxService / SshConnectionService (Structured list-panes, capture-pane, attach, kill-session)
     ↓
AgentInstanceRepository (Metadata persistence without credentials or conversation transcripts)
```

- **Execution Decoupling**: Complete separation between `AgentExecutionState` (`idle`, `starting`, `running`, `waitingUser`, `finished`, `failed`, `unknown`), `ConnectionState` (SSH), `TmuxSessionState` (`attached`, `detached`, `stale`), and `TerminalState`. If AgentDeck disconnects, the remote agent continues running uninterrupted in its tmux session.
- **Confidence & Observation Model**: `AgentObservation` tracks `state`, `confidence` (`confirmed`, `inferred`, `unknown`), `source` (`processExit`, `paneCommand`, `terminalPattern`, `tmuxSession`, `manual`), and timestamp. Signals like process exit codes provide `confirmed` status, while regex terminal output patterns provide `inferred` status.
- **Zero Shell Injection**: `AgentCommandSafety` enforces safe executable verification, POSIX single-quote escaping for arguments, and rigorous session naming sanitization (`ad_agent_<provider>_<project>_<nonce>`). Disallowed characters (`;`, `&&`, `|`, `$()`, backticks, newlines) are strictly blocked.
- **Output Classifiers & Bounded Observation**: Output classifiers (`CodexOutputClassifier`, `ClaudeCodeOutputClassifier`, `OpenCodeOutputClassifier`, `AntigravityOutputClassifier`, `GenericOutputClassifier`, `FakeAgentOutputClassifier`) inspect only the most recent ~15–30 lines of terminal output with ANSI stripping to detect prompts requiring user interaction (`WAITING_USER`). Full terminal transcripts and conversation histories are never stored or logged.
- **Stale Instance Detection**: When AgentDeck reconnects or refreshes, it reconciles local instance metadata against live remote tmux sessions. If a session is missing on the server (e.g., due to reboot or external kill), the instance is transitioned to `stale` rather than misleadingly reporting `RUNNING`.
- **Reusable Terminal Connection**: Direct integration with M2/M3 `TerminalPage` / `TerminalController` for attaching to agent tmux sessions, interacting with prompts, and detaching safely without killing the background process.
- **Security & Privacy Guardrails**: No automatic approvals or automated command execution. No agent API keys (`OPENAI_API_KEY`, `ANTHROPIC_API_KEY`) or environment variables stored in local credential storage. Production servers require explicit user confirmation for termination and display prominent visual badges.

## Real Local Lab

A disposable Alpine 3.21/OpenSSH + tmux container was executed on a dedicated Docker bridge with an unprivileged `lab` user, random credentials, dynamic port binding strictly to `127.0.0.1`, and host key fingerprint validation, running the deterministic `agentdeck-fake-agent` test binary.

| Scenario | Description | Result |
|---|---|---|
| A | Provider discovery (`fake-agent` available) | PASS |
| B | Version detection (`1.0.0-lab`) | PASS |
| C | Launch agent in managed tmux session | PASS |
| D | Running state observation | PASS |
| E | Waiting-user inference on interactive prompt | PASS |
| F | Terminal attach & interactive stdin communication | PASS |
| G | Detach PTY; process retains background execution | PASS |
| H | SSH connection drop while agent runs | PASS |
| I | Reconnect & discover running agent instance | PASS |
| J | Resume session over terminal | PASS |
| K | Successful exit detection (`exit 0` → `FINISHED`) | PASS |
| L | Failure exit detection (`exit 1` → `FAILED`) | PASS |
| M | Terminate instance & kill tmux session | PASS |
| N | Stale instance detection (metadata exists, session absent) | PASS |

All disposable container, network, image, and temporary secret resources were cleaned up upon test completion.

## Gates

- `dart format lib test tool`: PASS (0 format violations)
- `flutter analyze`: PASS (0 issues found)
- `flutter test`: PASS (84/84 tests passed)
- `powershell tool/agents_lab_docker.ps1`: PASS (Scenarios A through N)
