import '../../../core/infrastructure/json_file_store.dart';
import '../domain/push_device_registration.dart';

/// JSON-file persistent store for [PushDeviceRegistration].
class FilePushRegistrationRepository implements PushRegistrationRepository {
  const FilePushRegistrationRepository(this.store);

  final JsonFileStore store;

  @override
  Future<PushDeviceRegistration?> getRegistration() async {
    final items = await store.readAll();
    if (items.isEmpty || !items.first.containsKey('deviceToken')) {
      return null;
    }
    return PushDeviceRegistration.fromJson(items.first);
  }

  @override
  Future<void> saveRegistration(PushDeviceRegistration registration) async {
    await store.update((items) {
      items
        ..clear()
        ..add(registration.toJson());
    });
  }

  @override
  Future<void> clear() async {
    await store.update((items) {
      items.clear();
    });
  }
}
