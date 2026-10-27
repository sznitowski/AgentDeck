import 'dart:convert';
import 'dart:io';

import 'package:agentdeck/core/domain/agents.dart';
import 'package:agentdeck/core/domain/events.dart';
import 'package:agentdeck/core/domain/profiles.dart';
import 'package:agentdeck/core/domain/remote_contracts.dart';
import 'package:agentdeck/core/domain/workspace.dart';
import 'package:agentdeck/core/infrastructure/json_file_store.dart';
import 'package:agentdeck/features/agents/application/agent_coordinator.dart';
import 'package:agentdeck/features/agents/infrastructure/file_agent_instance_repository.dart';
import 'package:agentdeck/features/agents/providers/fake_agent_provider.dart';
import 'package:agentdeck/features/connections/application/ssh_connection_service.dart';
import 'package:agentdeck/features/connections/domain/ssh_models.dart';
import 'package:agentdeck/features/connections/infrastructure/dart_ssh_transport.dart';
import 'package:agentdeck/features/connections/infrastructure/file_known_host_repository.dart';
import 'package:agentdeck/features/files/application/remote_file_service.dart';
import 'package:agentdeck/features/git/application/git_service.dart';
import 'package:agentdeck/features/git/infrastructure/ssh_git_command_executor.dart';
import 'package:agentdeck/features/notifications/application/event_deduplicator.dart';
import 'package:agentdeck/features/notifications/application/notification_coordinator.dart';
import 'package:agentdeck/features/notifications/application/notification_delivery_service.dart';
import 'package:agentdeck/features/notifications/application/state_transition_detector.dart';
import 'package:agentdeck/features/notifications/domain/notification_policy.dart';
import 'package:agentdeck/features/notifications/infrastructure/file_event_repository.dart';
import 'package:agentdeck/features/projects/application/project_workspace_coordinator.dart';
import 'package:agentdeck/features/projects/infrastructure/file_project_profile_repository.dart';
import 'package:agentdeck/features/servers/application/server_operations_service.dart';
import 'package:agentdeck/features/servers/infrastructure/file_server_profile_repository.dart';
import 'package:agentdeck/features/servers/infrastructure/ssh_server_command_executor.dart';
import 'package:agentdeck/features/tmux/infrastructure/file_tmux_session_repository.dart';

class _LabSecrets implements SecureCredentialStore {
  _LabSecrets(this.secret);
  final List<int> secret;
  @override
  Future<List<int>?> get(String reference) async => secret;
  @override
  Future<void> put(String reference, List<int> value) async {}
  @override
  Future<void> delete(String reference) async {}
}

