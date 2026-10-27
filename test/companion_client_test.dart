import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';

import 'package:agentdeck/core/domain/events.dart';
import 'package:agentdeck/core/domain/profiles.dart';
import 'package:agentdeck/core/domain/remote_contracts.dart';
import 'package:agentdeck/features/connections/application/ssh_connection_service.dart';
import 'package:agentdeck/features/connections/domain/ssh_models.dart';
import 'package:agentdeck/features/notifications/domain/remote_companion_client.dart';
import 'package:agentdeck/features/notifications/infrastructure/ssh_companion_client.dart';

final testIdentity = HostIdentity('ssh-ed25519', 'SHA256:${'A' * 43}');

class MockTmuxHandle implements SshTmuxTransportHandle {
  final closed = Completer<void>();

  @override
  Future<void> get done => closed.future;

  @override
  Future<void> close() async {
    if (!closed.isCompleted) closed.complete();
  }

  @override
  Future<TerminalSession> openTerminal(int columns, int rows) async =>
      throw UnimplementedError();

  @override
  Future<TerminalSession> attachTmux(
          String name, int columns, int rows) async =>
      throw UnimplementedError();

  @override
  Future<RemoteCommandResult> run(
    List<String> arguments, {
    Duration timeout = const Duration(seconds: 10),
  }) async {
    final cmd = arguments.join(' ');

    if (cmd.contains('command -v agentdeck-companion')) {
      if (cmd.contains('not_installed')) {
        return const RemoteCommandResult(1, '', 'not found');
      }
      return const RemoteCommandResult(
          0, '/usr/local/bin/agentdeck-companion\n', '');
    }

    if (cmd.contains('agentdeck-companion version --json')) {
      if (cmd.contains('incompatible')) {
        return RemoteCommandResult(
          0,
          jsonEncode({
            'schemaVersion': 99,
            'binaryVersion': '9.0.0',
            'protocolVersion': 99,
          }),
          '',
        );
      }
      return RemoteCommandResult(
        0,
        jsonEncode({
          'schemaVersion': 1,
          'binaryVersion': '0.1.0',
          'protocolVersion': 1,
        }),
        '',
      );
    }

    if (cmd.contains('agentdeck-companion events')) {
      return RemoteCommandResult(
        0,
        jsonEncode({
          'schemaVersion': 1,
          'count': 1,
          'lastSequence': 15,
          'hasMore': false,
          'events': [
            {
              'sequence': 15,
              'eventId': 'evt_srv_1_15',
              'type': 'agentWaitingUser',
              'severity': 'actionRequired',
              'source': 'agent',
              'fingerprint': 'agent_waiting:inst_1',
              'title': 'Codex is waiting for input',
              'message': 'Interactive prompt requires approval.',
              'detectedAt': '2026-09-20T19:00:00Z',
              'serverId': 'srv_1',
              'projectId': 'proj_1',
              'agentInstanceId': 'inst_1',
              'isProduction': false,
              'destination': {
                'route': 'agent_terminal',
                'projectId': 'proj_1',
                'serverId': 'srv_1',
                'agentInstanceId': 'inst_1',
              },
              'metadata': {'detail': 'confirm command'}
            }
          ],
        }),
        '',
      );
    }

    if (cmd.contains('agentdeck-companion health --json')) {
      return RemoteCommandResult(
        0,
        jsonEncode({
          'schemaVersion': 1,
          'status': 'ok',
          'version': '0.1.0',
          'uptimeSeconds': 120,
          'observedProjects': 2,
        }),
        '',
      );
    }

    return const RemoteCommandResult(0, '{}', '');
  }
}

class FakeSshTransport implements SshTransport {
  const FakeSshTransport();

  @override
  Future<SshTransportHandle> open(
    ServerProfile profile,
    SshCredential credential,
    Future<bool> Function(String algorithm, String fingerprint) verifyHostKey,
    SshTimeouts timeouts,
  ) async {
    final accepted =
        await verifyHostKey(testIdentity.algorithm, testIdentity.fingerprint);
    if (!accepted) throw const SshFailure(SshFailureKind.hostUnknown);
    return MockTmuxHandle();
  }
}

class FakeCredentialStore implements SecureCredentialStore {
  final values = <String, List<int>>{};

  @override
  Future<void> put(String reference, List<int> secret) async =>
      values[reference] = secret;

  @override
  Future<List<int>?> get(String reference) async =>
      values[reference] ?? utf8.encode('password');

  @override
  Future<void> delete(String reference) async => values.remove(reference);
}

class FakeKnownHostRepository implements KnownHostRepository {
  KnownHost? host = KnownHost(
    hostname: '127.0.0.1',
    port: 22,
    identity: testIdentity,
    firstSeenAt: DateTime.now(),
    lastSeenAt: DateTime.now(),
  );

  @override
  Future<KnownHost?> find(String hostname, int port) async => host;

  @override
  Future<void> trust(KnownHost candidate) async => host = candidate;

  @override
  Future<void> replace(KnownHost candidate) async => host = candidate;

  @override
  Future<void> revoke(String hostname, int port) async {}

  @override
  Future<void> delete(String hostname, int port) async => host = null;

  @override
  Future<void> markSeen(String hostname, int port, DateTime at) async {}
}

void main() {
  group('SshCompanionClient Tests', () {
    late SshConnectionService connection;
    late SshCompanionClient client;

    setUp(() async {
      final creds = FakeCredentialStore();
      await creds.put('cred_1', utf8.encode('password'));

      connection = SshConnectionService(
        credentials: creds,
        knownHosts: FakeKnownHostRepository(),
        transport: const FakeSshTransport(),
      );

      await connection.connect(
        const ServerProfile(
          id: 'srv_1',
          name: 'Test Server',
          host: '127.0.0.1',
          port: 22,
          username: 'agentdeck',
          credentialId: 'cred_1',
          authenticationMethod: SshAuthenticationMethod.password,
        ),
      );

      client = SshCompanionClient(connection: connection);
    });

    test('discover returns available when protocol version matches', () async {
      final availability = await client.discover('srv_1');
      expect(availability.status, CompanionStatus.available);
      expect(availability.versionInfo?.protocolVersion, 1);
      expect(availability.isAvailable, isTrue);
    });

    test('fetchEvents parses CompanionEventBatch correctly', () async {
      final batch =
          await client.fetchEvents('srv_1', afterSequence: 0, limit: 10);
      expect(batch.schemaVersion, 1);
      expect(batch.lastSequence, 15);
      expect(batch.hasMore, isFalse);
      expect(batch.events.length, 1);

      final event = batch.events.first;
      expect(event.id, 'evt_srv_1_15');
      expect(event.type, EventType.agentWaitingUser);
      expect(event.severity, EventSeverity.actionRequired);
      expect(event.destination?.route, 'agent_terminal');
      expect(event.metadata['detail'], 'confirm command');
    });

    test('fetchHealth returns health telemetry map', () async {
      final health = await client.fetchHealth('srv_1');
      expect(health['status'], 'ok');
      expect(health['uptimeSeconds'], 120);
      expect(health['observedProjects'], 2);
    });
  });
}
