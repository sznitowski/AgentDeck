import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../../core/domain/remote_contracts.dart';

abstract interface class SecretValueBackend {
  Future<void> write(String key, String value);
  Future<String?> read(String key);
  Future<void> delete(String key);
}

class FlutterSecureStorageBackend implements SecretValueBackend {
  const FlutterSecureStorageBackend(this.storage);
  final FlutterSecureStorage storage;

  @override
  Future<void> write(String key, String value) =>
      storage.write(key: key, value: value);
  @override
  Future<String?> read(String key) => storage.read(key: key);
  @override
  Future<void> delete(String key) => storage.delete(key: key);
}

class PlatformSecureCredentialStore implements SecureCredentialStore {
  const PlatformSecureCredentialStore(this.backend);
  final SecretValueBackend backend;

  String _key(String reference) {
    if (reference.isEmpty) throw ArgumentError.value(reference, 'reference');
    return 'agentdeck.credential.v1.$reference';
  }

  @override
  Future<void> put(String reference, List<int> secret) =>
      backend.write(_key(reference), base64Encode(secret));

  @override
  Future<List<int>?> get(String reference) async {
    final encoded = await backend.read(_key(reference));
    return encoded == null ? null : base64Decode(encoded);
  }

  @override
  Future<void> delete(String reference) => backend.delete(_key(reference));
}
