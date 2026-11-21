import 'package:flutter/material.dart';

import '../../core/domain/installation_identity.dart';
import '../../shared/page_frame.dart';
import '../notifications/application/push_relay_pairing_service.dart';
import '../notifications/domain/push_device_registration.dart';
import '../notifications/domain/push_notification_service.dart';
import '../notifications/domain/push_relay_client.dart';
import '../notifications/domain/relay_config_repository.dart';
import '../notifications/presentation/notification_settings_page.dart';

/// Settings hub. Services are injected by the app shell (the same instances the
/// bootstrap composed); nothing is created here.
class SettingsPage extends StatelessWidget {
  const SettingsPage({
    super.key,
    this.pushService,
    this.pushRelayClient,
    this.pushRelayPairing,
    this.installationIdentity,
    this.pushRegistrations,
    this.relayConfig,
  });

  final PushNotificationService? pushService;
  final PushRelayClient? pushRelayClient;
  final PushRelayPairingService? pushRelayPairing;
  final InstallationIdentityRepository? installationIdentity;
  final PushRegistrationRepository? pushRegistrations;
  final RelayConfigRepository? relayConfig;

  bool get _notificationsAvailable =>
      pushService != null &&
      pushRelayClient != null &&
      pushRelayPairing != null &&
      installationIdentity != null &&
      pushRegistrations != null &&
      relayConfig != null;

  void _openNotificationSettings(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => NotificationSettingsPage(
          pushService: pushService!,
          relayClient: pushRelayClient!,
          pairing: pushRelayPairing!,
          identityRepo: installationIdentity!,
          registrationRepo: pushRegistrations,
          relayConfig: relayConfig!,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PageFrame(
      title: 'Settings',
      subtitle: 'Security and connection preferences',
      child: Card(
        child: ListTile(
          key: const Key('settings-push-notifications'),
          leading: const Icon(Icons.notifications_active_outlined),
          title: const Text('Push Notifications'),
          subtitle: Text(_notificationsAvailable
              ? 'Relay URL, pairing, alerts and lock-screen privacy'
              : 'Unavailable: app services are not initialized'),
          trailing: const Icon(Icons.chevron_right),
          enabled: _notificationsAvailable,
          onTap: _notificationsAvailable
              ? () => _openNotificationSettings(context)
              : null,
        ),
      ),
    );
  }
}
