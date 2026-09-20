import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';

import '../core/domain/remote_contracts.dart';
import '../core/infrastructure/json_file_store.dart';
import '../features/connections/application/ssh_connection_service.dart';
import '../features/connections/domain/ssh_models.dart';
import '../features/connections/infrastructure/dart_ssh_transport.dart';
import '../features/connections/infrastructure/file_known_host_repository.dart';
import '../features/connections/infrastructure/platform_secure_credential_store.dart';
import '../features/servers/domain/server_profile_repository.dart';
import '../features/servers/infrastructure/file_server_profile_repository.dart';

class AgentDeckServices {
  AgentDeckServices._(
      this.profiles, this.credentials, this.knownHosts, this.connection);

  final ServerProfileRepository profiles;
  final SecureCredentialStore credentials;
  final KnownHostRepository knownHosts;
  final SshConnectionService connection;

  static Future<AgentDeckServices> bootstrap({
    Directory? directory,
    SecretValueBackend? secretBackend,
    SshTransport? transport,
  }) async {
    final root = directory ?? await getApplicationSupportDirectory();
    final profiles = FileServerProfileRepository(JsonFileStore(
        File('${root.path}${Platform.pathSeparator}agentdeck_profiles.json')));
    final hosts = FileKnownHostRepository(JsonFileStore(File(
        '${root.path}${Platform.pathSeparator}agentdeck_known_hosts.json')));
    final credentials = PlatformSecureCredentialStore(secretBackend ??
        const FlutterSecureStorageBackend(FlutterSecureStorage(
          iOptions: IOSOptions(
            accessibility: KeychainAccessibility.unlocked_this_device,
            synchronizable: false,
          ),
        )));
    // Fail closed on corrupt/unsupported local data. Never silently reset trust.
    await profiles.all();
    await hosts.readCheck();
    final connection = SshConnectionService(
      credentials: credentials,
      knownHosts: hosts,
      transport: transport ?? const DartSshTransport(),
    );
    return AgentDeckServices._(profiles, credentials, hosts, connection);
  }

  Future<void> dispose() => connection.dispose();
}
