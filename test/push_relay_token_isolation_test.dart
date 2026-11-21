import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:agentdeck/core/domain/installation_identity.dart';
import 'package:agentdeck/core/domain/remote_contracts.dart';
import 'package:agentdeck/features/notifications/application/push_relay_pairing_service.dart';
import 'package:agentdeck/features/notifications/domain/push_device_registration.dart';
import 'package:agentdeck/features/notifications/domain/push_relay_client.dart';

class _Identity implements InstallationIdentityRepository {
  @override
  Future<InstallationIdentity> getIdentity() async => InstallationIdentity(
      id: 'inst_00000000000000000000000000000001',
      createdAt: DateTime.utc(2026));
}

class _Credentials implements SecureCredentialStore {
  final Map<String, List<int>> values = {};
  @override
  Future<void> put(String reference, List<int> secret) async =>
      values[reference] = secret;
  @override
  Future<List<int>?> get(String reference) async => values[reference];
  @override
  Future<void> delete(String reference) async => values.remove(reference);
}

/// Records every call (url + bearer) and answers with a scripted status.
class _ScriptedClient implements PushRelayClient {
  RelayCallStatus next = RelayCallStatus.ok;
  final List<({String url, String bearer})> calls = [];

  @override
  Future<RelayCallResult> exchangePairingCode(
          {required String pairingCode,
          required String installationId,
          required String relayUrl}) async =>
      next == RelayCallStatus.ok
          ? const RelayCallResult(RelayCallStatus.ok,
              installationToken: 'adt_issued')
          : RelayCallResult(next);

  @override
  Future<RelayCallResult> registerDevice(PushDeviceRegistration registration,
      {required String relayUrl, required String installationToken}) async {
    calls.add((url: relayUrl, bearer: installationToken));
    return RelayCallResult(next);
  }

  @override
  Future<RelayCallResult> unregisterDevice(String deviceToken,
      {required String relayUrl, required String installationToken}) async {
    calls.add((url: relayUrl, bearer: installationToken));
    return RelayCallResult(next);
  }

  @override
  Future<Map<String, dynamic>> checkRelayHealth(
          {required String relayUrl}) async =>
      {'status': 'ok'};
}

