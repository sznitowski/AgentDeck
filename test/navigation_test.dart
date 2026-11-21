import 'dart:convert';
import 'dart:io';

import 'package:agentdeck/app/agentdeck_app.dart';
import 'package:agentdeck/app/app_services.dart';
import 'package:agentdeck/features/connections/infrastructure/platform_secure_credential_store.dart';
import 'package:agentdeck/features/notifications/application/push_relay_pairing_service.dart';
import 'package:agentdeck/features/notifications/domain/push_device_registration.dart';
import 'package:agentdeck/features/notifications/domain/push_notification_service.dart';
import 'package:agentdeck/features/notifications/domain/push_relay_client.dart';
import 'package:agentdeck/features/notifications/domain/relay_config_repository.dart';
import 'package:agentdeck/features/notifications/domain/relay_url_policy.dart';
import 'package:agentdeck/features/notifications/infrastructure/push_notification_service_impl.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _MemorySecrets implements SecretValueBackend {
  final values = <String, String>{};
  @override
  Future<void> write(String key, String value) async => values[key] = value;
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> delete(String key) async => values.remove(key);
}

class _MemoryRelayConfig implements RelayConfigRepository {
  _MemoryRelayConfig([this.url]);
  String? url;
  @override
  Future<String?> getRelayUrl() async => url;
  @override
  Future<void> setRelayUrl(String? relayUrl) async =>
      url = relayUrl == null ? null : RelayUrlPolicy.normalize(relayUrl);
  @override
  Future<void> readCheck() async {}
}

class _RecordingRelayClient implements PushRelayClient {
  final healthUrls = <String>[];
  @override
  Future<Map<String, dynamic>> checkRelayHealth(
      {required String relayUrl}) async {
    healthUrls.add(relayUrl);
    return {'status': 'ok'};
  }

  @override
  Future<RelayCallResult> exchangePairingCode(
          {required String pairingCode,
          required String installationId,
          required String relayUrl}) async =>
      const RelayCallResult(RelayCallStatus.rejected);
  @override
  Future<RelayCallResult> registerDevice(PushDeviceRegistration registration,
          {required String relayUrl,
          required String installationToken}) async =>
      const RelayCallResult(RelayCallStatus.rejected);
  @override
  Future<RelayCallResult> unregisterDevice(String deviceToken,
          {required String relayUrl,
          required String installationToken}) async =>
      const RelayCallResult(RelayCallStatus.rejected);
}

