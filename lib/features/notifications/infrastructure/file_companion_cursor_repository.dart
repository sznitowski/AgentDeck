import '../../../core/infrastructure/json_file_store.dart';
import '../domain/companion_cursor_repository.dart';

/// Atomic JSON file storage for tracking server event cursors.
class FileCompanionCursorRepository implements CompanionCursorRepository {
  FileCompanionCursorRepository(this.store);

  final JsonFileStore store;

  @override
  Future<int> getLastSequence(String serverId) async {
    final items = await store.readAll();
    for (final item in items) {
      if (item['serverId'] == serverId) {
        return (item['lastSequence'] as num?)?.toInt() ?? 0;
      }
    }
    return 0;
  }

  @override
  Future<void> saveLastSequence(String serverId, int sequence) async {
    await store.update((items) {
      final index = items.indexWhere((item) => item['serverId'] == serverId);
      if (index >= 0) {
        final current = (items[index]['lastSequence'] as num?)?.toInt() ?? 0;
        if (sequence > current) {
          items[index]['lastSequence'] = sequence;
          items[index]['updatedAt'] = DateTime.now().toUtc().toIso8601String();
        }
      } else {
        items.add({
          'serverId': serverId,
          'lastSequence': sequence,
          'updatedAt': DateTime.now().toUtc().toIso8601String(),
        });
      }
    });
  }

  @override
  Future<void> clear(String serverId) async {
    await store.update((items) {
      items.removeWhere((item) => item['serverId'] == serverId);
    });
  }

  @override
  Future<void> clearAll() async {
    await store.update((items) {
      items.clear();
    });
  }
}
