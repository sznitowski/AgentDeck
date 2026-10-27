import '../../../core/domain/profiles.dart';

abstract interface class ProjectProfileRepository {
  Future<List<ProjectProfile>> all();
  Future<ProjectProfile?> find(String id);
  Future<List<ProjectProfile>> findByServer(String serverId);
  Future<void> save(ProjectProfile profile);
  Future<void> delete(String id);
}
