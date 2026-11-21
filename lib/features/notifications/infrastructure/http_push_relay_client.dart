import 'dart:convert';
import 'dart:io';

import '../domain/push_device_registration.dart';
import '../domain/push_relay_client.dart';
import '../domain/relay_url_policy.dart';

/// Concrete [PushRelayClient] over HTTPS (plain HTTP only for loopback).
///
/// Security properties:
/// - refuses non-HTTPS, non-loopback relay URLs before any byte is sent;
/// - never follows redirects (a redirect could forward the bearer token elsewhere);
/// - uses default certificate validation (no `badCertificateCallback`);
/// - never logs or returns request credentials.
class HttpPushRelayClient implements PushRelayClient {
  const HttpPushRelayClient({
    this.timeout = const Duration(seconds: 10),
  });

  final Duration timeout;

  static const _maxResponseBytes = 64 * 1024;

  @override
  Future<RelayCallResult> exchangePairingCode({
    required String pairingCode,
    required String installationId,
    required String relayUrl,
  }) async {
    final uri = RelayUrlPolicy.endpoint(relayUrl, '/v1/pairing/exchange');
    if (uri == null) return const RelayCallResult(RelayCallStatus.insecureUrl);
    final res = await _request('POST', uri, body: {
      'schemaVersion': 1,
      'installationId': installationId,
      'pairingCode': pairingCode.trim(),
    });
    if (res.status == null) {
      return const RelayCallResult(RelayCallStatus.unreachable);
    }
    if (res.status == 200) {
      final token = res.json?['installationToken'];
      if (token is String && token.isNotEmpty) {
        return RelayCallResult(RelayCallStatus.ok, installationToken: token);
      }
      return const RelayCallResult(RelayCallStatus.rejected);
    }
    if (res.status == 401) {
      return const RelayCallResult(RelayCallStatus.invalidCode);
    }
    return RelayCallResult(_mapFailure(res.status!));
  }

  @override
  Future<RelayCallResult> registerDevice(
    PushDeviceRegistration registration, {
    required String relayUrl,
    required String installationToken,
  }) async {
    final uri = RelayUrlPolicy.endpoint(relayUrl, '/v1/devices/register');
    if (uri == null) return const RelayCallResult(RelayCallStatus.insecureUrl);
    final res = await _request('POST', uri,
        body: registration.toJson(), bearer: installationToken);
    if (res.status == null) {
      return const RelayCallResult(RelayCallStatus.unreachable);
    }
    if (res.status == 200 && res.json?['status'] == 'registered') {
      return const RelayCallResult(RelayCallStatus.ok);
    }
    return RelayCallResult(_mapFailure(res.status!));
  }

  @override
  Future<RelayCallResult> unregisterDevice(
    String deviceToken, {
    required String relayUrl,
    required String installationToken,
  }) async {
    final uri = RelayUrlPolicy.endpoint(relayUrl, '/v1/devices/by-token');
    if (uri == null) return const RelayCallResult(RelayCallStatus.insecureUrl);
    final res = await _request('DELETE', uri,
        body: {'schemaVersion': 1, 'deviceToken': deviceToken},
        bearer: installationToken);
    if (res.status == null) {
      return const RelayCallResult(RelayCallStatus.unreachable);
    }
    if (res.status == 200) return const RelayCallResult(RelayCallStatus.ok);
    return RelayCallResult(_mapFailure(res.status!));
  }

  @override
  Future<Map<String, dynamic>> checkRelayHealth({
    required String relayUrl,
  }) async {
    final uri = RelayUrlPolicy.endpoint(relayUrl, '/v1/health');
    if (uri == null) return {'status': 'insecure_url'};
    final res = await _request('GET', uri);
    if (res.status == null) return {'status': 'unreachable'};
    if (res.status == 200 && res.json != null) return res.json!;
    return {'status': 'error', 'statusCode': res.status};
  }

  RelayCallStatus _mapFailure(int status) {
    switch (status) {
      case 401:
        return RelayCallStatus.unauthorized;
      case 403:
        return RelayCallStatus.forbidden;
      case 429:
        return RelayCallStatus.rateLimited;
      default:
        return RelayCallStatus.rejected;
    }
  }

  Future<_RelayResponse> _request(
    String method,
    Uri uri, {
    Map<String, dynamic>? body,
    String? bearer,
  }) async {
    final client = HttpClient()..connectionTimeout = timeout;
    try {
      final request = await client.openUrl(method, uri).timeout(timeout);
      request.followRedirects = false;
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      if (bearer != null) {
        request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $bearer');
      }
      if (body != null) {
        final bytes = utf8.encode(jsonEncode(body));
        request.headers.contentType = ContentType.json;
        request.contentLength = bytes.length;
        request.add(bytes);
      }
      final response = await request.close().timeout(timeout);
      if (response.contentLength > _maxResponseBytes) {
        await response.drain<void>();
        return _RelayResponse(response.statusCode, null);
      }
      final text =
          await response.transform(utf8.decoder).join().timeout(timeout);
      Map<String, dynamic>? json;
      try {
        final decoded = jsonDecode(text);
        if (decoded is Map<String, dynamic>) json = decoded;
      } catch (_) {}
      return _RelayResponse(response.statusCode, json);
    } catch (_) {
      return const _RelayResponse(null, null);
    } finally {
      client.close(force: true);
    }
  }
}

class _RelayResponse {
  const _RelayResponse(this.status, this.json);
  final int? status;
  final Map<String, dynamic>? json;
}
