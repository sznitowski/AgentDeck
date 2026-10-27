import '../../../core/domain/events.dart';

/// Repository contract for persistent event and notification history.
abstract class EventRepository {
  /// Returns stored events ordered newest first, with optional filtering and retention limits.
  Future<List<AgentDeckEvent>> all({
    int limit = 200,
    EventReadState? filterReadState,
    String? filterProjectId,
  });

  /// Retrieves a specific event by ID.
  Future<AgentDeckEvent?> getById(String id);

  /// Stores or updates an event. Enforces FIFO bounded retention.
  Future<void> save(AgentDeckEvent event);

  /// Stores multiple events atomically.
  Future<void> saveAll(List<AgentDeckEvent> events);

  /// Updates an event's read status to read.
  Future<void> markRead(String id);

  /// Marks all unread events as read, optionally filtered by project.
  Future<void> markAllRead({String? projectId});

  /// Deletes a single event by ID.
  Future<void> delete(String id);

  /// Clears stored events, optionally filtered by project.
  Future<void> clear({String? projectId});

  /// Returns count of unread events.
  Future<int> unreadCount({String? projectId});

  /// Returns count of unread actionable (critical/actionRequired) events.
  Future<int> actionableCount({String? projectId});

  /// Validates underlying storage readiness.
  Future<void> readCheck();
}
