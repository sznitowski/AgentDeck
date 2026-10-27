// Disposable loopback OpenSSH + tmux + Agent Orchestration integration lab.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:agentdeck/core/domain/agents.dart';
import 'package:agentdeck/core/domain/profiles.dart';
import 'package:agentdeck/core/domain/remote_contracts.dart';
import 'package:agentdeck/core/infrastructure/json_file_store.dart';
import 'package:agentdeck/features/agents/application/agent_coordinator.dart';
import 'package:agentdeck/features/agents/infrastructure/file_agent_instance_repository.dart';
import 'package:agentdeck/features/agents/providers/fake_agent_provider.dart';
import 'package:agentdeck/features/connections/application/ssh_connection_service.dart';
import 'package:agentdeck/features/connections/domain/ssh_models.dart';
import 'package:agentdeck/features/connections/infrastructure/dart_ssh_transport.dart';
import 'package:agentdeck/features/terminal/application/terminal_controller.dart';
import 'package:agentdeck/features/tmux/application/tmux_service.dart';
import 'package:agentdeck/features/tmux/infrastructure/file_tmux_session_repository.dart';

class _Secrets implements SecureCredentialStore {
  _Secrets(this.secret);
  final List<int> secret;
  @override
  Future<List<int>?> get(String reference) async => secret;
  @override
  Future<void> put(String reference, List<int> value) async =>
      throw UnsupportedError('Lab');
  @override
  Future<void> delete(String reference) async => throw UnsupportedError('Lab');
}

class _Hosts implements KnownHostRepository {
  _Hosts(this.host);
  final KnownHost host;
  @override
  Future<KnownHost?> find(String hostname, int port) async => host;
  @override
  Future<void> markSeen(String hostname, int port, DateTime at) async {}
  @override
  Future<void> trust(KnownHost host) async => throw UnsupportedError('Lab');
  @override
  Future<void> revoke(String hostname, int port) async =>
      throw UnsupportedError('Lab');
  @override
  Future<void> replace(KnownHost host) async => throw UnsupportedError('Lab');
  @override
  Future<void> delete(String hostname, int port) async =>
      throw UnsupportedError('Lab');
}

