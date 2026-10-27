import '../../../core/domain/agents.dart';
import '../../../core/domain/git.dart';
import '../../../core/domain/profiles.dart';
import '../../../core/domain/server_operations.dart';
import '../../../core/domain/workspace.dart';
import '../../agents/application/agent_coordinator.dart';
import '../../connections/application/ssh_connection_service.dart';
import '../../files/application/remote_file_service.dart';
import '../../git/application/git_service.dart';
import '../../git/infrastructure/ssh_git_command_executor.dart';
import '../../servers/application/server_operations_service.dart';
import '../../servers/domain/server_profile_repository.dart';
import '../../servers/infrastructure/ssh_server_command_executor.dart';

/// Application coordinator that composes multi-service project snapshots with partial failure isolation.
class ProjectWorkspaceCoordinator {
  ProjectWorkspaceCoordinator({
    required this.connection,
    required this.servers,
    this.agents,
    this.gitService,
    this.serverOpsService,
    this.fileService,
  });

  final SshConnectionService connection;
  final ServerProfileRepository servers;
  final AgentCoordinator? agents;
  final GitService? gitService;
  final ServerOperationsService? serverOpsService;
  final RemoteFileService? fileService;

  final Map<String, ProjectWorkspaceSnapshot> _lastKnownSnapshots = {};

  /// Gathers a full aggregated observation of a project.
  Future<ProjectWorkspaceSnapshot> inspectWorkspace(
      ProjectProfile project) async {
    final serverList = await servers.all();
    final server = serverList.cast<ServerProfile?>().firstWhere(
          (s) => s?.id == project.serverId,
          orElse: () => null,
        );

    final isConnected = server != null &&
        connection.state == ConnectionState.connected &&
        connection.connectedProfileId == server.id;

    final now = DateTime.now();

    if (!isConnected) {
      final cached = _lastKnownSnapshots[project.id];
      final attention = <WorkspaceAttentionItem>[
        WorkspaceAttentionItem(
          title: 'SSH Disconnected',
          message: server != null
              ? 'Connect to ${server.name} (${server.host}) to observe live project state.'
              : 'Server configuration not found.',
          severity: project.environment == Environment.production
              ? AttentionSeverity.critical
              : AttentionSeverity.warning,
          type: AttentionType.connectionLost,
          actionLabel: 'Connect',
          actionRoute: 'connection',
        ),
        if (cached != null)
          ...cached.attentionItems
              .where((a) => a.type != AttentionType.connectionLost),
      ];

      return ProjectWorkspaceSnapshot(
        project: project,
        server: server,
        connectionState: connection.state,
        observedAt: cached?.observedAt ?? now,
        git: cached?.git,
        agent: cached?.agent,
        tmux: cached?.tmux,
        serverHealth: cached?.serverHealth,
        files: cached?.files,
        attentionItems: attention,
      );
    }

    // Instantiating subsystem services over verified connection if not injected
    final effectiveGit = gitService ??
        RemoteGitService(
          executor: SshGitCommandExecutor(
            connection: connection,
            serverId: server.id,
          ),
        );

    final effectiveServerOps = serverOpsService ??
        RemoteServerOperationsService(
          executor: SshServerCommandExecutor(
            connection: connection,
            serverId: server.id,
          ),
        );

    final effectiveFiles = fileService ??
        RemoteFileService(
          connection: connection,
          serverId: server.id,
        );

    // Parallel execution with independent partial failure isolation
    final gitFuture =
        _fetchGitSummary(effectiveGit, project.workingDirectory, now);
    final agentFuture = _fetchAgentSummary(project.id, now);
    final serverOpsFuture = _fetchServerOpsSummary(effectiveServerOps, now);
    final filesFuture =
        _fetchFilesSummary(effectiveFiles, project.workingDirectory, now);

    final results = await Future.wait([
      gitFuture,
      agentFuture,
      serverOpsFuture,
      filesFuture,
    ]);

    final gitSummary = results[0] as WorkspaceGitSummary?;
    final agentSummary = results[1] as WorkspaceAgentSummary?;
    final serverSummary = results[2] as WorkspaceServerSummary?;
    final filesSummary = results[3] as WorkspaceFilesSummary?;

    // Derive Tmux summary from agent session or primary project session
    WorkspaceTmuxSummary? tmuxSummary;
    if (agentSummary?.tmuxSessionName != null) {
      tmuxSummary = WorkspaceTmuxSummary(
        sessionName: agentSummary!.tmuxSessionName,
        isAttached: true,
        isResumable: true,
        observedAt: now,
      );
    }

    final attention = _deriveAttentionItems(
      project: project,
      server: server,
      git: gitSummary,
      agent: agentSummary,
      serverHealth: serverSummary,
      files: filesSummary,
    );

    final snapshot = ProjectWorkspaceSnapshot(
      project: project,
      server: server,
      connectionState: connection.state,
      observedAt: now,
      git: gitSummary,
      agent: agentSummary,
      tmux: tmuxSummary,
      serverHealth: serverSummary,
      files: filesSummary,
      attentionItems: attention,
    );

    _lastKnownSnapshots[project.id] = snapshot;
    return snapshot;
  }

