import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:agentdeck/core/domain/events.dart';
import 'package:agentdeck/core/domain/installation_identity.dart';
import 'package:agentdeck/features/notifications/domain/notification_policy.dart';
import 'package:agentdeck/features/notifications/domain/push_device_registration.dart';
import 'package:agentdeck/features/notifications/domain/push_relay_client.dart';
import 'package:agentdeck/features/notifications/infrastructure/push_notification_service_impl.dart';
import 'package:agentdeck/features/notifications/presentation/notification_settings_page.dart';

class _FakeIdentityRepository implements InstallationIdentityRepository {
  @override
  Future<InstallationIdentity> getIdentity() async => InstallationIdentity(
      id: 'inst_test_123', createdAt: DateTime.now().toUtc());
}

class _FakePushRelayClient implements PushRelayClient {
  PushDeviceRegistration? lastRegistered;

  @override
  Future<bool> registerDevice(PushDeviceRegistration registration,
      {required String relayUrl}) async {
    lastRegistered = registration;
    return true;
  }

  @override
  Future<bool> unregisterDevice(String deviceToken,
          {required String relayUrl}) async =>
      true;

  @override
  Future<Map<String, dynamic>> checkRelayHealth(
          {required String relayUrl}) async =>
      {'status': 'ok', 'version': '0.1.0'};
}

void main() {
  group('NotificationSettingsPage Widget Tests', () {
    testWidgets(
        'renders status card, privacy options, category toggles, and diagnostics',
        (tester) async {
      tester.view.physicalSize = const Size(1200, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final pushService = FakePushNotificationService();
      final relayClient = _FakePushRelayClient();
      final identityRepo = _FakeIdentityRepository();

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(),
          home: NotificationSettingsPage(
            pushService: pushService,
            relayClient: relayClient,
            identityRepo: identityRepo,
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Permission status card
      expect(find.text('Push Notification Settings'), findsOneWidget);
      expect(find.text('iOS Permission: NOT REQUESTED'), findsOneWidget);
      expect(find.text('Enable Notifications'), findsOneWidget);

      // Privacy modes
      expect(find.text('Lock Screen Privacy'), findsOneWidget);
      expect(find.text('Full Preview'), findsOneWidget);
      expect(find.text('Project Only'), findsOneWidget);
      expect(find.text('Generic Mode'), findsOneWidget);

      // Category switches
      expect(find.text('Notification Categories'), findsOneWidget);
      expect(find.text('Agent Waiting for Input'), findsOneWidget);
      expect(find.text('Git Merge Conflicts'), findsOneWidget);

      // Diagnostics
      expect(find.text('Push Relay & Token Diagnostics'), findsOneWidget);
      expect(find.text('OK'), findsOneWidget);
    });

    testWidgets(
        'requesting permission displays contextual pre-prompt dialog and enables alerts',
        (tester) async {
      tester.view.physicalSize = const Size(1200, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final pushService = FakePushNotificationService();
      final relayClient = _FakePushRelayClient();
      final identityRepo = _FakeIdentityRepository();

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(),
          home: NotificationSettingsPage(
            pushService: pushService,
            relayClient: relayClient,
            identityRepo: identityRepo,
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Tap Enable Notifications
      await tester.tap(find.text('Enable Notifications'));
      await tester.pumpAndSettle();

      // Pre-prompt dialog shown
      expect(find.text('Enable Remote Alerts'), findsOneWidget);
      expect(
        find.textContaining(
            'AgentDeck will alert you on your iPhone lock screen'),
        findsOneWidget,
      );

      // Confirm dialog
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();

      // Status transitions to AUTHORIZED
      expect(find.text('iOS Permission: AUTHORIZED'), findsOneWidget);
      expect(relayClient.lastRegistered?.installationId, 'inst_test_123');
    });

    testWidgets('changing privacy mode notifies policy callback',
        (tester) async {
      tester.view.physicalSize = const Size(1200, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final pushService = FakePushNotificationService();
      final relayClient = _FakePushRelayClient();
      final identityRepo = _FakeIdentityRepository();

      NotificationPolicy? updatedPolicy;

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(),
          home: NotificationSettingsPage(
            pushService: pushService,
            relayClient: relayClient,
            identityRepo: identityRepo,
            onPolicyChanged: (p) => updatedPolicy = p,
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Select Generic mode
      await tester.tap(find.text('Generic Mode'));
      await tester.pumpAndSettle();

      expect(updatedPolicy?.globalPreferences.privacyMode,
          NotificationPrivacyMode.generic);
    });
  });
}
