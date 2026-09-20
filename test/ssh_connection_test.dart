import 'dart:async';
import 'dart:convert';

import 'package:agentdeck/core/domain/agents.dart';
import 'package:agentdeck/core/domain/profiles.dart';
import 'package:agentdeck/core/domain/remote_contracts.dart';
import 'package:agentdeck/features/connections/application/ssh_connection_service.dart';
import 'package:agentdeck/features/connections/domain/ssh_models.dart';
import 'package:flutter_test/flutter_test.dart';

final identityA = HostIdentity('ssh-ed25519', 'SHA256:' + ('A' * 43));
final identityB = HostIdentity('ssh-ed25519', 'SHA256:' + ('B' * 43));

ServerProfile profile(
        {SshAuthenticationMethod method = SshAuthenticationMethod.password}) =>
    ServerProfile(
      id: 'server-1',
      name: 'Lab',
      host: 'example.test',
      username: 'dev',
      credentialId: 'credential-1',
      authenticationMethod: method,
    );

class TestOnlyCredentialStore implements SecureCredentialStore {
  // TEST_ONLY. Never wire this into runtime composition.
  final values = <String, List<int>>{};
  @override
  Future<void> put(String reference, List<int> secret) async =>
      values[reference] = secret;
  @override
  Future<List<int>?> get(String reference) async => values[reference];
  @override
  Future<void> delete(String reference) async => values.remove(reference);
}

class TestOnlyKnownHosts implements KnownHostRepository {
  // TEST_ONLY. Production requires durable host trust before enabling connect.
  KnownHost? host;
  @override
  Future<KnownHost?> find(String hostname, int port) async =>
      host?.hostname == hostname && host?.port == port ? host : null;
  @override
  Future<void> trust(KnownHost candidate) async {
    if (host != null) throw StateError('Explicit replacement required');
    host = candidate;
  }

  @override
  Future<void> revoke(String hostname, int port) async {
    final old = await find(hostname, port);
    if (old == null) return;
    host = KnownHost(
      hostname: old.hostname,
      port: old.port,
      identity: old.identity,
      firstSeenAt: old.firstSeenAt,
      lastSeenAt: old.lastSeenAt,
      revoked: true,
    );
  }

  @override
  Future<void> replace(KnownHost replacement) async => host = replacement;
  @override
  Future<void> delete(String hostname, int port) async => host = null;

  @override
  Future<void> markSeen(String hostname, int port, DateTime at) async {
    final old = await find(hostname, port);
    if (old == null || old.revoked) throw StateError('Host is not trusted');
    host = KnownHost(
        hostname: old.hostname,
        port: old.port,
        identity: old.identity,
        firstSeenAt: old.firstSeenAt,
        lastSeenAt: at);
  }
}

class FakeHandle implements SshTransportHandle {
  final closed = Completer<void>();
  @override
  Future<void> get done => closed.future;
  @override
  Future<void> close() async {
    if (!closed.isCompleted) closed.complete();
  }
}

class FakeTransport implements SshTransport {
  final failures = <SshFailure>[];
  SshCredential? lastCredential;
  SshTimeouts? lastTimeouts;
  int opens = 0;
  FakeHandle? handle;
  HostIdentity identity = identityA;

  @override
  Future<SshTransportHandle> open(
    ServerProfile profile,
    SshCredential credential,
    Future<bool> Function(String algorithm, String fingerprint) verifyHostKey,
    SshTimeouts timeouts,
  ) async {
    opens++;
    lastCredential = credential;
    lastTimeouts = timeouts;
    if (failures.isNotEmpty) throw failures.removeAt(0);
    final accepted =
        await verifyHostKey(identity.algorithm, identity.fingerprint);
    if (!accepted) throw const SshFailure(SshFailureKind.hostUnknown);
    return handle = FakeHandle();
  }
}

