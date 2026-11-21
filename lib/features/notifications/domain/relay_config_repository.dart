/// Non-secret, persistent Push Relay configuration (the relay origin only).
///
/// Tokens never live here: they are stored exclusively in the Keychain through
/// `SecureCredentialStore`.
abstract class RelayConfigRepository {
  /// Normalized relay origin (`https://host[:port]`), or null when not configured.
  Future<String?> getRelayUrl();

  /// Persists the normalized origin of [relayUrl]; null clears the configuration.
  /// Throws [ArgumentError] when the URL violates `RelayUrlPolicy`.
  Future<void> setRelayUrl(String? relayUrl);

  /// Throws if the stored data is unreadable (fail closed at bootstrap).
  Future<void> readCheck();
}
