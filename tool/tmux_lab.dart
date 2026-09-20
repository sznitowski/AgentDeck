// Disposable loopback OpenSSH + tmux integration lab.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:agentdeck/core/domain/profiles.dart';
import 'package:agentdeck/core/domain/remote_contracts.dart';
import 'package:agentdeck/features/connections/application/ssh_connection_service.dart';
import 'package:agentdeck/features/connections/domain/ssh_models.dart';
import 'package:agentdeck/features/connections/infrastructure/dart_ssh_transport.dart';
import 'package:agentdeck/features/terminal/application/terminal_controller.dart';
import 'package:agentdeck/features/tmux/application/tmux_service.dart';
import 'package:agentdeck/features/tmux/domain/tmux_models.dart';
import 'package:agentdeck/features/tmux/infrastructure/file_tmux_session_repository.dart';
import 'package:agentdeck/core/infrastructure/json_file_store.dart';

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
      id: 'tmux-lab',
      name: 'Lab',
      host: host,
      port: port,
      username: 'lab',
      credentialId: 'lab',
      authenticationMethod: SshAuthenticationMethod.password);
  final now = DateTime.now().toUtc();
  final known = KnownHost(
      hostname: host,
      port: port,
      identity: HostIdentity('ssh-ed25519', fingerprint),
      firstSeenAt: now,
      lastSeenAt: now);
  SshConnectionService makeConnection() => SshConnectionService(
      credentials: _Secrets(utf8.encode(password)),
      knownHosts: _Hosts(known),
      transport: const DartSshTransport());
  final directory = await Directory.systemTemp.createTemp('agentdeck-m3-refs-');
  final file = File('${directory.path}${Platform.pathSeparator}refs.json');
  final refs = FileTmuxSessionRepository(JsonFileStore(file));
  var connection = makeConnection();
  var tmux = TmuxService(
      connection: connection, references: refs, serverId: profile.id);
  TerminalController? terminal;
  StreamSubscription<String>? sub;
  var output = '';
  String? name;
  Future<void> waitFor(String marker) async {
    final deadline = DateTime.now().add(const Duration(seconds: 15));
    while (!output.contains(marker)) {
      if (DateTime.now().isAfter(deadline))
        throw StateError('Marker timeout: $marker');
      await Future<void>.delayed(const Duration(milliseconds: 30));
    }
  }

  Future<String> command(String value, String marker) async {
    output = '';
    await terminal!.send('$value\n');
    await waitFor(marker);
    return output;
  }

  Future<void> openTmux() async {
    terminal = TerminalController(connection,
        openSession: (columns, rows) => tmux.attach(name!, columns, rows));
    sub = terminal!.output.listen((chunk) => output += chunk);
    await terminal!.open(columns: 80, rows: 24);
    await Future<void>.delayed(const Duration(milliseconds: 400));
    await terminal!.send('stty -echo\n');
    await Future<void>.delayed(const Duration(milliseconds: 200));
  }

  try {
    await connection.connect(profile);
    final capability = await tmux.detect();
    if (capability.availability != TmuxAvailability.available)
      throw StateError('A: tmux not detected');
    stdout.writeln('A detect tmux ${capability.version}: PASS');
    final session = await tmux.create(
        displayName: 'M3 lab session', workingDirectory: '/home/lab');
    name = session.remoteName;
    if (!validTmuxName(name)) throw StateError('B: generated name invalid');
    if (!(await tmux.list()).any((s) => s.remoteName == name && s.managed))
      throw StateError('B: create/list');
    stdout.writeln('B create/list: PASS');
    await openTmux();
    final echo = await command(
        'echo LAB_ECHO; printf "LAB_ECHO_DONE\\n"', 'LAB_ECHO_DONE');
    if (!echo.contains('LAB_ECHO')) throw StateError('C: echo');
    stdout.writeln('C attach and echo: PASS');
    final pwd = await command('pwd; printf "LAB_PWD_DONE\\n"', 'LAB_PWD_DONE');
    if (!pwd.contains('/home/lab')) throw StateError('D: cwd');
    stdout.writeln('D working directory: PASS');
    final utf = await command(
        'printf "ñ漢字🧪\\n"; printf "LAB_UTF_DONE\\n"', 'LAB_UTF_DONE');
    if (!utf.contains('ñ漢字🧪')) throw StateError('E: UTF-8');
    stdout.writeln('E UTF-8: PASS');
    final size1 = await command(
        'stty size; printf "LAB_SIZE1_DONE\\n"', 'LAB_SIZE1_DONE');
    if (!RegExp(r'(23|24)\s+80').hasMatch(size1)) {
      throw StateError('F: initial size ($size1)');
    }
    terminal!.resize(120, 40);
    await Future<void>.delayed(const Duration(milliseconds: 500));
    final size2 = await command(
        'stty size; printf "LAB_SIZE2_DONE\\n"', 'LAB_SIZE2_DONE');
    if (!RegExp(r'(39|40)\s+120').hasMatch(size2)) {
      throw StateError('F: resize ($size2)');
    }
    stdout.writeln('F resize: PASS');
    output = '';
    await terminal!.send('sleep 30; echo LAB_SLEEP_BAD\n');
    await Future<void>.delayed(const Duration(milliseconds: 500));
    await terminal!.send('\x03');
    final interrupt = await command('printf "LAB_INT_DONE\\n"', 'LAB_INT_DONE');
    if (interrupt.contains('LAB_SLEEP_BAD\r\n')) throw StateError('G: Ctrl+C');
    stdout.writeln('G Ctrl+C: PASS');
    final fileName = '/tmp/$name.survived';
    await terminal!.send('sleep 3; echo survived > $fileName\n');
    await Future<void>.delayed(const Duration(milliseconds: 300));
    await connection.disconnect();
    await sub?.cancel();
    await terminal?.close();
    sub = null;
    terminal = null;
    await Future<void>.delayed(const Duration(seconds: 4));
    connection = makeConnection();
    await connection.connect(profile);
    tmux = TmuxService(
        connection: connection,
        references: FileTmuxSessionRepository(JsonFileStore(file)),
        serverId: profile.id);
    final found = (await tmux.list()).where((s) => s.remoteName == name).single;
    if (!found.managed || found.state == TmuxSessionState.stale)
      throw StateError('H: session lost');
    final survived = await connection.runRemoteCommand(['cat', fileName]);
    if (survived.exitCode != 0 || survived.stdout.trim() != 'survived')
      throw StateError('H: process did not survive');
    stdout.writeln(
        'H SSH loss, process continuity and persisted reference: PASS');
    await openTmux();
    final resumed = await command(
        'echo LAB_RESUMED; printf "LAB_RESUME_DONE\\n"', 'LAB_RESUME_DONE');
    if (!resumed.contains('LAB_RESUMED')) throw StateError('I: resume');
    stdout.writeln('I reconnect and reattach: PASS');
    await terminal!.close();
    await sub?.cancel();
    terminal = null;
    sub = null;
    var detached = false;
    final deadline = DateTime.now().add(const Duration(seconds: 5));
    while (DateTime.now().isBefore(deadline)) {
      final list = await tmux.list();
      final current = list.where((s) => s.remoteName == name).firstOrNull;
      if (current != null && current.state == TmuxSessionState.detached) {
        detached = true;
        break;
      }
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    if (!detached) {
      final clientsRaw =
          await connection.runRemoteCommand(['tmux', 'list-clients']);
      final psRaw = await connection.runRemoteCommand(['ps', 'aux']);
      final sessionsRaw = await connection.runRemoteCommand([
        'tmux',
        'list-sessions',
        '-F',
        '#{session_name}:#{session_attached}:#{session_created}'
      ]);
      final stateNow = (await tmux.list())
          .where((s) => s.remoteName == name)
          .firstOrNull
          ?.state;
      throw StateError(
          'J: detach removed session (state: $stateNow, clients="${clientsRaw.stdout.trim()}", sessions="${sessionsRaw.stdout.trim()}", ps="${psRaw.stdout.trim()}")');
    }
    stdout.writeln('J detach retains session: PASS');
    await tmux.terminate(name);
    if ((await tmux.list()).any((s) => s.remoteName == name))
      throw StateError('K: termination');
    name = null;
    stdout.writeln('K terminate: PASS');
  } catch (error, stack) {
    stderr.writeln('M3 lab failed: $error');
    stderr.writeln(stack);
    exitCode = 1;
  } finally {
    await sub?.cancel();
    await terminal?.close();
    if (name != null) {
      try {
        await tmux.terminate(name);
      } catch (_) {}
    }
    await connection.dispose();
    await directory.delete(recursive: true);
  }
}
