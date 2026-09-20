// Disposable loopback-only OpenSSH terminal lab. No production targets.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:agentdeck/core/domain/profiles.dart';
import 'package:agentdeck/core/domain/remote_contracts.dart';
import 'package:agentdeck/features/connections/application/ssh_connection_service.dart';
import 'package:agentdeck/features/connections/domain/ssh_models.dart';
import 'package:agentdeck/features/connections/infrastructure/dart_ssh_transport.dart';
import 'package:agentdeck/features/terminal/application/terminal_controller.dart';

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
        'Loopback host, port, disposable password and pinned fingerprint required.');
    exitCode = 2;
    return;
  }
  final profile = ServerProfile(
      id: 'terminal-lab',
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
  final service = SshConnectionService(
      credentials: _Secrets(utf8.encode(password)),
      knownHosts: _Hosts(known),
      transport: const DartSshTransport());
  TerminalController? terminal;
  StreamSubscription<String>? sub;
  var output = '';
  Future<void> waitFor(String marker) async {
    final deadline = DateTime.now().add(const Duration(seconds: 15));
    while (!output.contains(marker)) {
      if (DateTime.now().isAfter(deadline))
        throw StateError('Timed out waiting for lab marker');
      await Future<void>.delayed(const Duration(milliseconds: 30));
    }
  }

  Future<String> command(String value, String marker) async {
    output = '';
    await terminal!.send('$value\n');
    await waitFor(marker);
    return output;
  }

  try {
    await service.connect(profile);
    terminal = TerminalController(service);
    sub = terminal.output.listen((value) => output += value);
    await terminal.open(columns: 80, rows: 24);
    await terminal.send('stty -echo\n');
    await Future<void>.delayed(const Duration(milliseconds: 150));
    final a = await command('tty; printf "LAB_A_DONE\\n"', 'LAB_A_DONE');
    if (!a.contains('/dev/pts/')) throw StateError('A: no PTY');
    final term = await command(
        'echo \$TERM; printf "LAB_TERM_DONE\\n"', 'LAB_TERM_DONE');
    if (!term.contains('xterm-256color')) throw StateError('A: TERM');
    stdout.writeln('A PTY and TERM: PASS');
    final b =
        await command('echo LAB_ECHO; printf "LAB_B_DONE\\n"', 'LAB_B_DONE');
    if (!b.contains('LAB_ECHO')) throw StateError('B: echo');
    stdout.writeln('B echo: PASS');
    final c = await command('pwd; printf "LAB_C_DONE\\n"', 'LAB_C_DONE');
    if (!c.contains('/home/lab')) throw StateError('C: pwd');
    stdout.writeln('C pwd: PASS');
    final d = await command(
        'printf "ñ漢字🧪\\n"; printf "LAB_D_DONE\\n"', 'LAB_D_DONE');
    if (!d.contains('ñ漢字🧪')) throw StateError('D: UTF-8');
    stdout.writeln('D UTF-8: PASS');
    final e1 =
        await command('stty size; printf "LAB_E1_DONE\\n"', 'LAB_E1_DONE');
    if (!e1.contains('24 80')) throw StateError('E: initial size');
    terminal.resize(120, 40);
    await Future<void>.delayed(const Duration(milliseconds: 300));
    final e2 =
        await command('stty size; printf "LAB_E2_DONE\\n"', 'LAB_E2_DONE');
    if (!e2.contains('40 120')) throw StateError('E: resized size');
    stdout.writeln('E resize: PASS');
    output = '';
    await terminal.send('sleep 30; echo LAB_SLEEP_BAD\n');
    await Future<void>.delayed(const Duration(milliseconds: 500));
    await terminal.send('\x03');
    final f = await command('printf "LAB_F_DONE\\n"', 'LAB_F_DONE');
    if (f.contains('LAB_SLEEP_BAD\r\n')) throw StateError('F: Ctrl+C failed');
    stdout.writeln('F Ctrl+C: PASS');
    final large = await command(
        'seq 1 2000; printf "LAB_LARGE_DONE\\n"', 'LAB_LARGE_DONE');
    if (!large.contains('\r\n2000\r\n'))
      throw StateError('Large output truncated');
    stdout.writeln('Large output: PASS');
    await terminal.close();
    // A channel close must leave the verified SSH connection available.
    if (service.state.name != 'connected')
      throw StateError('G: SSH connection closed');
    stdout.writeln('G channel cleanup: PASS');
    await service.disconnect();
    stdout.writeln('SSH disconnect: PASS');
  } catch (error) {
    stderr.writeln(
        'Terminal lab failed: ${error is SshFailure ? error.kind.name : error is StateError ? error.message : error.runtimeType}');
    exitCode = 1;
  } finally {
    await sub?.cancel();
    await terminal?.close();
    await service.dispose();
  }
}
