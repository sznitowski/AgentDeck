// Isolated manual lab harness. Never point this at production infrastructure.
import 'dart:convert';
import 'dart:io';

import 'package:agentdeck/core/domain/profiles.dart';
import 'package:agentdeck/core/domain/remote_contracts.dart';
import 'package:agentdeck/features/connections/application/ssh_connection_service.dart';
import 'package:agentdeck/features/connections/domain/ssh_models.dart';
import 'package:agentdeck/features/connections/infrastructure/dart_ssh_transport.dart';

class _LabSecretStore implements SecureCredentialStore {
  _LabSecretStore(this.secret, this.passphrase);
  List<int> secret;
  final List<int>? passphrase;
  @override
  Future<List<int>?> get(String reference) async => reference == 'lab-only'
      ? secret
      : reference == 'lab-passphrase'
          ? passphrase
          : null;
  @override
  Future<void> put(String reference, List<int> value) async =>
      throw UnsupportedError('Lab store is read-only');
  @override
  Future<void> delete(String reference) async =>
      throw UnsupportedError('Lab store is read-only');
}

class _LabKnownHosts implements KnownHostRepository {
  KnownHost? value;
  @override
  Future<KnownHost?> find(String hostname, int port) async =>
      value?.hostname == hostname && value?.port == port ? value : null;
  @override
  Future<void> trust(KnownHost host) async {
    if (value != null) throw StateError('Already trusted');
    value = host;
  }

  @override
  Future<void> revoke(String hostname, int port) async {
    throw UnsupportedError('Lab only');
  }

  @override
  Future<void> replace(KnownHost host) async {
    throw UnsupportedError('Lab only');
  }

  @override
  Future<void> delete(String hostname, int port) async {
    throw UnsupportedError('Lab only');
  }

  @override
  Future<void> markSeen(String hostname, int port, DateTime at) async {}
}

Future<void> main() async {
  final env = Platform.environment;
  final host = env['AGENTDECK_TEST_SSH_HOST'];
  final user = env['AGENTDECK_TEST_SSH_USER'];
  final port = int.tryParse(env['AGENTDECK_TEST_SSH_PORT'] ?? '22');
  final password = env['AGENTDECK_TEST_SSH_PASSWORD'];
  final passphrase = env['AGENTDECK_TEST_SSH_PASSPHRASE'];
  final keyPath = env['AGENTDECK_TEST_SSH_KEY_PATH'];
  if (host == null ||
      !{'127.0.0.1', 'localhost', '::1'}.contains(host) ||
      user == null ||
      user.isEmpty ||
      port == null ||
      port < 1 ||
      port > 65535 ||
      (password == null) == (keyPath == null)) {
    stderr.writeln(
        'Use a loopback lab HOST, USER, optional PORT, and exactly one of PASSWORD or KEY_PATH.');
    exitCode = 2;
    return;
  }
  final secret = keyPath == null
      ? utf8.encode(password!)
      : await File(keyPath).readAsBytes();
  final method = keyPath == null
      ? SshAuthenticationMethod.password
      : SshAuthenticationMethod.privateKey;
  final profile = ServerProfile(
      id: 'lab',
      name: 'Isolated lab',
      host: host,
      username: user,
      port: port,
      credentialId: 'lab-only',
      passphraseCredentialId: passphrase == null ? null : 'lab-passphrase',
      authenticationMethod: method);
  final hosts = _LabKnownHosts();
  final expected = env['AGENTDECK_TEST_SSH_FINGERPRINT'];
  if (expected != null) {
    final identity = HostIdentity(
        env['AGENTDECK_TEST_SSH_ALGORITHM'] ?? 'ssh-ed25519', expected);
    final now = DateTime.now().toUtc();
    hosts.value = KnownHost(
        hostname: host.toLowerCase(),
        port: port,
        identity: identity,
        firstSeenAt: now,
        lastSeenAt: now);
  }
  final credentials = _LabSecretStore(
      secret, passphrase == null ? null : utf8.encode(passphrase));
  final service = SshConnectionService(
      credentials: credentials,
      knownHosts: hosts,
      transport: const DartSshTransport());
  try {
    if (env['AGENTDECK_TEST_SSH_RECOVER'] == 'auth') {
      if (method != SshAuthenticationMethod.password || expected == null) {
        throw StateError(
            'Recovery mode requires password auth and a pinned host fingerprint');
      }
      credentials.secret =
          utf8.encode('invalid-lab-${DateTime.now().microsecondsSinceEpoch}');
      try {
        await service.connect(profile);
        throw StateError(
            'Unexpected authentication success with invalid lab credential');
      } on SshFailure catch (failure) {
        if (failure.kind != SshFailureKind.authentication) rethrow;
        stdout.writeln('FIRST_ATTEMPT: authentication failure');
      }
      credentials.secret = secret;
    }
    await service.connect(profile, approve: (server, identity) async {
      stdout.writeln('Unknown lab host: ${server.host}:${server.port}');
      stdout.writeln('Algorithm: ${identity.algorithm}');
      stdout.writeln('Fingerprint: ${identity.fingerprint}');
      stdout.write('Verify through another trusted channel, then type yes: ');
      return stdin.readLineSync() == 'yes';
    });
    stdout.writeln(
        'CONNECTED; host identity verified; auth method: ${method.name}');
    await service.disconnect();
    stdout.writeln('DISCONNECTED');
  } on SshFailure catch (failure) {
    stderr.writeln('SSH lab failure category: ${failure.kind.name}');
    exitCode = 1;
  } finally {
    await service.dispose();
  }
}
