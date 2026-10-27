import 'dart:async';
import 'dart:convert';

import '../../../core/domain/agents.dart';
import '../../../core/domain/profiles.dart';
import '../../../core/domain/remote_contracts.dart';
import '../../files/domain/remote_file_models.dart';
import '../../tmux/domain/tmux_models.dart';
import '../domain/ssh_models.dart';

class SshConnectionService {
  SshConnectionService({
    required this.credentials,
    required this.knownHosts,
    required this.transport,
    this.timeouts = const SshTimeouts(),
    Future<void> Function(Duration)? delay,
  }) : _delay = delay ?? Future<void>.delayed;

  final SecureCredentialStore credentials;
  final KnownHostRepository knownHosts;
  final SshTransport transport;
  final SshTimeouts timeouts;
  final Future<void> Function(Duration) _delay;

  final _states = StreamController<ConnectionState>.broadcast();
  Stream<ConnectionState> get states => _states.stream;
  ConnectionState state = ConnectionState.disconnected;
  SshFailure? lastFailure;
  String? connectedProfileId;
  SshTransportHandle? _handle;
  int _generation = 0;

  void _setState(ConnectionState value) {
    state = value;
    if (!_states.isClosed) _states.add(value);
  }

  Future<void> connect(ServerProfile profile, {HostApproval? approve}) async {
    if (state == ConnectionState.connecting ||
        state == ConnectionState.reconnecting ||
        state == ConnectionState.connected) {
      throw const SshFailure(SshFailureKind.invalidProfile);
    }
    final generation = ++_generation;
    await _attempt(profile, approve, generation, reconnecting: false);
  }

  Future<void> _attempt(
      ServerProfile profile, HostApproval? approve, int generation,
      {required bool reconnecting}) async {
    _setState(reconnecting
        ? ConnectionState.reconnecting
        : ConnectionState.connecting);
    lastFailure = null;
    try {
      if (profile.host.trim().isEmpty ||
          profile.username.trim().isEmpty ||
          profile.port < 1 ||
          profile.port > 65535 ||
          profile.credentialId.trim().isEmpty ||
          !timeouts.valid) {
        throw const SshFailure(SshFailureKind.invalidProfile);
      }
      final credential = await _resolveCredential(profile);
      if (generation != _generation) {
        throw const SshFailure(SshFailureKind.cancelled);
      }
      final trust = HostTrustService(knownHosts);
      final handle = await transport.open(
        profile,
        credential,
        (algorithm, fingerprint) async {
          await trust.verify(profile, HostIdentity(algorithm, fingerprint),
              approve: approve == null
                  ? null
                  : (server, identity) async {
                      final accepted = await approve(server, identity);
                      return accepted && generation == _generation;
                    });
          return true;
        },
        timeouts,
      );
      if (generation != _generation) {
        await handle.close();
        throw const SshFailure(SshFailureKind.cancelled);
      }
      _handle = handle;
      connectedProfileId = profile.id;
      _setState(ConnectionState.connected);
      unawaited(handle.done.then((_) {
        if (identical(_handle, handle)) {
          _handle = null;
          connectedProfileId = null;
          _setState(ConnectionState.disconnected);
        }
      }, onError: (Object _) {
        if (identical(_handle, handle)) {
          _handle = null;
          connectedProfileId = null;
          lastFailure = const SshFailure(SshFailureKind.closed);
          _setState(ConnectionState.disconnected);
        }
      }));
    } on SshFailure catch (failure) {
      if (generation != _generation) {
        throw const SshFailure(SshFailureKind.cancelled);
      }
      lastFailure = failure;
      _setState(failure.kind == SshFailureKind.cancelled
          ? ConnectionState.disconnected
          : ConnectionState.failed);
      rethrow;
    } catch (_) {
      if (generation != _generation) {
        throw const SshFailure(SshFailureKind.cancelled);
      }
      const failure = SshFailure(SshFailureKind.protocol);
      lastFailure = failure;
      _setState(ConnectionState.failed);
      throw failure;
    }
  }

  Future<SshCredential> _resolveCredential(ServerProfile profile) async {
    List<int>? raw;
    try {
      raw = await credentials.get(profile.credentialId);
    } catch (_) {
      throw const SshFailure(SshFailureKind.secureStorageUnavailable);
    }
    if (raw == null || raw.isEmpty) {
      throw const SshFailure(SshFailureKind.missingCredential);
    }
    final secret = utf8.decode(raw);
    if (profile.authenticationMethod == SshAuthenticationMethod.password) {
      return SshCredential.password(secret);
    }
    String? passphrase;
    final ref = profile.passphraseCredentialId;
    if (ref != null) {
      List<int>? passphraseBytes;
      try {
        passphraseBytes = await credentials.get(ref);
      } catch (_) {
        throw const SshFailure(SshFailureKind.secureStorageUnavailable);
      }
      if (passphraseBytes == null) {
        throw const SshFailure(SshFailureKind.missingCredential);
      }
      passphrase = utf8.decode(passphraseBytes);
    }
    return SshCredential.privateKey(secret, passphrase: passphrase);
  }

