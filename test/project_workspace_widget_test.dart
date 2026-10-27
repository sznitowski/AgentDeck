import 'package:flutter/material.dart' hide ConnectionState;
import 'package:flutter_test/flutter_test.dart';

import 'package:agentdeck/core/domain/agents.dart';
import 'package:agentdeck/core/domain/git.dart';
import 'package:agentdeck/core/domain/profiles.dart';
import 'package:agentdeck/core/domain/server_operations.dart';
import 'package:agentdeck/features/connections/application/ssh_connection_service.dart';
import 'package:agentdeck/features/connections/domain/ssh_models.dart';
import 'package:agentdeck/features/files/application/remote_file_service.dart';
import 'package:agentdeck/features/files/domain/remote_file_models.dart';
import 'package:agentdeck/features/git/presentation/git_changes_page.dart';
import 'package:agentdeck/features/projects/application/project_workspace_coordinator.dart';
import 'package:agentdeck/features/projects/presentation/project_workspace_page.dart';
import 'package:agentdeck/features/projects/presentation/workspace_agent_card.dart';
import 'package:agentdeck/features/projects/presentation/workspace_attention_banner.dart';
import 'package:agentdeck/features/projects/presentation/workspace_git_card.dart';
import 'package:agentdeck/features/projects/presentation/workspace_quick_actions.dart';
import 'package:agentdeck/features/projects/presentation/workspace_server_card.dart';
import 'package:agentdeck/features/servers/domain/server_profile_repository.dart';
import 'package:agentdeck/features/servers/presentation/server_operations_page.dart';

class _FakeServerProfileRepository implements ServerProfileRepository {
  _FakeServerProfileRepository(this.profiles);
  final List<ServerProfile> profiles;

  @override
  Future<List<ServerProfile>> all() async => profiles;
  @override
  Future<ServerProfile?> find(String id) async => profiles
      .cast<ServerProfile?>()
      .firstWhere((p) => p?.id == id, orElse: () => null);
  @override
  Future<void> save(ServerProfile profile) async {}
  @override
  Future<void> delete(String id) async {}
  Future<void> readCheck() async {}
}

class _FakeSshConnectionService implements SshConnectionService {
  _FakeSshConnectionService({
    this.state = ConnectionState.connected,
    this.connectedProfileId = 'srv-1',
  });

  @override
  ConnectionState state;

  @override
  String? connectedProfileId;

  @override
  Stream<ConnectionState> get states => Stream.value(state);

  @override
  Future<void> connect(ServerProfile profile, {HostApproval? approve}) async {
    state = ConnectionState.connected;
    connectedProfileId = profile.id;
  }

  @override
  Future<void> disconnect() async {
    state = ConnectionState.disconnected;
    connectedProfileId = null;
  }

