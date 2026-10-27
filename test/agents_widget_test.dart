import 'dart:async';
import 'dart:convert';

import 'package:agentdeck/core/domain/agents.dart';
import 'package:agentdeck/core/domain/profiles.dart';
import 'package:agentdeck/core/domain/remote_contracts.dart';
import 'package:agentdeck/features/agents/agents_page.dart';
import 'package:agentdeck/features/agents/application/agent_coordinator.dart';
import 'package:agentdeck/features/agents/presentation/agent_detail_page.dart';
import 'package:agentdeck/features/agents/providers/codex_provider.dart';
import 'package:agentdeck/features/agents/providers/fake_agent_provider.dart';
import 'package:agentdeck/features/connections/application/ssh_connection_service.dart';
import 'package:agentdeck/features/connections/domain/ssh_models.dart';
import 'package:agentdeck/features/servers/domain/server_profile_repository.dart';
import 'package:agentdeck/features/tmux/domain/tmux_models.dart';
import 'package:flutter/material.dart' hide ConnectionState;
import 'package:flutter_test/flutter_test.dart';

class _FakeSecrets implements SecureCredentialStore {
  @override
  Future<List<int>?> get(String reference) async => utf8.encode('secret');
  @override
  Future<void> put(String reference, List<int> value) async {}
  @override
  Future<void> delete(String reference) async {}
}

class _FakeHosts implements KnownHostRepository {
  @override
  Future<KnownHost?> find(String hostname, int port) async => null;
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
  final doneSignal = Completer<void>();

  @override
  Future<void> get done => doneSignal.future;

  @override
  Future<void> close() async {
    if (!doneSignal.isCompleted) doneSignal.complete();
  }

  @override
  Future<TerminalSession> openTerminal(int columns, int rows) =>
      throw UnsupportedError('Not used');

  @override
  Future<TerminalSession> attachTmux(
          String sessionName, int columns, int rows) =>
      throw UnsupportedError('Not used');

  @override
  Future<RemoteCommandResult> run(List<String> command,
      {Duration timeout = const Duration(seconds: 10)}) async {
    return const RemoteCommandResult(0, '', '');
  }
}

class _FakeTransport implements SshTransport {
  @override
  Future<SshTransportHandle> open(
    ServerProfile profile,
    SshCredential credential,
    Future<bool> Function(String algorithm, String fingerprint) verifyHostKey,
    SshTimeouts timeouts,
  ) async {
    await verifyHostKey(
        'ssh-ed25519', 'SHA256:AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA');
    return _FakeHandle();
  }
}

class _InMemoryInstanceRepo implements AgentInstanceRepository {
  final Map<String, AgentInstance> _items = {};

  @override
  Future<List<AgentInstance>> all() async => _items.values.toList();

  @override
  Future<List<AgentInstance>> forServer(String serverId) async =>
      _items.values.where((i) => i.serverId == serverId).toList();

  @override
  Future<List<AgentInstance>> forProject(
          String serverId, String projectId) async =>
      _items.values
          .where((i) => i.serverId == serverId && i.projectId == projectId)
          .toList();

  @override
  Future<AgentInstance?> find(String id) async => _items[id];

  @override
  Future<void> put(AgentInstance instance) async {
    _items[instance.id] = instance;
  }

  @override
  Future<void> delete(String id) async {
    _items.remove(id);
  }

  @override
  Future<void> readCheck() async {}
}

class _InMemoryServerRepo implements ServerProfileRepository {
  final Map<String, ServerProfile> _servers = {};

  @override
  Future<List<ServerProfile>> all() async => _servers.values.toList();

  @override
  Future<ServerProfile?> find(String id) async => _servers[id];

  @override
  Future<void> save(ServerProfile profile) async {
    _servers[profile.id] = profile;
  }

  @override
  Future<void> delete(String id) async {
    _servers.remove(id);
  }
}

class _InMemoryTmuxRepo implements TmuxSessionRepository {
  final List<TmuxSessionReference> _refs = [];

  @override
  Future<List<TmuxSessionReference>> forServer(String serverId) async =>
      _refs.where((r) => r.serverId == serverId).toList();

