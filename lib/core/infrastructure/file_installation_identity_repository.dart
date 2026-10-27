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
    if (items.isNotEmpty && items.first.containsKey('id')) {
      return InstallationIdentity.fromJson(items.first);
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