Future<void> main() async {
  final env = Platform.environment;
  final host = env['AGENTDECK_TEST_SSH_HOST'];
  final port = int.tryParse(env['AGENTDECK_TEST_SSH_PORT'] ?? '');
  final password = env['AGENTDECK_TEST_SSH_PASSWORD'];
  final fingerprint = env['AGENTDECK_TEST_SSH_FINGERPRINT'];
  if (host == null ||
      !{'127.0.0.1', 'localhost', '::1'}.contains(host) ||
      port == null ||
      port < 1 ||
      port > 65535 ||
      password == null ||
      fingerprint == null) {
    stderr.writeln(
        'Disposable loopback SSH credentials and pinned fingerprint required.');
    exitCode = 2;
    return;
  }

  final profile = ServerProfile(
    id: 'agent-lab',
    name: 'Agent Lab',
    host: host,
    port: port,
    username: 'lab',
    credentialId: 'lab',
    authenticationMethod: SshAuthenticationMethod.password,
  );

  final project = ProjectProfile(
    id: 'test-proj',
    name: 'Lab Project',
    serverId: profile.id,
    workingDirectory: '/home/lab',
    environment: Environment.development,
    executionPolicy:
        const ExecutionPolicy(environment: Environment.development),
  );

  final now = DateTime.now().toUtc();
  final known = KnownHost(
    hostname: host,
    port: port,
    identity: HostIdentity('ssh-ed25519', fingerprint),
    firstSeenAt: now,
    lastSeenAt: now,
  );

  SshConnectionService makeConnection() => SshConnectionService(
        credentials: _Secrets(utf8.encode(password)),
        knownHosts: _Hosts(known),
        transport: const DartSshTransport(),
      );

  final tempDir = await Directory.systemTemp.createTemp('agentdeck-m5-lab-');
  final tmuxRepo = FileTmuxSessionRepository(
      JsonFileStore(File('${tempDir.path}/tmux.json')));
  final instanceRepo = FileAgentInstanceRepository(
      JsonFileStore(File('${tempDir.path}/instances.json')));

  var connection = makeConnection();
  var coordinator = AgentCoordinator(
    connection: connection,
    tmuxReferences: tmuxRepo,
    instanceRepository: instanceRepo,
    providers: {
      'fake-agent': const FakeAgentProvider(),
    },
  );

  TerminalController? terminal;
  StreamSubscription<String>? sub;
  var output = '';

  Future<void> waitFor(String marker) async {
    final deadline = DateTime.now().add(const Duration(seconds: 10));
    while (!output.contains(marker)) {
      if (DateTime.now().isAfter(deadline)) {
        throw StateError('Marker timeout: $marker (output: "$output")');
      }
      await Future<void>.delayed(const Duration(milliseconds: 40));
    }
  }

  try {
    // -------------------------------------------------------------
    // Scenario A: Provider discovery
    // -------------------------------------------------------------
    await connection.connect(profile);
    final definitions = await coordinator.discoverAgents(profile.id);
    final fakeDef = definitions.firstWhere((d) => d.providerId == 'fake-agent');
    if (!fakeDef.isAvailable) {
      throw StateError('A: FakeAgent not discovered as AVAILABLE');
    }
    stdout.writeln('A provider discovery (fake-agent available): PASS');

    // -------------------------------------------------------------
    // Scenario B: Version detection
    // -------------------------------------------------------------
    if (fakeDef.version != '1.0.0-lab') {
      throw StateError(
          'B: Version mismatch: expected 1.0.0-lab, got ${fakeDef.version}');
    }
    stdout.writeln('B version detection (${fakeDef.version}): PASS');

    // -------------------------------------------------------------
    // Scenario C: Launch agent in background running mode
    // -------------------------------------------------------------
    final fakeProvider = const FakeAgentProvider();
    final runningInstance = await coordinator.launch(
      server: profile,
      project: project,
      provider: fakeProvider,
      extraArgs: ['running'],
    );
    if (!runningInstance.tmuxSessionName
        .startsWith('ad_agent_fake-agent_test-proj_')) {
      throw StateError(
          'C: Session name invalid: ${runningInstance.tmuxSessionName}');
    }
    stdout.writeln(
        'C launch agent in tmux session (${runningInstance.tmuxSessionName}): PASS');

    // -------------------------------------------------------------
    // Scenario D: Running state observation
    // -------------------------------------------------------------
    await Future<void>.delayed(const Duration(milliseconds: 500));
    final obsRunning = await coordinator.refreshInstance(runningInstance);
    if (obsRunning.executionState != AgentExecutionState.running) {
      throw StateError(
          'D: Expected running state, got ${obsRunning.executionState}');
    }
    stdout.writeln('D running state observation: PASS');

    // -------------------------------------------------------------
    // Scenario E: Waiting-user inference
    // -------------------------------------------------------------
    final waitingInstance = await coordinator.launch(
      server: profile,
      project: project,
      provider: fakeProvider,
      extraArgs: ['waiting'],
    );
    await Future<void>.delayed(const Duration(milliseconds: 800));
    final obsWaiting = await coordinator.refreshInstance(waitingInstance);
    if (obsWaiting.executionState != AgentExecutionState.waitingUser) {
      throw StateError(
          'E: Expected waitingUser state, got ${obsWaiting.executionState}');
    }
    stdout.writeln('E waiting-user inference: PASS');

    // -------------------------------------------------------------
    // Scenario F: Terminal attach and interaction
    // -------------------------------------------------------------
    final tmux = TmuxService(
      connection: connection,
      references: tmuxRepo,
      serverId: profile.id,
    );

    terminal = TerminalController(
      connection,
      openSession: (cols, rows) =>
          tmux.attach(waitingInstance.tmuxSessionName, cols, rows),
    );
    sub = terminal.output.listen((chunk) => output += chunk);
    await terminal.open(columns: 80, rows: 24);
    await Future<void>.delayed(const Duration(milliseconds: 300));
    await waitFor('[WAITING_USER]');

    output = '';
    await terminal.send('start-work\n');
    await waitFor('[RUNNING] User instructed: start-work');
    stdout.writeln('F terminal attach & interactive input: PASS');

    // -------------------------------------------------------------
    // Scenario G: Detach PTY
    // -------------------------------------------------------------
    await terminal.close();
    await sub.cancel();
    terminal = null;
    sub = null;
    await Future<void>.delayed(const Duration(milliseconds: 500));

    final afterDetach = await coordinator.refreshInstance(waitingInstance);
    if (afterDetach.executionState != AgentExecutionState.running) {
      throw StateError('G: Agent died after detach');
    }
    stdout.writeln('G detach retains background execution: PASS');

    // -------------------------------------------------------------
    // Scenario H: SSH disconnect while agent runs
    // -------------------------------------------------------------
    await connection.disconnect();
    await Future<void>.delayed(const Duration(seconds: 2));
    stdout.writeln('H SSH connection drop: PASS');

    // -------------------------------------------------------------
    // Scenario I: Reconnect & discover instance
    // -------------------------------------------------------------
    connection = makeConnection();
    coordinator = AgentCoordinator(
      connection: connection,
      tmuxReferences: tmuxRepo,
      instanceRepository: instanceRepo,
      providers: {
        'fake-agent': const FakeAgentProvider(),
      },
    );
    await connection.connect(profile);

    final discoveredInstances = await coordinator.listInstances(
      serverId: profile.id,
      projectId: project.id,
      refresh: true,
    );
    if (!discoveredInstances.any((i) =>
        i.id == waitingInstance.id &&
        i.executionState == AgentExecutionState.running)) {
      throw StateError('I: Instance not found or not running after reconnect');
    }
    stdout.writeln('I reconnect and discover running agent: PASS');

    // -------------------------------------------------------------
    // Scenario J: Resume session
    // -------------------------------------------------------------
    terminal = TerminalController(
      connection,
      openSession: (cols, rows) => TmuxService(
              connection: connection,
              references: tmuxRepo,
              serverId: profile.id)
          .attach(waitingInstance.tmuxSessionName, cols, rows),
    );
    output = '';
    sub = terminal.output.listen((chunk) => output += chunk);
    await terminal.open(columns: 80, rows: 24);
    await Future<void>.delayed(const Duration(milliseconds: 400));
    await terminal.close();
    await sub.cancel();
    terminal = null;
    sub = null;
    stdout.writeln('J resume session: PASS');

    // -------------------------------------------------------------
    // Scenario K: Successful exit detection (exit code 0 -> FINISHED)
    // -------------------------------------------------------------
    final successInstance = await coordinator.launch(
      server: profile,
      project: project,
      provider: fakeProvider,
      extraArgs: ['success'],
    );
    await Future<void>.delayed(const Duration(milliseconds: 600));
    final obsSuccess = await coordinator.refreshInstance(successInstance);
    if (obsSuccess.executionState != AgentExecutionState.finished ||
        obsSuccess.exitCode != 0) {
      throw StateError(
          'K: Expected finished with exit 0, got ${obsSuccess.executionState} (${obsSuccess.exitCode})');
    }
    stdout.writeln('K successful exit detection (exit 0 -> FINISHED): PASS');

    // -------------------------------------------------------------
    // Scenario L: Failure exit detection (exit code 1 -> FAILED)
    // -------------------------------------------------------------
    final failInstance = await coordinator.launch(
      server: profile,
      project: project,
      provider: fakeProvider,
      extraArgs: ['fail'],
    );
    await Future<void>.delayed(const Duration(milliseconds: 600));
    final obsFail = await coordinator.refreshInstance(failInstance);
    if (obsFail.executionState != AgentExecutionState.failed ||
        obsFail.exitCode != 1) {
      throw StateError(
          'L: Expected failed with exit 1, got ${obsFail.executionState} (${obsFail.exitCode})');
    }
    stdout.writeln('L failure exit detection (exit 1 -> FAILED): PASS');

    // -------------------------------------------------------------
    // Scenario M: Terminate agent session
    // -------------------------------------------------------------
    await coordinator.terminateInstance(runningInstance);
    await coordinator.terminateInstance(waitingInstance);
    await coordinator.terminateInstance(successInstance);
    await coordinator.terminateInstance(failInstance);

    final listAfterTerm = await TmuxService(
      connection: connection,
      references: tmuxRepo,
      serverId: profile.id,
    ).list();
    if (listAfterTerm
        .any((s) => s.remoteName == runningInstance.tmuxSessionName)) {
      throw StateError('M: Terminated session still present in tmux');
    }
    stdout.writeln('M terminate instance & kill session: PASS');

    // -------------------------------------------------------------
    // Scenario N: Stale instance detection
    // -------------------------------------------------------------
    final staleInstance = AgentInstance(
      id: 'ad_agent_fake-agent_test-proj_stale99',
      providerId: 'fake-agent',
      serverId: profile.id,
      projectId: project.id,
      tmuxSessionName: 'ad_agent_fake-agent_test-proj_stale99',
      workingDirectory: project.workingDirectory,
      startedAt: now,
      lastObservedAt: now,
    );
    await instanceRepo.put(staleInstance);

    final obsStale = await coordinator.refreshInstance(staleInstance);
    if (!obsStale.isStale) {
      throw StateError(
          'N: Instance not marked as stale when tmux session is absent');
    }
    stdout.writeln('N stale instance detection: PASS');
  } catch (error, stack) {
    stderr.writeln('M5 Agents lab failed: $error');
    stderr.writeln(stack);
    exitCode = 1;
  } finally {
    await sub?.cancel();
    await terminal?.close();
    await connection.dispose();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  }
}