SshConnectionService service(TestOnlyCredentialStore credentials,
        TestOnlyKnownHosts hosts, FakeTransport transport,
        {Future<void> Function(Duration)? delay}) =>
    SshConnectionService(
      credentials: credentials,
      knownHosts: hosts,
      transport: transport,
      delay: delay,
    );

void main() {
  test('unknown host requires approval and explicit trust is recorded',
      () async {
    final hosts = TestOnlyKnownHosts();
    var now = DateTime.utc(2026);
    final trust = HostTrustService(hosts, clock: () => now);
    await expectLater(
      trust.verify(profile(), identityA),
      throwsA(isA<SshFailure>()
          .having((e) => e.kind, 'kind', SshFailureKind.hostUnknown)),
    );
    expect(hosts.host, isNull);
    await trust.verify(profile(), identityA,
        approve: (algorithm, fingerprint) async => true);
    expect(hosts.host!.identity.fingerprint, identityA.fingerprint);
    expect(hosts.host!.firstSeenAt, DateTime.utc(2026));
    await trust.verify(profile(), identityA);
  });

  test('changed or revoked host is blocked even with an approval callback',
      () async {
    final hosts = TestOnlyKnownHosts();
    final trust = HostTrustService(hosts);
    await trust.verify(profile(), identityA,
        approve: (algorithm, fingerprint) async => true);
    await expectLater(
      trust.verify(profile(), identityB,
          approve: (algorithm, fingerprint) async => true),
      throwsA(isA<SshFailure>()
          .having((e) => e.kind, 'kind', SshFailureKind.hostMismatch)),
    );
    expect(hosts.host!.identity.fingerprint, identityA.fingerprint);
    await hosts.revoke('example.test', 22);
    await expectLater(
      trust.verify(profile(), identityA,
          approve: (algorithm, fingerprint) async => true),
      throwsA(isA<SshFailure>()
          .having((e) => e.kind, 'kind', SshFailureKind.hostRevoked)),
    );
    await hosts.replace(KnownHost(
      hostname: 'example.test',
      port: 22,
      identity: identityB,
      firstSeenAt: DateTime.utc(2026),
      lastSeenAt: DateTime.utc(2026),
    ));
    await trust.verify(profile(), identityB);
  });

  test('password is resolved by reference before transport opens', () async {
    final credentials = TestOnlyCredentialStore()
      ..values['credential-1'] = utf8.encode('test-password');
    final hosts = TestOnlyKnownHosts();
    final transport = FakeTransport();
    final connection = service(credentials, hosts, transport);
    final states = <ConnectionState>[];
    final subscription = connection.states.listen(states.add);
    await connection.connect(profile(),
        approve: (algorithm, fingerprint) async => true);
    expect(transport.lastCredential!.method, SshAuthenticationMethod.password);
    expect(transport.lastCredential!.secret, 'test-password');
    await Future<void>.delayed(Duration.zero);
    expect(states, [ConnectionState.connecting, ConnectionState.connected]);
    await connection.disconnect();
    await Future<void>.delayed(Duration.zero);
    expect(states.last, ConnectionState.disconnected);
    await subscription.cancel();
    await connection.dispose();
  });

  test('private key and passphrase are resolved through credential references',
      () async {
    final credentials = TestOnlyCredentialStore()
      ..values['credential-1'] = utf8.encode('test-pem')
      ..values['passphrase-1'] = utf8.encode('test-passphrase');
    final transport = FakeTransport();
    final connection = service(credentials, TestOnlyKnownHosts(), transport);
    const keyProfile = ServerProfile(
      id: 'key',
      name: 'Key host',
      host: 'example.test',
      username: 'dev',
      credentialId: 'credential-1',
      passphraseCredentialId: 'passphrase-1',
      authenticationMethod: SshAuthenticationMethod.privateKey,
    );
    await connection.connect(keyProfile,
        approve: (algorithm, fingerprint) async => true);
    expect(
        transport.lastCredential!.method, SshAuthenticationMethod.privateKey);
    expect(transport.lastCredential!.secret, 'test-pem');
    expect(transport.lastCredential!.passphrase, 'test-passphrase');
    await connection.dispose();
  });

  test('missing credential fails before network and enters failed state',
      () async {
    final transport = FakeTransport();
    final connection =
        service(TestOnlyCredentialStore(), TestOnlyKnownHosts(), transport);
    await expectLater(
      connection.connect(profile()),
      throwsA(isA<SshFailure>()
          .having((e) => e.kind, 'kind', SshFailureKind.missingCredential)),
    );
    expect(transport.opens, 0);
    expect(connection.state, ConnectionState.failed);
    await connection.dispose();
  });

  test('network failure enters failed state; bounded reconnect can recover',
      () async {
    final credentials = TestOnlyCredentialStore()
      ..values['credential-1'] = utf8.encode('test-password');
    final hosts = TestOnlyKnownHosts();
    final transport = FakeTransport()
      ..failures.add(const SshFailure(SshFailureKind.network));
    final connection =
        service(credentials, hosts, transport, delay: (_) async {});
    await expectLater(
      connection.connect(profile(),
          approve: (algorithm, fingerprint) async => true),
      throwsA(isA<SshFailure>()),
    );
    expect(connection.state, ConnectionState.failed);
    await connection.reconnect(
      profile(),
      const ReconnectPolicy(enabled: true, maxAttempts: 2),
      approve: (algorithm, fingerprint) async => true,
    );
    expect(connection.state, ConnectionState.connected);
    expect(transport.opens, 2);
    await connection.dispose();
  });

  test('reconnect stops on host mismatch without another attempt', () async {
    final credentials = TestOnlyCredentialStore()
      ..values['credential-1'] = utf8.encode('test-password');
    final hosts = TestOnlyKnownHosts();
    final transport = FakeTransport();
    final connection = service(credentials, hosts, transport);
    await connection.connect(profile(),
        approve: (algorithm, fingerprint) async => true);
    transport.identity = identityB;
    await expectLater(
      connection.reconnect(
          profile(), const ReconnectPolicy(enabled: true, maxAttempts: 3)),
      throwsA(isA<SshFailure>()
          .having((e) => e.kind, 'kind', SshFailureKind.hostMismatch)),
    );
    expect(transport.opens, 2);
    await connection.dispose();
  });

  test('reconnect can be cancelled during its delay', () async {
    final credentials = TestOnlyCredentialStore()
      ..values['credential-1'] = utf8.encode('test-password');
    final hosts = TestOnlyKnownHosts();
    final transport = FakeTransport()
      ..failures.add(const SshFailure(SshFailureKind.network));
    final delaying = Completer<void>();
    final connection =
        service(credentials, hosts, transport, delay: (_) => delaying.future);
    final future = connection.reconnect(
      profile(),
      const ReconnectPolicy(enabled: true, maxAttempts: 2),
      approve: (algorithm, fingerprint) async => true,
    );
    await Future<void>.delayed(Duration.zero);
    await connection.disconnect();
    delaying.complete();
    await expectLater(
      future,
      throwsA(isA<SshFailure>()
          .having((e) => e.kind, 'kind', SshFailureKind.cancelled)),
    );
    expect(transport.opens, 1);
    await connection.dispose();
  });

  test('timeout and reconnect policies reject invalid or unbounded settings',
      () {
    expect(const SshTimeouts().valid, isTrue);
    expect(const SshTimeouts(tcp: Duration.zero).valid, isFalse);
    expect(const ReconnectPolicy(enabled: true, maxAttempts: 3).valid, isTrue);
    expect(const ReconnectPolicy(enabled: true, maxAttempts: 0).valid, isFalse);
    expect(
        const ReconnectPolicy(enabled: true, maxAttempts: 100).valid, isFalse);
  });
}