  @override
  Future<RemoteCommandResult> runRemoteCommand(List<String> command,
          {Duration? timeout}) async =>
      const RemoteCommandResult(0, '', '');

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeGitService implements GitService {
  _FakeGitService({
    String branch = 'main',
    String headCommit = 'e89d1234567',
    this.isClean = false,
    bool isRepo = true,
    bool isInstalled = true,
    String? error,
  })  : _branch = branch,
        _headCommit = headCommit,
        _isRepo = isRepo,
        _isInstalled = isInstalled,
        _error = error;

  final String _branch;
  final String _headCommit;
  final bool isClean;
  final bool _isRepo;
  final bool _isInstalled;
  final String? _error;

  @override
  Future<GitAvailability> checkAvailability() async {
    if (_error != null) throw Exception(_error);
    return GitAvailability(
        isInstalled: _isInstalled, version: '2.39.2', binaryPath: 'git');
  }

  @override
  Future<GitRepository> inspectRepository(String workingDirectory) async {
    if (_error != null) throw Exception(_error);
    return GitRepository(path: workingDirectory, isRepository: _isRepo);
  }

  @override
  Future<GitStatus> getStatus(String workingDirectory) async {
    if (_error != null) throw Exception(_error);
    return GitStatus(
      branch: _branch,
      headCommit: _headCommit,
      changedFiles: isClean
          ? []
          : [
              const GitFileChange(
                path: 'app.go',
                indexStatus: GitFileStatus.modified,
                workTreeStatus: GitFileStatus.unmodified,
              ),
              const GitFileChange(
                path: 'main.go',
                indexStatus: GitFileStatus.unmodified,
                workTreeStatus: GitFileStatus.modified,
              ),
            ],
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeServerOpsService implements ServerOperationsService {
  _FakeServerOpsService({
    double cpuPercent = 18.5,
    double memPercent = 54.0,
    double diskPercent = 63.0,
    double load1m = 0.42,
  })  : _cpuPercent = cpuPercent,
        _memPercent = memPercent,
        _diskPercent = diskPercent,
        _load1m = load1m;

  final double _cpuPercent;
  final double _memPercent;
  final double _diskPercent;
  final double _load1m;

  @override
  Future<ServerHealthSnapshot> getHealthSnapshot() async {
    return ServerHealthSnapshot(
      observedAt: DateTime.now().toUtc(),
      cpu: CpuUsage(
        totalPercent: _cpuPercent,
        userPercent: _cpuPercent * 0.7,
        systemPercent: _cpuPercent * 0.3,
        idlePercent: 100.0 - _cpuPercent,
      ),
      memory: MemoryUsage(
        totalBytes: 8000000000,
        availableBytes: (8000000000 * (1 - _memPercent / 100)).round(),
        usedBytes: (8000000000 * (_memPercent / 100)).round(),
        freeBytes: (8000000000 * (1 - _memPercent / 100)).round(),
        cachedBytes: 1000000000,
        buffersBytes: 200000000,
        swapTotalBytes: 2000000000,
        swapUsedBytes: 0,
        swapFreeBytes: 2000000000,
      ),
      loadAvg1m: _load1m,
      loadAvg5m: _load1m,
      loadAvg15m: _load1m,
      disks: [
        DiskUsage(
          filesystem: '/dev/sda1',
          mountPoint: '/',
          totalBytes: 100000000000,
          usedBytes: (100000000000 * (_diskPercent / 100)).round(),
          availableBytes: (100000000000 * (1 - _diskPercent / 100)).round(),
          usagePercent: _diskPercent,
        ),
      ],
      processCount: 110,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeRemoteFileService extends RemoteFileService {
  _FakeRemoteFileService({required super.connection, required super.serverId});

  @override
  Future<RemoteEntry> stat(String path, {bool followLinks = true}) async {
    return RemoteEntry(
      path: path,
      name: path.split('/').last,
      type: RemoteEntryType.directory,
      size: 4096,
      modifiedAt: DateTime.now().toUtc(),
    );
  }
}

void main() {
  final server = const ServerProfile(
    id: 'srv-1',
    name: 'UNIBER-FENIX',
    host: '10.0.0.1',
    port: 22,
    username: 'deploy',
    credentialId: 'cred-1',
  );

  final project = const ProjectProfile(
    id: 'proj-1',
    name: 'Portal Proveedores',
    serverId: 'srv-1',
    workingDirectory: '/var/docker/portal-proveedores',
    environment: Environment.production,
    executionPolicy: ExecutionPolicy(environment: Environment.production),
  );

  Widget buildTestApp({
    required ProjectProfile project,
    required ProjectWorkspaceCoordinator coordinator,
    SshConnectionService? connection,
    GitService? gitService,
    ServerOperationsService? serverOpsService,
    RemoteFileService? fileService,
  }) {
    return MaterialApp(
      theme: ThemeData.dark(),
      home: ProjectWorkspacePage(
        project: project,
        coordinator: coordinator,
        connection: connection,
        serverProfiles: _FakeServerProfileRepository([server]),
        gitService: gitService,
        serverOpsService: serverOpsService,
        fileService: fileService,
      ),
    );
  }

  group('ProjectWorkspacePage Widget Tests', () {
    testWidgets('renders all control center modules cleanly when connected',
        (tester) async {
      tester.view.physicalSize = const Size(1200, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final connection = _FakeSshConnectionService();
      final servers = _FakeServerProfileRepository([server]);
      final git = _FakeGitService();
      final serverOps = _FakeServerOpsService();
      final files =
          _FakeRemoteFileService(connection: connection, serverId: 'srv-1');

      final coordinator = ProjectWorkspaceCoordinator(
        connection: connection,
        servers: servers,
        gitService: git,
        serverOpsService: serverOps,
        fileService: files,
      );

      await tester.pumpWidget(buildTestApp(
        project: project,
        coordinator: coordinator,
        connection: connection,
        gitService: git,
        serverOpsService: serverOps,
        fileService: files,
      ));

      await tester.pumpAndSettle();

      // Header: Project title and PRODUCTION tag
      expect(find.text('Portal Proveedores'), findsOneWidget);
      expect(find.text('PRODUCTION ENVIRONMENT'), findsOneWidget);

      // Connection banner
      expect(find.text('CONNECTED'), findsOneWidget);
      expect(find.textContaining('UNIBER-FENIX (10.0.0.1)'), findsOneWidget);

      // Quick action buttons
      expect(find.byType(WorkspaceQuickActions), findsOneWidget);
      expect(find.text('Terminal'), findsOneWidget);
      expect(find.text('Files'), findsOneWidget);
      expect(find.text('Git'), findsOneWidget);
      expect(find.text('Server'), findsOneWidget);

      // Agent Card
      expect(find.byType(WorkspaceAgentCard), findsOneWidget);
      expect(find.text('Agent Orchestration'), findsOneWidget);
      expect(find.text('No active background agent running for this project.'),
          findsOneWidget);

      // Git Card
      expect(find.byType(WorkspaceGitCard), findsOneWidget);
      expect(find.text('Git Repository'), findsOneWidget);
      expect(find.text('main'), findsOneWidget);
      expect(find.text('e89d123'), findsOneWidget);
      expect(find.text('1 staged'), findsOneWidget);
      expect(find.text('1 unstaged'), findsOneWidget);
      expect(find.text('View Changes (2)'), findsOneWidget);

      // Server Health Card
      expect(find.byType(WorkspaceServerCard), findsOneWidget);
      expect(find.text('Server Health'), findsWidgets);
      expect(find.text('18.5%'), findsOneWidget); // CPU
      expect(find.text('54.0%'), findsOneWidget); // RAM
      expect(find.text('63.0%'), findsOneWidget); // Disk
      expect(find.text('HEALTHY'), findsOneWidget);

      // Working Directory Card
      expect(find.text('Working Directory'), findsOneWidget);
      expect(find.text('/var/docker/portal-proveedores'), findsOneWidget);
      expect(find.text('VERIFIED'), findsOneWidget);
      expect(find.text('Browse Files'), findsOneWidget);
    });

    testWidgets('renders clean Git state and clean badge', (tester) async {
      tester.view.physicalSize = const Size(1200, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final connection = _FakeSshConnectionService();
      final servers = _FakeServerProfileRepository([server]);
      final git = _FakeGitService(isClean: true);
      final serverOps = _FakeServerOpsService();
      final files =
          _FakeRemoteFileService(connection: connection, serverId: 'srv-1');

      final coordinator = ProjectWorkspaceCoordinator(
        connection: connection,
        servers: servers,
        gitService: git,
        serverOpsService: serverOps,
        fileService: files,
      );

      await tester.pumpWidget(buildTestApp(
        project: project,
        coordinator: coordinator,
        connection: connection,
        gitService: git,
        serverOpsService: serverOps,
        fileService: files,
      ));

      await tester.pumpAndSettle();

      expect(find.text('CLEAN'), findsOneWidget);
      expect(find.text('Working tree clean'), findsOneWidget);
      expect(find.text('View Changes (0)'), findsNothing);
    });

    testWidgets(
        'renders disconnected mode with attention banner and connect CTA',
        (tester) async {
      tester.view.physicalSize = const Size(1200, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final connection = _FakeSshConnectionService(
        state: ConnectionState.disconnected,
        connectedProfileId: null,
      );
      final servers = _FakeServerProfileRepository([server]);

      final coordinator = ProjectWorkspaceCoordinator(
        connection: connection,
        servers: servers,
      );

      await tester.pumpWidget(buildTestApp(
        project: project,
        coordinator: coordinator,
        connection: connection,
      ));

      await tester.pumpAndSettle();

      expect(find.text('DISCONNECTED'), findsOneWidget);
      expect(find.text('Connect'), findsWidgets);
      expect(find.byType(WorkspaceAttentionBanner), findsOneWidget);
      expect(find.text('SSH Disconnected'), findsOneWidget);
    });

    testWidgets('navigates to GitChangesPage when View Changes is tapped',
        (tester) async {
      tester.view.physicalSize = const Size(1200, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final connection = _FakeSshConnectionService();
      final servers = _FakeServerProfileRepository([server]);
      final git = _FakeGitService();
      final serverOps = _FakeServerOpsService();
      final files =
          _FakeRemoteFileService(connection: connection, serverId: 'srv-1');

      final coordinator = ProjectWorkspaceCoordinator(
        connection: connection,
        servers: servers,
        gitService: git,
        serverOpsService: serverOps,
        fileService: files,
      );

      await tester.pumpWidget(buildTestApp(
        project: project,
        coordinator: coordinator,
        connection: connection,
        gitService: git,
        serverOpsService: serverOps,
        fileService: files,
      ));

      await tester.pumpAndSettle();

      final viewChangesBtn = find.text('View Changes (2)');
      expect(viewChangesBtn, findsOneWidget);

      await tester.tap(viewChangesBtn);
      await tester.pumpAndSettle();

      expect(find.byType(GitChangesPage), findsOneWidget);
    });

    testWidgets(
        'navigates to ServerOperationsPage when Server Health is tapped',
        (tester) async {
      tester.view.physicalSize = const Size(1200, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final connection = _FakeSshConnectionService();
      final servers = _FakeServerProfileRepository([server]);
      final git = _FakeGitService(isClean: true);
      final serverOps = _FakeServerOpsService();
      final files =
          _FakeRemoteFileService(connection: connection, serverId: 'srv-1');

      final coordinator = ProjectWorkspaceCoordinator(
        connection: connection,
        servers: servers,
        gitService: git,
        serverOpsService: serverOps,
        fileService: files,
      );

      await tester.pumpWidget(buildTestApp(
        project: project,
        coordinator: coordinator,
        connection: connection,
        gitService: git,
        serverOpsService: serverOps,
        fileService: files,
      ));

      await tester.pumpAndSettle();

      // Tap on Server Health button inside WorkspaceServerCard
      final serverHealthBtn =
          find.widgetWithText(OutlinedButton, 'Server Health');
      expect(serverHealthBtn, findsOneWidget);

      await tester.tap(serverHealthBtn);
      await tester.pumpAndSettle();

      expect(find.byType(ServerOperationsPage), findsOneWidget);
    });
  });
}
