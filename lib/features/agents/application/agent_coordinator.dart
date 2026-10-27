import '../../../core/domain/agents.dart';
import '../../../core/domain/profiles.dart';
import '../../connections/application/ssh_connection_service.dart';
import '../../tmux/application/tmux_service.dart';
import '../../tmux/domain/tmux_models.dart';
import '../domain/agent_models.dart';
import '../providers/antigravity_provider.dart';
import '../providers/claude_code_provider.dart';
import '../providers/codex_provider.dart';
import '../providers/fake_agent_provider.dart';
import '../providers/generic_cli_provider.dart';
import '../providers/opencode_provider.dart';

class AgentCoordinator {
  AgentCoordinator({
    required this.connection,
    required this.tmuxReferences,
    required this.instanceRepository,
    Map<String, AgentProvider>? providers,
    DateTime Function()? clock,
  })  : _clock = clock ?? DateTime.now,
        _providers = providers ??
            {
              'codex': const CodexProvider(),
              'claude': const ClaudeCodeProvider(),
              'opencode': const OpenCodeProvider(),
              'antigravity': const AntigravityProvider(),
              'fake-agent': const FakeAgentProvider(),
              'generic': const GenericCliProvider(),
            };

  final SshConnectionService connection;
  final TmuxSessionRepository tmuxReferences;
  final AgentInstanceRepository instanceRepository;
  final Map<String, AgentProvider> _providers;
  final DateTime Function() _clock;

  List<AgentProvider> get registeredProviders => _providers.values.toList();

  AgentProvider? getProvider(String providerId) => _providers[providerId];

  void registerProvider(AgentProvider provider) {
    _providers[provider.id] = provider;
  }

  TmuxService _getTmux(String serverId) => TmuxService(
        connection: connection,
        references: tmuxReferences,
        serverId: serverId,
        clock: _clock,
      );

  Future<List<AgentDefinition>> discoverAgents(String serverId) async {
    if (connection.connectedProfileId != serverId) {
      // Return unverified definitions if not currently connected
      return registeredProviders
          .map((p) => AgentDefinition(
                id: p.id,
                providerId: p.id,
                displayName: p.displayName,
                isAvailable: false,
                capabilities: p.capabilities,
                installGuidance: p.installGuidance,
              ))
          .toList();
    }

    final definitions = <AgentDefinition>[];
    for (final provider in registeredProviders) {
      bool available = false;
      String? version;
      String? foundExec;

      for (final bin in provider.binaryCandidates) {
        try {
          final res = await connection.runRemoteCommand(['command', '-v', bin]);
          if (res.exitCode == 0 && res.stdout.trim().isNotEmpty) {
            available = true;
            foundExec = bin;
            try {
              final vRes =
                  await connection.runRemoteCommand([bin, '--version']);
              if (vRes.exitCode == 0) {
                final out = vRes.stdout.trim();
                final match = RegExp(r'(\d+\.\d+[\.\w\-]*)').firstMatch(out);
                version = match?.group(1) ?? out;
              }
            } catch (_) {}
            break;
          }
        } catch (_) {}
      }

      definitions.add(AgentDefinition(
        id: provider.id,
        providerId: provider.id,
        displayName: provider.displayName,
        executable: foundExec,
        version: version,
        isAvailable: available,
        capabilities: provider.capabilities,
        installGuidance: provider.installGuidance,
      ));
    }
    return definitions;
  }

  Future<AgentInstance> launch({
    required ServerProfile server,
    required ProjectProfile project,
    required AgentProvider provider,
    String? customExecutable,
    List<String>? extraArgs,
  }) async {
    if (connection.connectedProfileId != server.id) {
      throw StateError('SSH connection to ${server.name} is not active');
    }

    final executable = customExecutable ?? provider.binaryCandidates.first;
    AgentCommandSafety.sanitizeExecutable(executable);

    final sessionName = AgentCommandSafety.generateAgentSessionName(
      providerId: provider.id,
      projectId: project.id,
    );

    final launchCmd = provider.buildLaunchCommand(
      executable: executable,
      workingDirectory: project.workingDirectory,
      extraArgs: extraArgs,
    );

    final tmux = _getTmux(server.id);
    final now = _clock().toUtc();

    await tmux.create(
      displayName: '${provider.displayName} — ${project.name}',
      projectId: project.id,
      workingDirectory: project.workingDirectory,
      sessionName: sessionName,
      initialCommand: launchCmd,
    );

    final instance = AgentInstance(
      id: sessionName,
      providerId: provider.id,
      serverId: server.id,
      projectId: project.id,
      tmuxSessionName: sessionName,
      workingDirectory: project.workingDirectory,
      displayName: '${provider.displayName} (${project.name})',
      executionState: AgentExecutionState.running,
      observation: AgentObservation(
        state: AgentExecutionState.running,
        confidence: ObservationConfidence.confirmed,
        source: ObservationSource.tmuxSession,
        observedAt: now,
        detail: 'Agent process launched in tmux session $sessionName',
      ),
      startedAt: now,
      lastObservedAt: now,
      isStale: false,
    );

    await instanceRepository.put(instance);
    return instance;
  }

