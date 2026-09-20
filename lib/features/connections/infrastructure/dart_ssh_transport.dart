import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';

import '../../../core/domain/profiles.dart';
import '../../../core/domain/remote_contracts.dart';
import '../../files/domain/remote_file_models.dart';
import '../../files/infrastructure/dart_ssh_sftp_adapter.dart';
import '../domain/ssh_models.dart';

class DartSshTransport implements SshTransport {
  const DartSshTransport();

  @override
  Future<SshTransportHandle> open(
    ServerProfile profile,
    SshCredential credential,
    Future<bool> Function(String algorithm, String fingerprint) verifyHostKey,
    SshTimeouts timeouts,
  ) async {
    SSHSocket? socket;
    SSHClient? client;
    SshFailure? trustFailure;
    try {
      socket = await SSHSocket.connect(
        profile.host,
        profile.port,
        timeout: timeouts.tcp,
      );
      final identities = credential.method == SshAuthenticationMethod.privateKey
          ? SSHKeyPair.fromPem(credential.secret, credential.passphrase)
          : null;
      client = SSHClient(
        socket,
        username: profile.username,
        onPasswordRequest: credential.method == SshAuthenticationMethod.password
            ? () => credential.secret
            : null,
        identities: identities,
        onVerifyHostKey: (algorithm, fingerprint) async {
          try {
            return await verifyHostKey(algorithm, utf8.decode(fingerprint));
          } on SshFailure catch (failure) {
            trustFailure = failure;
            return false;
          } catch (_) {
            trustFailure = const SshFailure(SshFailureKind.protocol);
            return false;
          }
        },
        handshakeTimeout: timeouts.handshake,
        authTimeout: timeouts.authentication,
        keepAliveInterval: null,
      );
      await client.authenticated;
      return _DartSshHandle(client);
    } catch (error) {
      if (client != null) {
        try {
          await client.close();
        } catch (_) {}
      } else {
        socket?.destroy();
      }
      if (trustFailure != null) throw trustFailure!;
      throw _mapError(error);
    }
  }

  SshFailure _mapError(Object error) {
    if (error is SshFailure) return error;
    if (error is TimeoutException) {
      return const SshFailure(SshFailureKind.timeout);
    }
    if (error is SSHAuthFailError) {
      return const SshFailure(SshFailureKind.authentication);
    }
    if (error is SSHKeyDecodeError || error is UnsupportedError) {
      return const SshFailure(SshFailureKind.unsupportedAlgorithm);
    }
    if (error is SocketException) return classifySocketException(error);
    if (error is SSHSocketError) {
      return _mapError(error.error);
    }
    if (error is SSHHostkeyError) {
      return const SshFailure(SshFailureKind.hostMismatch);
    }
    if (error is SSHAuthAbortError || error is SSHDisconnectError) {
      return const SshFailure(SshFailureKind.closed);
    }
    return const SshFailure(SshFailureKind.protocol);
  }
}

String quotePosixArgument(String value) {
  if (value.contains('\u0000') ||
      value.contains('\n') ||
      value.contains('\r')) {
    throw const SshFailure(SshFailureKind.invalidProfile);
  }
  return "'" + value.replaceAll("'", "'\"'\"'") + "'";
}

class _DartSshHandle implements SshSftpTransportHandle {
  const _DartSshHandle(this.client);
  final SSHClient client;

  @override
  Future<RemoteFileSystem> openSftp() async {
    try {
      final sftp = await client.sftp();
      return DartSshSftpAdapter(sftp);
    } catch (_) {
      throw const SshFailure(SshFailureKind.protocol);
    }
  }

  @override
  Future<TerminalSession> openTerminal(int columns, int rows) async {
    try {
      final session = await client.shell(
        pty: SSHPtyConfig(type: 'xterm-256color', width: columns, height: rows),
      );
      return _DartTerminalSession(session);
    } catch (_) {
      throw const SshFailure(SshFailureKind.protocol);
    }
  }

