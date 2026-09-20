import '../../../core/domain/profiles.dart';
import '../../../core/infrastructure/json_file_store.dart';
import '../domain/server_profile_repository.dart';

class FileServerProfileRepository implements ServerProfileRepository {
  FileServerProfileRepository(this.store);
  final JsonFileStore store;

  @override
  Future<List<ServerProfile>> all() async =>
      (await store.readAll()).map(_decode).toList(growable: false);

  @override
  Future<ServerProfile?> find(String id) async {
    for (final profile in await all()) {
      if (profile.id == id) return profile;
    }
    return null;
  }

  @override
  Future<void> save(ServerProfile profile) => store.update((items) {
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

  Map<String, dynamic> _encode(ServerProfile p) => {
        'id': p.id,
        'name': p.name,
        'host': p.host,
        'port': p.port,
        'username': p.username,
        'authenticationMethod': p.authenticationMethod.name,
        'environment': p.environment.name,
        'credentialId': p.credentialId,
        'passphraseCredentialId': p.passphraseCredentialId,
      };

  ServerProfile _decode(Map<String, dynamic> row) => ServerProfile(
        id: row['id'] as String,
        name: row['name'] as String,
        host: row['host'] as String,
        port: row['port'] as int,
        username: row['username'] as String,
        authenticationMethod: SshAuthenticationMethod.values
            .byName(row['authenticationMethod'] as String),
        environment: Environment.values.byName(row['environment'] as String),
        credentialId: row['credentialId'] as String,
        passphraseCredentialId: row['passphraseCredentialId'] as String?,
      );
}
