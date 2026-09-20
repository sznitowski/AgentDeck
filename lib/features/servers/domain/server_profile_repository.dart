import '../../../core/domain/profiles.dart';

abstract interface class ServerProfileRepository {
  Future<List<ServerProfile>> all();
  Future<ServerProfile?> find(String id);
  Future<void> save(ServerProfile profile);
  Future<void> delete(String id);
}
