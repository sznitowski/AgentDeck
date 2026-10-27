import '../../../core/domain/agents.dart';
import '../../../core/domain/events.dart';
import '../../../core/domain/workspace.dart';

/// Tracks internal transition state for server resource hysteresis.
enum ServerResourceAlertState {
  normal,
  warning,
  critical,
}

/// Detects discrete state transitions across successive observations.
class StateTransitionDetector {
  StateTransitionDetector({
    this.disconnectDebounce = const Duration(seconds: 3),
    this.criticalMetricThreshold = 90.0,
    this.criticalRecoveryThreshold = 85.0,
    this.warningMetricThreshold = 75.0,
    this.warningRecoveryThreshold = 70.0,
  });

  final Duration disconnectDebounce;
  final double criticalMetricThreshold;
  final double criticalRecoveryThreshold;
  final double warningMetricThreshold;
  final double warningRecoveryThreshold;

  // State caches per target entity
  final Map<String, AgentExecutionState> _lastAgentStates = {};
  final Map<String, int> _lastGitConflictCounts = {};
  final Map<String, bool> _lastConnectionStates = {};
  final Map<String, DateTime> _disconnectTimestamps = {};
  final Map<String, bool> _disconnectAlerted = {};
  final Map<String, ServerResourceAlertState> _lastServerResourceStates = {};
  final Map<String, bool> _lastDirectoryMissing = {};

  int _eventCounter = 0;

  String _generateEventId() {
    final now = DateTime.now().microsecondsSinceEpoch;
    _eventCounter++;
    return 'evt_${now}_$_eventCounter';
  }

