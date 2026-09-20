import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dartssh2/dartssh2.dart';

import '../../../core/domain/profiles.dart';
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

class _DartSshHandle implements SshTransportHandle {
  const _DartSshHandle(this.client);
  final SSHClient client;

  @override
  Future<void> get done => client.done;

  @override
  Future<void> close() => client.close();
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