  @override
  Future<void> save(TmuxSessionReference reference) async {
    _refs.removeWhere((r) =>
        r.serverId == reference.serverId &&
        r.remoteName == reference.remoteName);
    _refs.add(reference);
  }

  @override
  Future<void> delete(String serverId, String remoteName) async {
    _refs.removeWhere(
        (r) => r.serverId == serverId && r.remoteName == remoteName);
  }

  @override
  Future<void> deleteServer(String serverId) async {
    _refs.removeWhere((r) => r.serverId == serverId);
  }

  @override
  Future<void> readCheck() async {}
}

void main() {
  late _InMemoryInstanceRepo instanceRepo;
  late _InMemoryTmuxRepo tmuxRepo;
  late _InMemoryServerRepo serverRepo;
  late SshConnectionService connection;
  late AgentCoordinator coordinator;

  setUp(() async {
    instanceRepo = _InMemoryInstanceRepo();
    tmuxRepo = _InMemoryTmuxRepo();
    serverRepo = _InMemoryServerRepo();

    connection = SshConnectionService(
      credentials: _FakeSecrets(),
      knownHosts: _FakeHosts(),
      transport: _FakeTransport(),
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
  });

  tearDown(() async {
    await connection.dispose();
  });

  testWidgets('AgentsPage renders summary cards and instances', (tester) async {
    final now = DateTime.now().toUtc();
    await serverRepo.save(const ServerProfile(
      id: 'srv-1',
      name: 'Production VPS',
      host: '10.0.0.1',
      username: 'root',
      credentialId: 'c1',
      environment: Environment.production,
    ));

    await instanceRepo.put(AgentInstance(
      id: 'inst-1',
      providerId: 'codex',
      serverId: 'srv-1',
      projectId: 'p1',
      tmuxSessionName: 'ad_agent_codex_p1_1234',
      workingDirectory: '/var/www',
      displayName: 'OpenAI Codex (p1)',
      executionState: AgentExecutionState.running,
      startedAt: now,
      lastObservedAt: now,
    ));

    await tester.pumpWidget(
      MaterialApp(
        home: AgentsPage(
          coordinator: coordinator,
          serverProfiles: serverRepo,
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.text('Agents'), findsOneWidget);
    expect(find.text('Running'), findsOneWidget);
    expect(find.text('Waiting User'), findsOneWidget);
    expect(find.text('1 active'), findsOneWidget);
    expect(find.text('OpenAI Codex (p1)'), findsOneWidget);
    expect(find.text('Open'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('AgentDetailPage displays status and terminate confirmation',
      (tester) async {
    final now = DateTime.now().toUtc();
    const prodServer = ServerProfile(
      id: 'srv-prod',
      name: 'PROD-ALPHA',
      host: '10.0.0.1',
      username: 'root',
      credentialId: 'c1',
      environment: Environment.production,
    );
    await serverRepo.save(prodServer);

    final instance = AgentInstance(
      id: 'inst-detail',
      providerId: 'codex',
      serverId: 'srv-prod',
      projectId: 'proj-x',
      tmuxSessionName: 'ad_agent_codex_proj_x_9999',
      workingDirectory: '/var/docker/app',
      displayName: 'Codex (proj-x)',
      executionState: AgentExecutionState.waitingUser,
      observation: AgentObservation(
        state: AgentExecutionState.waitingUser,
        confidence: ObservationConfidence.inferred,
        source: ObservationSource.terminalPattern,
        observedAt: now,
        detail: 'Waiting on approval',
      ),
      startedAt: now,
      lastObservedAt: now,
    );
    await instanceRepo.put(instance);

    await tester.pumpWidget(
      MaterialApp(
        home: AgentDetailPage(
          instance: instance,
          coordinator: coordinator,
          serverProfiles: serverRepo,
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.text('Codex (proj-x)'), findsOneWidget);
    expect(find.text('PRODUCTION SERVER'), findsOneWidget);
    expect(find.text('WAITINGUSER'), findsOneWidget);
    expect(find.text('Agent is waiting for user input or approval.'),
        findsOneWidget);
    expect(find.text('Open Terminal'), findsOneWidget);
    expect(find.text('Terminate'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
  });
}
