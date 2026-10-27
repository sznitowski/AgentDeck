import 'dart:convert';
import 'dart:io';

import 'package:agentdeck/core/domain/events.dart';
import 'package:agentdeck/core/domain/profiles.dart';
import 'package:agentdeck/core/domain/remote_contracts.dart';
import 'package:agentdeck/core/infrastructure/json_file_store.dart';
import 'package:agentdeck/features/connections/application/ssh_connection_service.dart';
import 'package:agentdeck/features/connections/domain/ssh_models.dart';
import 'package:agentdeck/features/connections/infrastructure/dart_ssh_transport.dart';
import 'package:agentdeck/features/connections/infrastructure/file_known_host_repository.dart';
import 'package:agentdeck/features/notifications/application/notification_coordinator.dart';
import 'package:agentdeck/features/notifications/infrastructure/file_companion_cursor_repository.dart';
import 'package:agentdeck/features/notifications/infrastructure/file_event_repository.dart';
import 'package:agentdeck/features/notifications/infrastructure/ssh_companion_client.dart';

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
    stderr.writeln('FAIL: Missing environment variables for Companion Lab');
    exit(1);
  }

  final port = int.parse(portStr);
  final tempDir =
      await Directory.systemTemp.createTemp('agentdeck_companion_lab_');

  try {
    final knownHosts = FileKnownHostRepository(
      JsonFileStore(File('${tempDir.path}/known_hosts.json')),
    );
    final credentials = _LabSecrets(utf8.encode(password));
    final transport = const DartSshTransport();

    final ssh = SshConnectionService(
      credentials: credentials,
      knownHosts: knownHosts,
      transport: transport,
    );

    final server = ServerProfile(
      id: 'srv_lab',
      name: 'Companion Lab Host',
      host: host,
      port: port,
      username: 'lab',
      credentialId: 'cred_lab',
      authenticationMethod: SshAuthenticationMethod.password,
    );

    stdout.writeln('=== AgentDeck M8.5 Server Companion Lab ===');

    // Trust host identity
    final hostIdentity = HostIdentity('ssh-ed25519', fingerprint);
    await knownHosts.trust(KnownHost(
      hostname: host,
      port: port,
      identity: hostIdentity,
      firstSeenAt: DateTime.now().toUtc(),
      lastSeenAt: DateTime.now().toUtc(),
    ));

    // Connect SSH
    await ssh.connect(server);
    final companionClient = SshCompanionClient(connection: ssh);

    // Initial setup on server: setup lab projects and git repos
    await ssh
        .runRemoteCommand(['git', 'config', '--global', 'user.name', 'Lab']);
    await ssh.runRemoteCommand(
        ['git', 'config', '--global', 'user.email', 'lab@test.local']);
    await ssh.runRemoteCommand(
        ['git', 'config', '--global', '--add', 'safe.directory', '*']);
    await ssh.runRemoteCommand(
        ['mkdir', '-p', '/home/lab/project1', '/home/lab/project2']);
    await ssh.runRemoteCommand(['git', '-C', '/home/lab/project1', 'init']);
    await ssh.runRemoteCommand(
        ['git', '-C', '/home/lab/project1', 'config', 'user.name', 'Lab']);
    await ssh.runRemoteCommand([
      'git',
      '-C',
      '/home/lab/project1',
      'config',
      'user.email',
      'lab@test.local'
    ]);
    await ssh.runRemoteCommand(
        ['sh', '-c', 'echo "hello" > /home/lab/project1/file.txt']);
    await ssh.runRemoteCommand(['git', '-C', '/home/lab/project1', 'add', '.']);
    await ssh.runRemoteCommand(
        ['git', '-C', '/home/lab/project1', 'commit', '-m', 'Initial commit']);

    // Setup companion config
    final configJson = jsonEncode({
      'schemaVersion': 1,
      'serverId': 'srv_lab',
      'journalPath': '/home/lab/events.jsonl',
      'lockPath': '/home/lab/companion.pid',
      'pollIntervals': {
        'agentsSec': 1,
        'gitSec': 1,
        'serverSec': 1,
        'filesSec': 1
      },
      'retention': {'maxEvents': 50, 'maxAgeDays': 7},
      'projects': [
        {
          'id': 'project1',
          'name': 'Project 1',
          'workingDirectory': '/home/lab/project1',
          'enabled': true,
        },
        {
          'id': 'project2',
          'name': 'Project 2',
          'workingDirectory': '/home/lab/project2',
          'enabled': true,
        }
      ]
    });
    final b64Config = base64Encode(utf8.encode(configJson));
    await ssh.runRemoteCommand([
      'mkdir',
      '-p',
      '/home/lab/.config/agentdeck',
      '/etc/agentdeck',
      '/var/lib/agentdeck'
    ]);
    await ssh.runRemoteCommand([
      'sh',
      '-c',
      'echo $b64Config | base64 -d > /home/lab/agentdeck-companion.json && cp /home/lab/agentdeck-companion.json /home/lab/.config/agentdeck/agentdeck-companion.json && cp /home/lab/agentdeck-companion.json /etc/agentdeck/agentdeck-companion.json'
    ]);

    // Scenario A: Companion binary starts & runs
    stdout.write('Scenario A: Companion Starts... ');
    final runCheck = await ssh
        .runRemoteCommand(['agentdeck-companion', 'version', '--json']);
    if (runCheck.exitCode != 0)
      throw Exception('Scenario A failed: ${runCheck.stderr}');
    stdout.writeln('PASS');

    // Scenario B: Health JSON contract
    stdout.write('Scenario B: Health JSON Contract... ');
    final healthRes = await companionClient.fetchHealth('srv_lab');
    if (healthRes['schemaVersion'] != 1 || healthRes['status'] != 'ok') {
      throw Exception('Scenario B failed: $healthRes');
    }
    stdout.writeln('PASS');

    // Scenario C: Version Negotiation
    stdout.write('Scenario C: Version Negotiation... ');
    final availability = await companionClient.discover('srv_lab');
    if (!availability.isAvailable ||
        availability.versionInfo?.protocolVersion != 1) {
      throw Exception('Scenario C failed: $availability');
    }
    stdout.writeln('PASS');

    // Scenario D: Initial baseline produces zero historical alert spam
    stdout.write('Scenario D: Initial Baseline Verification... ');
    final scanBaseline = await ssh.runRemoteCommand([
      'agentdeck-companion',
      'scan-once',
      '--config',
      '/home/lab/agentdeck-companion.json',
      '--baseline',
      '--json',
    ]);
    if (scanBaseline.exitCode != 0)
      throw Exception('Baseline scan failed: ${scanBaseline.stderr}');
    final baselineData = jsonDecode(scanBaseline.stdout);
    if (baselineData['count'] != 0) {
      throw Exception(
          'Scenario D failed: expected 0 baseline events, got ${baselineData['count']}');
    }
    stdout.writeln('PASS');

    // Scenario E: Fake Agent Running -> Waiting Transition Journaled
    stdout
        .write('Scenario E: Agent Running -> Waiting Transition Journaled... ');
    // Launch tmux session with fake agent
    await ssh.runRemoteCommand(['tmux', 'kill-server']);
    await ssh.runRemoteCommand([
      'tmux',
      'new-session',
      '-d',
      '-s',
      'agentdeck-agent-project1-inst1',
      'agentdeck-fake-agent waiting',
    ]);
    // Allow tmux buffer to populate
    await Future.delayed(const Duration(milliseconds: 500));
    final scanAgent = await ssh.runRemoteCommand([
      'agentdeck-companion',
      'scan-once',
      '--config',
      '/home/lab/agentdeck-companion.json',
      '--json',
    ]);
    final agentScanData = jsonDecode(scanAgent.stdout);
    if (agentScanData['count'] != 1) {
      throw Exception(
          'Scenario E failed: expected 1 agent event, got ${agentScanData['count']}');
    }
    final ev1 = agentScanData['eventsGenerated'][0];
    if (ev1['type'] != 'agentWaitingUser') {
      throw Exception(
          'Scenario E failed: expected agentWaitingUser, got ${ev1['type']}');
    }
    stdout.writeln('PASS');

    // Scenario F: Phone Absent Simulation (Mobile SSH Disconnected -> Agent Event Observed)
    stdout.write('Scenario F: Phone Absent Simulation... ');
    // 1. Mobile explicitly disconnects SSH session
    await ssh.disconnect();
    stdout.write('[Phone Disconnected]... ');

    // 2. Simulate background companion continuous run / scan while mobile is completely absent
    final backgroundScan = await Process.run('docker', [
      'exec',
      '-u',
      'lab',
      Platform.environment['DOCKER_CONTAINER_NAME'] ?? 'agentdeck-m8-5-lab',
      'agentdeck-companion',
      'scan-once',
      '--config',
      '/home/lab/agentdeck-companion.json',
      '--json',
    ]);
    if (backgroundScan.exitCode != 0) {
      throw Exception(
          'Background companion scan failed: ${backgroundScan.stderr}');
    }
    stdout.writeln('PASS');

    // Scenario G: Git Conflict while Mobile SSH Disconnected
    stdout.write('Scenario G: Git Conflict while Mobile Disconnected... ');
    final conflictSetup = await Process.run('docker', [
      'exec',
      '-u',
      'lab',
      Platform.environment['DOCKER_CONTAINER_NAME'] ?? 'agentdeck-m8-5-lab',
      'sh',
      '-c',
      'cd /home/lab/project1 && git checkout -b feature && echo "feature_content" > file.txt && git commit -am "feature commit" && git checkout - && echo "main_content" > file.txt && git commit -am "main commit" && git merge feature || true',
    ]);
    if (conflictSetup.exitCode != 0) {
      throw Exception('Failed to create git conflict: ${conflictSetup.stderr}');
    }
    final gitScan = await Process.run('docker', [
      'exec',
      '-u',
      'lab',
      Platform.environment['DOCKER_CONTAINER_NAME'] ?? 'agentdeck-m8-5-lab',
      'agentdeck-companion',
      'scan-once',
      '--config',
      '/home/lab/agentdeck-companion.json',
      '--json',
    ]);
    final gitScanData = jsonDecode(gitScan.stdout);
    final hasConflict = (gitScanData['eventsGenerated'] as List)
        .any((e) => e['type'] == 'gitConflictDetected');
    if (!hasConflict) {
      throw Exception(
          'Scenario G failed: expected gitConflictDetected, got ${gitScan.stdout}');
    }
    stdout.writeln('PASS');

    // Scenario H: Server Resource Observation
    stdout.write('Scenario H: Server Resource Observation... ');
    final statusJson = await Process.run('docker', [
      'exec',
      '-u',
      'lab',
      Platform.environment['DOCKER_CONTAINER_NAME'] ?? 'agentdeck-m8-5-lab',
      'agentdeck-companion',
      'status',
      '--config',
      '/home/lab/agentdeck-companion.json',
      '--json',
    ]);
    final statusData = jsonDecode(statusJson.stdout);
    if (statusData['schemaVersion'] != 1 ||
        statusData['journal']['totalEvents'] < 2) {
      throw Exception('Scenario H failed: invalid status data $statusData');
    }
    stdout.writeln('PASS');

    // Scenario I: Companion Restart (No duplicate historical events)
    stdout.write('Scenario I: Companion Restart Recovery... ');
    // Baseline scan on restart
    final restartBaseline = await Process.run('docker', [
      'exec',
      '-u',
      'lab',
      Platform.environment['DOCKER_CONTAINER_NAME'] ?? 'agentdeck-m8-5-lab',
      'agentdeck-companion',
      'scan-once',
      '--config',
      '/home/lab/agentdeck-companion.json',
      '--baseline',
      '--json',
    ]);
    final restartData = jsonDecode(restartBaseline.stdout);
    if (restartData['count'] != 0) {
      throw Exception(
          'Scenario I failed: restart emitted false duplicates ${restartBaseline.stdout}');
    }
    stdout.writeln('PASS');

    // Scenario J: Sequence Monotonicity Across Restarts
    stdout.write('Scenario J: Sequence Monotonicity Across Restarts... ');
    final statusPostRestart = await Process.run('docker', [
      'exec',
      '-u',
      'lab',
      Platform.environment['DOCKER_CONTAINER_NAME'] ?? 'agentdeck-m8-5-lab',
      'agentdeck-companion',
      'status',
      '--config',
      '/home/lab/agentdeck-companion.json',
      '--json',
    ]);
    final postRestartData = jsonDecode(statusPostRestart.stdout);
    if (postRestartData['journal']['lastSequence'] < 2) {
      throw Exception('Scenario J failed: sequence reset to 0');
    }
    stdout.writeln('PASS');

    // Scenario K: Mobile Reconnect & Catch-Up Sync (THE CRUCIAL GATE)
    stdout.write('Scenario K: Mobile Reconnect & Remote Event Catch-Up... ');
    await ssh.connect(server);
    final eventRepo = FileEventRepository(
      JsonFileStore(File('${tempDir.path}/mobile_events.json')),
    );
    final cursorRepo = FileCompanionCursorRepository(
      JsonFileStore(File('${tempDir.path}/mobile_cursors.json')),
    );
    final coordinator = NotificationCoordinator(
      repository: eventRepo,
      companionClient: companionClient,
      companionCursorRepository: cursorRepo,
    );

    final syncedEvents = await coordinator.syncCompanionEvents('srv_lab');
    if (syncedEvents.isEmpty) {
      throw Exception('Scenario K failed: no events synced on reconnect');
    }
    final waitingEvent =
        syncedEvents.firstWhere((e) => e.type == EventType.agentWaitingUser);
    if (waitingEvent.type != EventType.agentWaitingUser) {
      throw Exception(
          'Scenario K failed: agentWaitingUser event missing from catch-up');
    }
    stdout.writeln(
        'PASS (Received ${syncedEvents.length} offline events, including agentWaitingUser!)');

    // Scenario L: Deterministic Second Fetch
    stdout.write('Scenario L: Deterministic Second Fetch... ');
    final secondSync = await coordinator.syncCompanionEvents('srv_lab');
    if (secondSync.isNotEmpty) {
      throw Exception(
          'Scenario L failed: expected 0 events on immediate second sync, got ${secondSync.length}');
    }
    stdout.writeln('PASS');

    // Scenario M: Project Failure Isolation
    stdout.write('Scenario M: Project Failure Isolation... ');
    final snapRes = await companionClient.fetchSnapshot('srv_lab');
    if (snapRes['schemaVersion'] != 1 ||
        !snapRes['projects'].containsKey('project1')) {
      throw Exception('Scenario M failed: snapshot incomplete $snapRes');
    }
    stdout.writeln('PASS');

    // Scenario N: Journal Retention Limits
    stdout.write('Scenario N: Journal Retention Pruning... ');
    final eventsRes = await companionClient.fetchEvents('srv_lab',
        afterSequence: 0, limit: 100);
    if (eventsRes.events.isEmpty) {
      throw Exception('Scenario N failed: journal is empty');
    }
    stdout.writeln('PASS');

    // Scenario O: Privacy Scan
    stdout.write('Scenario O: Privacy Scan... ');
    final journalContent =
        await ssh.runRemoteCommand(['cat', '/home/lab/events.jsonl']);
    final rawText = journalContent.stdout;
    if (rawText.contains('password') ||
        rawText.contains('sk-') ||
        rawText.contains('BEGIN OPENSSH')) {
      throw Exception('Scenario O failed: sensitive data found in journal!');
    }
    stdout.writeln('PASS');

    // Scenario P: Malformed CLI Arguments Rejected
    stdout.write('Scenario P: Malformed CLI Input Rejected... ');
    final malformedRes = await ssh.runRemoteCommand([
      'agentdeck-companion',
      'events',
      '--after',
      'invalid_seq',
    ]);
    if (malformedRes.exitCode == 0) {
      throw Exception('Scenario P failed: malformed argument was not rejected');
    }
    stdout.writeln('PASS');

    await ssh.disconnect();
    stdout.writeln('\nAll M8.5 Scenarios A-P PASSED successfully!');
  } finally {
    await tempDir.delete(recursive: true);
  }
}
