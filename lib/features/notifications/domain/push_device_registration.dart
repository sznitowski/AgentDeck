/// Represents a device token registration submitted to the Push Relay.
class PushDeviceRegistration {
  const PushDeviceRegistration({
    required this.installationId,
    required this.deviceToken,
    this.platform = 'ios',
    this.bundleId = 'com.agentdeck.app',
    this.environment = 'sandbox',
    this.appVersion = '1.0.0',
    this.privacyMode = 'full',
    this.enabled = true,
    this.registeredAt,
  });

  final String installationId;
  final String deviceToken;
  final String platform;
  final String bundleId;
  final String environment;
  final String appVersion;
  final String privacyMode;
  final bool enabled;
  final DateTime? registeredAt;

  factory PushDeviceRegistration.fromJson(Map<String, dynamic> json) =>
      PushDeviceRegistration(
        installationId: json['installationId'] as String? ?? '',
        deviceToken: json['deviceToken'] as String? ?? '',
        platform: json['platform'] as String? ?? 'ios',
        bundleId: json['bundleId'] as String? ?? 'com.agentdeck.app',
        environment: json['environment'] as String? ?? 'sandbox',
        appVersion: json['appVersion'] as String? ?? '1.0.0',
        privacyMode: json['privacyMode'] as String? ?? 'full',
        enabled: json['enabled'] as bool? ?? true,
        registeredAt: json['registeredAt'] != null
            ? DateTime.tryParse(json['registeredAt'] as String)
            : null,
      );

  Map<String, dynamic> toJson() => {
        'schemaVersion': 1,
        'installationId': installationId,
        'deviceToken': deviceToken,
        'platform': platform,
        'bundleId': bundleId,
        'environment': environment,
        'appVersion': appVersion,
        'privacyMode': privacyMode,
        'enabled': enabled,
        if (registeredAt != null)
          'registeredAt': registeredAt!.toIso8601String(),
      };
}

/// Abstract contract for persisting local push registration state.
abstract class PushRegistrationRepository {
  Future<PushDeviceRegistration?> getRegistration();
  Future<void> saveRegistration(PushDeviceRegistration registration);
  Future<void> clear();
}
