import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:agentdeck/core/domain/installation_identity.dart';
import 'package:agentdeck/core/domain/remote_contracts.dart';
import 'package:agentdeck/features/notifications/application/push_relay_pairing_service.dart';
import 'package:agentdeck/features/notifications/domain/push_device_registration.dart';
import 'package:agentdeck/features/notifications/domain/push_relay_client.dart';
import 'package:agentdeck/features/notifications/domain/relay_url_policy.dart';
import 'package:agentdeck/features/notifications/infrastructure/http_push_relay_client.dart';

class _Identity implements InstallationIdentityRepository {
  @override
  Future<InstallationIdentity> getIdentity() async => InstallationIdentity(
      id: 'inst_pairing_test', createdAt: DateTime.utc(2026));
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

class _RecordedRequest {
  _RecordedRequest(this.method, this.path, this.authorization, this.body);
  final String method;
  final String path;
  final String? authorization;
  final Map<String, dynamic>? body;
}

/// A loopback stand-in for the relay that records what the client sends.
class _StubRelay {
  _StubRelay(this.server) {
    port; // cache the bound port before any close()
    server.listen((request) async {
      final text = await utf8.decoder.bind(request).join();
      Map<String, dynamic>? body;
      try {
        body = jsonDecode(text) as Map<String, dynamic>;
      } catch (_) {}
      requests.add(_RecordedRequest(
        request.method,
        request.uri.path,
        request.headers.value(HttpHeaders.authorizationHeader),
        body,
      ));
      final reply = responder(request.method, request.uri.path);
      request.response.statusCode = reply.$1;
      if (reply.$3 != null) {
        request.response.headers.set(HttpHeaders.locationHeader, reply.$3!);
      }
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode(reply.$2));
      await request.response.close();
    });
  }

  final HttpServer server;
  final List<_RecordedRequest> requests = [];
  (int, Map<String, dynamic>, String?) Function(String method, String path)
      responder = (m, p) => (200, <String, dynamic>{}, null);

  late final int port = server.port; // cached: unreadable once closed

  String get url => 'http://127.0.0.1:$port';

  static Future<_StubRelay> start() async =>
      _StubRelay(await HttpServer.bind(InternetAddress.loopbackIPv4, 0));

  bool _closed = false;

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await server.close(force: true);
  }
}

