import '../../../core/infrastructure/json_file_store.dart';
import '../domain/tmux_models.dart';

class FileTmuxSessionRepository implements TmuxSessionRepository {
  FileTmuxSessionRepository(this.store);
  final JsonFileStore store;

  TmuxSessionReference _decode(Map<String, dynamic> row) {
    final server = row['serverId'];
    final name = row['remoteName'];
    final display = row['displayName'];
    final project = row['projectId'];
    final last = row['lastAttachedAt'];
    if (server is! String ||
        server.isEmpty ||
        name is! String ||
        !validTmuxName(name) ||
        display is! String ||
        display.isEmpty ||
        (project != null && project is! String) ||
        (last != null && last is! String)) {
      throw const FormatException('Invalid tmux reference');
    }
    return TmuxSessionReference(
        serverId: server,
        remoteName: name,
        displayName: display,
        projectId: project as String?,
        lastAttachedAt: last == null ? null : DateTime.parse(last as String));
  }

  Map<String, dynamic> _encode(TmuxSessionReference row) => {
        'serverId': row.serverId,
        'remoteName': row.remoteName,
        'displayName': row.displayName,
        'projectId': row.projectId,
        'lastAttachedAt': row.lastAttachedAt?.toUtc().toIso8601String(),
      };

  @override
  Future<List<TmuxSessionReference>> forServer(String serverId) async =>
      (await store.readAll())
          .map(_decode)
          .where((row) => row.serverId == serverId)
          .toList();

  @override
  Future<void> readCheck() async {
    (await store.readAll()).map(_decode).toList();
  }

  @override
  Future<void> save(TmuxSessionReference reference) {
    if (!validTmuxName(reference.remoteName))
      throw const FormatException('Invalid tmux name');
    return store.update((rows) {
      final index = rows.indexWhere((row) =>
          row['serverId'] == reference.serverId &&
          row['remoteName'] == reference.remoteName);
      if (index < 0) {
        rows.add(_encode(reference));
      } else {
        rows[index] = _encode(reference);
      }
    });
  }

  @override
  Future<void> delete(String serverId, String remoteName) =>
      store.update((rows) => rows.removeWhere((row) =>
          row['serverId'] == serverId && row['remoteName'] == remoteName));

  @override
  Future<void> deleteServer(String serverId) => store
      .update((rows) => rows.removeWhere((row) => row['serverId'] == serverId));
}
