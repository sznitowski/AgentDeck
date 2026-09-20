import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:agentdeck/app/app_services.dart';
import 'package:agentdeck/core/domain/profiles.dart';
import 'package:agentdeck/core/infrastructure/json_file_store.dart';
import 'package:agentdeck/features/connections/domain/ssh_models.dart';
import 'package:agentdeck/features/connections/application/ssh_connection_service.dart';
import 'package:agentdeck/features/servers/domain/server_profile_repository.dart';
import 'package:agentdeck/features/servers/servers_page.dart';
import 'package:agentdeck/features/connections/infrastructure/file_known_host_repository.dart';
import 'package:agentdeck/features/connections/infrastructure/platform_secure_credential_store.dart';
import 'package:agentdeck/features/servers/infrastructure/file_server_profile_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeSecretBackend implements SecretValueBackend {
  final values = <String, String>{};
  @override
  Future<void> write(String key, String value) async => values[key] = value;
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> delete(String key) async => values.remove(key);
}

class FakeHandle implements SshTransportHandle {
  @override
  Future<void> get done => _done.future;
  final _done = Completer<void>();
  @override
  Future<void> close() async {
    if (!_done.isCompleted) _done.complete();
  }
}

class FakeTransport implements SshTransport {
  int opens = 0;
  String? secret;
  HostIdentity identity = HostIdentity('ssh-ed25519', 'SHA256:${'A' * 43}');
  @override
  Future<SshTransportHandle> open(
      ServerProfile profile,
      SshCredential credential,
      Future<bool> Function(String algorithm, String fingerprint) verifyHostKey,
      SshTimeouts timeouts) async {
    opens++;
    secret = credential.secret;
    await verifyHostKey(identity.algorithm, identity.fingerprint);
    return FakeHandle();
  }
}

class MemoryProfiles implements ServerProfileRepository {
  final values = <String, ServerProfile>{};
  @override
  Future<List<ServerProfile>> all() async => values.values.toList();
  @override
  Future<ServerProfile?> find(String id) async => values[id];
  @override
  Future<void> save(ServerProfile profile) async =>
      values[profile.id] = profile;
  @override
  Future<void> delete(String id) async => values.remove(id);
}

class MemoryHosts implements KnownHostRepository {
  KnownHost? value;
  @override
  Future<KnownHost?> find(String hostname, int port) async =>
      value?.hostname == hostname && value?.port == port ? value : null;
  @override
  Future<void> trust(KnownHost host) async => value = host;
  @override
  Future<void> revoke(String hostname, int port) async {}
  @override
  Future<void> replace(KnownHost host) async => value = host;
  @override
  Future<void> delete(String hostname, int port) async => value = null;
  @override
  Future<void> markSeen(String hostname, int port, DateTime at) async {}
}

