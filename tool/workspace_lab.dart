import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:agentdeck/core/domain/agents.dart';
import 'package:agentdeck/core/domain/profiles.dart';
import 'package:agentdeck/core/domain/remote_contracts.dart';
import 'package:agentdeck/core/domain/workspace.dart';
import 'package:agentdeck/features/agents/application/agent_coordinator.dart';
import 'package:agentdeck/features/agents/providers/fake_agent_provider.dart';
import 'package:agentdeck/features/connections/application/ssh_connection_service.dart';
import 'package:agentdeck/features/connections/domain/ssh_models.dart';
import 'package:agentdeck/features/connections/infrastructure/dart_ssh_transport.dart';
import 'package:agentdeck/features/files/application/remote_file_service.dart';
import 'package:agentdeck/features/git/application/git_service.dart';
import 'package:agentdeck/features/git/infrastructure/ssh_git_command_executor.dart';
import 'package:agentdeck/features/projects/application/project_workspace_coordinator.dart';
import 'package:agentdeck/features/servers/application/server_operations_service.dart';
import 'package:agentdeck/features/servers/domain/server_profile_repository.dart';
import 'package:agentdeck/features/servers/infrastructure/ssh_server_command_executor.dart';
import 'package:agentdeck/features/tmux/domain/tmux_models.dart';

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

class _MemServerRepo implements ServerProfileRepository {
  _MemServerRepo(this.server);
  final ServerProfile server;
  @override
  Future<List<ServerProfile>> all() async => [server];
  @override
  Future<ServerProfile?> find(String id) async =>
      id == server.id ? server : null;
  @override
  Future<void> save(ServerProfile profile) async {}
  @override
  Future<void> delete(String id) async {}
  Future<void> readCheck() async {}
}

class _MemAgentRepo implements AgentInstanceRepository {
  final Map<String, AgentInstance> _instances = {};
  @override
  Future<List<AgentInstance>> all() async => _instances.values.toList();
  @override
  Future<List<AgentInstance>> forProject(
          String serverId, String projectId) async =>
      _instances.values
          .where((i) => i.serverId == serverId && i.projectId == projectId)
          .toList();
  @override
  Future<List<AgentInstance>> forServer(String serverId) async =>
      _instances.values.where((i) => i.serverId == serverId).toList();
  @override
  Future<AgentInstance?> find(String id) async => _instances[id];
  @override
  Future<void> put(AgentInstance instance) async =>
      _instances[instance.id] = instance;
  @override
  Future<void> delete(String id) async => _instances.remove(id);
  @override
  Future<void> readCheck() async {}
}

class _MemTmuxRepo implements TmuxSessionRepository {
  final Map<String, TmuxSessionReference> _refs = {};
  @override
  Future<List<TmuxSessionReference>> forServer(String serverId) async =>
      _refs.values.where((r) => r.serverId == serverId).toList();
  @override
  Future<void> save(TmuxSessionReference reference) async =>
      _refs['${reference.serverId}:${reference.remoteName}'] = reference;
  @override
  Future<void> delete(String serverId, String remoteName) async =>
      _refs.remove('$serverId:$remoteName');
  @override
  Future<void> deleteServer(String serverId) async =>
      _refs.removeWhere((k, _) => k.startsWith('$serverId:'));
  @override
  Future<void> readCheck() async {}
}