  Future<WorkspaceGitSummary> _fetchGitSummary(
    GitService git,
    String workingDirectory,
    DateTime timestamp,
  ) async {
    try {
      final avail = await git.checkAvailability();
      if (!avail.isInstalled) {
        return WorkspaceGitSummary(
          isGitMissing: true,
          isClean: true,
          observedAt: timestamp,
        );
      }

      final repo = await git.inspectRepository(workingDirectory);
      if (!repo.isRepository) {
        return WorkspaceGitSummary(
          isNotRepository: true,
          isClean: true,
          observedAt: timestamp,
        );
      }

      final status = await git.getStatus(workingDirectory);
      var staged = 0;
      var unstaged = 0;
      var untracked = 0;
      var conflicts = 0;

      for (final f in status.changedFiles) {
        if (f.isConflict) {
          conflicts++;
        } else if (f.isUntracked) {
          untracked++;
        } else {
          if (f.indexStatus != GitFileStatus.unmodified) staged++;
          if (f.workTreeStatus != GitFileStatus.unmodified) unstaged++;
        }
      }

      return WorkspaceGitSummary(
        branch: status.branch,
        headCommit: status.headCommit,
        stagedCount: staged,
        unstagedCount: unstaged,
        untrackedCount: untracked,
        conflictCount: conflicts,
        isClean: status.changedFiles.isEmpty,
        isDetachedHead: status.isDetachedHead,
        observedAt: timestamp,
      );
    } catch (e) {
      return WorkspaceGitSummary(
        error: e.toString(),
        isClean: false,
        observedAt: timestamp,
      );
    }
  }

  Future<WorkspaceAgentSummary?> _fetchAgentSummary(
    String projectId,
    DateTime timestamp,
  ) async {
    if (agents == null) return null;
    try {
      final allInstances = await agents!.instanceRepository.all();
      final projectInstances =
          allInstances.where((i) => i.projectId == projectId).toList();

      if (projectInstances.isEmpty) {
        return null;
      }

      // Prioritize waitingUser or running instance
      final primary = projectInstances.firstWhere(
        (i) => i.executionState == AgentExecutionState.waitingUser,
        orElse: () => projectInstances.firstWhere(
          (i) => i.executionState == AgentExecutionState.running,
          orElse: () => projectInstances.first,
        ),
      );

      final provider =
          agents!.registeredProviders.cast<AgentProvider?>().firstWhere(
                (p) => p?.id == primary.providerId,
                orElse: () => null,
              );

      return WorkspaceAgentSummary(
        instanceId: primary.id,
        providerId: primary.providerId,
        providerName:
            provider?.displayName ?? primary.displayName ?? primary.providerId,
        state: primary.executionState,
        confidence: primary.observation?.confidence,
        tmuxSessionName: primary.tmuxSessionName,
        isWaitingUser:
            primary.executionState == AgentExecutionState.waitingUser,
        isFailed: primary.executionState == AgentExecutionState.failed,
        isRunning: primary.executionState == AgentExecutionState.running,
        observedAt: timestamp,
      );
    } catch (e) {
      return WorkspaceAgentSummary(
        error: e.toString(),
        observedAt: timestamp,
      );
    }
  }