void main() {
  late Directory temp;
  setUp(() async =>
      temp = await Directory.systemTemp.createTemp('agentdeck-m15-'));
  tearDown(() async {
    if (await temp.exists()) await temp.delete(recursive: true);
  });

  test('profiles save, read, update, delete and survive repository restart',
      () async {
    final file = File('${temp.path}/profiles.json');
    final first = FileServerProfileRepository(JsonFileStore(file));
    const profile = ServerProfile(
        id: 'one',
        name: 'Lab',
        host: 'lab.test',
        username: 'dev',
        credentialId: 'secret-ref',
        environment: Environment.staging);
    await first.save(profile);
    final restarted = FileServerProfileRepository(JsonFileStore(file));
    expect((await restarted.find('one'))?.name, 'Lab');
    const updated = ServerProfile(
        id: 'one',
        name: 'Updated',
        host: 'lab.test',
        username: 'dev',
        credentialId: 'secret-ref',
        authenticationMethod: SshAuthenticationMethod.privateKey);
    await restarted.save(updated);
    expect((await first.all()).single.name, 'Updated');
    expect((await file.readAsString()).contains('test-password'), isFalse);
    await restarted.delete('one');
    expect(await first.all(), isEmpty);
  });

  test('secure credential adapter writes, replaces, reads, deletes and misses',
      () async {
    final backend = FakeSecretBackend();
    final store = PlatformSecureCredentialStore(backend);
    expect(await store.get('ref'), isNull);
    await store.put('ref', utf8.encode('dummy-password'));
    expect(utf8.decode((await store.get('ref'))!), 'dummy-password');
    expect(backend.values.values.single.contains('dummy-password'), isFalse);
    await store.put('ref', utf8.encode('replacement'));
    expect(utf8.decode((await store.get('ref'))!), 'replacement');
    await store.delete('ref');
    expect(await store.get('ref'), isNull);
  });

  test(
      'known host survives restart, blocks mismatch/revocation, allows explicit removal',
      () async {
    final file = File('${temp.path}/hosts.json');
    final first = FileKnownHostRepository(JsonFileStore(file));
    final identity = HostIdentity('ssh-ed25519', 'SHA256:${'A' * 43}');
    const server = ServerProfile(
        id: 'one',
        name: 'Lab',
        host: 'lab.test',
        username: 'dev',
        credentialId: 'ref');
    await HostTrustService(first)
        .verify(server, identity, approve: (p, i) async => true);
    final restarted = FileKnownHostRepository(JsonFileStore(file));
    expect((await restarted.find('lab.test', 22))?.identity.fingerprint,
        identity.fingerprint);
    await HostTrustService(restarted).verify(server, identity);
    final changed = HostIdentity('ssh-ed25519', 'SHA256:${'B' * 43}');
    await expectLater(
        HostTrustService(restarted)
            .verify(server, changed, approve: (p, i) async => true),
        throwsA(isA<SshFailure>()
            .having((e) => e.kind, 'kind', SshFailureKind.hostMismatch)));
    await restarted.revoke('lab.test', 22);
    await expectLater(
        HostTrustService(restarted).verify(server, identity),
        throwsA(isA<SshFailure>()
            .having((e) => e.kind, 'kind', SshFailureKind.hostRevoked)));
    await restarted.delete('lab.test', 22);
    expect(await first.find('lab.test', 22), isNull);
  });

  test('bootstrap wires persisted profile, credential reference and host trust',
      () async {
    final backend = FakeSecretBackend();
    final transport = FakeTransport();
    final services = await AgentDeckServices.bootstrap(
        directory: temp, secretBackend: backend, transport: transport);
    const profile = ServerProfile(
        id: 'one',
        name: 'Lab',
        host: 'lab.test',
        username: 'dev',
        credentialId: 'ref');
    await services.credentials.put('ref', utf8.encode('dummy-password'));
    await services.profiles.save(profile);
    await services.connection.connect(profile, approve: (p, i) async => true);
    expect(transport.secret, 'dummy-password');
    expect(
        (await services.knownHosts.find('lab.test', 22))?.identity.fingerprint,
        transport.identity.fingerprint);
    await services.connection.disconnect();
    await services.dispose();
    final reopened = await AgentDeckServices.bootstrap(
        directory: temp, secretBackend: backend, transport: transport);
    expect((await reopened.profiles.all()).single.name, 'Lab');
    await reopened.connection.connect((await reopened.profiles.all()).single);
    expect(transport.opens, 2);
    await reopened.dispose();
    final profilesFile =
        await File('${temp.path}/agentdeck_profiles.json').readAsString();
    final hostsFile =
        await File('${temp.path}/agentdeck_known_hosts.json').readAsString();
    expect(profilesFile.contains('dummy-password'), isFalse);
    expect(hostsFile.contains('dummy-password'), isFalse);
    expect(hostsFile.contains('PRIVATE KEY'), isFalse);
  });

  test('corrupt trust file fails closed at bootstrap', () async {
    await File('${temp.path}/agentdeck_known_hosts.json')
        .writeAsString('not json');
    await expectLater(
        AgentDeckServices.bootstrap(
            directory: temp,
            secretBackend: FakeSecretBackend(),
            transport: FakeTransport()),
        throwsA(isA<FormatException>()));
  });

  testWidgets('Servers CRUD and connection approval use injected services',
      (tester) async {
    final backend = FakeSecretBackend();
    final transport = FakeTransport();
    final profiles = MemoryProfiles();
    final credentials = PlatformSecureCredentialStore(backend);
    final hosts = MemoryHosts();
    final connection = SshConnectionService(
        credentials: credentials, knownHosts: hosts, transport: transport);
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: ServersPage(
                profiles: profiles,
                credentials: credentials,
                knownHosts: hosts,
                connection: connection))));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Add server'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Name'), 'Lab');
    await tester.enterText(
        find.widgetWithText(TextField, 'Hostname'), 'lab.test');
    await tester.enterText(find.widgetWithText(TextField, 'Username'), 'dev');
    await tester.enterText(
        find.widgetWithText(TextField, 'Password'), 'dummy-password');
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();
    expect(find.text('Lab'), findsWidgets);
    expect(find.text('dummy-password'), findsNothing);
    await tester.tap(find.widgetWithText(FilledButton, 'Connect'));
    await tester.pumpAndSettle();
    expect(find.text('Host identity unknown'), findsOneWidget);
    await tester.tap(find.text('Trust & Connect'));
    await tester.pumpAndSettle();
    expect(find.textContaining('CONNECTED'), findsWidgets);
    await tester.tap(find.widgetWithText(OutlinedButton, 'Disconnect'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Remove trusted key'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Remove trust'));
    await tester.pumpAndSettle();
    expect(hosts.value, isNull);
    expect((await profiles.all()).length, 1);
    await tester.tap(find.widgetWithText(TextButton, 'Edit'));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.widgetWithText(TextField, 'Name'), 'Lab edited');
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();
    expect((await profiles.all()).single.name, 'Lab edited');
    await tester.tap(find.widgetWithText(TextButton, 'Delete'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pumpAndSettle();
    expect(await profiles.all(), isEmpty);
    expect(backend.values, isEmpty);
    await tester.pumpWidget(const SizedBox.shrink());
    await connection.dispose();
  });

  test(
      'interrupted file replacement recovers backup; corrupt main fails closed',
      () async {
    final file = File('${temp.path}/recover.json');
    final store = JsonFileStore(file);
    await store.update((items) => items.add({'id': 'safe'}));
    await file.rename('${file.path}.bak');
    final reopened = JsonFileStore(file);
    expect((await reopened.readAll()).single['id'], 'safe');
    await file.writeAsString('{broken');
    await expectLater(reopened.readAll(), throwsA(isA<FormatException>()));
  });

  test('serialized profiles and model diagnostics never contain secret values',
      () async {
    final file = File('${temp.path}/profiles.json');
    final repository = FileServerProfileRepository(JsonFileStore(file));
    const profile = ServerProfile(
        id: 'one',
        name: 'Lab',
        host: 'lab.test',
        username: 'dev',
        credentialId: 'opaque-ref');
    await repository.save(profile);
    final data = await file.readAsString();
    for (final value in ['dummy-password', 'PRIVATE KEY', 'test-passphrase']) {
      expect(data.contains(value), isFalse);
      expect(profile.toString().contains(value), isFalse);
    }
  });
}
