import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:agentdeck/core/domain/profiles.dart';
import 'package:agentdeck/core/domain/remote_contracts.dart';
import 'package:agentdeck/core/infrastructure/json_file_store.dart';
import 'package:agentdeck/features/connections/application/ssh_connection_service.dart';
import 'package:agentdeck/features/connections/domain/ssh_models.dart';
import 'package:agentdeck/features/connections/infrastructure/dart_ssh_transport.dart';
import 'package:agentdeck/features/tmux/application/tmux_service.dart';
import 'package:agentdeck/features/tmux/domain/tmux_models.dart';
import 'package:agentdeck/features/tmux/infrastructure/file_tmux_session_repository.dart';
import 'package:agentdeck/features/tmux/persistent_sessions_page.dart';
import 'package:flutter/material.dart' hide ConnectionState;
import 'package:flutter_test/flutter_test.dart';

class FakeCredentials implements SecureCredentialStore {
  @override
  Future<List<int>?> get(String reference) async => utf8.encode('dummy');
  @override
  Future<void> put(String reference, List<int> value) async {}
  @override
  Future<void> delete(String reference) async {}
}

class FakeKnownHosts implements KnownHostRepository {
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

class MemoryRefs implements TmuxSessionRepository {
  final rows = <TmuxSessionReference>[];
  @override
  Future<List<TmuxSessionReference>> forServer(String serverId) async =>
      rows.where((row) => row.serverId == serverId).toList();
  @override
  Future<void> save(TmuxSessionReference reference) async {
    rows.removeWhere((row) =>
        row.serverId == reference.serverId &&
        row.remoteName == reference.remoteName);
    rows.add(reference);
  }

  @override
  Future<void> delete(String serverId, String remoteName) async =>
      rows.removeWhere(
          (row) => row.serverId == serverId && row.remoteName == remoteName);
  @override
  Future<void> deleteServer(String serverId) async =>
      rows.removeWhere((row) => row.serverId == serverId);
  @override
  Future<void> readCheck() async {}
}

class Remote {
  bool installed = true;
  final sessions = <String, int>{};
  final commands = <List<String>>[];
  int attached = 0;
}

class FakeTerminal implements TerminalSession {
  FakeTerminal(this.onClose);
  final void Function() onClose;
  final stream = StreamController<List<int>>.broadcast();
  bool closed = false;
  @override
  Stream<List<int>> get output => stream.stream;
  @override
  Future<void> send(List<int> input) async {}
  @override
  Future<void> resize(int columns, int rows) async {}
  @override
  Future<void> close() async {
    if (closed) return;
    closed = true;
    onClose();
    await stream.close();
  }
}

class FakeHandle implements SshTmuxTransportHandle {
  FakeHandle(this.remote);
  final Remote remote;
  final doneSignal = Completer<void>();
  @override
  Future<void> get done => doneSignal.future;
  @override
  Future<void> close() async {
    if (!doneSignal.isCompleted) doneSignal.complete();
  }

  @override
  Future<TerminalSession> openTerminal(int columns, int rows) async =>
      FakeTerminal(() {});
  @override
  Future<TerminalSession> attachTmux(String name, int columns, int rows) async {
    remote.attached++;
    remote.sessions[name] = (remote.sessions[name] ?? 0) + 1;
    return FakeTerminal(() {
      remote.attached--;
      remote.sessions[name] = (remote.sessions[name] ?? 1) - 1;
    });
  }