void main() async {
  final host = Platform.environment['AGENTDECK_TEST_SSH_HOST'] ?? '127.0.0.1';
  final portStr = Platform.environment['AGENTDECK_TEST_SSH_PORT'];
  final password = Platform.environment['AGENTDECK_TEST_SSH_PASSWORD'];
  final fingerprint = Platform.environment['AGENTDECK_TEST_SSH_FINGERPRINT'];

  if (portStr == null || password == null || fingerprint == null) {
    stderr.writeln('Environment variables missing for Workspace lab');
    exit(1);
  }

  final port = int.parse(portStr);
  final credentials = _Secrets(utf8.encode(password));
  final knownHosts = _Hosts(KnownHost(
    hostname: host,
    port: port,
    identity: HostIdentity('ssh-ed25519', fingerprint),
    firstSeenAt: DateTime.now().toUtc(),
    lastSeenAt: DateTime.now().toUtc(),
  ));
  final transport = const DartSshTransport();

  const credId = 'cred_lab';
  final server = ServerProfile(
    id: 'srv_lab',
    name: 'Docker Alpine Lab',
    host: host,
    port: port,
    username: 'lab',
    credentialId: credId,
    environment: Environment.production,
  );

  final connection = SshConnectionService(
    credentials: credentials,
    knownHosts: knownHosts,
    transport: transport,
  );

  final serverRepo = _MemServerRepo(server);
  final agentRepo = _MemAgentRepo();
  final tmuxRepo = _MemTmuxRepo();

  final agentCoordinator = AgentCoordinator(
    connection: connection,
    tmuxReferences: tmuxRepo,
    instanceRepository: agentRepo,
  );

  final gitService = RemoteGitService(
    executor: SshGitCommandExecutor(
      connection: connection,
      serverId: server.id,
    ),
  );

  final serverOpsService = RemoteServerOperationsService(
    executor: SshServerCommandExecutor(
      connection: connection,
      serverId: server.id,
    ),
  );

  final fileService = RemoteFileService(
    connection: connection,
    serverId: server.id,
  );

  final coordinator = ProjectWorkspaceCoordinator(
    connection: connection,
    servers: serverRepo,
    agents: agentCoordinator,
    gitService: gitService,
    serverOpsService: serverOpsService,
    fileService: fileService,
  );

  final results = <String, bool>{};

  try {
    // 0. Connect SSH
    await connection.connect(server);

    // Prepare test directory on remote Linux host
    const workDir = '/home/lab/project_main';
    await connection.runRemoteCommand(['rm', '-rf', workDir]);
    await connection.runRemoteCommand(['mkdir', '-p', workDir]);
    await connection.runRemoteCommand(
        ['git', 'config', '--global', 'user.name', 'Lab User']);
    await connection.runRemoteCommand(
        ['git', 'config', '--global', 'user.email', 'lab@agentdeck.local']);
    await connection.runRemoteCommand(
        ['git', 'config', '--global', 'init.defaultBranch', 'main']);

    await connection.runRemoteCommand(['git', '-C', workDir, 'init']);
    await connection.runRemoteCommand(
        ['sh', '-c', 'echo "Hello AgentDeck" > $workDir/file.txt']);
    await connection
        .runRemoteCommand(['git', '-C', workDir, 'add', 'file.txt']);
    await connection.runRemoteCommand(
        ['git', '-C', workDir, 'commit', '-m', 'Initial commit']);

    final project = const ProjectProfile(
      id: 'proj_main',
      name: 'Portal Proveedores',
      serverId: 'srv_lab',
      workingDirectory: workDir,
      environment: Environment.production,
      executionPolicy: ExecutionPolicy(environment: Environment.production),
    );

    // Scenario A: Project loads
    stdout.write('Scenario A: Project loads ... ');
    final snapA = await coordinator.inspectWorkspace(project);
    final passA =
        snapA.project.id == 'proj_main' && snapA.server?.id == 'srv_lab';
    results['A'] = passA;
    stdout.writeln(passA ? 'PASS' : 'FAIL');

    // Scenario B: SSH connected summary
    stdout.write('Scenario B: SSH connected summary ... ');
    final passB =
        snapA.isConnected && snapA.connectionState == ConnectionState.connected;
    results['B'] = passB;
    stdout.writeln(passB ? 'PASS' : 'FAIL');

    // Scenario C: Fake Agent running
    stdout.write('Scenario C: Fake Agent running ... ');
    final fakeProvider = const FakeAgentProvider();
    final agentInstance = await agentCoordinator.launch(
      server: server,
      project: project,
      provider: fakeProvider,
      extraArgs: ['running'],
    );
    // Allow process to settle in tmux
    await Future.delayed(const Duration(milliseconds: 1500));
    final snapC = await coordinator.inspectWorkspace(project);
    final passC = snapC.agent != null &&
        snapC.agent!.isRunning &&
        snapC.agent!.state == AgentExecutionState.running;
    results['C'] = passC;
    stdout.writeln(passC ? 'PASS' : 'FAIL');

    // Scenario D: Fake Agent waitingUser
    stdout.write('Scenario D: Fake Agent waitingUser ... ');
    // Manually register waiting instance to test prompt detection
    final waitingInstance = AgentInstance(
      id: 'ad_agent_fake_proj_main_wait',
      providerId: 'fake-agent',
      serverId: 'srv_lab',
      projectId: 'proj_main',
      tmuxSessionName: agentInstance.tmuxSessionName,
      workingDirectory: workDir,
      executionState: AgentExecutionState.waitingUser,
      observation: AgentObservation(
        state: AgentExecutionState.waitingUser,
        confidence: ObservationConfidence.inferred,
        source: ObservationSource.terminalPattern,
        observedAt: DateTime.now().toUtc(),
        detail: 'Please provide user instruction:',
      ),
      startedAt: DateTime.now().toUtc(),
      lastObservedAt: DateTime.now().toUtc(),
    );
    await agentRepo.put(waitingInstance);
    final snapD = await coordinator.inspectWorkspace(project);
    final passD = snapD.agent != null &&
        snapD.agent!.isWaitingUser &&
        snapD.topAttentionItem != null &&
        snapD.topAttentionItem!.type == AttentionType.agentWaiting &&
        snapD.topAttentionItem!.actionLabel == 'Respond';
    results['D'] = passD;
    stdout.writeln(passD ? 'PASS' : 'FAIL');

    // Scenario E: Git dirty state
    stdout.write('Scenario E: Git dirty state ... ');
    await connection
        .runRemoteCommand(['sh', '-c', 'echo "modified" >> $workDir/file.txt']);
    await connection.runRemoteCommand(
        ['sh', '-c', 'echo "new staged" > $workDir/staged.txt']);
    await connection
        .runRemoteCommand(['git', '-C', workDir, 'add', 'staged.txt']);
    final snapE = await coordinator.inspectWorkspace(project);
    final passE = snapE.git != null &&
        !snapE.git!.isClean &&
        snapE.git!.stagedCount >= 1 &&
        snapE.git!.unstagedCount >= 1 &&
        snapE.git!.totalChanged >= 2;
    results['E'] = passE;
    stdout.writeln(passE ? 'PASS' : 'FAIL');

    // Scenario F: Git conflict priority
    stdout.write('Scenario F: Git conflict priority ... ');
    // Commit staged and create branch conflict
    await connection
        .runRemoteCommand(['git', '-C', workDir, 'commit', '-m', 'Add staged']);
    await connection
        .runRemoteCommand(['git', '-C', workDir, 'checkout', '-b', 'branch_b']);
    await connection.runRemoteCommand(
        ['sh', '-c', 'echo "line B" > $workDir/conflict.txt']);
    await connection
        .runRemoteCommand(['git', '-C', workDir, 'add', 'conflict.txt']);
    await connection
        .runRemoteCommand(['git', '-C', workDir, 'commit', '-m', 'Commit B']);
    await connection
        .runRemoteCommand(['git', '-C', workDir, 'checkout', 'main']);
    await connection.runRemoteCommand(
        ['sh', '-c', 'echo "line A" > $workDir/conflict.txt']);
    await connection
        .runRemoteCommand(['git', '-C', workDir, 'add', 'conflict.txt']);
    await connection
        .runRemoteCommand(['git', '-C', workDir, 'commit', '-m', 'Commit A']);
    await connection.runRemoteCommand(
        ['git', '-C', workDir, 'merge', 'branch_b']); // Creates conflict
    final snapF = await coordinator.inspectWorkspace(project);
    final passF = snapF.git != null &&
        snapF.git!.conflictCount > 0 &&
        snapF.attentionItems.any((a) =>
            a.type == AttentionType.gitConflict &&
            a.severity == AttentionSeverity.critical);
    results['F'] = passF;
    stdout.writeln(passF ? 'PASS' : 'FAIL');

    // Scenario G: tmux resumable
    stdout.write('Scenario G: tmux resumable ... ');
    final passG = snapF.tmux != null &&
        snapF.tmux!.sessionName != null &&
        snapF.tmux!.isResumable;
    results['G'] = passG;
    stdout.writeln(passG ? 'PASS' : 'FAIL');

    // Scenario H: server health summary
    stdout.write('Scenario H: server health summary ... ');
    final snapH = await coordinator.inspectWorkspace(project);
    final passH = snapH.serverHealth != null &&
        snapH.serverHealth!.cpuPercent != null &&
        snapH.serverHealth!.memoryPercent != null &&
        snapH.serverHealth!.diskPercent != null &&
        snapH.serverHealth!.load1m != null;
    results['H'] = passH;
    stdout.writeln(passH ? 'PASS' : 'FAIL');

    // Scenario I: working directory accessible
    stdout.write('Scenario I: working directory accessible ... ');
    final passI = snapH.files != null &&
        snapH.files!.exists &&
        snapH.files!.workingDirectory == workDir;
    results['I'] = passI;
    stdout.writeln(passI ? 'PASS' : 'FAIL');

    // Scenario J: one module failure does not break workspace
    stdout
        .write('Scenario J: one module failure does not break workspace ... ');
    const invalidProj = ProjectProfile(
      id: 'proj_invalid',
      name: 'Invalid Project',
      serverId: 'srv_lab',
      workingDirectory: '/home/lab/nonexistent_directory_404',
      environment: Environment.development,
      executionPolicy: ExecutionPolicy(environment: Environment.development),
    );
    final snapJ = await coordinator.inspectWorkspace(invalidProj);
    final passJ = snapJ.files != null &&
        !snapJ.files!.exists &&
        snapJ.git != null &&
        snapJ.serverHealth != null &&
        snapJ.serverHealth!.isHealthy;
    results['J'] = passJ;
    stdout.writeln(passJ ? 'PASS' : 'FAIL');

    // Scenario K: SSH loss marks data stale
    stdout.write('Scenario K: SSH loss marks data stale ... ');
    await connection.disconnect();
    final snapK = await coordinator.inspectWorkspace(project);
    final passK = !snapK.isConnected &&
        snapK.connectionState == ConnectionState.disconnected &&
        snapK.git != null &&
        snapK.serverHealth != null &&
        snapK.attentionItems.any((a) =>
            a.type == AttentionType.connectionLost &&
            a.severity == AttentionSeverity.critical);
    results['K'] = passK;
    stdout.writeln(passK ? 'PASS' : 'FAIL');

    // Scenario L: reconnect refreshes all summaries
    stdout.write('Scenario L: reconnect refreshes all summaries ... ');
    await connection.connect(server);
    final snapL = await coordinator.inspectWorkspace(project);
    final passL = snapL.isConnected &&
        snapL.connectionState == ConnectionState.connected &&
        snapL.serverHealth != null &&
        snapL.git != null &&
        !snapL.attentionItems
            .any((a) => a.type == AttentionType.connectionLost);
    results['L'] = passL;
    stdout.writeln(passL ? 'PASS' : 'FAIL');

    // Print summary matrix
    stdout.writeln('\n--- M7.5 Project Workspace Lab Results ---');
    results.forEach(
        (k, v) => stdout.writeln('Scenario $k: ${v ? "PASS" : "FAIL"}'));

    final allPass = results.values.every((v) => v);
    if (!allPass) {
      exitCode = 1;
    }
  } catch (e, st) {
    stderr.writeln('Lab execution failed: $e\n$st');
    exit(1);
  } finally {
    await connection.dispose();
  }
}