void main() {
  group('RelayUrlPolicy (one relay per origin)', () {
    test('accepts https origins and loopback http, normalizing them', () {
      const cases = {
        'https://relay.example.com': 'https://relay.example.com',
        'https://relay.example.com/': 'https://relay.example.com',
        ' https://Relay.Example.COM/ ': 'https://relay.example.com',
        'HTTPS://relay.example.com': 'https://relay.example.com',
        'https://relay.example.com:8443': 'https://relay.example.com:8443',
        'https://relay.example.com:8443/': 'https://relay.example.com:8443',
        'https://relay.example.com:443': 'https://relay.example.com',
        'http://127.0.0.1:8443': 'http://127.0.0.1:8443',
        'http://localhost:8443/': 'http://localhost:8443',
        'http://[::1]:8443': 'http://[::1]:8443',
        'http://127.0.0.1:80': 'http://127.0.0.1',
      };
      for (final entry in cases.entries) {
        expect(RelayUrlPolicy.normalize(entry.key), entry.value,
            reason: entry.key);
        expect(RelayUrlPolicy.problem(entry.key), isNull, reason: entry.key);
      }
    });

    test('rejects everything that is not a bare origin', () {
      const invalid = [
        'https://user:pw@relay.example.com',
        'https://user@relay.example.com',
        'https://relay.example.com?x=1',
        'https://relay.example.com/?x=1',
        'https://relay.example.com#frag',
        'https://relay.example.com/prefix',
        'https://relay.example.com/prefix/',
        'https://relay.example.com//',
        'https://relay.example.com:0',
        'https://relay.example.com:99999',
        'https://relay.example.com:',
        'https://relay.example.com:abc',
        'https://:8443',
        'https://',
        'https:///',
        'ftp://relay.example.com',
        'wss://relay.example.com',
        'relay.example.com',
        '//relay.example.com',
        'https://relay example.com',
      ];
      for (final bad in invalid) {
        expect(RelayUrlPolicy.normalize(bad), isNull, reason: bad);
        expect(RelayUrlPolicy.problem(bad), RelayUrlProblem.invalid,
            reason: bad);
      }
    });

    test('empty and plain remote http have their own problems', () {
      expect(RelayUrlPolicy.problem(''), RelayUrlProblem.empty);
      expect(RelayUrlPolicy.problem('   '), RelayUrlProblem.empty);
      for (final insecure in [
        'http://relay.example.com',
        'http://10.0.0.5:8443',
        'http://127.0.0.1.evil.com',
        'http://localhost.evil.com',
      ]) {
        expect(RelayUrlPolicy.problem(insecure), RelayUrlProblem.insecure,
            reason: insecure);
        expect(RelayUrlPolicy.isAllowed(insecure), isFalse);
      }
    });

    test('loopback http is strict: valid 127.0.0.0/8, localhost and ::1 only',
        () {
      for (final ok in [
        'http://127.0.0.1:8443',
        'http://127.1.2.3:8443',
        'http://127.255.255.255:8443',
        'http://localhost:8443',
        'http://[::1]:8443',
      ]) {
        expect(RelayUrlPolicy.problem(ok), isNull, reason: ok);
        expect(RelayUrlPolicy.normalize(ok), isNotNull, reason: ok);
      }
      for (final bad in [
        'http://127.999.999.999:8443',
        'http://127.0.0.256:8443',
        'http://127.0.0:8443',
        'http://127.0.0.1.2:8443',
        'http://128.0.0.1:8443',
        'http://localhost.example.com:8443',
        'http://127.00.0.1:8443', // leading zero: ambiguous (octal) notation
        'http://127.0.0.01:8443',
        'http://127.0.0.-1:8443',
        'http://127.0.0.1a:8443',
      ]) {
        expect(RelayUrlPolicy.normalize(bad), isNull, reason: bad);
        expect(RelayUrlPolicy.isLoopbackHost(Uri.parse(bad).host), isFalse,
            reason: bad);
      }
      // The same invalid hosts are not rescued by HTTPS-only rules either:
      // https accepts any valid DNS-style host, but never claims loopback.
      expect(RelayUrlPolicy.isLoopbackHost('127.999.999.999'), isFalse);
      expect(RelayUrlPolicy.isLoopbackHost('127.0.0.1'), isTrue);
      expect(RelayUrlPolicy.isLoopbackHost('localhost'), isTrue);
      expect(RelayUrlPolicy.isLoopbackHost('::1'), isTrue);
    });

    test('endpoint is built from the origin only', () {
      expect(
        RelayUrlPolicy.endpoint('https://r.example.com/', '/v1/health')
            .toString(),
        'https://r.example.com/v1/health',
      );
      expect(RelayUrlPolicy.endpoint('https://r.example.com/prefix', '/v1/x'),
          isNull);
      expect(RelayUrlPolicy.endpoint('http://evil.com', '/v1/health'), isNull);
    });
  });

  group('HttpPushRelayClient against a loopback relay', () {
    late _StubRelay relay;
    const client = HttpPushRelayClient(timeout: Duration(seconds: 3));

    setUp(() async => relay = await _StubRelay.start());
    tearDown(() async => await relay.close());

    test('exchange posts the code and returns the opaque token', () async {
      relay.responder = (m, p) => (
            200,
            <String, dynamic>{
              'status': 'paired',
              'installationToken': 'adt_abc'
            },
            null
          );
      final result = await client.exchangePairingCode(
        pairingCode: ' ABCD-EFGH-IJKL-MNOP ',
        installationId: 'inst_pairing_test',
        relayUrl: relay.url,
      );
      expect(result.isOk, isTrue);
      expect(result.installationToken, 'adt_abc');
      expect(result.toString(), isNot(contains('adt_abc')));
      final req = relay.requests.single;
      expect(req.path, '/v1/pairing/exchange');
      expect(req.authorization, isNull);
      expect(req.body?['pairingCode'], 'ABCD-EFGH-IJKL-MNOP');
      expect(req.body?['installationId'], 'inst_pairing_test');
    });

    test('exchange maps 401, 429 and unreachable', () async {
      relay.responder = (m, p) => (401, <String, dynamic>{'error': 'x'}, null);
      expect(
          (await client.exchangePairingCode(
                  pairingCode: 'x', installationId: 'i', relayUrl: relay.url))
              .status,
          RelayCallStatus.invalidCode);
      relay.responder = (m, p) => (429, <String, dynamic>{}, null);
      expect(
          (await client.exchangePairingCode(
                  pairingCode: 'x', installationId: 'i', relayUrl: relay.url))
              .status,
          RelayCallStatus.rateLimited);
      await relay.close();
      expect(
          (await client.exchangePairingCode(
                  pairingCode: 'x', installationId: 'i', relayUrl: relay.url))
              .status,
          RelayCallStatus.unreachable);
    });

    test('register and unregister send the bearer token', () async {
      relay.responder = (m, p) => (
            200,
            <String, dynamic>{
              'status': m == 'POST' ? 'registered' : 'deactivated'
            },
            null
          );
      final reg = await client.registerDevice(
        const PushDeviceRegistration(
            installationId: 'inst_pairing_test', deviceToken: 'apns_token_1'),
        relayUrl: relay.url,
        installationToken: 'adt_secret',
      );
      expect(reg.isOk, isTrue);
      final unreg = await client.unregisterDevice('apns_token_1',
          relayUrl: relay.url, installationToken: 'adt_secret');
      expect(unreg.isOk, isTrue);
      expect(relay.requests.map((r) => r.method), ['POST', 'DELETE']);
      expect(
          relay.requests.every((r) => r.authorization == 'Bearer adt_secret'),
          isTrue);
    });

    test('401 and 403 map to unauthorized and forbidden', () async {
      for (final entry in {
        401: RelayCallStatus.unauthorized,
        403: RelayCallStatus.forbidden,
        500: RelayCallStatus.rejected,
      }.entries) {
        relay.responder = (m, p) => (entry.key, <String, dynamic>{}, null);
        final res = await client.registerDevice(
          const PushDeviceRegistration(
              installationId: 'inst_pairing_test', deviceToken: 'apns_token_1'),
          relayUrl: relay.url,
          installationToken: 't',
        );
        expect(res.status, entry.value);
      }
    });

    test('redirects are never followed (bearer cannot leak)', () async {
      final other = await _StubRelay.start();
      addTearDown(other.close);
      relay.responder = (m, p) =>
          (307, <String, dynamic>{}, '${other.url}/v1/devices/register');
      final res = await client.registerDevice(
        const PushDeviceRegistration(
            installationId: 'inst_pairing_test', deviceToken: 'apns_token_1'),
        relayUrl: relay.url,
        installationToken: 'adt_secret',
      );
      expect(res.isOk, isFalse);
      expect(other.requests, isEmpty);
    });

    test('health works and remote http is refused before connecting', () async {
      relay.responder = (m, p) => (
            200,
            <String, dynamic>{'status': 'ok', 'apnsConfigured': false},
            null
          );
      expect(
          (await client.checkRelayHealth(relayUrl: relay.url))['status'], 'ok');
      expect(
          (await client.checkRelayHealth(
              relayUrl: 'http://relay.example.com'))['status'],
          'insecure_url');
      final res = await client.exchangePairingCode(
          pairingCode: 'x',
          installationId: 'i',
          relayUrl: 'http://relay.example.com');
      expect(res.status, RelayCallStatus.insecureUrl);
    });
  });

  group('PushRelayPairingService', () {
    late _StubRelay relay;
    late _Credentials credentials;
    late PushRelayPairingService service;
    const reg = PushDeviceRegistration(
        installationId: 'inst_pairing_test', deviceToken: 'apns_token_1');

    setUp(() async {
      relay = await _StubRelay.start();
      credentials = _Credentials();
      service = PushRelayPairingService(
        client: const HttpPushRelayClient(timeout: Duration(seconds: 3)),
        credentials: credentials,
        identity: _Identity(),
      );
    });
    tearDown(() async => await relay.close());

    void relayIssuesToken() {
      relay.responder = (m, p) => p == '/v1/pairing/exchange'
          ? (
              200,
              <String, dynamic>{
                'status': 'paired',
                'installationToken': 'adt_issued'
              },
              null
            )
          : (200, <String, dynamic>{'status': 'registered'}, null);
    }

    test('pair stores the token only in the credential store', () async {
      relayIssuesToken();
      expect(await service.isPaired(relay.url), isFalse);
      expect(
          await service.pair('CODE', relayUrl: relay.url), RelayCallStatus.ok);
      expect(await service.isPaired(relay.url), isTrue);
      expect(credentials.values.length, 1);
      expect(utf8.decode(credentials.values.values.single), 'adt_issued');
      expect(
          relay.requests.single.body?['installationId'], 'inst_pairing_test');
    });

    test('registration uses the stored token as bearer', () async {
      relayIssuesToken();
      await service.pair('CODE', relayUrl: relay.url);
      final res = await service.registerDevice(reg, relayUrl: relay.url);
      expect(res.isOk, isTrue);
      expect(relay.requests.last.authorization, 'Bearer adt_issued');
    });

    test('without pairing nothing is sent and the result is unauthorized',
        () async {
      relayIssuesToken();
      final res = await service.registerDevice(reg, relayUrl: relay.url);
      expect(res.status, RelayCallStatus.unauthorized);
      expect(relay.requests, isEmpty);
    });

    test('the token is never sent to a different relay', () async {
      relayIssuesToken();
      await service.pair('CODE', relayUrl: relay.url);
      final other = await _StubRelay.start();
      addTearDown(other.close);
      final res = await service.registerDevice(reg, relayUrl: other.url);
      expect(res.status, RelayCallStatus.unauthorized);
      expect(other.requests, isEmpty);
    });

    test('a 401 (revoked token) wipes the stored token', () async {
      relayIssuesToken();
      await service.pair('CODE', relayUrl: relay.url);
      relay.responder = (m, p) => (401, <String, dynamic>{}, null);
      final res = await service.registerDevice(reg, relayUrl: relay.url);
      expect(res.status, RelayCallStatus.unauthorized);
      expect(await service.isPaired(relay.url), isFalse);
      expect(credentials.values, isEmpty);
    });

    test('a failed exchange stores nothing', () async {
      relay.responder = (m, p) => (401, <String, dynamic>{}, null);
      expect(await service.pair('BAD', relayUrl: relay.url),
          RelayCallStatus.invalidCode);
      expect(credentials.values, isEmpty);
    });

    test('remote plain http is refused and stores nothing', () async {
      expect(await service.pair('CODE', relayUrl: 'http://relay.example.com'),
          RelayCallStatus.insecureUrl);
      expect(credentials.values, isEmpty);
    });

    test('forget removes the local token', () async {
      relayIssuesToken();
      await service.pair('CODE', relayUrl: relay.url);
      await service.forget(relay.url);
      expect(await service.isPaired(relay.url), isFalse);
    });
  });
}
