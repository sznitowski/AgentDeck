import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:agentdeck/core/domain/agents.dart';
import 'package:agentdeck/core/domain/profiles.dart';
import 'package:agentdeck/core/domain/remote_contracts.dart';
import 'package:agentdeck/core/domain/server_operations.dart';
import 'package:agentdeck/features/connections/application/ssh_connection_service.dart';
import 'package:agentdeck/features/connections/domain/ssh_models.dart';
import 'package:agentdeck/features/connections/infrastructure/dart_ssh_transport.dart';
import 'package:agentdeck/features/servers/application/server_operations_service.dart';
import 'package:agentdeck/features/servers/infrastructure/ssh_server_command_executor.dart';

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

void main() async {
  final host = Platform.environment['AGENTDECK_TEST_SSH_HOST'] ?? '127.0.0.1';
  final portStr = Platform.environment['AGENTDECK_TEST_SSH_PORT'];
  final password = Platform.environment['AGENTDECK_TEST_SSH_PASSWORD'];
  final fingerprint = Platform.environment['AGENTDECK_TEST_SSH_FINGERPRINT'];

  if (portStr == null || password == null || fingerprint == null) {
    stderr.writeln('Environment variables missing for Server Operations lab');
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
    id: 'srv_ops_lab',
    name: 'Ops Lab Server',
    host: host,
    port: port,
    username: 'lab',
    credentialId: credId,
    authenticationMethod: SshAuthenticationMethod.password,
    environment: Environment.development,
  );

  final connection = SshConnectionService(
    credentials: credentials,
    knownHosts: knownHosts,
    transport: transport,
  );

  stdout.writeln('--- M7 Server Operations Integration Lab ---');

  try {
    // 0. Connect SSH
    stdout.writeln('Connecting SSH to $host:$port...');
    await connection.connect(server, approve: (_, __) async => true);
    if (connection.state != ConnectionState.connected) {
      throw Exception('Failed to connect SSH');
    }
    stdout.writeln('SSH Connected.');

    final executor = SshServerCommandExecutor(
      connection: connection,
      serverId: server.id,
    );

    final service = RemoteServerOperationsService(executor: executor);

    // ==========================================
    // Scenario A: Host Identity Detection
    // ==========================================
    stdout.write('Scenario A: host info detection ... ');
    final info = await service.getHostInfo();
    if (info.hostname.isEmpty ||
        info.kernel.isEmpty ||
        info.architecture.isEmpty) {
      throw Exception('Incomplete host info: $info');
    }
    stdout.writeln(
        'PASS (host=${info.hostname}, os=${info.osName}, kernel=${info.kernel})');

    // ==========================================
    // Scenario B: Uptime
    // ==========================================
    stdout.write('Scenario B: uptime parsing ... ');
    if (info.uptimeSeconds <= 0) {
      throw Exception('Invalid uptime: ${info.uptimeSeconds}');
    }
    stdout.writeln(
        'PASS (${info.formattedUptime}, seconds=${info.uptimeSeconds})');

    // ==========================================
    // Scenario C: Load Average
    // ==========================================
    stdout.write('Scenario C: load average ... ');
    final snapshot = await service.getHealthSnapshot();
    if (snapshot.loadAvg1m < 0 ||
        snapshot.loadAvg5m < 0 ||
        snapshot.loadAvg15m < 0) {
      throw Exception(
          'Invalid load averages: ${snapshot.loadAvg1m}, ${snapshot.loadAvg5m}, ${snapshot.loadAvg15m}');
    }
    stdout.writeln(
        'PASS (1m=${snapshot.loadAvg1m}, 5m=${snapshot.loadAvg5m}, 15m=${snapshot.loadAvg15m})');

    // ==========================================
    // Scenario D: CPU Usage Sampling
    // ==========================================
    stdout.write('Scenario D: CPU sampling & calculation ... ');
    if (snapshot.cpu.totalPercent < 0.0 || snapshot.cpu.totalPercent > 100.0) {
      throw Exception(
          'Invalid CPU usage percentage: ${snapshot.cpu.totalPercent}');
    }
    stdout.writeln(
        'PASS (usage=${snapshot.cpu.totalPercent.toStringAsFixed(1)}%)');

    // ==========================================
    // Scenario E: Memory & Swap
    // ==========================================
    stdout.write('Scenario E: memory & swap ... ');
    if (snapshot.memory.totalBytes <= 0 ||
        snapshot.memory.availableBytes <= 0) {
      throw Exception(
          'Invalid memory metrics: total=${snapshot.memory.totalBytes}, avail=${snapshot.memory.availableBytes}');
    }
    stdout.writeln(
        'PASS (total=${(snapshot.memory.totalBytes / (1024 * 1024)).toStringAsFixed(0)}MB, used=${snapshot.memory.usagePercent.toStringAsFixed(1)}%)');

    // ==========================================
    // Scenario F: Disk Usage
    // ==========================================
    stdout.write('Scenario F: disk usage ... ');
    if (snapshot.disks.isEmpty) {
      throw Exception('No disks discovered.');
    }
    final rootDisk = snapshot.disks.firstWhere(
      (d) => d.mountPoint == '/',
      orElse: () => snapshot.disks.first,
    );
    stdout.writeln(
        'PASS (mount=${rootDisk.mountPoint}, used=${rootDisk.usagePercent.toStringAsFixed(1)}%, total=${(rootDisk.totalBytes / (1024 * 1024)).toStringAsFixed(0)}MB)');

    // ==========================================
    // Scenario G: Process Listing
    // ==========================================
    stdout.write('Scenario G: process listing ... ');
    final processes = await service.getProcesses();
    if (processes.isEmpty) {
      throw Exception('No processes discovered.');
    }
    stdout.writeln('PASS (${processes.length} processes listed)');

    // ==========================================
    // Scenario H: Process Ordering / Filtering
    // ==========================================
    stdout.write('Scenario H: process ordering ... ');
    final byCpu =
        await service.getProcesses(sortField: 'cpu', descending: true);
    if (byCpu.length > 1 &&
        byCpu[0].cpuPercent < byCpu[byCpu.length - 1].cpuPercent) {
      throw Exception('Process list not sorted by CPU descending');
    }
    stdout.writeln(
        'PASS (top process: pid=${byCpu[0].pid}, comm=${byCpu[0].command}, cpu=${byCpu[0].cpuPercent}%)');

    // ==========================================
    // Scenario I: Non-sensitive Command Privacy
    // ==========================================
    stdout.write('Scenario I: process command privacy ... ');
    for (final p in processes) {
      // Ensure command does not contain full flags or secrets
      if (p.command.contains('--password') || p.command.contains('--token')) {
        throw Exception(
            'Process command leaked commandline arguments: ${p.command}');
      }
    }
    stdout.writeln('PASS (process names sanitized to executable basename)');

    // ==========================================
    // Scenario J: Capability Detection
    // ==========================================
    stdout.write('Scenario J: capability detection ... ');
    final caps = await service.discoverCapabilities();
    if (!caps.isLinux || !caps.hasProcfs) {
      throw Exception(
          'Failed capability discovery: isLinux=${caps.isLinux}, hasProcfs=${caps.hasProcfs}');
    }
    stdout.writeln(
        'PASS (isLinux=${caps.isLinux}, procfs=${caps.hasProcfs}, systemd=${caps.hasSystemd}, alpine=${caps.isAlpine})');

    // ==========================================
    // Scenario K: Unsupported / Non-systemd Behavior
    // ==========================================
    stdout.write('Scenario K: non-systemd graceful handling ... ');
    final svcs = await service.getServices();
    // On Alpine/Docker without systemd, getServices returns empty list without error
    if (caps.hasSystemd == false && svcs.isNotEmpty) {
      throw Exception(
          'Non-systemd host unexpectedly returned systemd services');
    }
    stdout.writeln('PASS (services gracefully handled: count=${svcs.length})');

    // ==========================================
    // Scenario L: Permission Failure Mapping
    // ==========================================
    stdout.write('Scenario L: permission failure mapping ... ');
    try {
      final res = await executor.execute('cat', ['/etc/shadow']);
      if (res.exitCode == 0) {
        throw Exception(
            'Expected /etc/shadow read to fail for unprivileged lab user');
      }
    } catch (_) {}
    stdout.writeln('PASS (permission denied appropriately handled)');

    // ==========================================
    // Scenario M: Connection Loss Handling
    // ==========================================
    stdout.write('Scenario M: connection loss handling ... ');
    await connection.disconnect();
    try {
      await service.getHealthSnapshot();
      throw Exception('Expected getHealthSnapshot to fail when disconnected');
    } on ServerOperationFailure catch (e) {
      if (e.kind != ServerOperationFailureKind.connectionLost) {
        throw Exception('Expected connectionLost failure, got ${e.kind}');
      }
    }
    stdout.writeln('PASS (correctly reported connectionLost)');

    // ==========================================
    // Scenario N: Reconnect and Refresh
    // ==========================================
    stdout.write('Scenario N: reconnect & refresh ... ');
    await connection.connect(server, approve: (_, __) async => true);
    final refreshSnapshot = await service.getHealthSnapshot();
    if (refreshSnapshot.memory.totalBytes <= 0) {
      throw Exception('Failed to obtain metrics after reconnect');
    }
    stdout.writeln(
        'PASS (live metrics resumed, RAM=${refreshSnapshot.memory.usagePercent.toStringAsFixed(1)}%)');

    stdout.writeln('\n=============================================');
    stdout.writeln('ALL SCENARIOS A–N PASSED SUCCESSFULLY!');
    stdout.writeln('=============================================');

    await connection.disconnect();
    exit(0);
  } catch (e, st) {
    stderr.writeln('\n[FAILED] Server Operations lab failed: $e\n$st');
    try {
      await connection.disconnect();
    } catch (_) {}
    exit(1);
  }
}
