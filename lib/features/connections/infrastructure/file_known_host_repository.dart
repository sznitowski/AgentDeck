import '../../../core/infrastructure/json_file_store.dart';
import '../domain/ssh_models.dart';

class FileKnownHostRepository implements KnownHostRepository {
  FileKnownHostRepository(this.store);
  final JsonFileStore store;

  Future<void> readCheck() async {
    for (final row in await store.readAll()) {
      _decode(row);
    }
  }

  @override
  Future<KnownHost?> find(String hostname, int port) async {
    for (final row in await store.readAll()) {
      if (row['hostname'] == hostname && row['port'] == port)
        return _decode(row);
    }
    return null;
  }

  @override
  Future<void> trust(KnownHost host) => store.update((items) {
        if (_index(items, host.hostname, host.port) >= 0) {
          throw StateError('Known host already exists');
        }
        items.add(_encode(host));
      });

  @override
  Future<void> revoke(String hostname, int port) => store.update((items) {
        final index = _index(items, hostname, port);
        if (index < 0) return;
        items[index]['revoked'] = true;
      });

  @override
  Future<void> replace(KnownHost host) => store.update((items) {
        final index = _index(items, host.hostname, host.port);
        if (index < 0) throw StateError('No known host to replace');
        items[index] = _encode(host);
      });

  @override
  Future<void> markSeen(String hostname, int port, DateTime at) =>
      store.update((items) {
        final index = _index(items, hostname, port);
        if (index < 0 || items[index]['revoked'] == true) {
          throw StateError('Host is not trusted');
        }
        items[index]['lastSeenAt'] = at.toUtc().toIso8601String();
      });

  @override
  Future<void> delete(String hostname, int port) => store.update((items) {
        items.removeWhere(
            (row) => row['hostname'] == hostname && row['port'] == port);
      });

  int _index(List<Map<String, dynamic>> items, String host, int port) =>
      items.indexWhere((row) => row['hostname'] == host && row['port'] == port);

  Map<String, dynamic> _encode(KnownHost h) => {
        'hostname': h.hostname,
        'port': h.port,
        'algorithm': h.identity.algorithm,
        'fingerprint': h.identity.fingerprint,
        'firstSeenAt': h.firstSeenAt.toUtc().toIso8601String(),
        'lastSeenAt': h.lastSeenAt.toUtc().toIso8601String(),
        'revoked': h.revoked,
      };

  KnownHost _decode(Map<String, dynamic> row) => KnownHost(
        hostname: row['hostname'] as String,
        port: row['port'] as int,
        identity: HostIdentity(
            row['algorithm'] as String, row['fingerprint'] as String),
        firstSeenAt: DateTime.parse(row['firstSeenAt'] as String),
        lastSeenAt: DateTime.parse(row['lastSeenAt'] as String),
        revoked: row['revoked'] as bool,
      );
}