/// Bounded settle: other tabs run real file I/O that never completes in the
/// fake-async zone and keeps spinners animating, so `pumpAndSettle` would time out.
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  testWidgets('all five destinations navigate to their pages', (tester) async {
    await tester.pumpWidget(const AgentDeckApp());
    expect(find.text('No servers yet'), findsOneWidget);

    for (final label in ['Servers', 'Projects', 'Agents', 'Settings']) {
      await tester.tap(find.widgetWithText(NavigationDestination, label));
      await tester.pumpAndSettle();
      expect(find.text(label, skipOffstage: false), findsWidgets);
    }
    // The M0 placeholder is gone.
    expect(find.text('M0 Bootstrap'), findsNothing);
    expect(find.text('Build stage'), findsNothing);
  });

  testWidgets('without services Settings shows push settings as unavailable',
      (tester) async {
    await tester.pumpWidget(const AgentDeckApp());
    await tester.tap(find.widgetWithText(NavigationDestination, 'Settings'));
    await tester.pumpAndSettle();
    final tile = tester
        .widget<ListTile>(find.byKey(const Key('settings-push-notifications')));
    expect(tile.enabled, isFalse);
  });

  group('Settings with real bootstrap services', () {
    late Directory dir;
    late _MemorySecrets secrets;
    late FakePushNotificationService push;
    late _RecordingRelayClient relayClient;
    late _MemoryRelayConfig relayConfig;
    late AgentDeckServices services;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('agentdeck_nav_');
      secrets = _MemorySecrets();
      push = FakePushNotificationService()
        ..setAuthorizationStatus(PushAuthorizationStatus.authorized);
      relayClient = _RecordingRelayClient();
      relayConfig = _MemoryRelayConfig('https://relay.example.com');
    });

    tearDown(() async => await dir.delete(recursive: true));

    Future<void> openApp(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1200, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());
      // Bootstrap performs real file I/O, so it runs outside the fake-async zone.
      services = (await tester.runAsync(() => AgentDeckServices.bootstrap(
            directory: dir,
            secretBackend: secrets,
            pushNotificationService: push,
            pushRelay: relayClient,
            relayConfigRepository: relayConfig,
          )))!;
      await tester.pumpWidget(AgentDeckApp(services: services));
      await tester.pump();
    }

    Future<void> openPushSettings(WidgetTester tester) async {
      await tester.tap(find.widgetWithText(NavigationDestination, 'Settings'));
      await settle(tester);
      await tester.tap(find.byKey(const Key('settings-push-notifications')));
      await settle(tester);
    }

    testWidgets('Settings is in the main navigation and opens Push settings',
        (tester) async {
      await openApp(tester);
      expect(find.widgetWithText(NavigationDestination, 'Settings'),
          findsOneWidget);

      await tester.tap(find.widgetWithText(NavigationDestination, 'Settings'));
      await settle(tester);
      final tile = tester.widget<ListTile>(
          find.byKey(const Key('settings-push-notifications')));
      expect(tile.enabled, isTrue);

      await tester.tap(find.byKey(const Key('settings-push-notifications')));
      await settle(tester);
      expect(find.text('Push Notification Settings'), findsOneWidget);
    });

    testWidgets('the page receives the bootstrap services, not copies',
        (tester) async {
      // Token stored through the bootstrap credential store (Keychain backend).
      secrets.values['agentdeck.credential.v1.'
              '${PushRelayPairingService.credentialReference('https://relay.example.com')}'] =
          base64Encode(utf8.encode('adt_seeded'));

      await openApp(tester);
      await openPushSettings(tester);

      // pushService: the injected fake's state is what the page shows.
      expect(find.text('iOS Permission: AUTHORIZED'), findsOneWidget);
      // relayConfig: the bootstrap repository supplied the URL.
      expect(find.text('https://relay.example.com'), findsOneWidget);
      // pushRelayClient: health was checked against that URL.
      expect(relayClient.healthUrls, ['https://relay.example.com']);
      // pushRelayPairing + credentials: the Keychain-backed token marks it paired.
      expect(find.text('PAIRED'), findsOneWidget);
      // The same instances are exposed by the services object.
      expect(identical(services.pushService, push), isTrue);
      expect(identical(services.pushRelayClient, relayClient), isTrue);
      expect(identical(services.relayConfig, relayConfig), isTrue);
    });

    testWidgets('the pairing dialog opens from the real flow', (tester) async {
      await openApp(tester);
      await openPushSettings(tester);

      expect(find.text('NOT PAIRED'), findsOneWidget);
      await tester.tap(find.text('Pair with code'));
      await settle(tester);
      expect(find.text('Pair with Push Relay'), findsOneWidget);
      expect(find.byKey(const Key('pairing-code-field')), findsOneWidget);
    });

    testWidgets('an unconfigured relay contacts nothing from the real app',
        (tester) async {
      relayConfig.url = null;
      await openApp(tester);
      await openPushSettings(tester);

      expect(find.text('Not configured'), findsOneWidget);
      expect(relayClient.healthUrls, isEmpty);
    });

    testWidgets('going back keeps the Settings tab and its state',
        (tester) async {
      await openApp(tester);
      await openPushSettings(tester);
      expect(find.text('Push Notification Settings'), findsOneWidget);

      await tester.pageBack();
      await settle(tester);

      expect(find.text('Push Notification Settings'), findsNothing);
      final bar = tester.widget<NavigationBar>(find.byType(NavigationBar));
      expect(bar.selectedIndex, 4);
      expect(
          find.byKey(const Key('settings-push-notifications')), findsOneWidget);

      // Other tabs still work and Settings is preserved when coming back.
      await tester.tap(find.widgetWithText(NavigationDestination, 'Home'));
      await settle(tester);
      await tester.tap(find.widgetWithText(NavigationDestination, 'Settings'));
      await settle(tester);
      expect(
          find.byKey(const Key('settings-push-notifications')), findsOneWidget);
    });
  });
}