  /// Evaluates transitions across an updated [ProjectWorkspaceSnapshot].
  List<AgentDeckEvent> evaluateWorkspaceSnapshot(
    ProjectWorkspaceSnapshot snapshot, {
    DateTime? now,
  }) {
    final timestamp = now ?? DateTime.now();
    final events = <AgentDeckEvent>[];

    final projectId = snapshot.project.id;
    final projectName = snapshot.project.name;
    final serverId = snapshot.server?.id ?? snapshot.project.serverId;
    final serverName = snapshot.server?.name ?? snapshot.project.serverId;
    final isProduction = snapshot.isProduction;

    // 1. Connection state transition
    final isConnected = snapshot.isConnected;
    final connKey = serverId;
    final wasConnected = _lastConnectionStates[connKey] ?? true;

    if (!isConnected) {
      if (wasConnected) {
        _disconnectTimestamps[connKey] = timestamp;
      }
      final discTime = _disconnectTimestamps[connKey] ?? timestamp;
      final elapsed = timestamp.difference(discTime);
      final alreadyAlerted = _disconnectAlerted[connKey] ?? false;

      if (elapsed >= disconnectDebounce && !alreadyAlerted) {
        _disconnectAlerted[connKey] = true;
        events.add(AgentDeckEvent(
          id: _generateEventId(),
          type: EventType.connectionLost,
          detectedAt: timestamp,
          severity:
              isProduction ? EventSeverity.critical : EventSeverity.warning,
          source: EventSource.connection,
          fingerprint: 'conn_lost:$serverId',
          title: 'SSH Connection Lost',
          message: 'Connection to $serverName was lost.',
          projectId: projectId,
          projectName: projectName,
          serverId: serverId,
          serverName: serverName,
          isProduction: isProduction,
          actionLabel: 'Reconnect',
          destination: NotificationDestination(
            route: 'connection',
            projectId: projectId,
            serverId: serverId,
          ),
        ));
      }
    } else {
      final wasAlerted = _disconnectAlerted[connKey] ?? false;
      if (wasAlerted) {
        _disconnectAlerted[connKey] = false;
        events.add(AgentDeckEvent(
          id: _generateEventId(),
          type: EventType.connectionRestored,
          detectedAt: timestamp,
          severity: EventSeverity.info,
          source: EventSource.connection,
          fingerprint: 'conn_restored:$serverId',
          title: 'SSH Connection Restored',
          message: 'Reconnected to $serverName successfully.',
          projectId: projectId,
          projectName: projectName,
          serverId: serverId,
          serverName: serverName,
          isProduction: isProduction,
          destination: NotificationDestination(
            route: 'workspace',
            projectId: projectId,
            serverId: serverId,
          ),
        ));
      }
      _disconnectTimestamps.remove(connKey);
    }
    _lastConnectionStates[connKey] = isConnected;

    // If disconnected, we do not evaluate further remote transitions
    if (!isConnected) {
      return events;
    }

    // 2. Agent state transitions
    if (snapshot.agent != null && snapshot.agent!.state != null) {
      final agent = snapshot.agent!;
      final agentKey = agent.instanceId ?? projectId;
      final prevState = _lastAgentStates[agentKey];
      final currState = agent.state!;

      if (prevState != currState) {
        if (currState == AgentExecutionState.waitingUser &&
            prevState != AgentExecutionState.waitingUser) {
          events.add(AgentDeckEvent(
            id: _generateEventId(),
            type: EventType.agentWaitingUser,
            detectedAt: timestamp,
            severity: EventSeverity.actionRequired,
            source: EventSource.agent,
            fingerprint: 'agent_waiting:$agentKey',
            title: '${agent.providerName ?? 'Agent'} is waiting for input',
            message: 'Interactive CLI prompt requires your response.',
            projectId: projectId,
            projectName: projectName,
            serverId: serverId,
            serverName: serverName,
            agentInstanceId: agent.instanceId,
            agentProviderId: agent.providerId,
            agentProviderName: agent.providerName,
            isProduction: isProduction,
            actionLabel: 'Respond',
            destination: NotificationDestination(
              route: 'agent_terminal',
              projectId: projectId,
              serverId: serverId,
              agentInstanceId: agent.instanceId,
              tmuxSessionName: agent.tmuxSessionName,
            ),
          ));
        } else if (currState == AgentExecutionState.failed &&
            prevState != AgentExecutionState.failed) {
          events.add(AgentDeckEvent(
            id: _generateEventId(),
            type: EventType.agentFailed,
            detectedAt: timestamp,
            severity: EventSeverity.critical,
            source: EventSource.agent,
            fingerprint: 'agent_failed:$agentKey',
            title: '${agent.providerName ?? 'Agent'} execution failed',
            message: 'Agent process terminated with an error state.',
            projectId: projectId,
            projectName: projectName,
            serverId: serverId,
            serverName: serverName,
            agentInstanceId: agent.instanceId,
            agentProviderId: agent.providerId,
            agentProviderName: agent.providerName,
            isProduction: isProduction,
            actionLabel: 'Inspect',
            destination: NotificationDestination(
              route: 'agent_details',
              projectId: projectId,
              serverId: serverId,
              agentInstanceId: agent.instanceId,
            ),
          ));
        } else if (currState == AgentExecutionState.finished &&
            prevState != AgentExecutionState.finished) {
          events.add(AgentDeckEvent(
            id: _generateEventId(),
            type: EventType.agentFinished,
            detectedAt: timestamp,
            severity: EventSeverity.info,
            source: EventSource.agent,
            fingerprint: 'agent_finished:$agentKey',
            title: '${agent.providerName ?? 'Agent'} finished execution',
            message: 'Agent task completed successfully.',
            projectId: projectId,
            projectName: projectName,
            serverId: serverId,
            serverName: serverName,
            agentInstanceId: agent.instanceId,
            agentProviderId: agent.providerId,
            agentProviderName: agent.providerName,
            isProduction: isProduction,
            destination: NotificationDestination(
              route: 'workspace',
              projectId: projectId,
              serverId: serverId,
              agentInstanceId: agent.instanceId,
            ),
          ));
        }
      }
      _lastAgentStates[agentKey] = currState;
    }

    // 3. Git conflict transitions
    if (snapshot.git != null && !snapshot.git!.isNotRepository) {
      final git = snapshot.git!;
      final gitKey = projectId;
      final prevConflicts = _lastGitConflictCounts[gitKey] ?? 0;
      final currConflicts = git.conflictCount;

      if (prevConflicts == 0 && currConflicts > 0) {
        events.add(AgentDeckEvent(
          id: _generateEventId(),
          type: EventType.gitConflictDetected,
          detectedAt: timestamp,
          severity: EventSeverity.critical,
          source: EventSource.git,
          fingerprint: 'git_conflict:$projectId:$currConflicts',
          title: 'Git Merge Conflicts Detected',
          message: '$currConflicts file(s) contain unresolved merge conflicts.',
          projectId: projectId,
          projectName: projectName,
          serverId: serverId,
          serverName: serverName,
          isProduction: isProduction,
          actionLabel: 'View Conflicts',
          destination: NotificationDestination(
            route: 'git',
            projectId: projectId,
            serverId: serverId,
          ),
        ));
      } else if (prevConflicts > 0 && currConflicts == 0) {
        events.add(AgentDeckEvent(
          id: _generateEventId(),
          type: EventType.gitConflictResolved,
          detectedAt: timestamp,
          severity: EventSeverity.info,
          source: EventSource.git,
          fingerprint: 'git_conflict_resolved:$projectId',
          title: 'Git Merge Conflicts Resolved',
          message: 'All repository merge conflicts have been resolved.',
          projectId: projectId,
          projectName: projectName,
          serverId: serverId,
          serverName: serverName,
          isProduction: isProduction,
          destination: NotificationDestination(
            route: 'git',
            projectId: projectId,
            serverId: serverId,
          ),
        ));
      }
      _lastGitConflictCounts[gitKey] = currConflicts;
    }

    // 4. Server resource metrics with Hysteresis
    if (snapshot.serverHealth != null) {
      final s = snapshot.serverHealth!;
      final srvKey = serverId;
      final maxPercent = [
        s.cpuPercent ?? 0.0,
        s.memoryPercent ?? 0.0,
        s.diskPercent ?? 0.0,
      ].reduce((a, b) => a > b ? a : b);

      final prevState =
          _lastServerResourceStates[srvKey] ?? ServerResourceAlertState.normal;
      ServerResourceAlertState nextState = prevState;

      if (maxPercent >= criticalMetricThreshold) {
        nextState = ServerResourceAlertState.critical;
        if (prevState != ServerResourceAlertState.critical) {
          events.add(AgentDeckEvent(
            id: _generateEventId(),
            type: EventType.serverResourceCritical,
            detectedAt: timestamp,
            severity:
                isProduction ? EventSeverity.critical : EventSeverity.warning,
            source: EventSource.server,
            fingerprint: 'srv_crit:$serverId',
            title: 'Critical Server Resource Pressure',
            message:
                'Server resource utilization reached ${maxPercent.toStringAsFixed(1)}%.',
            projectId: projectId,
            projectName: projectName,
            serverId: serverId,
            serverName: serverName,
            isProduction: isProduction,
            actionLabel: 'Server Health',
            destination: NotificationDestination(
              route: 'server',
              projectId: projectId,
              serverId: serverId,
            ),
          ));
        }
      } else if (maxPercent >= warningMetricThreshold) {
        if (prevState == ServerResourceAlertState.critical) {
          // Check hysteresis: only recover from critical if below recovery threshold
          if (maxPercent < criticalRecoveryThreshold) {
            nextState = ServerResourceAlertState.warning;
          }
        } else if (prevState == ServerResourceAlertState.normal) {
          nextState = ServerResourceAlertState.warning;
          events.add(AgentDeckEvent(
            id: _generateEventId(),
            type: EventType.serverResourceWarning,
            detectedAt: timestamp,
            severity: EventSeverity.warning,
            source: EventSource.server,
            fingerprint: 'srv_warn:$serverId',
            title: 'Server Resource Warning',
            message:
                'Server resource utilization reached ${maxPercent.toStringAsFixed(1)}%.',
            projectId: projectId,
            projectName: projectName,
            serverId: serverId,
            serverName: serverName,
            isProduction: isProduction,
            actionLabel: 'Server Health',
            destination: NotificationDestination(
              route: 'server',
              projectId: projectId,
              serverId: serverId,
            ),
          ));
        }
      } else {
        // Below warning threshold
        if (prevState == ServerResourceAlertState.critical &&
            maxPercent < criticalRecoveryThreshold) {
          nextState = maxPercent < warningRecoveryThreshold
              ? ServerResourceAlertState.normal
              : ServerResourceAlertState.warning;
        } else if (prevState == ServerResourceAlertState.warning &&
            maxPercent < warningRecoveryThreshold) {
          nextState = ServerResourceAlertState.normal;
        }

        if (prevState != ServerResourceAlertState.normal &&
            nextState == ServerResourceAlertState.normal) {
          events.add(AgentDeckEvent(
            id: _generateEventId(),
            type: EventType.serverResourceRecovered,
            detectedAt: timestamp,
            severity: EventSeverity.info,
            source: EventSource.server,
            fingerprint: 'srv_rec:$serverId',
            title: 'Server Resources Recovered',
            message:
                'Server resource utilization normalized (${maxPercent.toStringAsFixed(1)}%).',
            projectId: projectId,
            projectName: projectName,
            serverId: serverId,
            serverName: serverName,
            isProduction: isProduction,
            destination: NotificationDestination(
              route: 'server',
              projectId: projectId,
              serverId: serverId,
            ),
          ));
        }
      }
      _lastServerResourceStates[srvKey] = nextState;
    }

    // 5. Working directory missing
    if (snapshot.files != null) {
      final filesKey = projectId;
      final wasMissing = _lastDirectoryMissing[filesKey] ?? false;
      final isMissing =
          !snapshot.files!.exists && snapshot.files!.error != null;

      if (!wasMissing && isMissing) {
        events.add(AgentDeckEvent(
          id: _generateEventId(),
          type: EventType.workingDirectoryMissing,
          detectedAt: timestamp,
          severity: EventSeverity.warning,
          source: EventSource.files,
          fingerprint: 'dir_missing:$projectId',
          title: 'Working Directory Missing',
          message:
              'Project path "${snapshot.project.workingDirectory}" cannot be accessed.',
          projectId: projectId,
          projectName: projectName,
          serverId: serverId,
          serverName: serverName,
          isProduction: isProduction,
          actionLabel: 'Browse Files',
          destination: NotificationDestination(
            route: 'files',
            projectId: projectId,
            serverId: serverId,
          ),
        ));
      }
      _lastDirectoryMissing[filesKey] = isMissing;
    }

    return events;
  }

  /// Resets state tracking for testing or full re-observation.
  void reset() {
    _lastAgentStates.clear();
    _lastGitConflictCounts.clear();
    _lastConnectionStates.clear();
    _disconnectTimestamps.clear();
    _disconnectAlerted.clear();
    _lastServerResourceStates.clear();
    _lastDirectoryMissing.clear();
  }
}
