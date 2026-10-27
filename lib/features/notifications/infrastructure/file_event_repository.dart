import '../../../core/domain/events.dart';
import '../../../core/infrastructure/json_file_store.dart';
import '../domain/event_repository.dart';

/// Atomic, bounded JSON file implementation of [EventRepository].
class FileEventRepository implements EventRepository {
  FileEventRepository(this.store, {this.maxRetention = 200});

  final JsonFileStore store;
  final int maxRetention;

  @override
  Future<List<AgentDeckEvent>> all({
    int limit = 200,
    EventReadState? filterReadState,
    String? filterProjectId,
  }) async {
    final raw = await store.readAll();
    var events = raw.map((m) => AgentDeckEvent.fromJson(m)).toList();

    if (filterReadState != null) {
      events = events.where((e) => e.readState == filterReadState).toList();
    }
    if (filterProjectId != null) {
      events = events.where((e) => e.projectId == filterProjectId).toList();
    }

    // Sort newest first
    events.sort((a, b) => b.detectedAt.compareTo(a.detectedAt));

    if (events.length > limit) {
      events = events.sublist(0, limit);
    }

    return events;
  }

  @override
  Future<AgentDeckEvent?> getById(String id) async {
    final raw = await store.readAll();
    for (final item in raw) {
      if (item['id'] == id) {
        return AgentDeckEvent.fromJson(item);
      }
    }
    return null;
  }

  @override
  Future<void> save(AgentDeckEvent event) => saveAll([event]);

  @override
  Future<void> saveAll(List<AgentDeckEvent> events) async {
    if (events.isEmpty) return;

    await store.update((items) {
      final sanitizedNew =
          events.map((e) => _sanitizeForStorage(e).toJson()).toList();

      for (final newItem in sanitizedNew) {
        final id = newItem['id'];
        final index = items.indexWhere((m) => m['id'] == id);
        if (index != -1) {
          items[index] = newItem;
        } else {
          items.add(newItem);
        }
      }

      // Enforce FIFO bounded retention: newest preserved
      if (items.length > maxRetention) {
        items.sort((a, b) {
          final tA = DateTime.tryParse(a['detectedAt'] as String? ?? '') ??
              DateTime(1970);
          final tB = DateTime.tryParse(b['detectedAt'] as String? ?? '') ??
              DateTime(1970);
          return tB.compareTo(tA);
        });

        while (items.length > maxRetention) {
          items.removeLast();
        }
      }
    });
  }

  @override
  Future<void> markRead(String id) async {
    await store.update((items) {
      final index = items.indexWhere((m) => m['id'] == id);
      if (index != -1) {
        items[index]['readState'] = EventReadState.read.name;
      }
    });
  }

  @override
  Future<void> markAllRead({String? projectId}) async {
    await store.update((items) {
      for (final item in items) {
        if (projectId == null || item['projectId'] == projectId) {
          item['readState'] = EventReadState.read.name;
        }
      }
    });
  }

  @override
  Future<void> delete(String id) async {
    await store.update((items) {
      items.removeWhere((m) => m['id'] == id);
    });
  }

  @override
  Future<void> clear({String? projectId}) async {
    await store.update((items) {
      if (projectId == null) {
        items.clear();
      } else {
        items.removeWhere((m) => m['projectId'] == projectId);
      }
    });
  }

  @override
  Future<int> unreadCount({String? projectId}) async {
    final raw = await store.readAll();
    return raw.where((m) {
      final matchesProject = projectId == null || m['projectId'] == projectId;
      final isUnread = m['readState'] == EventReadState.unread.name;
      return matchesProject && isUnread;
    }).length;
  }

  @override
  Future<int> actionableCount({String? projectId}) async {
    final raw = await store.readAll();
    return raw.where((m) {
      final matchesProject = projectId == null || m['projectId'] == projectId;
      final isUnread = m['readState'] == EventReadState.unread.name;
      final sev = m['severity'];
      final isActionable = sev == EventSeverity.actionRequired.name ||
          sev == EventSeverity.critical.name;
      return matchesProject && isUnread && isActionable;
    }).length;
  }

  @override
  Future<void> readCheck() async {
    await store.readAll();
  }

  /// Ensures sensitive keys, raw command streams, prompt questions, or diffs are never stored.
  AgentDeckEvent _sanitizeForStorage(AgentDeckEvent event) {
    final safeMetadata = <String, dynamic>{};
    for (final entry in event.metadata.entries) {
      final key = entry.key.toLowerCase();
      // Exclude known sensitive payload keys
      if (key.contains('pass') ||
          key.contains('secret') ||
          key.contains('token') ||
          key.contains('key') ||
          key.contains('diff') ||
          key.contains('prompt') ||
          key.contains('stdout') ||
          key.contains('stderr') ||
          key.contains('output') ||
          key.contains('body')) {
        continue;
      }
      safeMetadata[entry.key] = entry.value;
    }

    return event.copyWith(metadata: safeMetadata);
  }
}
