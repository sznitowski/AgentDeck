import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';

import '../core/domain/agents.dart';
import '../core/domain/remote_contracts.dart';
import '../core/infrastructure/json_file_store.dart';
import '../features/agents/application/agent_coordinator.dart';
import '../features/agents/infrastructure/file_agent_instance_repository.dart';
import '../features/connections/application/ssh_connection_service.dart';
import '../features/connections/domain/ssh_models.dart';
import '../features/connections/infrastructure/dart_ssh_transport.dart';
import '../features/connections/infrastructure/file_known_host_repository.dart';
import '../features/connections/infrastructure/platform_secure_credential_store.dart';
import '../features/notifications/application/notification_coordinator.dart';
import '../features/notifications/domain/companion_cursor_repository.dart';
import '../features/notifications/domain/event_repository.dart';
import '../features/notifications/domain/remote_companion_client.dart';
import '../features/notifications/infrastructure/file_companion_cursor_repository.dart';
import '../features/notifications/infrastructure/file_event_repository.dart';
import '../features/notifications/infrastructure/ssh_companion_client.dart';
import '../features/projects/domain/project_profile_repository.dart';
import '../features/projects/infrastructure/file_project_profile_repository.dart';
import '../features/servers/domain/server_profile_repository.dart';
import '../features/servers/infrastructure/file_server_profile_repository.dart';
import '../features/tmux/domain/tmux_models.dart';
import '../features/tmux/infrastructure/file_tmux_session_repository.dart';

import '../core/domain/installation_identity.dart';
import '../core/infrastructure/file_installation_identity_repository.dart';
import '../features/notifications/domain/push_device_registration.dart';
import '../features/notifications/domain/push_notification_service.dart';
import '../features/notifications/domain/push_relay_client.dart';
import '../features/notifications/infrastructure/file_push_registration_repository.dart';
import '../features/notifications/infrastructure/http_push_relay_client.dart';
import '../features/notifications/infrastructure/push_notification_service_impl.dart';

class AgentDeckServices {
  AgentDeckServices._({
    required this.profiles,
    required this.projects,
    required this.credentials,
    required this.knownHosts,
    required this.tmuxReferences,
    required this.instances,
    required this.events,
    required this.notifications,
    required this.connection,
    required this.agents,
    required this.companionCursors,
    required this.companionClient,
    required this.installationIdentity,
    required this.pushRegistrations,
    required this.pushService,
    required this.pushRelayClient,
  });

  final ServerProfileRepository profiles;
  final ProjectProfileRepository projects;
  final SecureCredentialStore credentials;
  final KnownHostRepository knownHosts;
  final TmuxSessionRepository tmuxReferences;
  final AgentInstanceRepository instances;
  final EventRepository events;
  final NotificationCoordinator notifications;
  final SshConnectionService connection;
  final AgentCoordinator agents;
  final CompanionCursorRepository companionCursors;
  final RemoteCompanionClient companionClient;
  final InstallationIdentityRepository installationIdentity;
  final PushRegistrationRepository pushRegistrations;
  final PushNotificationService pushService;
  final PushRelayClient pushRelayClient;

  static Future<AgentDeckServices> bootstrap({
    Directory? directory,
    SecretValueBackend? secretBackend,
    SshTransport? transport,
    PushNotificationService? pushNotificationService,
    PushRelayClient? pushRelay,
  }) async {
    final root = directory ?? await getApplicationSupportDirectory();
    final profiles = FileServerProfileRepository(JsonFileStore(
        File('${root.path}${Platform.pathSeparator}agentdeck_profiles.json')));
    final projects = FileProjectProfileRepository(JsonFileStore(
        File('${root.path}${Platform.pathSeparator}agentdeck_projects.json')));
    final hosts = FileKnownHostRepository(JsonFileStore(File(
        '${root.path}${Platform.pathSeparator}agentdeck_known_hosts.json')));
    final tmuxReferences = FileTmuxSessionRepository(JsonFileStore(File(
        '${root.path}${Platform.pathSeparator}agentdeck_tmux_references.json')));
    final instances = FileAgentInstanceRepository(JsonFileStore(File(
        '${root.path}${Platform.pathSeparator}agentdeck_agent_instances.json')));
    final events = FileEventRepository(JsonFileStore(
        File('${root.path}${Platform.pathSeparator}agentdeck_events.json')));
    final companionCursors = FileCompanionCursorRepository(JsonFileStore(File(
        '${root.path}${Platform.pathSeparator}agentdeck_companion_cursors.json')));
    final installationIdentity = FileInstallationIdentityRepository(
        JsonFileStore(File(
            '${root.path}${Platform.pathSeparator}agentdeck_installation.json')));
    final pushRegistrations = FilePushRegistrationRepository(JsonFileStore(File(
        '${root.path}${Platform.pathSeparator}agentdeck_push_registration.json')));
    final credentials = PlatformSecureCredentialStore(secretBackend ??
        const FlutterSecureStorageBackend(FlutterSecureStorage(
          iOptions: IOSOptions(
            accessibility: KeychainAccessibility.unlocked_this_device,
            synchronizable: false,
          ),
        )));

    // Fail closed on corrupt/unsupported local data. Never silently reset trust.
    await profiles.all();
    await projects.all();
    await hosts.readCheck();
    await tmuxReferences.readCheck();
    await instances.readCheck();
    await events.readCheck();
    await companionCursors.getLastSequence('__check__');
    await installationIdentity.getIdentity();

    final connection = SshConnectionService(
      credentials: credentials,
      knownHosts: hosts,
      transport: transport ?? const DartSshTransport(),
    );

    final agents = AgentCoordinator(
      connection: connection,
      tmuxReferences: tmuxReferences,
      instanceRepository: instances,
    );

    final companionClient = SshCompanionClient(connection: connection);

    final notifications = NotificationCoordinator(
      repository: events,
      companionClient: companionClient,
      companionCursorRepository: companionCursors,
    );

    final pushService =
        pushNotificationService ?? FakePushNotificationService();
    final pushRelayClient = pushRelay ?? const HttpPushRelayClient();

    return AgentDeckServices._(
      profiles: profiles,
      projects: projects,
      credentials: credentials,
      knownHosts: hosts,
      tmuxReferences: tmuxReferences,
      instances: instances,
      events: events,
      notifications: notifications,
      connection: connection,
      agents: agents,
      companionCursors: companionCursors,
      companionClient: companionClient,
      installationIdentity: installationIdentity,
      pushRegistrations: pushRegistrations,
      pushService: pushService,
      pushRelayClient: pushRelayClient,
    );
  }

  Future<void> dispose() async {
    await notifications.dispose();
    await connection.dispose();
  }
}
