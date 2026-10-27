import 'dart:convert';

import '../../../core/domain/agents.dart';
import '../../connections/application/ssh_connection_service.dart';
import '../../connections/domain/ssh_models.dart';
import '../domain/remote_companion_client.dart';

/// Concrete implementation of [RemoteCompanionClient] communicating over authenticated SSH.
class SshCompanionClient implements RemoteCompanionClient {
  const SshCompanionClient({required this.connection});

  final SshConnectionService connection;

  void _assertConnected(String serverId) {
    if (connection.state != ConnectionState.connected ||
        connection.connectedProfileId != serverId) {
      throw const SshFailure(
        SshFailureKind.closed,
      );
    }
  }

  @override
  Future<CompanionAvailability> discover(String serverId) async {
    if (connection.state != ConnectionState.connected ||
        connection.connectedProfileId != serverId) {
      return const CompanionAvailability(
        status: CompanionStatus.unhealthy,
        error: 'SSH transport is not connected to target server.',
      );
    }

    try {
      // 1. Check if binary is available in PATH
      final checkRes = await connection.runRemoteCommand(
        ['command', '-v', 'agentdeck-companion'],
        timeout: const Duration(seconds: 10),
      );

      if (checkRes.exitCode != 0 || checkRes.stdout.trim().isEmpty) {
        return const CompanionAvailability(
          status: CompanionStatus.notInstalled,
        );
      }

      // 2. Query version and protocol
      final versionRes = await connection.runRemoteCommand(
        ['agentdeck-companion', 'version', '--json'],
        timeout: const Duration(seconds: 10),
      );

      if (versionRes.exitCode != 0) {
        return CompanionAvailability(
          status: CompanionStatus.unhealthy,
          error: 'Version query failed: ${versionRes.stderr.trim()}',
        );
      }

      final json = jsonDecode(versionRes.stdout) as Map<String, dynamic>;
      final versionInfo = CompanionVersionInfo.fromJson(json);

      if (versionInfo.protocolVersion != 1) {
        return CompanionAvailability(
          status: CompanionStatus.incompatibleVersion,
          versionInfo: versionInfo,
          error:
              'Incompatible protocol version: ${versionInfo.protocolVersion} (expected 1)',
        );
      }

      return CompanionAvailability(
        status: CompanionStatus.available,
        versionInfo: versionInfo,
      );
    } catch (e) {
      return CompanionAvailability(
        status: CompanionStatus.unhealthy,
        error: e.toString(),
      );
    }
  }

  @override
  Future<CompanionEventBatch> fetchEvents(
    String serverId, {
    required int afterSequence,
    int limit = 100,
  }) async {
    _assertConnected(serverId);

    final res = await connection.runRemoteCommand(
      [
        'agentdeck-companion',
        'events',
        '--after',
        afterSequence.toString(),
        '--limit',
        limit.toString(),
        '--json',
      ],
      timeout: const Duration(seconds: 15),
    );

    if (res.exitCode != 0) {
      throw Exception('Companion events fetch failed: ${res.stderr.trim()}');
    }

    final data = jsonDecode(res.stdout) as Map<String, dynamic>;
    return CompanionEventBatch.fromJson(data);
  }

  @override
  Future<Map<String, dynamic>> fetchHealth(String serverId) async {
    _assertConnected(serverId);

    final res = await connection.runRemoteCommand(
      ['agentdeck-companion', 'health', '--json'],
      timeout: const Duration(seconds: 10),
    );

    if (res.exitCode != 0) {
      throw Exception('Companion health check failed: ${res.stderr.trim()}');
    }

    return jsonDecode(res.stdout) as Map<String, dynamic>;
  }

  @override
  Future<Map<String, dynamic>> fetchStatus(String serverId) async {
    _assertConnected(serverId);

    final res = await connection.runRemoteCommand(
      ['agentdeck-companion', 'status', '--json'],
      timeout: const Duration(seconds: 10),
    );

    if (res.exitCode != 0) {
      throw Exception('Companion status query failed: ${res.stderr.trim()}');
    }

    return jsonDecode(res.stdout) as Map<String, dynamic>;
  }

  @override
  Future<Map<String, dynamic>> fetchSnapshot(String serverId) async {
    _assertConnected(serverId);

    final res = await connection.runRemoteCommand(
      ['agentdeck-companion', 'snapshot', '--json'],
      timeout: const Duration(seconds: 15),
    );

    if (res.exitCode != 0) {
      throw Exception(
          'Companion snapshot capture failed: ${res.stderr.trim()}');
    }

    return jsonDecode(res.stdout) as Map<String, dynamic>;
  }
}