void main() {
  const reg = PushDeviceRegistration(
      installationId: 'inst_00000000000000000000000000000001',
      deviceToken: 'apns_token_1');
  late _ScriptedClient client;
  late _Credentials credentials;
  late PushRelayPairingService service;

  setUp(() {
    client = _ScriptedClient();
    credentials = _Credentials();
    service = PushRelayPairingService(
        client: client, credentials: credentials, identity: _Identity());
  });

  String? ref(String url) => PushRelayPairingService.credentialReference(url);

  group('credential reference (one relay per origin)', () {
    test('equivalent spellings of one origin share a reference', () {
      expect(
          ref('https://relay.example.com'), ref('https://relay.example.com/'));
      expect(ref('https://relay.example.com'),
          ref('https://Relay.Example.com:443'));
      expect(ref('https://relay.example.com'),
          'push_relay_installation_token@https://relay.example.com');
    });

    test('different hosts, ports and schemes never share a reference', () {
      final refs = <String?>{
        ref('https://relay.example.com'),
        ref('https://relay.example.org'),
        ref('https://relay.example.com:8443'),
        ref('https://relay.example.com:8444'),
        ref('https://sub.relay.example.com'),
        ref('http://127.0.0.1:8443'),
        ref('http://127.0.0.1:8444'),
        ref('http://localhost:8443'),
      };
      expect(refs.length, 8);
      expect(refs.contains(null), isFalse);
    });

    test('invalid or insecure URLs have no reference at all', () {
      for (final bad in [
        '',
        'https://relay.example.com/prefix',
        'https://u:p@relay.example.com',
        'http://relay.example.com',
        'https://relay.example.com:99999',
        'nonsense',
      ]) {
        expect(ref(bad), isNull, reason: bad);
      }
    });
  });

  group('token is never shared or sent to the wrong place', () {
    Future<void> pairWith(String url) async {
      client.next = RelayCallStatus.ok;
      expect(await service.pair('CODE', relayUrl: url), RelayCallStatus.ok);
    }

    test('a token for relay A is invisible to other hosts and ports', () async {
      await pairWith('https://relay-a.example.com');
      for (final other in [
        'https://relay-b.example.com',
        'https://relay-a.example.com:8443',
        'http://relay-a.example.com', // remote plain http
        'http://127.0.0.1:8443',
      ]) {
        expect(await service.isPaired(other), isFalse, reason: other);
        final res = await service.registerDevice(reg, relayUrl: other);
        expect(res.status, RelayCallStatus.unauthorized, reason: other);
      }
      expect(client.calls, isEmpty);
      expect(await service.isPaired('https://relay-a.example.com/'), isTrue);
    });

    test('invalid URLs never read or send a token', () async {
      await pairWith('https://relay-a.example.com');
      for (final bad in [
        'https://relay-a.example.com/prefix',
        'https://user@relay-a.example.com',
        'https://relay-a.example.com?x=1',
        '',
      ]) {
        expect(await service.isPaired(bad), isFalse, reason: bad);
        expect((await service.registerDevice(reg, relayUrl: bad)).status,
            RelayCallStatus.unauthorized);
        expect(await service.pair('CODE', relayUrl: bad),
            isNot(RelayCallStatus.ok));
      }
      expect(client.calls, isEmpty);
      expect(credentials.values.length, 1);
    });

    test('the bearer sent is the one issued for that exact origin', () async {
      client.next = RelayCallStatus.ok;
      credentials.values[ref('https://relay-a.example.com')!] =
          utf8.encode('adt_for_a');
      credentials.values[ref('https://relay-b.example.com')!] =
          utf8.encode('adt_for_b');
      await service.registerDevice(reg,
          relayUrl: 'https://relay-b.example.com');
      await service.registerDevice(reg,
          relayUrl: 'https://relay-a.example.com/');
      expect(client.calls.map((c) => '${c.url}|${c.bearer}'), [
        'https://relay-b.example.com|adt_for_b',
        'https://relay-a.example.com/|adt_for_a',
      ]);
    });
  });

  group('which relay responses delete the stored token', () {
    const url = 'https://relay-a.example.com';

    setUp(() async {
      credentials.values[ref(url)!] = utf8.encode('adt_for_a');
      credentials.values[ref('https://relay-b.example.com')!] =
          utf8.encode('adt_for_b');
    });

    test('401 deletes only the token of the current relay', () async {
      client.next = RelayCallStatus.unauthorized;
      await service.registerDevice(reg, relayUrl: url);
      expect(await service.isPaired(url), isFalse);
      expect(await service.isPaired('https://relay-b.example.com'), isTrue);
    });

    test('401 on unregister deletes only the current relay token', () async {
      client.next = RelayCallStatus.unauthorized;
      await service.unregisterDevice('apns_token_1', relayUrl: url);
      expect(await service.isPaired(url), isFalse);
      expect(await service.isPaired('https://relay-b.example.com'), isTrue);
    });

    for (final status in [
      RelayCallStatus.unreachable,
      RelayCallStatus.forbidden,
      RelayCallStatus.rateLimited,
      RelayCallStatus.rejected,
      RelayCallStatus.insecureUrl,
      RelayCallStatus.ok,
    ]) {
      test('$status keeps the token', () async {
        client.next = status;
        await service.registerDevice(reg, relayUrl: url);
        await service.unregisterDevice('apns_token_1', relayUrl: url);
        expect(await service.isPaired(url), isTrue);
        expect(credentials.values.length, 2);
      });
    }

    test('changing the configured URL never deletes other relay tokens',
        () async {
      // Simulates the user pointing the app at relay C and back.
      expect(await service.isPaired('https://relay-c.example.com'), isFalse);
      await service.forget('https://relay-c.example.com');
      expect(credentials.values.length, 2);
    });

    test('a failed pairing exchange keeps the existing token', () async {
      client.next = RelayCallStatus.invalidCode;
      expect(await service.pair('BAD', relayUrl: url),
          RelayCallStatus.invalidCode);
      expect(await service.isPaired(url), isTrue);
    });
  });
}
