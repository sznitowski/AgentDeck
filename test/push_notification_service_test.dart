import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

import 'package:agentdeck/core/domain/events.dart';
import 'package:agentdeck/core/infrastructure/file_installation_identity_repository.dart';
import 'package:agentdeck/core/infrastructure/json_file_store.dart';
import 'package:agentdeck/features/notifications/domain/push_device_registration.dart';
import 'package:agentdeck/features/notifications/domain/push_notification_service.dart';
import 'package:agentdeck/features/notifications/infrastructure/file_push_registration_repository.dart';
import 'package:agentdeck/features/notifications/infrastructure/push_notification_service_impl.dart';

void main() {
  group('PushNotificationService & Repositories Unit Tests', () {
    late Directory tempDir;
    late FileInstallationIdentityRepository identityRepo;
    late FilePushRegistrationRepository registrationRepo;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('agentdeck_push_test_');
      identityRepo = FileInstallationIdentityRepository(
        JsonFileStore(File('${tempDir.path}/identity.json')),
      );
      registrationRepo = FilePushRegistrationRepository(
        JsonFileStore(File('${tempDir.path}/registration.json')),
      );
    });

    tearDown(() async {
      await tempDir.delete(recursive: true);
    });

    test('InstallationIdentity persists stable UUID across multiple reads',
        () async {
      final id1 = await identityRepo.getIdentity();
      expect(id1.id.startsWith('inst_'), isTrue);

      final id2 = await identityRepo.getIdentity();
      expect(id2.id, id1.id);
      expect(id2.createdAt, id1.createdAt);
    });

    test('PushRegistrationRepository saves and retrieves registration',
        () async {
      final reg = const PushDeviceRegistration(
        installationId: 'inst_123',
        deviceToken: 'token_abc_456',
        platform: 'ios',
        environment: 'sandbox',
        privacyMode: 'projectOnly',
      );

      await registrationRepo.saveRegistration(reg);
      final retrieved = await registrationRepo.getRegistration();

      expect(retrieved, isNotNull);
      expect(retrieved!.installationId, 'inst_123');
      expect(retrieved.deviceToken, 'token_abc_456');
      expect(retrieved.privacyMode, 'projectOnly');
      expect(retrieved.enabled, isTrue);

      await registrationRepo.clear();
      final cleared = await registrationRepo.getRegistration();
      expect(cleared, isNull);
    });

    test(
        'FakePushNotificationService handles permissions, token stream, and tap events',
        () async {
      final service = FakePushNotificationService();

      // 1. Initial status
      final initialStatus = await service.getAuthorizationStatus();
      expect(initialStatus, PushAuthorizationStatus.notDetermined);
      expect(await service.getDeviceToken(), isNull);

      // 2. Request authorization
      final requestedStatus = await service.requestAuthorization();
      expect(requestedStatus, PushAuthorizationStatus.authorized);
      expect(await service.getDeviceToken(), isNotNull);

      // 3. Token refresh stream
      final refreshedTokens = <String>[];
      final tokenSub =
          service.onTokenRefresh.listen((t) => refreshedTokens.add(t));
      service.emitTokenRefresh('new_rotated_token_999');
      await Future.delayed(const Duration(milliseconds: 10));
      expect(refreshedTokens, ['new_rotated_token_999']);
      expect(await service.getDeviceToken(), 'new_rotated_token_999');
      await tokenSub.cancel();

      // 4. Notification tap stream & pending tap handling
      const dest = NotificationDestination(
        route: 'agent_terminal',
        projectId: 'proj_1',
        serverId: 'srv_1',
      );

      service.setPendingNotificationTap(dest);
      expect(service.getPendingNotificationTap()?.route, 'agent_terminal');

      service.clearPendingNotificationTap();
      expect(service.getPendingNotificationTap(), isNull);

      final taps = <NotificationDestination>[];
      final tapSub = service.onNotificationTap.listen((d) => taps.add(d));
      service.emitNotificationTap(dest);
      await Future.delayed(const Duration(milliseconds: 10));
      expect(taps.length, 1);
      expect(taps.first.route, 'agent_terminal');
      await tapSub.cancel();

      await service.dispose();
    });
  });
}
