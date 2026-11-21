import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:agentdeck/core/domain/events.dart';
import 'package:agentdeck/core/domain/installation_identity.dart';
import 'package:agentdeck/core/domain/remote_contracts.dart';
import 'package:agentdeck/features/notifications/application/push_relay_pairing_service.dart';
import 'package:agentdeck/features/notifications/domain/notification_policy.dart';
import 'package:agentdeck/features/notifications/domain/push_device_registration.dart';
import 'package:agentdeck/features/notifications/domain/push_relay_client.dart';
import 'package:agentdeck/features/notifications/domain/relay_config_repository.dart';
import 'package:agentdeck/features/notifications/domain/relay_url_policy.dart';
import 'package:agentdeck/features/notifications/infrastructure/push_notification_service_impl.dart';
import 'package:agentdeck/features/notifications/presentation/notification_settings_page.dart';

class _FakeIdentityRepository implements InstallationIdentityRepository {
  @override
  Future<InstallationIdentity> getIdentity() async => InstallationIdentity(
      id: 'inst_00000000000000000000000000000123',
      createdAt: DateTime.now().toUtc());
}

class _MemoryCredentials implements SecureCredentialStore {
  final Map<String, List<int>> values = {};

  @override
  Future<void> put(String reference, List<int> secret) async =>
      values[reference] = secret;

  @override
  Future<List<int>?> get(String reference) async => values[reference];

  @override
  Future<void> delete(String reference) async => values.remove(reference);
}

class _MemoryRelayConfig implements RelayConfigRepository {
  String? url;

  @override
  Future<String?> getRelayUrl() async => url;

  @override
  Future<void> setRelayUrl(String? relayUrl) async {
    final normalized =
        relayUrl == null ? null : RelayUrlPolicy.normalize(relayUrl);
    if (relayUrl != null && normalized == null) throw ArgumentError(relayUrl);
    url = normalized;
  }

  @override
  Future<void> readCheck() async {}
}

class _FakePushRelayClient implements PushRelayClient {
  PushDeviceRegistration? lastRegistered;
  String? lastBearer;
  String? lastRegisterUrl;
  String? lastPairingCode;
  String? lastPairingUrl;
  final List<String> healthCalls = [];
  Map<String, dynamic> health = {'status': 'ok', 'version': '0.1.0'};
  RelayCallStatus exchangeStatus = RelayCallStatus.ok;

  @override
  Future<RelayCallResult> exchangePairingCode({
    required String pairingCode,
    required String installationId,
    required String relayUrl,
  }) async {
    lastPairingCode = pairingCode;
    lastPairingUrl = relayUrl;
    return exchangeStatus == RelayCallStatus.ok
        ? const RelayCallResult(RelayCallStatus.ok,
            installationToken: 'adt_fake_token')
        : RelayCallResult(exchangeStatus);
  }

  @override
  Future<RelayCallResult> registerDevice(PushDeviceRegistration registration,
      {required String relayUrl, required String installationToken}) async {
    lastRegistered = registration;
    lastBearer = installationToken;
    lastRegisterUrl = relayUrl;
    return const RelayCallResult(RelayCallStatus.ok);
  }

  @override
  Future<RelayCallResult> unregisterDevice(String deviceToken,
          {required String relayUrl,
          required String installationToken}) async =>
      const RelayCallResult(RelayCallStatus.ok);

  @override
  Future<Map<String, dynamic>> checkRelayHealth(
      {required String relayUrl}) async {
    healthCalls.add(relayUrl);
    return health;
  }
}

