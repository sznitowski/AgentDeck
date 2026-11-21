import '../../../core/infrastructure/json_file_store.dart';
import '../domain/relay_config_repository.dart';
import '../domain/relay_url_policy.dart';

/// Versioned, atomic JSON storage (via [JsonFileStore]) for the relay origin.
class FileRelayConfigRepository implements RelayConfigRepository {
  const FileRelayConfigRepository(this.store);

  final JsonFileStore store;

  @override
  Future<String?> getRelayUrl() async {
    final items = await store.readAll();
    if (items.isEmpty) return null;
    final value = items.first['relayUrl'];
    if (value is! String) return null;
    // A hand-edited or tampered file can never smuggle in a URL the policy rejects.
    return RelayUrlPolicy.normalize(value);
  }

  @override
  Future<void> setRelayUrl(String? relayUrl) async {
    final normalized =
        relayUrl == null ? null : RelayUrlPolicy.normalize(relayUrl);
    if (relayUrl != null && normalized == null) {
      throw ArgumentError.value(
          relayUrl, 'relayUrl', 'Not an allowed relay URL');
    }
    await store.update((items) {
      items.clear();
      if (normalized != null) items.add({'relayUrl': normalized});
    });
  }

  @override
  Future<void> readCheck() async {
    await getRelayUrl();
  }
}
