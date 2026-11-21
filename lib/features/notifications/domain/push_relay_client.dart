import 'push_device_registration.dart';

/// Outcome of a call to the Push Relay. Never carries secrets in [status].
enum RelayCallStatus {
  ok,

  /// Missing, invalid or revoked installation token (HTTP 401).
  unauthorized,

  /// Token is valid but bound to another installation (HTTP 403).
  forbidden,

  /// Pairing code unknown, expired or already used (HTTP 401 on exchange).
  invalidCode,

  /// Too many failed pairing attempts (HTTP 429).
  rateLimited,

  /// The relay URL is not HTTPS (and not loopback). Nothing was sent.
  insecureUrl,

  /// Network failure or timeout.
  unreachable,

  /// Any other relay rejection.
  rejected,
}

class RelayCallResult {
  const RelayCallResult(this.status, {this.installationToken});

  final RelayCallStatus status;

  /// Opaque installation token. Only set on a successful pairing exchange and
  /// must be handed straight to the secure credential store.
  final String? installationToken;

  bool get isOk => status == RelayCallStatus.ok;

  @override
  String toString() => 'RelayCallResult($status)'; // never prints the token
}

/// Abstract contract for communication between mobile client and the central Push Relay.
abstract class PushRelayClient {
  /// Exchanges a one-time pairing code for an opaque installation token.
  Future<RelayCallResult> exchangePairingCode({
    required String pairingCode,
    required String installationId,
    required String relayUrl,
  });

  /// Registers or updates the APNs device token (requires the installation token).
  Future<RelayCallResult> registerDevice(
    PushDeviceRegistration registration, {
    required String relayUrl,
    required String installationToken,
  });

  /// Deactivates an APNs device token (requires the installation token).
  Future<RelayCallResult> unregisterDevice(
    String deviceToken, {
    required String relayUrl,
    required String installationToken,
  });

  /// Checks Push Relay service health (unauthenticated, minimal data).
  Future<Map<String, dynamic>> checkRelayHealth({
    required String relayUrl,
  });
}
