import '../../../core/domain/agents.dart';
import '../../../core/infrastructure/json_file_store.dart';

class FileAgentInstanceRepository implements AgentInstanceRepository {
  FileAgentInstanceRepository(this.store);

  final JsonFileStore store;

  AgentInstance _decode(Map<String, dynamic> row) {
    return AgentInstance.fromJson(row);
  }

  Map<String, dynamic> _encode(AgentInstance instance) {
    return instance.toJson();
  }

  @override
  Future<List<AgentInstance>> all() async {
    final rows = await store.readAll();
    return rows.map(_decode).toList();
  }

  @override
  Future<List<AgentInstance>> forServer(String serverId) async {
    final allInstances = await all();
    return allInstances.where((i) => i.serverId == serverId).toList();
  }

  @override
  Future<List<AgentInstance>> forProject(
      String serverId, String projectId) async {
    final allInstances = await all();
    return allInstances
        .where((i) => i.serverId == serverId && i.projectId == projectId)
        .toList();
  }

  @override
  Future<AgentInstance?> find(String id) async {
    final allInstances = await all();
    for (final i in allInstances) {
      if (i.id == id) return i;
    }
    return null;
  }

  @override
  Future<void> put(AgentInstance instance) async {
    await store.update((rows) {
      final index = rows.indexWhere((r) => r['id'] == instance.id);
      if (index >= 0) {
        rows[index] = _encode(instance);
      } else {
        rows.add(_encode(instance));
      }
    });
  }

  @override
  Future<void> delete(String id) async {
    await store.update((rows) {
      rows.removeWhere((r) => r['id'] == id);
    });
  }

  @override
  Future<void> readCheck() async {
    await all();
  }
}
