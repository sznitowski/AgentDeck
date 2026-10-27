import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:agentdeck/core/domain/agents.dart';
import 'package:agentdeck/core/domain/profiles.dart';
import 'package:agentdeck/core/domain/remote_contracts.dart';
import 'package:agentdeck/core/infrastructure/json_file_store.dart';
import 'package:agentdeck/features/agents/application/agent_coordinator.dart';
import 'package:agentdeck/features/agents/infrastructure/file_agent_instance_repository.dart';
import 'package:agentdeck/features/agents/providers/codex_provider.dart';
import 'package:agentdeck/features/agents/providers/fake_agent_provider.dart';
import 'package:agentdeck/features/connections/application/ssh_connection_service.dart';
import 'package:agentdeck/features/connections/domain/ssh_models.dart';
import 'package:agentdeck/features/tmux/infrastructure/file_tmux_session_repository.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeSecrets implements SecureCredentialStore {
  _FakeSecrets(this.secret);
  final List<int> secret;
  @override
  Future<List<int>?> get(String reference) async => secret;
  @override
  Future<void> put(String reference, List<int> value) async {}
  @override
  Future<void> delete(String reference) async {}
}

class _FakeHosts implements KnownHostRepository {
  _FakeHosts(this.host);
  final KnownHost host;
  @override
  Future<KnownHost?> find(String hostname, int port) async => host;
  @override
  Future<void> markSeen(String hostname, int port, DateTime at) async {}
  @override
  Future<void> trust(KnownHost host) async {}
  @override
  Future<void> revoke(String hostname, int port) async {}
  @override
  Future<void> replace(KnownHost host) async {}
  @override
  Future<void> delete(String hostname, int port) async {}
}

class _FakeHandle implements SshTmuxTransportHandle {
  _FakeHandle(this.commands);
  final Map<String, RemoteCommandResult> commands;
  final doneSignal = Completer<void>();

  @override
  Future<void> get done => doneSignal.future;

  @override
  Future<void> close() async {
    if (!doneSignal.isCompleted) doneSignal.complete();
  }

  @override
  Future<TerminalSession> openTerminal(int columns, int rows) =>
      throw UnsupportedError('Not used in test');

  @override
  Future<TerminalSession> attachTmux(
          String sessionName, int columns, int rows) =>
      throw UnsupportedError('Not used in test');

  final activeSessions = <String>{};

  @override
  Future<RemoteCommandResult> run(List<String> command,
      {Duration timeout = const Duration(seconds: 10)}) async {
    final key = command.join(' ');
    for (final entry in commands.entries) {
      if (key == entry.key || key.startsWith(entry.key)) {
        return entry.value;
      }
    }

    if (command.contains('new-session')) {
      final sIdx = command.indexOf('-s');
      if (sIdx != -1 && sIdx + 1 < command.length) {
        activeSessions.add(command[sIdx + 1]);
      }
      return const RemoteCommandResult(0, '', '');
    }

    if (command.contains('list-sessions')) {
      final out = activeSessions.map((s) => '$s:0:1700000000').join('\n') +
          (activeSessions.isNotEmpty ? '\n' : '');
      return RemoteCommandResult(0, out, '');
    }

    if (command.contains('kill-session')) {
      final tIdx = command.indexOf('-t');
      if (tIdx != -1 && tIdx + 1 < command.length) {
        activeSessions.remove(command[tIdx + 1]);
      }
      return const RemoteCommandResult(0, '', '');
    }

    return const RemoteCommandResult(1, '', 'command not found');
  }
}

class _FakeTransport implements SshTransport {
  _FakeTransport(this.commands);
  final Map<String, RemoteCommandResult> commands;

  @override
  Future<SshTransportHandle> open(
    ServerProfile profile,
    SshCredential credential,
    Future<bool> Function(String algorithm, String fingerprint) verifyHostKey,
    SshTimeouts timeouts,
  ) async {
    await verifyHostKey(
        'ssh-ed25519', 'SHA256:AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA');
    return _FakeHandle(commands);
  }
}

