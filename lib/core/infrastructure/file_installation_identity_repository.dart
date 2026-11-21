import '../domain/installation_identity.dart';
import 'json_file_store.dart';

/// JSON-file persistent store for [InstallationIdentity].
class FileInstallationIdentityRepository
    implements InstallationIdentityRepository {
  const FileInstallationIdentityRepository(this.store);

  final JsonFileStore store;

  @override
  Future<InstallationIdentity> getIdentity() async {
    final items = await store.readAll();
    if (items.isNotEmpty) {
      final existing = InstallationIdentity.fromJson(items.first);
      // Valid (current or legacy) identities are kept as-is; only a missing or
      // malformed id is replaced.
      if (InstallationIdentity.isValidId(existing.id)) return existing;
    }
    final newIdentity = InstallationIdentity.generate();
    await store.update((list) {
      list
        ..clear()
        ..add(newIdentity.toJson());
    });
    return newIdentity;
  }
}
