import '../../../core/domain/profiles.dart';

enum SshFailureKind {
  invalidProfile,
  missingCredential,
  secureStorageUnavailable,
  hostUnknown,
  hostMismatch,
  hostRevoked,
  authentication,
  dns,
  timeout,
  refused,
  network,
  protocol,
  unsupportedAlgorithm,
  closed,
  cancelled,
}

class SshFailure implements Exception {
  const SshFailure(this.kind, {this.expected, this.received});
  final SshFailureKind kind;
  final HostIdentity? expected;
  final HostIdentity? received;
}

class HostIdentity {
  HostIdentity(String algorithm, String fingerprint)
      : algorithm = algorithm.trim(),
        fingerprint = fingerprint.trim() {
    if (this.algorithm.isEmpty ||
        !RegExp(r'^SHA256:[A-Za-z0-9+/]{43}$').hasMatch(this.fingerprint)) {
      throw const FormatException('Invalid SSH host fingerprint');
    }
  }

  final String algorithm;
  final String fingerprint;

  bool sameAs(HostIdentity other) =>
      algorithm == other.algorithm && fingerprint == other.fingerprint;
}

class KnownHost {
  const KnownHost({
    required this.hostname,
    required this.port,
    required this.identity,
    required this.firstSeenAt,
    required this.lastSeenAt,
    this.revoked = false,
  });

  final String hostname;
  final int port;
  final HostIdentity identity;
  final DateTime firstSeenAt;
  final DateTime lastSeenAt;
  final bool revoked;
}

abstract interface class KnownHostRepository {
  Future<KnownHost?> find(String hostname, int port);
  Future<void> trust(KnownHost host);
  Future<void> revoke(String hostname, int port);
  Future<void> replace(KnownHost host);
  Future<void> delete(String hostname, int port);
  Future<void> markSeen(String hostname, int port, DateTime at);
}

typedef HostApproval = Future<bool> Function(
    ServerProfile profile, HostIdentity identity);

class HostTrustService {
  HostTrustService(this.repository, {DateTime Function()? clock})
      : _clock = clock ?? DateTime.now;

  final KnownHostRepository repository;
  final DateTime Function() _clock;

  Future<void> verify(ServerProfile profile, HostIdentity candidate,
      {HostApproval? approve}) async {
    final host = profile.host.trim().toLowerCase();
    final known = await repository.find(host, profile.port);
    if (known?.revoked == true) {
      throw SshFailure(SshFailureKind.hostRevoked,
          expected: known!.identity, received: candidate);
    }
    if (known == null) {
      if (approve == null || !await approve(profile, candidate)) {
        throw SshFailure(SshFailureKind.hostUnknown, received: candidate);
      }
      final now = _clock();
      await repository.trust(KnownHost(
        hostname: host,
        port: profile.port,
        identity: candidate,
        firstSeenAt: now,
        lastSeenAt: now,
      ));
      return;
    }
    if (!known.identity.sameAs(candidate)) {
      throw SshFailure(SshFailureKind.hostMismatch,
          expected: known.identity, received: candidate);
    }
    await repository.markSeen(host, profile.port, _clock());
  }
}

class SshCredential {
  const SshCredential.password(this.secret)
      : method = SshAuthenticationMethod.password,
        passphrase = null;
  const SshCredential.privateKey(this.secret, {this.passphrase})
      : method = SshAuthenticationMethod.privateKey;

  final SshAuthenticationMethod method;
  final String secret;
  final String? passphrase;
}

class SshTimeouts {
  const SshTimeouts({
    this.tcp = const Duration(seconds: 10),
    this.handshake = const Duration(seconds: 15),
    this.authentication = const Duration(seconds: 15),
  });

  final Duration tcp;
  final Duration handshake;
  final Duration authentication;

  bool get valid =>
      tcp > Duration.zero &&
      handshake > Duration.zero &&
      authentication > Duration.zero;
}

class ReconnectPolicy {
  const ReconnectPolicy({
    this.enabled = false,
    this.maxAttempts = 2,
    this.delay = const Duration(seconds: 2),
  });

  final bool enabled;
  final int maxAttempts;
  final Duration delay;

  bool get valid =>
      maxAttempts >= (enabled ? 1 : 0) &&
      maxAttempts <= 5 &&
      delay >= Duration.zero;
}

abstract interface class SshTransportHandle {
  Future<void> get done;
  Future<void> close();
}

abstract interface class SshTransport {
  Future<SshTransportHandle> open(
    ServerProfile profile,
    SshCredential credential,
    Future<bool> Function(String algorithm, String fingerprint) verifyHostKey,
    SshTimeouts timeouts,
  );
}