void main() {
  late Directory tempDir;
  late FileAgentInstanceRepository instanceRepo;
  late FileTmuxSessionRepository tmuxRepo;
  late SshConnectionService connection;
  late AgentCoordinator coordinator;
  late ServerProfile server;
  late ProjectProfile project;
  final commandMap = <String, RemoteCommandResult>{};

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('agentdeck_coord_test_');
    final iFile = File('${tempDir.path}/instances.json');
    final tFile = File('${tempDir.path}/tmux.json');
    instanceRepo = FileAgentInstanceRepository(JsonFileStore(iFile));
    tmuxRepo = FileTmuxSessionRepository(JsonFileStore(tFile));

    server = const ServerProfile(
      id: 'srv-1',
      name: 'Test Server',
      host: '127.0.0.1',
      username: 'lab',
      credentialId: 'cred-1',
    );

    project = ProjectProfile(
      id: 'proj-1',
      name: 'Backend Service',
      serverId: server.id,
      workingDirectory: '/var/docker/backend',
      environment: Environment.development,
      executionPolicy:
          const ExecutionPolicy(environment: Environment.development),
    );

    final known = KnownHost(
      hostname: '127.0.0.1',
      port: 22,
      identity: HostIdentity(
          'ssh-ed25519', 'SHA256:AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA'),
      firstSeenAt: DateTime.now().toUtc(),
      lastSeenAt: DateTime.now().toUtc(),
    );

    connection = SshConnectionService(
      credentials: _FakeSecrets(utf8.encode('secret')),
      knownHosts: _FakeHosts(known),
      transport: _FakeTransport(commandMap),
    );

    coordinator = AgentCoordinator(
      connection: connection,
      tmuxReferences: tmuxRepo,
      instanceRepository: instanceRepo,
      providers: {
        'codex': const CodexProvider(),
        'fake-agent': const FakeAgentProvider(),
      },
    );

    commandMap.clear();
  });

  tearDown(() async {
    await connection.dispose();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test(
      'discoverAgents queries availability and version over connected transport',
      () async {
    commandMap['command -v codex'] =
        const RemoteCommandResult(0, '/usr/bin/codex\n', '');
    commandMap['codex --version'] =
        const RemoteCommandResult(0, 'codex 0.4.12\n', '');
    commandMap['command -v agentdeck-fake-agent'] =
        const RemoteCommandResult(1, '', 'not found');

    await connection.connect(server);

    final defs = await coordinator.discoverAgents(server.id);
    expect(defs.length, 2);

    final codexDef = defs.firstWhere((d) => d.providerId == 'codex');
    expect(codexDef.isAvailable, isTrue);
    expect(codexDef.version, '0.4.12');

    final fakeDef = defs.firstWhere((d) => d.providerId == 'fake-agent');
    expect(fakeDef.isAvailable, isFalse);
    expect(fakeDef.version, isNull);
  });

  test('launch creates tmux session and persists agent instance', () async {
    await connection.connect(server);

    final provider = const CodexProvider();
    final instance = await coordinator.launch(
      server: server,
      project: project,
      provider: provider,
    );

    expect(instance.providerId, 'codex');
    expect(instance.serverId, server.id);
    expect(instance.projectId, project.id);
    expect(instance.workingDirectory, '/var/docker/backend');
    expect(instance.tmuxSessionName, startsWith('ad_agent_codex_proj-1_'));
    expect(instance.executionState, AgentExecutionState.running);

    final inRepo = await instanceRepo.find(instance.id);
    expect(inRepo, isNotNull);
    expect(inRepo?.id, instance.id);
  });

  test('refreshInstance updates status based on tmux pane dead status',
      () async {
    final now = DateTime.now().toUtc();
    final instance = AgentInstance(
      id: 'ad_agent_fake_1',
      providerId: 'fake-agent',
      serverId: server.id,
      projectId: project.id,
      tmuxSessionName: 'ad_agent_fake_1',
      workingDirectory: project.workingDirectory,
      startedAt: now,
      lastObservedAt: now,
    );
    await instanceRepo.put(instance);

    await connection.connect(server);

    // Session exists
    commandMap['tmux list-sessions'] = RemoteCommandResult(
      0,
      '${instance.tmuxSessionName}:0:${now.millisecondsSinceEpoch ~/ 1000}\n',
      '',
    );

    // Case 1: Pane dead with exit code 0 -> finished
    commandMap['tmux list-panes -t ${instance.tmuxSessionName}'] =
        const RemoteCommandResult(0, '1234:sh:1:0\n', '');

    final finished = await coordinator.refreshInstance(instance);
    expect(finished.executionState, AgentExecutionState.finished);
    expect(finished.exitCode, 0);
    expect(finished.observation?.confidence, ObservationConfidence.confirmed);

    // Case 2: Pane dead with exit code 1 -> failed
    commandMap['tmux list-panes -t ${instance.tmuxSessionName}'] =
        const RemoteCommandResult(0, '1234:sh:1:1\n', '');

    final failed = await coordinator.refreshInstance(instance);
    expect(failed.executionState, AgentExecutionState.failed);
    expect(failed.exitCode, 1);
  });

  test('refreshInstance infers waitingUser from capture-pane output', () async {
    final now = DateTime.now().toUtc();
    final instance = AgentInstance(
      id: 'ad_agent_fake_2',
      providerId: 'fake-agent',
      serverId: server.id,
      projectId: project.id,
      tmuxSessionName: 'ad_agent_fake_2',
      workingDirectory: project.workingDirectory,
      startedAt: now,
      lastObservedAt: now,
    );
    await instanceRepo.put(instance);

    await connection.connect(server);

    commandMap['tmux list-sessions'] = RemoteCommandResult(
      0,
      '${instance.tmuxSessionName}:0:${now.millisecondsSinceEpoch ~/ 1000}\n',
      '',
    );
    commandMap['tmux list-panes -t ${instance.tmuxSessionName}'] =
        const RemoteCommandResult(0, '1234:fake-agent:0:0\n', '');
    commandMap['tmux capture-pane -t ${instance.tmuxSessionName}'] =
        const RemoteCommandResult(
      0,
      'Starting agent...\n[WAITING_USER] Please provide task\n',
      '',
    );

    final waiting = await coordinator.refreshInstance(instance);
    expect(waiting.executionState, AgentExecutionState.waitingUser);
    expect(waiting.observation?.confidence, ObservationConfidence.confirmed);
  });

  test('refreshInstance marks stale if tmux session is missing', () async {
    final now = DateTime.now().toUtc();
    final instance = AgentInstance(
      id: 'ad_agent_fake_missing',
      providerId: 'fake-agent',
      serverId: server.id,
      projectId: project.id,
      tmuxSessionName: 'ad_agent_fake_missing',
      workingDirectory: project.workingDirectory,
      startedAt: now,
      lastObservedAt: now,
    );
    await instanceRepo.put(instance);

    await connection.connect(server);

    commandMap['tmux list-sessions'] = const RemoteCommandResult(
      0,
      'other_session:0:123456\n',
      '',
    );

    final stale = await coordinator.refreshInstance(instance);
    expect(stale.isStale, isTrue);
    expect(stale.executionState, AgentExecutionState.finished);
  });
}
