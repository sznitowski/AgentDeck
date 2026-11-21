import 'dart:convert';

import '../../../core/domain/installation_identity.dart';
import '../../../core/domain/remote_contracts.dart';
import '../domain/push_device_registration.dart';
import '../domain/push_relay_client.dart';
import '../domain/relay_url_policy.dart';

/// Pairs this installation with a Push Relay and authenticates later calls.
///
/// The opaque installation token lives only in the [SecureCredentialStore]
/// (iOS Keychain). It is never written to JSON/preferences or logged, and it is
/// bound to the relay authority so it can never be sent to a different host.
class PushRelayPairingService {
  const PushRelayPairingService({
    required this.client,
    required this.credentials,
    required this.identity,
  });

  final PushRelayClient client;
  final SecureCredentialStore credentials;
  final InstallationIdentityRepository identity;

  /// Keychain reference for the token of one relay **origin**
  /// (`scheme://host[:port]`). Different hosts, ports or schemes never share a
  /// reference; `https://r.example.com` and `https://r.example.com/` do.
  /// Returns null for URLs the policy rejects.
  static String? credentialReference(String relayUrl) {
    final origin = RelayUrlPolicy.normalize(relayUrl);
    return origin == null ? null : 'push_relay_installation_token@$origin';
  }

  String? _reference(String relayUrl) => credentialReference(relayUrl);

  Future<bool> isPaired(String relayUrl) async {
    final ref = _reference(relayUrl);
    if (ref == null) return false;
    return (await credentials.get(ref)) != null;
  }

  /// Exchanges [pairingCode] for a token and stores it in the Keychain.
  Future<RelayCallStatus> pair(String pairingCode,
      {required String relayUrl}) async {
    final ref = _reference(relayUrl);
    if (ref == null) return RelayCallStatus.insecureUrl;
    final me = await identity.getIdentity();
    final result = await client.exchangePairingCode(
      pairingCode: pairingCode,
      installationId: me.id,
      relayUrl: relayUrl,
    );
    final token = result.installationToken;
    if (result.isOk && token != null) {
      await credentials.put(ref, utf8.encode(token));
      return RelayCallStatus.ok;
    }
    return result.status == RelayCallStatus.ok
        ? RelayCallStatus.rejected
        : result.status;
  }

  Future<RelayCallResult> registerDevice(PushDeviceRegistration registration,
      {required String relayUrl}) async {
    final token = await _token(relayUrl);
    if (token == null) {
      return const RelayCallResult(RelayCallStatus.unauthorized);
    }
    final result = await client.registerDevice(registration,
        relayUrl: relayUrl, installationToken: token);
    await _dropTokenIfRejected(result, relayUrl);
    return result;
  }

  Future<RelayCallResult> unregisterDevice(String deviceToken,
      {required String relayUrl}) async {
    final token = await _token(relayUrl);
    if (token == null) {
      return const RelayCallResult(RelayCallStatus.unauthorized);
    }
    final result = await client.unregisterDevice(deviceToken,
        relayUrl: relayUrl, installationToken: token);
    await _dropTokenIfRejected(result, relayUrl);
    return result;
  }

  /// Removes the stored token locally (the relay-side token is revoked by an admin).
  Future<void> forget(String relayUrl) async {
    final ref = _reference(relayUrl);
    if (ref != null) await credentials.delete(ref);
  }

  Future<String?> _token(String relayUrl) async {
    final ref = _reference(relayUrl);
    if (ref == null) return null;
    final bytes = await credentials.get(ref);
    return bytes == null ? null : utf8.decode(bytes);
  }

  /// A 401 means the relay revoked or lost this token: forget it so the UI asks
  /// for a new pairing code instead of retrying a dead credential forever.
  Future<void> _dropTokenIfRejected(
      RelayCallResult result, String relayUrl) async {
    if (result.status == RelayCallStatus.unauthorized) {
      await forget(relayUrl);
    }
  }
}
