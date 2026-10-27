import 'agents.dart';
import 'profiles.dart';

/// Priority severity for attention-demanding items in a workspace.
enum AttentionSeverity {
  critical,
  actionRequired,
  warning,
  info,
}

/// Category of an attention item.
enum AttentionType {
  agentWaiting,
  agentFailed,
  gitConflict,
  connectionLost,
  serverCritical,
  gitDirty,
  noAgentRunning,
  generic,
}

/// An actionable or alert event derived from workspace state.
class WorkspaceAttentionItem {
  const WorkspaceAttentionItem({
    required this.title,
    required this.message,
    required this.severity,
    required this.type,
    this.actionLabel,
    this.actionRoute,
  });

  final String title;
  final String message;
  final AttentionSeverity severity;
  final AttentionType type;
  final String? actionLabel;
  final String? actionRoute;
}

/// High-level Git status summary for a project workspace.
class WorkspaceGitSummary {
  const WorkspaceGitSummary({
    this.branch,
    this.headCommit,
    this.stagedCount = 0,
    this.unstagedCount = 0,
    this.untrackedCount = 0,
    this.conflictCount = 0,
    this.isClean = true,
    this.isDetachedHead = false,
    this.isNotRepository = false,
    this.isGitMissing = false,
    this.error,
    this.observedAt,
  });

  final String? branch;
  final String? headCommit;
  final int stagedCount;
  final int unstagedCount;
  final int untrackedCount;
  final int conflictCount;
  final bool isClean;
  final bool isDetachedHead;
  final bool isNotRepository;
  final bool isGitMissing;
  final String? error;
  final DateTime? observedAt;

  int get totalChanged =>
      stagedCount + unstagedCount + untrackedCount + conflictCount;

  String get shortHead => headCommit != null && headCommit!.length > 7
      ? headCommit!.substring(0, 7)
      : (headCommit ?? '');
}

/// High-level active Agent lifecycle summary for a project workspace.
class WorkspaceAgentSummary {
  const WorkspaceAgentSummary({
    this.instanceId,
    this.providerId,
    this.providerName,
    this.state,
    this.confidence,
    this.tmuxSessionName,
    this.isWaitingUser = false,
    this.isFailed = false,
    this.isRunning = false,
    this.error,
    this.observedAt,
  });

  final String? instanceId;
  final String? providerId;
  final String? providerName;
  final AgentExecutionState? state;
  final ObservationConfidence? confidence;
  final String? tmuxSessionName;
  final bool isWaitingUser;
  final bool isFailed;
  final bool isRunning;
  final String? error;
  final DateTime? observedAt;
}

/// Summary of the primary tmux session attached or associated with a project.
class WorkspaceTmuxSummary {
  const WorkspaceTmuxSummary({
    this.sessionName,
    this.isAttached = false,
    this.isResumable = false,
    this.error,
    this.observedAt,
  });

  final String? sessionName;
  final bool isAttached;
  final bool isResumable;
  final String? error;
  final DateTime? observedAt;
}

/// Summary of the remote Linux server resource health.
class WorkspaceServerSummary {
  const WorkspaceServerSummary({
    this.hostname,
    this.cpuPercent,
    this.memoryPercent,
    this.diskPercent,
    this.load1m,
    this.isHealthy = true,
    this.error,
    this.observedAt,
  });

  final String? hostname;
  final double? cpuPercent;
  final double? memoryPercent;
  final double? diskPercent;
  final double? load1m;
  final bool isHealthy;
  final String? error;
  final DateTime? observedAt;
}

/// Verification summary of project working directory on remote filesystem.
class WorkspaceFilesSummary {
  const WorkspaceFilesSummary({
    required this.workingDirectory,
    this.exists = true,
    this.error,
    this.observedAt,
  });

  final String workingDirectory;
  final bool exists;
  final String? error;
  final DateTime? observedAt;
}

/// Aggregated ephemeral snapshot of a project's full operational context.
class ProjectWorkspaceSnapshot {
  const ProjectWorkspaceSnapshot({
    required this.project,
    this.server,
    required this.connectionState,
    required this.observedAt,
    this.git,
    this.agent,
    this.tmux,
    this.serverHealth,
    this.files,
    this.attentionItems = const [],
  });

  final ProjectProfile project;
  final ServerProfile? server;
  final ConnectionState connectionState;
  final DateTime observedAt;
  final WorkspaceGitSummary? git;
  final WorkspaceAgentSummary? agent;
  final WorkspaceTmuxSummary? tmux;
  final WorkspaceServerSummary? serverHealth;
  final WorkspaceFilesSummary? files;
  final List<WorkspaceAttentionItem> attentionItems;

  bool get isConnected => connectionState == ConnectionState.connected;
  bool get isProduction => project.environment == Environment.production;

  /// Returns the top urgent attention item if any exists.
  WorkspaceAttentionItem? get topAttentionItem =>
      attentionItems.isNotEmpty ? attentionItems.first : null;
}
