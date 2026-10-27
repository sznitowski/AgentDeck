# M6 — Git Operations

## Goal
Implement safe, decoupled remote Git inspection and guarded operations for repositories on Linux servers over verified SSH.

## Why this milestone exists
Coding agents (M5) and remote workflows modify files in project working directories. Users need visibility into repository status, branch, staged/unstaged changes, textual diffs, and commit history from their mobile device, with strict guardrails against destructive actions or accidental pushes to production.

## Scope
- Remote Git availability detection (`git --version`) without auto-installation.
- Repository detection (`git rev-parse --is-inside-work-tree`, `git rev-parse --show-toplevel`).
- Branch & HEAD inspection (current branch, detached HEAD, upstream, ahead/behind based on existing local refs).
- Comprehensive status parsing using `git status --porcelain=v2 --branch` (staged, unstaged, untracked, renamed, deleted, conflicted).
- UTF-8 and space-tolerant path handling.
- Textual diff viewer with paging/truncation bounds and sensitive file detection (`.env`, `*.key`, `*.pem`, `credentials*`).
- Commit history viewer (paginated / bounded to 50 commits) and commit detail view.
- Guarded mutations: `git add -- <path>` (stage), `git restore --staged -- <path>` (unstage), and explicit user-driven `git commit -m <msg>` (no `-a`, no auto-add, no amend).
- Production policy enforcement with persistent `PRODUCTION` badge and explicit confirmation dialogues.
- Complete command safety (`GitCommandSafety`) blocking shell injection and path option injection (leading `-`).

## Out of scope (Explicitly Deferred)
- Remote fetch (`FETCH_DEFERRED`): No background network operations or credential prompts.
- Remote push / push force (`PUSH_DEFERRED`): M6 is repository-local on the remote server.
- Automatic pull / rebase (`PULL_DEFERRED`).
- Merge conflict auto-resolution (`CONFLICT_RESOLUTION_DEFERRED`): Conflicts are flagged clearly as `CONFLICT`.
- Submodule management (`SUBMODULE_MANAGEMENT_DEFERRED`).
- Destructive commands (`git reset --hard`, `git clean -fd`, `git checkout -- .`, `git branch -D`): Completely blocked from GitService.
- Git credential / token management: No storing of GitHub/GitLab tokens.
- Automatic `safe.directory` modifications: Never bypass Git ownership checks silently.

## Architecture Impact
- Domain: `GitRepository`, `GitStatus`, `GitFileChange`, `GitCommit`, `GitDiff`, `GitAvailability`, `GitCommandSafety`, `GitService`, `GitCommandExecutor`.
- Infrastructure: `SshGitCommandExecutor` adapting `SshTmuxTransportHandle.run` with `git -C <workingDirectory>` command isolation.
- Presentation: `ProjectGitView`, `GitChangesPage`, `GitDiffViewerPage`, `GitHistoryPage`, `GitCommitDetailPage`.

## Validation
- Unit tests: porcelain v2 parser, command safety & injection prevention, path option protection, diff model, sensitive file classifier.
- Widget tests: Git project dashboard, changes list, diff viewer, history view, production warnings.
- Docker integration lab: Scenarios A through N running against an OpenSSH + Git Linux container.
- Quality gates: `flutter analyze` (0 issues), `flutter test` (100% pass), `dart format` (clean).

## Result
M6_DONE (core). Remote Git inspection, machine-readable porcelain status parsing, diff viewing, commit history, and guarded stage/unstage/commit actions fully implemented and verified via Docker integration lab (Scenarios A through N). iOS device gestures and keyboard integration remain PENDING_MACOS_VALIDATION.

## Follow-up
Next milestone: M7 — Server Operations.