  @override
  Future<RemoteCommandResult> run(List<String> arguments,
      {Duration timeout = const Duration(seconds: 10)}) async {
    if (arguments.isEmpty ||
        arguments.length > 16 ||
        arguments.any((part) => part.length > 4096)) {
      throw const SshFailure(SshFailureKind.invalidProfile);
    }
    SSHSession? session;
    try {
      session =
          await client.execute(arguments.map(quotePosixArgument).join(' '));
      final out = <int>[];
      final err = <int>[];
      var overflow = false;
      void collect(List<int> bytes, List<int> target) {
        if (out.length + err.length + bytes.length > 65536) {
          overflow = true;
          session?.close();
        } else {
          target.addAll(bytes);
        }
      }

      final outDone =
          session.stdout.listen((data) => collect(data, out)).asFuture<void>();
      final errDone =
          session.stderr.listen((data) => collect(data, err)).asFuture<void>();
      await Future.wait([session.done, outDone, errDone]).timeout(timeout);
      if (overflow) throw const SshFailure(SshFailureKind.protocol);
      return RemoteCommandResult(
          session.exitCode ?? 255,
          utf8.decode(out, allowMalformed: true),
          utf8.decode(err, allowMalformed: true));
    } on TimeoutException {
      session?.close();
      throw const SshFailure(SshFailureKind.timeout);
    } on SshFailure {
      rethrow;
    } catch (_) {
      session?.close();
      throw const SshFailure(SshFailureKind.protocol);
    }
  }

  @override
  Future<TerminalSession> attachTmux(String name, int columns, int rows) async {
    try {
      final command = ['tmux', '-u', 'attach-session', '-t', '=' + name]
          .map(quotePosixArgument)
          .join(' ');
      final session = await client.execute(command,
          pty: SSHPtyConfig(
              type: 'xterm-256color', width: columns, height: rows));
      return _DartTerminalSession(session);
    } catch (_) {
      throw const SshFailure(SshFailureKind.protocol);
    }
  }

  @override
  Future<void> get done => client.done;

  @override
  Future<void> close() => client.close();
}

class _DartTerminalSession implements TerminalSession {
  _DartTerminalSession(this.session);
  final SSHSession session;
  bool _closed = false;

  @override
  Stream<List<int>> get output => session.stdout;

  @override
  Future<void> send(List<int> input) async {
    if (_closed) throw const SshFailure(SshFailureKind.closed);
    try {
      session.write(Uint8List.fromList(input));
    } catch (_) {
      throw const SshFailure(SshFailureKind.closed);
    }
  }

  @override
  Future<void> resize(int columns, int rows) async {
    if (_closed) throw const SshFailure(SshFailureKind.closed);
    session.resizeTerminal(columns, rows);
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    try {
      session.write(
          Uint8List.fromList(const [2, 100])); // Ctrl+B, d (tmux detach client)
      await Future<void>.delayed(const Duration(milliseconds: 100));
    } catch (_) {}
    session.close();
    try {
      await session.done.timeout(const Duration(seconds: 2));
    } catch (_) {}
  }
}

/// Classifies OS socket errors without depending only on localized messages.
SshFailure classifySocketException(SocketException error) {
  final code = error.osError?.errorCode;
  if (code == 10060 || code == 110) {
    return const SshFailure(SshFailureKind.timeout);
  }
  if (code == 10061 || code == 1225 || code == 111) {
    return const SshFailure(SshFailureKind.refused);
  }
  if (code == 11001 || code == 7 || code == 8) {
    return const SshFailure(SshFailureKind.dns);
  }
  final message = error.message.toLowerCase();
  if (message.contains('timed out')) {
    return const SshFailure(SshFailureKind.timeout);
  }
  if (message.contains('failed host lookup') ||
      message.contains('no such host')) {
    return const SshFailure(SshFailureKind.dns);
  }
  if (message.contains('refused')) {
    return const SshFailure(SshFailureKind.refused);
  }
  return const SshFailure(SshFailureKind.network);
}
