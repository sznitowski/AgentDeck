import 'dart:convert';
import 'dart:io';

import '../domain/push_device_registration.dart';
import '../domain/push_relay_client.dart';

/// Concrete implementation of [PushRelayClient] communicating over HTTP/HTTPS.
class HttpPushRelayClient implements PushRelayClient {
  const HttpPushRelayClient({
    this.timeout = const Duration(seconds: 10),
  });

  final Duration timeout;

  @override
  Future<bool> registerDevice(
    PushDeviceRegistration registration, {
    required String relayUrl,
  }) async {
    try {
      final uri = Uri.parse('$relayUrl/v1/devices/register');
      final client = HttpClient();
      final request = await client.postUrl(uri).timeout(timeout);
      request.headers.contentType = ContentType.json;
      final bytes = utf8.encode(jsonEncode(registration.toJson()));
      request.contentLength = bytes.length;
      request.add(bytes);

      final response = await request.close().timeout(timeout);
      final body = await response.transform(utf8.decoder).join();
      client.close();

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final data = jsonDecode(body) as Map<String, dynamic>;
        return data['status'] == 'registered';
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> unregisterDevice(
    String deviceToken, {
    required String relayUrl,
  }) async {
    try {
      final uri = Uri.parse('$relayUrl/v1/devices/by-token');
      final client = HttpClient();
      final request = await client.deleteUrl(uri).timeout(timeout);
      request.headers.contentType = ContentType.json;
      final bytes = utf8.encode(jsonEncode({
        'schemaVersion': 1,
        'deviceToken': deviceToken,
      }));
      request.contentLength = bytes.length;
      request.add(bytes);

      final response = await request.close().timeout(timeout);
      client.close();
      return response.statusCode >= 200 && response.statusCode < 300;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<Map<String, dynamic>> checkRelayHealth({
    required String relayUrl,
  }) async {
    try {
      final uri = Uri.parse('$relayUrl/v1/health');
      final client = HttpClient();
      final request = await client.getUrl(uri).timeout(timeout);
      final response = await request.close().timeout(timeout);
      final body = await response.transform(utf8.decoder).join();
      client.close();

      if (response.statusCode == 200) {
        return jsonDecode(body) as Map<String, dynamic>;
      }
      return {'status': 'error', 'statusCode': response.statusCode};
    } catch (e) {
      return {'status': 'unreachable', 'error': e.toString()};
    }
  }
}