  Future<TerminalSession> openTerminal(int columns, int rows) async {
    final handle = _handle;
    if (state != ConnectionState.connected ||
        handle is! SshTerminalTransportHandle) {
      throw const SshFailure(SshFailureKind.closed);
    }
    if (columns < 1 || rows < 1 || columns > 1000 || rows > 1000) {
      throw const SshFailure(SshFailureKind.invalidProfile);
    }
    final session = await handle.openTerminal(columns, rows);
    if (!identical(_handle, handle) || state != ConnectionState.connected) {
      await session.close();
      throw const SshFailure(SshFailureKind.closed);
    }
    return session;
  }

  Future<RemoteCommandResult> runRemoteCommand(List<String> arguments,
      {Duration timeout = const Duration(seconds: 10)}) async {
    final handle = _handle;
    if (state != ConnectionState.connected ||
        handle is! SshTmuxTransportHandle) {
      throw const SshFailure(SshFailureKind.closed);
    }
    final result = await handle.run(arguments, timeout: timeout);
    if (!identical(_handle, handle))
      throw const SshFailure(SshFailureKind.closed);
    return result;
  }

  Future<TerminalSession> attachTmux(String name, int columns, int rows) async {
    final handle = _handle;
    if (state != ConnectionState.connected ||
        handle is! SshTmuxTransportHandle) {
      throw const SshFailure(SshFailureKind.closed);
    }
    if (!validTmuxName(name) ||
        columns < 1 ||
        rows < 1 ||
        columns > 1000 ||
        rows > 1000) {
      throw const SshFailure(SshFailureKind.invalidProfile);
    }
    final session = await handle.attachTmux(name, columns, rows);
    if (!identical(_handle, handle) || state != ConnectionState.connected) {
      await session.close();
      throw const SshFailure(SshFailureKind.closed);
    }
    return session;
  }

  Future<RemoteFileSystem> openSftp() async {
    final handle = _handle;
    if (state != ConnectionState.connected ||
        handle is! SshSftpTransportHandle) {
      throw const SshFailure(SshFailureKind.closed);
    }
    final fs = await handle.openSftp();
    if (!identical(_handle, handle) || state != ConnectionState.connected) {
      await fs.close();
      throw const SshFailure(SshFailureKind.closed);
    }
    return fs;
  }

  Future<void> disconnect() async {
    _generation++;
    final old = _handle;
    _handle = null;
    connectedProfileId = null;
    if (old != null) {
      try {
        await old.close();
      } catch (_) {
        // Closing is best effort; the service is disconnected either way.
      }
    }
    _setState(ConnectionState.disconnected);
  }

  Future<void> reconnect(ServerProfile profile, ReconnectPolicy policy,
      {HostApproval? approve}) async {
    if (!policy.valid || !policy.enabled) {
      throw const SshFailure(SshFailureKind.cancelled);
    }
    final generation = ++_generation;
    final old = _handle;
    _handle = null;
    connectedProfileId = null;
    if (old != null) await old.close();
    for (var attempt = 0; attempt < policy.maxAttempts; attempt++) {
      if (generation != _generation) {
        throw const SshFailure(SshFailureKind.cancelled);
      }
      if (attempt > 0) {
        await _delay(policy.delay);
        if (generation != _generation) {
          throw const SshFailure(SshFailureKind.cancelled);
        }
      }
      try {
        await _attempt(profile, approve, generation, reconnecting: true);
        return;
      } on SshFailure catch (failure) {
        if ({
          SshFailureKind.hostUnknown,
          SshFailureKind.hostMismatch,
          SshFailureKind.hostRevoked,
          SshFailureKind.authentication,
          SshFailureKind.missingCredential,
          SshFailureKind.secureStorageUnavailable,
          SshFailureKind.invalidProfile,
          SshFailureKind.cancelled,
        }.contains(failure.kind)) {
          rethrow;
        }
        if (attempt == policy.maxAttempts - 1) rethrow;
      }
    }
  }

  Future<void> dispose() async {
    await disconnect();
    await _states.close();
  }
}