  Future<WorkspaceServerSummary?> _fetchServerOpsSummary(
    ServerOperationsService ops,
    DateTime timestamp,
  ) async {
    try {
      final snapshot = await ops.getHealthSnapshot();
      final diskPercent =
          snapshot.disks.isNotEmpty ? snapshot.disks.first.usagePercent : null;

      final isHealthy = snapshot.cpu.totalPercent < 90 &&
          snapshot.memory.usagePercent < 90 &&
          (diskPercent == null || diskPercent < 90);

      return WorkspaceServerSummary(
        cpuPercent: snapshot.cpu.totalPercent,
        memoryPercent: snapshot.memory.usagePercent,
        diskPercent: diskPercent,
        load1m: snapshot.loadAvg1m,
        isHealthy: isHealthy,
        observedAt: timestamp,
      );
    } catch (e) {
      return WorkspaceServerSummary(
        error: e.toString(),
        isHealthy: false,
        observedAt: timestamp,
      );
    }
  }

  Future<WorkspaceFilesSummary> _fetchFilesSummary(
    RemoteFileService files,
    String workingDirectory,
    DateTime timestamp,
  ) async {
    try {
      final entry = await files.stat(workingDirectory);
      return WorkspaceFilesSummary(
        workingDirectory: workingDirectory,
        exists: entry.isDirectory,
        observedAt: timestamp,
      );
    } catch (e) {
      return WorkspaceFilesSummary(
        workingDirectory: workingDirectory,
        exists: false,
        error: e.toString(),
        observedAt: timestamp,
      );
    }
  }

  List<WorkspaceAttentionItem> _deriveAttentionItems({
    required ProjectProfile project,
    required ServerProfile? server,
    required WorkspaceGitSummary? git,
    required WorkspaceAgentSummary? agent,
    required WorkspaceServerSummary? serverHealth,
    required WorkspaceFilesSummary? files,
  }) {
    final items = <WorkspaceAttentionItem>[];

    // 1. Priority: Agent waiting for user
    if (agent?.isWaitingUser == true) {
      items.add(WorkspaceAttentionItem(
        title: '${agent!.providerName ?? 'Agent'} is waiting for input',
        message: 'Interactive CLI prompt requires your response.',
        severity: AttentionSeverity.actionRequired,
        type: AttentionType.agentWaiting,
        actionLabel: 'Respond',
        actionRoute: 'agent_terminal',
      ));
    }

    // 2. Priority: Agent failed
    if (agent?.isFailed == true) {
      items.add(WorkspaceAttentionItem(
        title: '${agent!.providerName ?? 'Agent'} execution failed',
        message: 'The agent process terminated with an error state.',
        severity: AttentionSeverity.critical,
        type: AttentionType.agentFailed,
        actionLabel: 'Inspect',
        actionRoute: 'agent',
      ));
    }

    // 3. Priority: Git merge conflicts
    if (git != null && git.conflictCount > 0) {
      items.add(WorkspaceAttentionItem(
        title: 'Git Merge Conflicts Detected',
        message:
            '${git.conflictCount} file(s) contain unresolved merge conflicts.',
        severity: AttentionSeverity.critical,
        type: AttentionType.gitConflict,
        actionLabel: 'View Conflicts',
        actionRoute: 'git',
      ));
    }

    // 4. Priority: Working directory not found
    if (files != null && !files.exists && files.error != null) {
      items.add(WorkspaceAttentionItem(
        title: 'Working Directory Missing or Inaccessible',
        message:
            'Directory "${project.workingDirectory}" could not be accessed.',
        severity: AttentionSeverity.warning,
        type: AttentionType.generic,
        actionLabel: 'Browse Files',
        actionRoute: 'files',
      ));
    }

    // 5. Priority: Server resource pressure
    if (serverHealth != null && !serverHealth.isHealthy) {
      items.add(const WorkspaceAttentionItem(
        title: 'High Server Resource Pressure',
        message: 'CPU, Memory, or Disk utilization has exceeded 90%.',
        severity: AttentionSeverity.warning,
        type: AttentionType.serverCritical,
        actionLabel: 'Server Health',
        actionRoute: 'server',
      ));
    }

    // 6. Informational: Uncommitted Git changes
    if (git != null &&
        !git.isClean &&
        git.totalChanged > 0 &&
        git.conflictCount == 0) {
      items.add(WorkspaceAttentionItem(
        title: 'Uncommitted Changes (${git.totalChanged})',
        message:
            '${git.stagedCount} staged, ${git.unstagedCount} unstaged, ${git.untrackedCount} untracked files.',
        severity: AttentionSeverity.info,
        type: AttentionType.gitDirty,
        actionLabel: 'View Changes',
        actionRoute: 'git',
      ));
    }

    return items;
  }
}