void main() async {
  final host = Platform.environment['AGENTDECK_TEST_SSH_HOST'];
  final portStr = Platform.environment['AGENTDECK_TEST_SSH_PORT'];
  final password = Platform.environment['AGENTDECK_TEST_SSH_PASSWORD'];
  final fingerprint = Platform.environment['AGENTDECK_TEST_SSH_FINGERPRINT'];

  if (host == null ||
      portStr == null ||
      password == null ||
      fingerprint == null) {
    stderr.writeln('FAIL: Missing environment variables for Notifications Lab');
    exit(1);
  }

  final port = int.parse(portStr);
  final tempDir =
      await Directory.systemTemp.createTemp('agentdeck_notifications_lab_');

  stdout.writeln(
      '=== AgentDeck Milestone M8 — Notifications & Event Core Lab ===');

  try {
    // 1. Bootstrap services
    final profilesFile = File('${tempDir.path}/profiles.json');
    final knownHostsFile = File('${tempDir.path}/known_hosts.json');
    final projectsFile = File('${tempDir.path}/projects.json');
    final tmuxFile = File('${tempDir.path}/tmux.json');
    final agentsFile = File('${tempDir.path}/agents.json');
    final eventsFile = File('${tempDir.path}/events.json');

    final serverRepo = FileServerProfileRepository(JsonFileStore(profilesFile));
    final knownHostsRepo =
        FileKnownHostRepository(JsonFileStore(knownHostsFile));
    final projectRepo =
        FileProjectProfileRepository(JsonFileStore(projectsFile));
    final tmuxRepo = FileTmuxSessionRepository(JsonFileStore(tmuxFile));
    final agentRepo = FileAgentInstanceRepository(JsonFileStore(agentsFile));
    final eventRepo =
        FileEventRepository(JsonFileStore(eventsFile), maxRetention: 200);

    final credStore = _LabSecrets(utf8.encode(password));

    const server = ServerProfile(
      id: 'srv_lab_1',
      name: 'linux-docker-lab',
      host: '127.0.0.1',
      port: 22,
      username: 'lab',
      credentialId: 'cred_lab_1',
      environment: Environment.production,
    );
    await serverRepo.save(server);

    const project = ProjectProfile(
      id: 'proj_lab_1',
      name: 'Lab Notifications Project',
      serverId: 'srv_lab_1',
      workingDirectory: '/home/lab/workspace',
      environment: Environment.production,
      executionPolicy: ExecutionPolicy(environment: Environment.production),
    );
    await projectRepo.save(project);

    final connService = SshConnectionService(
      credentials: credStore,
      knownHosts: knownHostsRepo,
      transport: const DartSshTransport(),
    );

    final agentCoord = AgentCoordinator(
      connection: connService,
      tmuxReferences: tmuxRepo,
      instanceRepository: agentRepo,
      providers: {
        'fake-agent': const FakeAgentProvider(),
      },
    );

    final gitService = RemoteGitService(
      executor:
          SshGitCommandExecutor(connection: connService, serverId: server.id),
    );

    final serverOps = RemoteServerOperationsService(
      executor: SshServerCommandExecutor(
          connection: connService, serverId: server.id),
    );

    final fileService = RemoteFileService(
      connection: connService,
      serverId: server.id,
    );

    final workspaceCoord = ProjectWorkspaceCoordinator(
      connection: connService,
      servers: serverRepo,
      agents: agentCoord,
      gitService: gitService,
      serverOpsService: serverOps,
      fileService: fileService,
    );

    final transitionDetector = StateTransitionDetector(
      disconnectDebounce: const Duration(seconds: 1),
    );
    final deduplicator = EventDeduplicator();
    final policy = NotificationPolicy();
    final delivery = InAppNotificationDelivery();

    final notifCoord = NotificationCoordinator(
      repository: eventRepo,
      transitionDetector: transitionDetector,
      deduplicator: deduplicator,
      policy: policy,
      deliveryService: delivery,
    );

    // Approve host fingerprint
    final knownHost = KnownHost(
      hostname: '127.0.0.1',
      port: port,
      identity: HostIdentity('ssh-ed25519', fingerprint),
      firstSeenAt: DateTime.now().toUtc(),
      lastSeenAt: DateTime.now().toUtc(),
    );
    await knownHostsRepo.trust(knownHost);

    final connectServer = ServerProfile(
      id: server.id,
      name: server.name,
      host: '127.0.0.1',
      port: port,
      username: 'lab',
      credentialId: 'cred_lab_1',
      environment: Environment.production,
    );

    // Initial connection
    await connService.connect(connectServer);

    // Setup working directory and git repo on remote host
    await connService.runRemoteCommand([
      'sh',
      '-c',
      'mkdir -p /home/lab/workspace && cd /home/lab/workspace && git init && git config user.name "Lab" && git config user.email "lab@test.local" && git branch -M main && echo "initial" > file.txt && git add file.txt && git commit -m "init"'
    ]);

    // SCENARIO A: Agent running initial state -> 0 events
    stdout.write('Scenario A (Agent running initial state): ');
    final instanceA = await agentCoord.launch(
      server: connectServer,
      project: project,
      provider: const FakeAgentProvider(),
      extraArgs: ['running'],
    );
    await Future.delayed(const Duration(milliseconds: 1000));
    final snapA = await workspaceCoord.inspectWorkspace(project);
    final eventsA = await notifCoord.processWorkspaceSnapshot(snapA);
    if (eventsA
        .where((e) =>
            e.type == EventType.agentWaitingUser ||
            e.type == EventType.agentFailed)
        .isEmpty) {
      stdout.writeln('PASS (0 agent alert events on steady running state)');
    } else {
      stderr.writeln(
          'FAIL (Expected 0 agent alert events, got ${eventsA.length})');
      exit(1);
    }

    // SCENARIO B: Agent transitions to waitingUser -> 1 agentWaitingUser event
    stdout.write('Scenario B (Agent transitions to waitingUser): ');
    await connService.runRemoteCommand(
        ['tmux', 'kill-session', '-t', instanceA.tmuxSessionName]);
    await agentRepo.delete(instanceA.id);
    final instanceB = await agentCoord.launch(
      server: connectServer,
      project: project,
      provider: const FakeAgentProvider(),
      extraArgs: ['waiting'],
    );
    await Future.delayed(const Duration(milliseconds: 1000));
    await agentCoord.refreshInstance(instanceB);
    final snapB = await workspaceCoord.inspectWorkspace(project);
    final eventsB = await notifCoord.processWorkspaceSnapshot(snapB);
    if (eventsB.any((e) =>
        e.type == EventType.agentWaitingUser && e.actionLabel == 'Respond')) {
      stdout
          .writeln('PASS (1 agentWaitingUser event emitted with Respond CTA)');
    } else {
      stderr.writeln(
          'FAIL (Expected agentWaitingUser event, got ${eventsB.map((e) => e.type)})');
      exit(1);
    }

    // SCENARIO C: Repeated refresh while waitingUser -> 0 duplicate events
    stdout.write('Scenario C (Repeated refresh deduplication): ');
    final snapC = await workspaceCoord.inspectWorkspace(project);
    final eventsC = await notifCoord.processWorkspaceSnapshot(snapC);
    if (eventsC.where((e) => e.type == EventType.agentWaitingUser).isEmpty) {
      stdout.writeln(
          'PASS (0 duplicate agentWaitingUser events on repeated poll)');
    } else {
      stderr
          .writeln('FAIL (Deduplication failed: got ${eventsC.length} events)');
      exit(1);
    }

    // SCENARIO D: Agent transitions to failed -> 1 agentFailed critical event
    stdout.write('Scenario D (Agent transitions to failed): ');
    await connService.runRemoteCommand(
        ['tmux', 'kill-session', '-t', instanceB.tmuxSessionName]);
    await agentRepo.delete(instanceB.id);
    final instanceD = await agentCoord.launch(
      server: connectServer,
      project: project,
      provider: const FakeAgentProvider(),
      extraArgs: ['fail'],
    );
    await Future.delayed(const Duration(milliseconds: 1500));
    await agentCoord.refreshInstance(instanceD);
    final snapD = await workspaceCoord.inspectWorkspace(project);
    final eventsD = await notifCoord.processWorkspaceSnapshot(snapD);
    if (eventsD.any((e) => e.type == EventType.agentFailed)) {
      stdout.writeln('PASS (1 agentFailed critical event emitted)');
    } else {
      stderr.writeln(
          'FAIL (Expected agentFailed event, got ${eventsD.map((e) => e.type)}, snapState=${snapD.agent?.state})');
      exit(1);
    }

    // SCENARIO E: Git conflict appears -> 1 gitConflictDetected event
    stdout.write('Scenario E (Git conflict detected): ');
    await connService.runRemoteCommand([
      'sh',
      '-c',
      'cd /home/lab/workspace && git checkout -b feature && echo "feature" > file.txt && git commit -am "feature" && git checkout main && echo "main" > file.txt && git commit -am "main" && git merge feature || true'
    ]);
    final snapE = await workspaceCoord.inspectWorkspace(project);
    final eventsE = await notifCoord.processWorkspaceSnapshot(snapE);
    if (eventsE.any((e) => e.type == EventType.gitConflictDetected)) {
      stdout.writeln('PASS (1 gitConflictDetected event emitted)');
    } else {
      stderr.writeln(
          'FAIL (Expected gitConflictDetected, got ${eventsE.map((e) => e.type)})');
      exit(1);
    }

    // SCENARIO F: Git conflict remains -> 0 duplicate events
    stdout.write('Scenario F (Git conflict steady state): ');
    final snapF = await workspaceCoord.inspectWorkspace(project);
    final eventsF = await notifCoord.processWorkspaceSnapshot(snapF);
    if (eventsF.where((e) => e.type == EventType.gitConflictDetected).isEmpty) {
      stdout.writeln(
          'PASS (0 duplicate git conflict events while conflict persists)');
    } else {
      stderr
          .writeln('FAIL (Expected 0 duplicate events, got ${eventsF.length})');
      exit(1);
    }

    // SCENARIO G: Git conflict resolved -> 1 gitConflictResolved event
    stdout.write('Scenario G (Git conflict resolved): ');
    await connService.runRemoteCommand([
      'sh',
      '-c',
      'cd /home/lab/workspace && echo "resolved" > file.txt && git commit -am "resolved"'
    ]);
    final snapG = await workspaceCoord.inspectWorkspace(project);
    final eventsG = await notifCoord.processWorkspaceSnapshot(snapG);
    if (eventsG.any((e) => e.type == EventType.gitConflictResolved)) {
      stdout.writeln('PASS (1 gitConflictResolved event emitted)');
    } else {
      stderr.writeln(
          'FAIL (Expected gitConflictResolved, got ${eventsG.map((e) => e.type)})');
      exit(1);
    }

    // SCENARIO H: Sustained SSH disconnection -> 1 connectionLost event
    stdout.write('Scenario H (Sustained SSH disconnect): ');
    await connService.disconnect();
    final tDisc = DateTime.now();
    final snapH = await workspaceCoord.inspectWorkspace(project);
    // 1. Initial disconnect observation marks debounce start timestamp
    final evH1 = await notifCoord.processWorkspaceSnapshot(snapH, now: tDisc);
    // 2. Sustained disconnect past 1s debounce emits connectionLost
    final eventsH = await notifCoord.processWorkspaceSnapshot(
      snapH,
      now: tDisc.add(const Duration(seconds: 2)),
    );
    if (evH1.isEmpty &&
        eventsH.any((e) => e.type == EventType.connectionLost)) {
      stdout.writeln('PASS (1 connectionLost event emitted after debounce)');
    } else {
      stderr.writeln(
          'FAIL (Expected connectionLost event, got evH1=${evH1.map((e) => e.type)}, evH2=${eventsH.map((e) => e.type)})');
      exit(1);
    }

    // SCENARIO I: SSH Reconnected -> 1 connectionRestored event
    stdout.write('Scenario I (SSH reconnection restored): ');
    await connService.connect(connectServer);
    final snapI = await workspaceCoord.inspectWorkspace(project);
    final eventsI = await notifCoord.processWorkspaceSnapshot(snapI);
    if (eventsI.any((e) => e.type == EventType.connectionRestored)) {
      stdout.writeln('PASS (1 connectionRestored event emitted)');
    } else {
      stderr.writeln('FAIL (Expected connectionRestored event)');
      exit(1);
    }

    // SCENARIO J: Server resource crosses critical threshold (simulated 93%) -> 1 serverResourceCritical
    stdout.write('Scenario J (Server resource spike >= 90%): ');
    const simServer = ServerProfile(
      id: 'srv_sim_metrics',
      name: 'Simulated Metric Server',
      host: '127.0.0.1',
      port: 22,
      username: 'lab',
      credentialId: 'cred_lab_1',
      environment: Environment.production,
    );
    final snapJ = ProjectWorkspaceSnapshot(
      project: project,
      server: simServer,
      connectionState: ConnectionState.connected,
      observedAt: DateTime.now(),
      serverHealth: const WorkspaceServerSummary(memoryPercent: 93.0),
    );
    final eventsJ = await notifCoord.processWorkspaceSnapshot(snapJ);
    if (eventsJ.any((e) => e.type == EventType.serverResourceCritical)) {
      stdout.writeln('PASS (1 serverResourceCritical event emitted)');
    } else {
      stderr.writeln(
          'FAIL (Expected serverResourceCritical event, got ${eventsJ.map((e) => e.type)})');
      exit(1);
    }

    // SCENARIO K: Server metric remains critical at 91% -> 0 duplicate events
    stdout.write('Scenario K (Server metric remains critical): ');
    final snapK = ProjectWorkspaceSnapshot(
      project: project,
      server: simServer,
      connectionState: ConnectionState.connected,
      observedAt: DateTime.now(),
      serverHealth: const WorkspaceServerSummary(memoryPercent: 91.0),
    );
    final eventsK = await notifCoord.processWorkspaceSnapshot(snapK);
    if (eventsK
        .where((e) => e.type == EventType.serverResourceCritical)
        .isEmpty) {
      stdout.writeln(
          'PASS (0 duplicate critical resource events while metric remains critical)');
    } else {
      stderr.writeln('FAIL (Expected 0 events, got ${eventsK.length})');
      exit(1);
    }

    // SCENARIO L: Server metric drops to 60% (< 70% hysteresis) -> 1 serverResourceRecovered
    stdout.write('Scenario L (Server resource recovery with hysteresis): ');
    final snapL = ProjectWorkspaceSnapshot(
      project: project,
      server: simServer,
      connectionState: ConnectionState.connected,
      observedAt: DateTime.now(),
      serverHealth: const WorkspaceServerSummary(memoryPercent: 60.0),
    );
    final eventsL = await notifCoord.processWorkspaceSnapshot(snapL);
    if (eventsL.any((e) => e.type == EventType.serverResourceRecovered)) {
      stdout.writeln('PASS (1 serverResourceRecovered event emitted)');
    } else {
      stderr.writeln(
          'FAIL (Expected serverResourceRecovered event, got ${eventsL.map((e) => e.type)})');
      exit(1);
    }

    // SCENARIO M: Privacy payload inspection -> verify zero secret tokens/passwords in stored file
    stdout.write('Scenario M (Stored event privacy inspection): ');
    final storedJson = await eventsFile.readAsString();
    final hasPassword =
        storedJson.contains('SUPER_SECRET') || storedJson.contains(password);
    final hasDiffBody = storedJson.contains('diff --git');
    if (!hasPassword && !hasDiffBody) {
      stdout.writeln(
          'PASS (Zero secrets, passwords, or raw diffs in event store)');
    } else {
      stderr.writeln('FAIL (Sensitive data leaked in events store)');
      exit(1);
    }

    // SCENARIO N: Bounded retention cleanup
    stdout.write('Scenario N (Bounded event retention limit): ');
    final burstEvents = List.generate(
      250,
      (i) => AgentDeckEvent(
        id: 'burst_evt_$i',
        type: EventType.agentWaitingUser,
        detectedAt: DateTime.now().add(Duration(seconds: i)),
        severity: EventSeverity.info,
        source: EventSource.agent,
        fingerprint: 'burst_fp_$i',
        title: 'Burst Event $i',
        message: 'Burst Msg $i',
      ),
    );
    await eventRepo.saveAll(burstEvents);
    final retainedEvents = await eventRepo.all(limit: 500);
    if (retainedEvents.length == 200) {
      stdout.writeln(
          'PASS (Burst of 250 events capped strictly to 200 max retention)');
    } else {
      stderr.writeln(
          'FAIL (Expected exactly 200 retained events, got ${retainedEvents.length})');
      exit(1);
    }

    await notifCoord.dispose();
    await connService.dispose();

    stdout
        .writeln('=== Milestone M8 Notifications Lab: ALL SCENARIOS PASS ===');
  } finally {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  }
}
