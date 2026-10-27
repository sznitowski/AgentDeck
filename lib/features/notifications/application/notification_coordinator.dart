import 'dart:async';

import '../../../core/domain/events.dart';
import '../../../core/domain/workspace.dart';
import '../domain/companion_cursor_repository.dart';
import '../domain/event_repository.dart';
import '../domain/notification_policy.dart';
import '../domain/remote_companion_client.dart';
import 'app_lifecycle_coordinator.dart';
import 'event_deduplicator.dart';
import 'notification_delivery_service.dart';
import 'state_transition_detector.dart';

/// Central coordinator that binds observation streams, state transition detection,
/// deduplication, persistent event storage, notification policy, delivery, and remote companion sync.
class NotificationCoordinator {
  NotificationCoordinator({
    required this.repository,
    StateTransitionDetector? transitionDetector,
    EventDeduplicator? deduplicator,
    NotificationPolicy? policy,
    NotificationDeliveryService? deliveryService,
    AppLifecycleCoordinator? lifecycleCoordinator,
    this.companionClient,
    this.companionCursorRepository,
  })  : transitionDetector = transitionDetector ?? StateTransitionDetector(),
        deduplicator = deduplicator ?? EventDeduplicator(),
        policy = policy ?? NotificationPolicy(),
        deliveryService = deliveryService ?? InAppNotificationDelivery(),
        lifecycleCoordinator = lifecycleCoordinator;

  final EventRepository repository;
  final StateTransitionDetector transitionDetector;
  final EventDeduplicator deduplicator;
  final NotificationPolicy policy;
  final NotificationDeliveryService deliveryService;
  final AppLifecycleCoordinator? lifecycleCoordinator;
  final RemoteCompanionClient? companionClient;
  final CompanionCursorRepository? companionCursorRepository;

  /// In-app live events stream.
  Stream<AgentDeckEvent> get liveEvents => deliveryService.inAppEvents;

  /// Processes a workspace snapshot observation, detecting transitions, deduplicating,
  /// persisting records, and notifying users.
  Future<List<AgentDeckEvent>> processWorkspaceSnapshot(
    ProjectWorkspaceSnapshot snapshot, {
    DateTime? now,
  }) async {
    final rawEvents =
        transitionDetector.evaluateWorkspaceSnapshot(snapshot, now: now);
    if (rawEvents.isEmpty) return const [];

    final uniqueEvents = deduplicator.filterDuplicates(rawEvents, now: now);
    if (uniqueEvents.isEmpty) return const [];

    // Persist to atomic event store
    await repository.saveAll(uniqueEvents);

    // Evaluate notification policy & deliver
    for (final event in uniqueEvents) {
      if (policy.shouldNotify(event)) {
        final payload = policy.sanitizeForPreview(event);
        await deliveryService.deliver(event, payload);
      }
    }

    return uniqueEvents;
  }

  /// Synchronizes remote events from the server companion after the last known sequence cursor.
  /// Deduplicates records, persists to the event store, and delivers active notifications.
  Future<List<AgentDeckEvent>> syncCompanionEvents(
    String serverId, {
    DateTime? now,
  }) async {
    final client = companionClient;
    final cursorRepo = companionCursorRepository;
    if (client == null || cursorRepo == null) return const [];

    final availability = await client.discover(serverId);
    if (!availability.isAvailable) return const [];

    final lastSeq = await cursorRepo.getLastSequence(serverId);
    final batch = await client.fetchEvents(
      serverId,
      afterSequence: lastSeq,
      limit: 100,
    );

    if (batch.events.isEmpty) return const [];

    final uniqueEvents = deduplicator.filterDuplicates(batch.events, now: now);
    if (uniqueEvents.isNotEmpty) {
      await repository.saveAll(uniqueEvents);

      for (final event in uniqueEvents) {
        if (policy.shouldNotify(event)) {
          final payload = policy.sanitizeForPreview(event);
          await deliveryService.deliver(event, payload);
        }
      }
    }

    // Always advance cursor to batch.lastSequence
    await cursorRepo.saveLastSequence(serverId, batch.lastSequence);
    return uniqueEvents;
  }

  /// Queries stored events with filtering and sorting.
  Future<List<AgentDeckEvent>> getRecentEvents({
    int limit = 50,
    EventReadState? filterReadState,
    String? filterProjectId,
  }) {
    return repository.all(
      limit: limit,
      filterReadState: filterReadState,
      filterProjectId: filterProjectId,
    );
  }

  /// Returns unread count.
  Future<int> getUnreadCount({String? projectId}) {
    return repository.unreadCount(projectId: projectId);
  }

  /// Returns count of unread actionable items.
  Future<int> getActionableCount({String? projectId}) {
    return repository.actionableCount(projectId: projectId);
  }

  /// Marks a specific event as read.
  Future<void> markRead(String id) {
    return repository.markRead(id);
  }

  /// Marks all unread events as read.
  Future<void> markAllRead({String? projectId}) {
    return repository.markAllRead(projectId: projectId);
  }

  /// Clears stored events.
  Future<void> clearHistory({String? projectId}) {
    return repository.clear(projectId: projectId);
  }

  /// Releases resources.
  Future<void> dispose() async {
    lifecycleCoordinator?.dispose();
    await deliveryService.dispose();
  }
}