void main() {
  late _FakePushRelayClient relayClient;
  late _MemoryCredentials credentials;
  late _MemoryRelayConfig relayConfig;
  late PushRelayPairingService pairing;

  setUp(() {
    relayClient = _FakePushRelayClient();
    credentials = _MemoryCredentials();
    relayConfig = _MemoryRelayConfig();
    pairing = PushRelayPairingService(
      client: relayClient,
      credentials: credentials,
      identity: _FakeIdentityRepository(),
    );
  });

  Widget page({
    FakePushNotificationService? pushService,
    ValueChanged<NotificationPolicy>? onPolicyChanged,
  }) =>
      MaterialApp(
        theme: ThemeData.dark(),
        home: NotificationSettingsPage(
          pushService: pushService ?? FakePushNotificationService(),
          relayClient: relayClient,
          pairing: pairing,
          identityRepo: _FakeIdentityRepository(),
          relayConfig: relayConfig,
          onPolicyChanged: onPolicyChanged,
        ),
      );

  void bigScreen(WidgetTester tester) {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());
  }

  void seedToken(String relayUrl, String token) {
    credentials.values[PushRelayPairingService.credentialReference(relayUrl)!] =
        utf8.encode(token);
  }

  Future<void> enterRelayUrl(WidgetTester tester, String text) async {
    await tester.tap(find.byKey(const Key('edit-relay-url')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('relay-url-field')), text);
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
  }

  group('NotificationSettingsPage', () {
    testWidgets('starts with no relay URL and contacts nothing',
        (tester) async {
      bigScreen(tester);
      await tester.pumpWidget(page());
      await tester.pumpAndSettle();

      expect(find.text('Push Notification Settings'), findsOneWidget);
      expect(find.text('iOS Permission: NOT REQUESTED'), findsOneWidget);
      expect(find.text('Lock Screen Privacy'), findsOneWidget);
      expect(find.text('Notification Categories'), findsOneWidget);
      expect(find.text('Push Relay & Token Diagnostics'), findsOneWidget);

      expect(find.text('Not configured'), findsOneWidget);
      expect(find.text('NOT CONFIGURED'), findsOneWidget);
      expect(find.text('NOT PAIRED'), findsOneWidget);
      expect(find.text('Set relay URL'), findsOneWidget);
      expect(relayClient.healthCalls, isEmpty);

      // Pairing is disabled until a relay URL exists.
      final pair = tester.widget<OutlinedButton>(
          find.widgetWithText(OutlinedButton, 'Pair with code'));
      expect(pair.onPressed, isNull);
    });

    testWidgets('relay URL validation shows clear messages and saves nothing',
        (tester) async {
      bigScreen(tester);
      await tester.pumpWidget(page());
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('edit-relay-url')));
      await tester.pumpAndSettle();

      Future<void> tryUrl(String text, String expected) async {
        await tester.enterText(find.byKey(const Key('relay-url-field')), text);
        await tester.tap(find.text('Save'));
        await tester.pumpAndSettle();
        expect(find.textContaining(expected), findsOneWidget, reason: text);
      }

      await tryUrl('', 'Enter the relay URL');
      await tryUrl('ftp://relay.example.com', 'Use an origin');
      await tryUrl('https://relay.example.com/path', 'Use an origin');
      await tryUrl('https://u:p@relay.example.com', 'Use an origin');
      await tryUrl('http://relay.example.com', 'HTTPS is required');
      expect(relayConfig.url, isNull);
      expect(relayClient.healthCalls, isEmpty);
    });

    testWidgets('a valid URL is persisted normalized and health is checked',
        (tester) async {
      bigScreen(tester);
      await tester.pumpWidget(page());
      await tester.pumpAndSettle();

      await enterRelayUrl(tester, ' https://Relay.Example.com/ ');

      expect(relayConfig.url, 'https://relay.example.com');
      expect(find.text('https://relay.example.com'), findsOneWidget);
      expect(find.text('OK'), findsOneWidget);
      expect(relayClient.healthCalls, ['https://relay.example.com']);
      expect(find.text('Edit relay URL'), findsOneWidget);
    });

    testWidgets('an unreachable relay is reported clearly', (tester) async {
      bigScreen(tester);
      relayConfig.url = 'https://relay.example.com';
      relayClient.health = {'status': 'unreachable'};
      await tester.pumpWidget(page());
      await tester.pumpAndSettle();

      expect(find.text('UNREACHABLE'), findsOneWidget);
      expect(find.text('The relay could not be reached.'), findsOneWidget);
    });

    testWidgets('paired installation registers its APNs token with the bearer',
        (tester) async {
      bigScreen(tester);
      relayConfig.url = 'http://127.0.0.1:8443';
      seedToken('http://127.0.0.1:8443', 'adt_seeded');

      await tester.pumpWidget(page());
      await tester.pumpAndSettle();
      expect(find.text('PAIRED'), findsOneWidget);

      await tester.tap(find.text('Enable Notifications'));
      await tester.pumpAndSettle();
      expect(find.text('Enable Remote Alerts'), findsOneWidget);
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();

      expect(find.text('iOS Permission: AUTHORIZED'), findsOneWidget);
      expect(relayClient.lastRegistered?.installationId,
          'inst_00000000000000000000000000000123');
      expect(relayClient.lastBearer, 'adt_seeded');
      expect(relayClient.lastRegisterUrl, 'http://127.0.0.1:8443');
    });

    testWidgets('enabling notifications without a relay URL registers nothing',
        (tester) async {
      bigScreen(tester);
      await tester.pumpWidget(page());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Enable Notifications'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();

      expect(relayClient.lastRegistered, isNull);
      expect(find.text('Set the relay URL first.'), findsOneWidget);
    });

    testWidgets('unpaired installation never registers with the relay',
        (tester) async {
      bigScreen(tester);
      relayConfig.url = 'https://relay.example.com';
      await tester.pumpWidget(page());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Enable Notifications'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();

      expect(relayClient.lastRegistered, isNull);
      expect(find.textContaining('Pair this device with the relay'),
          findsOneWidget);
    });

    testWidgets('pairing with a code stores the token under the relay origin',
        (tester) async {
      bigScreen(tester);
      relayConfig.url = 'https://relay.example.com';
      await tester.pumpWidget(page());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Pair with code'));
      await tester.pumpAndSettle();
      await tester.enterText(
          find.byKey(const Key('pairing-code-field')), 'ABCD-EFGH-IJKL-MNOP');
      await tester.tap(find.text('Pair'));
      await tester.pumpAndSettle();

      expect(relayClient.lastPairingCode, 'ABCD-EFGH-IJKL-MNOP');
      expect(relayClient.lastPairingUrl, 'https://relay.example.com');
      expect(find.text('PAIRED'), findsOneWidget);
      expect(find.text('Forget pairing'), findsOneWidget);
      expect(credentials.values.keys.single,
          'push_relay_installation_token@https://relay.example.com');
    });

    testWidgets('a rejected pairing code shows an error and stores nothing',
        (tester) async {
      bigScreen(tester);
      relayConfig.url = 'https://relay.example.com';
      relayClient.exchangeStatus = RelayCallStatus.invalidCode;
      await tester.pumpWidget(page());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Pair with code'));
      await tester.pumpAndSettle();
      await tester.enterText(
          find.byKey(const Key('pairing-code-field')), 'WRONG-CODE');
      await tester.tap(find.text('Pair'));
      await tester.pumpAndSettle();

      expect(find.text('NOT PAIRED'), findsOneWidget);
      expect(find.textContaining('invalid, expired or already used'),
          findsOneWidget);
      expect(credentials.values, isEmpty);
    });

    testWidgets(
        'switching relay URL shows NOT PAIRED, keeps the old token and never sends it to the new relay',
        (tester) async {
      bigScreen(tester);
      relayConfig.url = 'https://relay-a.example.com';
      seedToken('https://relay-a.example.com', 'adt_for_a');
      await tester.pumpWidget(page());
      await tester.pumpAndSettle();
      expect(find.text('PAIRED'), findsOneWidget);

      await enterRelayUrl(tester, 'https://relay-b.example.com');
      expect(find.text('NOT PAIRED'), findsOneWidget);
      expect(credentials.values.length, 1); // relay A's token is untouched

      await tester.tap(find.text('Enable Notifications'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      expect(relayClient.lastBearer, isNull);
      expect(relayClient.lastRegistered, isNull);

      // Switching back finds relay A still paired.
      await enterRelayUrl(tester, 'https://relay-a.example.com/');
      expect(find.text('PAIRED'), findsOneWidget);
    });

    testWidgets('changing privacy mode notifies policy callback',
        (tester) async {
      bigScreen(tester);
      NotificationPolicy? updatedPolicy;
      await tester.pumpWidget(page(onPolicyChanged: (p) => updatedPolicy = p));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Generic Mode'));
      await tester.pumpAndSettle();

      expect(updatedPolicy?.globalPreferences.privacyMode,
          NotificationPrivacyMode.generic);
    });
  });
}
