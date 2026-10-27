import 'push_device_registration.dart';

/// Abstract contract for communication between mobile client and the central Push Relay.
abstract class PushRelayClient {
  /// Registers or updates device token with Push Relay.
  Future<bool> registerDevice(
    PushDeviceRegistration registration, {
    required String relayUrl,
  });

  /// Deactivates device token from Push Relay.
  Future<bool> unregisterDevice(
    String deviceToken, {
    required String relayUrl,
  });

  /// Checks Push Relay service health.
  Future<Map<String, dynamic>> checkRelayHealth({
    required String relayUrl,
  });
}
