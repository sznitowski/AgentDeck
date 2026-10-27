import '../../../core/domain/profiles.dart';
import '../../../core/infrastructure/json_file_store.dart';
import '../domain/project_profile_repository.dart';

class FileProjectProfileRepository implements ProjectProfileRepository {
  FileProjectProfileRepository(this.store);
  final JsonFileStore store;

  @override
  Future<List<ProjectProfile>> all() async =>
      (await store.readAll()).map(_decode).toList(growable: false);

  @override
  Future<ProjectProfile?> find(String id) async {
    for (final profile in await all()) {
      if (profile.id == id) return profile;
    }
    return null;
  }

  @override
  Future<List<ProjectProfile>> findByServer(String serverId) async {
    final list = <ProjectProfile>[];
    for (final profile in await all()) {
      if (profile.serverId == serverId) list.add(profile);
    }
    return list;
  }

  @override
  Future<void> save(ProjectProfile profile) => store.update((items) {
        final row = _encode(profile);
        final index = items.indexWhere((item) => item['id'] == profile.id);
        if (index < 0) {
          items.add(row);
        } else {
          items[index] = row;
        }
      });

  @override
  Future<void> delete(String id) => store.update((items) {
        items.removeWhere((item) => item['id'] == id);
      });

  Map<String, dynamic> _encode(ProjectProfile p) => {
        'id': p.id,
        'name': p.name,
        'serverId': p.serverId,
        'workingDirectory': p.workingDirectory,
        'environment': p.environment.name,
        'repository': p.repository,
        'runtime': p.runtime,
        'preferredAgentId': p.preferredAgentId,
        'capabilities': p.capabilities.toList(),
      };

  ProjectProfile _decode(Map<String, dynamic> row) => ProjectProfile(
        id: row['id'] as String,
        name: row['name'] as String,
        serverId: row['serverId'] as String,
        workingDirectory: row['workingDirectory'] as String,
        environment: Environment.values.byName(row['environment'] as String),
        executionPolicy: ExecutionPolicy(
            environment:
                Environment.values.byName(row['environment'] as String)),
        repository: row['repository'] as String?,
        runtime: row['runtime'] as String?,
        preferredAgentId: row['preferredAgentId'] as String?,
        capabilities: (row['capabilities'] as List<dynamic>?)
                ?.map((e) => e as String)
                .toSet() ??
            const {},
      );
}
