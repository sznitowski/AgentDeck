import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

import 'package:agentdeck/core/domain/events.dart';
import 'package:agentdeck/core/infrastructure/json_file_store.dart';
import 'package:agentdeck/features/notifications/application/notification_coordinator.dart';
import 'package:agentdeck/features/notifications/application/notification_delivery_service.dart';
import 'package:agentdeck/features/notifications/domain/remote_companion_client.dart';
import 'package:agentdeck/features/notifications/infrastructure/file_companion_cursor_repository.dart';
import 'package:agentdeck/features/notifications/infrastructure/file_event_repository.dart';

class MockCompanionClient implements RemoteCompanionClient {
  MockCompanionClient({
    this.status = CompanionStatus.available,
    this.eventsToReturn = const [],
  });

  CompanionStatus status;
  List<AgentDeckEvent> eventsToReturn;
  int lastQueriedAfterSequence = -1;

  @override
  Future<CompanionAvailability> discover(String serverId) async {
    return CompanionAvailability(
      status: status,
      versionInfo: const CompanionVersionInfo(
        schemaVersion: 1,
        binaryVersion: '0.1.0',
        protocolVersion: 1,
      ),
    );
  }

  @override
  Future<CompanionEventBatch> fetchEvents(
    String serverId, {
    required int afterSequence,
    int limit = 100,
  }) async {
    lastQueriedAfterSequence = afterSequence;
    final lastSeq = eventsToReturn.isNotEmpty ? 42 : afterSequence;
    return CompanionEventBatch(
      schemaVersion: 1,
      events: eventsToReturn,
      lastSequence: lastSeq,
      hasMore: false,
    );
  }

  @override
  Future<Map<String, dynamic>> fetchHealth(String serverId) async =>
      {'status': 'ok'};

  @override
  Future<Map<String, dynamic>> fetchSnapshot(String serverId) async =>
      {'status': 'ok'};

  @override
  Future<Map<String, dynamic>> fetchStatus(String serverId) async =>
      {'status': 'ok'};
}

void main() {
  group('Companion Synchronization Integration Tests', () {
    late Directory tempDir;
    late FileEventRepository eventRepository;
    late FileCompanionCursorRepository cursorRepository;
    late InAppNotificationDelivery deliveryService;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('companion_sync_test_');
      eventRepository = FileEventRepository(
        JsonFileStore(File('${tempDir.path}/events.json')),
      );
      cursorRepository = FileCompanionCursorRepository(
        JsonFileStore(File('${tempDir.path}/cursors.json')),
      );
      deliveryService = InAppNotificationDelivery();
    });

    tearDown(() async {
      await tempDir.delete(recursive: true);
    });

    test('syncs events from companion and advances cursor', () async {
      final companionEvent = AgentDeckEvent(
        id: 'evt_comp_1',
        type: EventType.agentWaitingUser,
        severity: EventSeverity.actionRequired,
        source: EventSource.agent,
        fingerprint: 'fp_waiting_1',
        title: 'Agent needs prompt input',
        message: 'Please review tool execution',
        detectedAt: DateTime.now().toUtc(),
        serverId: 'srv_1',
        projectId: 'proj_1',
        isProduction: false,
      );

      final client = MockCompanionClient(
        status: CompanionStatus.available,
        eventsToReturn: [companionEvent],
      );

      final coordinator = NotificationCoordinator(
        repository: eventRepository,
        deliveryService: deliveryService,
        companionClient: client,
        companionCursorRepository: cursorRepository,
      );

      // 1. Initial sequence cursor is 0
      final initialSeq = await cursorRepository.getLastSequence('srv_1');
      expect(initialSeq, 0);

      // 2. Perform synchronization
      final syncedEvents = await coordinator.syncCompanionEvents('srv_1');
      expect(syncedEvents.length, 1);
      expect(syncedEvents.first.id, 'evt_comp_1');
      expect(client.lastQueriedAfterSequence, 0);

      // 3. Verify sequence cursor updated to 42
      final updatedSeq = await cursorRepository.getLastSequence('srv_1');
      expect(updatedSeq, 42);

      // 4. Verify stored in repository
      final storedEvents = await eventRepository.all();
      expect(storedEvents.length, 1);
      expect(storedEvents.first.id, 'evt_comp_1');

      // 5. Next sync with no new events does not produce duplicates
      client.eventsToReturn = [];
      final secondSync = await coordinator.syncCompanionEvents('srv_1');
      expect(secondSync.length, 0);
      expect(client.lastQueriedAfterSequence, 42);
    });

    test('does not sync when companion is not installed', () async {
      final client = MockCompanionClient(
        status: CompanionStatus.notInstalled,
      );

      final coordinator = NotificationCoordinator(
        repository: eventRepository,
        deliveryService: deliveryService,
        companionClient: client,
        companionCursorRepository: cursorRepository,
      );

      final syncedEvents = await coordinator.syncCompanionEvents('srv_1');
      expect(syncedEvents.isEmpty, isTrue);
      expect(client.lastQueriedAfterSequence, -1);
    });
  });
}
