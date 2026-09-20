import 'dart:async';
import 'dart:convert';

import 'package:agentdeck/core/domain/agents.dart';
import 'package:agentdeck/core/domain/profiles.dart';
import 'package:agentdeck/core/domain/remote_contracts.dart';
import 'package:agentdeck/features/connections/application/ssh_connection_service.dart';
import 'package:agentdeck/features/connections/domain/ssh_models.dart';
import 'package:agentdeck/features/terminal/application/terminal_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart' hide ConnectionState;
import 'package:agentdeck/features/terminal/terminal_page.dart';

class MemorySecrets implements SecureCredentialStore {
  @override
  Future<List<int>?> get(String reference) async => utf8.encode('dummy');
  @override
  Future<void> put(String reference, List<int> value) async {}
  @override
  Future<void> delete(String reference) async {}
}

class MemoryHosts implements KnownHostRepository {
  @override
  Future<KnownHost?> find(String hostname, int port) async => null;
  @override
  Future<void> trust(KnownHost host) async {}
  @override
  Future<void> markSeen(String hostname, int port, DateTime at) async {}
  @override
  Future<void> revoke(String hostname, int port) async {}
  @override
  Future<void> replace(KnownHost host) async {}
  @override
  Future<void> delete(String hostname, int port) async {}
}

class FakeSession implements TerminalSession {
  final chunks = StreamController<List<int>>();
  final sent = <List<int>>[];
  final sizes = <String>[];
  int closes = 0;
  @override
  Stream<List<int>> get output => chunks.stream;
  @override
  Future<void> send(List<int> input) async => sent.add(input);
  @override
  Future<void> resize(int columns, int rows) async =>
      sizes.add('$columns:$rows');
  @override
  Future<void> close() async {
    closes++;
    await chunks.close();
  }
}

class FakeHandle implements SshTerminalTransportHandle {
  FakeHandle(this.session);
  final FakeSession session;
  final doneSignal = Completer<void>();
  int opens = 0;
  @override
  Future<void> get done => doneSignal.future;
  @override
  Future<TerminalSession> openTerminal(int columns, int rows) async {
    opens++;
    return session;
  }

  @override
  Future<void> close() async {
    if (!doneSignal.isCompleted) doneSignal.complete();
  }
}

class FakeTransport implements SshTransport {
  FakeTransport(this.handle);
  final FakeHandle handle;
  @override
  Future<SshTransportHandle> open(
      ServerProfile profile,
      SshCredential credential,
      Future<bool> Function(String, String) verifyHostKey,
      SshTimeouts timeouts) async {
    await verifyHostKey('ssh-ed25519', 'SHA256:${'A' * 43}');
    return handle;
  }
}

void main() {
  const profile = ServerProfile(
      id: 'one',
      name: 'Lab',
      host: '127.0.0.1',
      username: 'lab',
      credentialId: 'dummy',
      authenticationMethod: SshAuthenticationMethod.password);

  test('UTF-8 chunks, input, resize and channel cleanup', () async {
    final session = FakeSession();
    final handle = FakeHandle(session);
    final service = SshConnectionService(
        credentials: MemorySecrets(),
        knownHosts: MemoryHosts(),
        transport: FakeTransport(handle));
    await service.connect(profile, approve: (_, __) async => true);
    final terminal = TerminalController(service);
    final text = <String>[];
    final subscription = terminal.output.listen(text.add);
    await terminal.open();
    expect(handle.opens, 1);
    final bytes = utf8.encode('ñ🧪');
    session.chunks.add(bytes.sublist(0, 1));
    session.chunks.add(bytes.sublist(1, 3));
    session.chunks.add(bytes.sublist(3));
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(text.join(), 'ñ🧪');
    await terminal.send('é');
    expect(session.sent.single, utf8.encode('é'));
    terminal.resize(120, 40);
    terminal.resize(120, 40);
    await Future<void>.delayed(const Duration(milliseconds: 150));
    expect(session.sizes, ['120:40']);
    await terminal.close();
    expect(session.closes, 1);
    expect(service.state, ConnectionState.connected);
    await subscription.cancel();
    await service.dispose();
  });

  testWidgets('terminal page shows production, toolbar and connection loss',
      (tester) async {
    final session = FakeSession();
    final service = SshConnectionService(
        credentials: MemorySecrets(),
        knownHosts: MemoryHosts(),
        transport: FakeTransport(FakeHandle(session)));
    const production = ServerProfile(
        id: 'prod',
        name: 'Production lab',
        host: '127.0.0.1',
        username: 'lab',
        credentialId: 'dummy',
        environment: Environment.production,
        authenticationMethod: SshAuthenticationMethod.password);
    await service.connect(production, approve: (_, __) async => true);
    await tester.pumpWidget(MaterialApp(
        home: TerminalPage(profile: production, connection: service)));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('PRODUCTION'), findsOneWidget);
    expect(find.text('Esc'), findsOneWidget);
    await tester.tap(find.byTooltip('Hide key toolbar'));
    await tester.pump();
    expect(find.text('Esc'), findsNothing);
    await tester.tap(find.byTooltip('Show key toolbar'));
    await tester.pump();
    await tester.tap(find.text('Esc'));
    await tester.pump();
    expect(session.sent.last, [27]);
    await session.chunks.close();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.textContaining('CONNECTION LOST'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await service.dispose();
  });

  test('remote channel loss prevents further writes and closes safely',
      () async {
    final session = FakeSession();
    final service = SshConnectionService(
        credentials: MemorySecrets(),
        knownHosts: MemoryHosts(),
        transport: FakeTransport(FakeHandle(session)));
    await service.connect(profile, approve: (_, __) async => true);
    final terminal = TerminalController(service);
    await terminal.open();
    await session.chunks.close();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(terminal.status, TerminalStatus.lost);
    await terminal.send('ignored');
    expect(session.sent, isEmpty);
    await terminal.close();
    await service.dispose();
  });
}
