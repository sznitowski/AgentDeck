# M7.5 — Project Workspace / Control Center

## Objective
Implement the unified Project Workspace and Control Center in AgentDeck, composing existing modular subsystems (SSH connection, Git repository status, remote Agent lifecycle, persistent tmux sessions, SFTP file browsing, and Linux server resource health) into an integrated, mobile-first control surface centered around `ProjectProfile`.

---

## Architectural Principles
1. **Compose & Coordinate, Never Re-Implement**: Reuses existing domain models and application services (`SshConnectionService`, `GitService`, `AgentCoordinator`, `TmuxService`, `ServerOperationsService`, `RemoteFileService`). No duplicate SSH channels or protocol logic.
2. **Single Sources of Truth**: Each module maintains its own state and lifecycle. The workspace reads, summarizes, and coordinates without replacing underlying subsystem state.
3. **Actionable Priority Hierarchy**: Highlights attention-demanding conditions (agent waiting for input, Git merge conflicts, SSH disconnection, failed agent jobs) at the top of the mobile view before displaying standard metrics.
4. **Partial Failure Isolation**: A failure in one subsystem (e.g. non-Git directory or unreadable server metrics) does not cause the entire workspace to fail. Each subsystem populates its summary independently with error details when unavailable.
5. **Clear Staleness & Disconnect Indicators**: When SSH is disconnected, the workspace retains and displays last-known observations with exact timestamps marked as `DISCONNECTED / Last known`, preventing stale data from being misinterpreted as live.

---

## Deliverables
- **Domain Layer** (`lib/core/domain/workspace.dart`):
  - `ProjectWorkspaceSnapshot`, `WorkspaceAttentionItem`, `AttentionSeverity`, `WorkspaceGitSummary`, `WorkspaceAgentSummary`, `WorkspaceTmuxSummary`, `WorkspaceServerSummary`, `WorkspaceFilesSummary`.
- **Application Layer** (`lib/features/projects/application/project_workspace_coordinator.dart`):
  - `ProjectWorkspaceCoordinator` coordinating concurrent, isolated status queries across all services.
- **Presentation Layer** (`lib/features/projects/presentation/`):
  - `ProjectWorkspacePage`: Mobile-first control center with connection header, persistent `PRODUCTION` badge, attention banner, modular cards (Agent, Git, Server, Sessions, Files), and quick actions toolbar.
  - `WorkspaceAttentionBanner`, `WorkspaceAgentCard`, `WorkspaceGitCard`, `WorkspaceServerCard`, `WorkspaceQuickActions`.
  - `ProjectsPage` integration opening the Project Workspace on project selection.
- **Integration Lab & Tooling** (`tool/workspace_lab.dart` & `tool/workspace_lab_docker.ps1`):
  - Scenarios A through L validating project loading, connection summary, active agent, waitingUser priority, Git dirty tracking, conflict alerts, tmux resumability, server metrics, working directory check, partial failure resilience, disconnection staleness, and reconnection refresh.
- **Quality Gates**:
  - `dart format`, `flutter analyze` (0 issues), `flutter test` (100% pass).

---

## Result
M7_5_DONE.

## Follow-up
Next milestone: M8 — Notifications & Background Tasks.