  Future<AgentInstance> refreshInstance(
    AgentInstance instance, {
    ServerProfile? server,
  }) async {
    final now = _clock().toUtc();

    // If not connected to the instance's server, we cannot observe remote state
    if (connection.connectedProfileId != instance.serverId) {
      return instance;
    }

    final tmux = _getTmux(instance.serverId);
    final sessions = await tmux.list();
    final session = sessions
        .where((s) => s.remoteName == instance.tmuxSessionName)
        .firstOrNull;

    if (session == null || session.state == TmuxSessionState.stale) {
      final state = (instance.executionState == AgentExecutionState.finished ||
              instance.executionState == AgentExecutionState.failed)
          ? instance.executionState
          : AgentExecutionState.finished;
      final updated = instance.copyWith(
        isStale: true,
        executionState: state,
        exitCode: instance.exitCode ??
            (state == AgentExecutionState.finished ? 0 : 1),
        observation: AgentObservation(
          state: state,
          confidence: ObservationConfidence.confirmed,
          source: ObservationSource.tmuxSession,
          observedAt: now,
          detail: 'Tmux session no longer exists on remote server',
        ),
        lastObservedAt: now,
      );
      await instanceRepository.put(updated);
      return updated;
    }

    // Query tmux pane information
    final paneRes = await connection.runRemoteCommand([
      'tmux',
      'list-panes',
      '-t',
      instance.tmuxSessionName,
      '-F',
      '#{pane_pid}:#{pane_current_command}:#{pane_dead}:#{pane_dead_status}',
    ]);

    if (paneRes.exitCode != 0) {
      return instance;
    }

    final lines = paneRes.stdout.trim().split('\n');
    if (lines.isEmpty || lines.first.isEmpty) {
      return instance;
    }

    final parts = lines.first.split(':');
    final dead = parts.length > 2 && parts[2] == '1';
    final deadStatus = parts.length > 3 ? int.tryParse(parts[3]) : null;
    final currentCmd = parts.length > 1 ? parts[1] : '';

    if (dead) {
      final exitCode = deadStatus ?? 0;
      final state = exitCode == 0
          ? AgentExecutionState.finished
          : AgentExecutionState.failed;

      final updated = instance.copyWith(
        executionState: state,
        exitCode: exitCode,
        isStale: false,
        observation: AgentObservation(
          state: state,
          confidence: ObservationConfidence.confirmed,
          source: ObservationSource.processExit,
          observedAt: now,
          detail: 'Pane process exited with code $exitCode',
        ),
        lastObservedAt: now,
      );
      await instanceRepository.put(updated);
      return updated;
    }

    // Active pane: capture recent terminal lines for WAITING_USER classification
    final provider = getProvider(instance.providerId);
    if (provider != null) {
      final capRes = await connection.runRemoteCommand([
        'tmux',
        'capture-pane',
        '-t',
        instance.tmuxSessionName,
        '-p',
        '-S',
        '-30',
      ]);

      if (capRes.exitCode == 0) {
        final obs = provider.outputClassifier.classify(capRes.stdout);
        if (obs.state == AgentExecutionState.waitingUser) {
          final updated = instance.copyWith(
            executionState: AgentExecutionState.waitingUser,
            observation: obs,
            lastObservedAt: now,
            isStale: false,
          );
          await instanceRepository.put(updated);
          return updated;
        } else if (obs.state != AgentExecutionState.unknown) {
          final exitCode = obs.state == AgentExecutionState.finished
              ? 0
              : (obs.state == AgentExecutionState.failed
                  ? 1
                  : instance.exitCode);
          final updated = instance.copyWith(
            executionState: obs.state,
            exitCode: exitCode,
            observation: obs,
            lastObservedAt: now,
            isStale: false,
          );
          await instanceRepository.put(updated);
          return updated;
        }
      }
    }

    // Default running state when pane is alive
    final updated = instance.copyWith(
      executionState: AgentExecutionState.running,
      observation: AgentObservation(
        state: AgentExecutionState.running,
        confidence: ObservationConfidence.confirmed,
        source: ObservationSource.paneCommand,
        observedAt: now,
        detail: 'Active pane running: $currentCmd',
      ),
      lastObservedAt: now,
      isStale: false,
    );
    await instanceRepository.put(updated);
    return updated;
  }

  Future<List<AgentInstance>> listInstances({
    required String serverId,
    String? projectId,
    bool refresh = false,
  }) async {
    final instances = projectId != null
        ? await instanceRepository.forProject(serverId, projectId)
        : await instanceRepository.forServer(serverId);

    if (!refresh || connection.connectedProfileId != serverId) {
      return instances;
    }

    final refreshed = <AgentInstance>[];
    for (final inst in instances) {
      try {
        refreshed.add(await refreshInstance(inst));
      } catch (_) {
        refreshed.add(inst);
      }
    }
    return refreshed;
  }

  Future<void> terminateInstance(
    AgentInstance instance, {
    ServerProfile? server,
  }) async {
    if (connection.connectedProfileId == instance.serverId) {
      final tmux = _getTmux(instance.serverId);
      try {
        await tmux.terminate(instance.tmuxSessionName);
      } catch (_) {}
    }

    final updated = instance.copyWith(
      executionState: AgentExecutionState.finished,
      isStale: false,
      observation: AgentObservation(
        state: AgentExecutionState.finished,
        confidence: ObservationConfidence.confirmed,
        source: ObservationSource.manual,
        observedAt: _clock().toUtc(),
        detail: 'Agent terminated by user',
      ),
      lastObservedAt: _clock().toUtc(),
    );
    await instanceRepository.put(updated);
  }
}