  @override
  Future<RemoteCommandResult> run(List<String> arguments,
      {Duration timeout = const Duration(seconds: 10)}) async {
    remote.commands.add(List.of(arguments));
    if (arguments.first == 'command') {
      return RemoteCommandResult(remote.installed ? 0 : 1,
          remote.installed ? '/usr/bin/tmux\n' : '', '');
    }
    if (arguments.length > 1 && arguments[1] == '-V') {
      return const RemoteCommandResult(0, 'tmux 3.5a\n', '');
    }
    if (arguments.length > 1 && arguments[1] == 'list-sessions') {
      if (remote.sessions.isEmpty) return const RemoteCommandResult(1, '', '');
      final lines = remote.sessions.entries
          .map((row) => row.key + ':' + row.value.toString() + ':1700000000')
          .join('\n');
      return RemoteCommandResult(0, lines + '\n', '');
    }
    if (arguments.contains('new-session')) {
      remote.sessions[arguments[arguments.indexOf('-s') + 1]] = 0;
      return const RemoteCommandResult(0, '', '');
    }
    if (arguments.contains('kill-session')) {
      remote.sessions.remove(arguments.last.substring(1));
      return const RemoteCommandResult(0, '', '');
    }
    return const RemoteCommandResult(2, '', '');
  }
}

class FakeTransport implements SshTransport {
  FakeTransport(this.remote);
  final Remote remote;
  @override
  Future<SshTransportHandle> open(
      ServerProfile profile,
      SshCredential credential,
      Future<bool> Function(String, String) verifyHostKey,
      SshTimeouts timeouts) async {
    await verifyHostKey('ssh-ed25519', 'SHA256:' + 'A' * 43);
    return FakeHandle(remote);
  }
}

void main() {
  const profile = ServerProfile(
      id: 'server',
      name: 'Lab',
      host: '127.0.0.1',
      username: 'lab',
      credentialId: 'dummy');

  Future<SshConnectionService> connect(Remote remote) async {
    final service = SshConnectionService(
        credentials: FakeCredentials(),
        knownHosts: FakeKnownHosts(),
        transport: FakeTransport(remote));
    await service.connect(profile, approve: (_, __) async => true);
    return service;
  }

  test('session names and working directories block injection', () {
    expect(validTmuxName(newTmuxName()), isTrue);
    for (final bad in [
      ';',
      '&&',
      '|',
      String.fromCharCode(96),
      r'$()',
      '"',
      "'",
      'a\nb'
    ]) {
      expect(validTmuxName('ad_' + bad), isFalse);
      expect(validWorkingDirectory('/home/' + bad), isFalse);
    }
    expect(validWorkingDirectory('/home/lab/my project'), isTrue);
    expect(validWorkingDirectory('relative'), isFalse);
    expect(validWorkingDirectory('/home/../root'), isFalse);
    expect(quotePosixArgument("a'b"), "'a'\"'\"'b'");
    expect(() => quotePosixArgument('a\nb'), throwsA(isA<SshFailure>()));
  });

  test('detect, create, attach, detach, reconnect, stale and terminate',
      () async {
    final remote = Remote();
    final refs = MemoryRefs();
    final connection = await connect(remote);
    final tmux = TmuxService(
        connection: connection, references: refs, serverId: profile.id);
    final capability = await tmux.detect();
    expect(capability.availability, TmuxAvailability.available);
    expect(capability.version, '3.5a');
    remote.sessions['external'] = 1;
    final created = await tmux.create(
        displayName: 'Working session',
        workingDirectory: '/home/lab/my project');
    expect(validTmuxName(created.remoteName), isTrue);
    expect(remote.commands.lastWhere((args) => args.contains('new-session')),
        contains('/home/lab/my project'));
    final listed = await tmux.list();
    expect(listed.where((s) => s.remoteName == 'external').single.managed,
        isFalse);
    expect(
        listed.where((s) => s.remoteName == created.remoteName).single.managed,
        isTrue);
    final channel = await tmux.attach(created.remoteName, 80, 24);
    expect(remote.attached, 1);
    await tmux.detach(channel);
    expect(remote.attached, 0);
    expect(remote.sessions.containsKey(created.remoteName), isTrue);
    await connection.disconnect();
    expect(remote.sessions.containsKey(created.remoteName), isTrue);
    await connection.connect(profile, approve: (_, __) async => true);
    final resumed = await tmux.attach(created.remoteName, 120, 40);
    expect(remote.attached, 1);
    await resumed.close();
    expect(refs.rows.single.lastAttachedAt, isNotNull);
    await tmux.terminate(created.remoteName);
    expect(remote.sessions.containsKey(created.remoteName), isFalse);
    expect(refs.rows, isEmpty);
    expect(remote.sessions.containsKey('external'), isTrue);
    await connection.dispose();
  });

  test('missing remote session is stale and cannot be resumed', () async {
    final remote = Remote();
    final refs = MemoryRefs();
    final connection = await connect(remote);
    final tmux = TmuxService(
        connection: connection, references: refs, serverId: profile.id);
    const name = 'ad_0011223344556677';
    await refs.save(const TmuxSessionReference(
        serverId: 'server', remoteName: name, displayName: 'Old'));
    expect((await tmux.list()).single.state, TmuxSessionState.stale);
    await expectLater(tmux.attach(name, 80, 24),
        throwsA(isA<TmuxFailure>().having((e) => e.kind, 'kind', 'missing')));
    await expectLater(
        tmux.attach('ad_;evil', 80, 24), throwsA(isA<TmuxFailure>()));
    await connection.dispose();
  });

  test('no tmux leaves SSH connected', () async {
    final remote = Remote()..installed = false;
    final connection = await connect(remote);
    final tmux = TmuxService(
        connection: connection, references: MemoryRefs(), serverId: profile.id);
    expect((await tmux.detect()).availability, TmuxAvailability.notInstalled);
    expect(connection.connectedProfileId, profile.id);
    await connection.dispose();
  });

  test('reference file survives restart and rejects corruption', () async {
    final directory =
        await Directory.systemTemp.createTemp('agentdeck-tmux-test-');
    try {
      final file = File(directory.path + Platform.pathSeparator + 'refs.json');
      final first = FileTmuxSessionRepository(JsonFileStore(file));
      await first.save(const TmuxSessionReference(
          serverId: 'server',
          remoteName: 'ad_0011223344556677',
          displayName: 'Saved'));
      final second = FileTmuxSessionRepository(JsonFileStore(file));
      expect((await second.forServer('server')).single.displayName, 'Saved');
      await second.deleteServer('server');
      expect(await second.forServer('server'), isEmpty);
      await file.writeAsString(
          '{"schema":1,"items":[{"serverId":"server","remoteName":";"}]}');
      await expectLater(second.readCheck(), throwsFormatException);
    } finally {
      await directory.delete(recursive: true);
    }
  });

  testWidgets('no tmux page shows fallback and production', (tester) async {
    final remote = Remote()..installed = false;
    final connection = await connect(remote);
    const production = ServerProfile(
        id: 'server',
        name: 'Production Lab',
        host: '127.0.0.1',
        username: 'lab',
        credentialId: 'dummy',
        environment: Environment.production);
    await tester.pumpWidget(MaterialApp(
        home: PersistentSessionsPage(
            profile: production,
            connection: connection,
            references: MemoryRefs())));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('PRODUCTION'), findsOneWidget);
    expect(find.textContaining('tmux is not installed'), findsOneWidget);
    expect(find.text('New temporary shell'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await connection.dispose();
  });
}
