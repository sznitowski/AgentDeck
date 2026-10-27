import 'package:flutter_test/flutter_test.dart';

import 'package:agentdeck/core/domain/agents.dart';
import 'package:agentdeck/core/domain/git.dart';
import 'package:agentdeck/core/domain/profiles.dart';
import 'package:agentdeck/core/domain/server_operations.dart';
import 'package:agentdeck/core/domain/workspace.dart';
import 'package:agentdeck/features/agents/application/agent_coordinator.dart';
import 'package:agentdeck/features/connections/application/ssh_connection_service.dart';
import 'package:agentdeck/features/connections/domain/ssh_models.dart';
import 'package:agentdeck/features/files/application/remote_file_service.dart';
import 'package:agentdeck/features/files/domain/remote_file_models.dart';
import 'package:agentdeck/features/projects/application/project_workspace_coordinator.dart';
import 'package:agentdeck/features/servers/domain/server_profile_repository.dart';
import 'package:agentdeck/features/tmux/domain/tmux_models.dart';

// Fake implementations for testing
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
    bool isInstalled = true,
    bool isRepo = true,
    this.branch = 'main',
    this.headCommit = 'a1b2c3d4e5f6',
    this.changedFiles = const [],
    this.shouldThrow = false,
  })  : _isInstalled = isInstalled,
        _isRepo = isRepo;

  final bool _isInstalled;
  final bool _isRepo;
  final String branch;
  final String headCommit;
  final List<GitFileChange> changedFiles;
  final bool shouldThrow;

  @override
  Future<GitAvailability> checkAvailability() async {
    if (shouldThrow) throw Exception('SSH pipe broken');
    return GitAvailability(
        isInstalled: _isInstalled, version: '2.39.2', binaryPath: 'git');
  }

  @override
  Future<GitRepository> inspectRepository(String workingDirectory) async {
    if (shouldThrow) throw Exception('SSH pipe broken');
    return GitRepository(path: workingDirectory, isRepository: _isRepo);
  }

  @override
  Future<GitStatus> getStatus(String workingDirectory) async {
    if (shouldThrow) throw Exception('SSH pipe broken');
    return GitStatus(
      branch: branch,
      headCommit: headCommit,
      changedFiles: changedFiles,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeServerOperationsService implements ServerOperationsService {
  _FakeServerOperationsService({
    this.cpuPercent = 25.0,
    this.memPercent = 45.0,
    this.diskPercent = 55.0,
    this.load1m = 0.65,
    bool shouldThrow = false,
  }) : _shouldThrow = shouldThrow;

  final double cpuPercent;
  final double memPercent;
  final double diskPercent;
  final double load1m;
  final bool _shouldThrow;

  @override
  Future<ServerHealthSnapshot> getHealthSnapshot() async {
    if (_shouldThrow) throw Exception('procfs unreadable');
    return ServerHealthSnapshot(
      observedAt: DateTime.now().toUtc(),
      cpu: CpuUsage(
        totalPercent: cpuPercent,
        userPercent: cpuPercent * 0.7,
        systemPercent: cpuPercent * 0.3,
        idlePercent: 100.0 - cpuPercent,
      ),
      memory: MemoryUsage(
        totalBytes: 8000000000,
        availableBytes: (8000000000 * (1 - memPercent / 100)).round(),
        usedBytes: (8000000000 * (memPercent / 100)).round(),
        freeBytes: (8000000000 * (1 - memPercent / 100)).round(),
        cachedBytes: 1000000000,
        buffersBytes: 200000000,
        swapTotalBytes: 2000000000,
        swapUsedBytes: 0,
        swapFreeBytes: 2000000000,
      ),
      loadAvg1m: load1m,
      loadAvg5m: load1m,
      loadAvg15m: load1m,
      disks: [
        DiskUsage(
          filesystem: '/dev/sda1',
          mountPoint: '/',
          totalBytes: 100000000000,
          usedBytes: (100000000000 * (diskPercent / 100)).round(),
          availableBytes: (100000000000 * (1 - diskPercent / 100)).round(),
          usagePercent: diskPercent,
        ),
      ],
      processCount: 120,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeFileService extends RemoteFileService {
  _FakeFileService({
    required super.connection,
    required super.serverId,
    this.isDirectory = true,
    bool shouldThrow = false,
  }) : _shouldThrow = shouldThrow;

  final bool isDirectory;
  final bool _shouldThrow;

  @override
  Future<RemoteEntry> stat(String path, {bool followLinks = true}) async {
    if (_shouldThrow)
      throw Exception('Permission denied or path does not exist');
    return RemoteEntry(
      path: path,
      name: path.split('/').last,
      type: isDirectory ? RemoteEntryType.directory : RemoteEntryType.file,
      size: 4096,
      modifiedAt: DateTime.now().toUtc(),
    );
  }
}

class _FakeAgentInstanceRepository implements AgentInstanceRepository {
  _FakeAgentInstanceRepository(this.instances);
  final List<AgentInstance> instances;

  @override
  Future<List<AgentInstance>> all() async => instances;
  @override
  Future<List<AgentInstance>> forProject(
          String serverId, String projectId) async =>
      instances
          .where((i) => i.serverId == serverId && i.projectId == projectId)
          .toList();
  @override
  Future<List<AgentInstance>> forServer(String serverId) async =>
      instances.where((i) => i.serverId == serverId).toList();
  @override
  Future<AgentInstance?> find(String id) async => instances
      .cast<AgentInstance?>()
      .firstWhere((i) => i?.id == id, orElse: () => null);
  @override
  Future<void> put(AgentInstance instance) async {}
  @override
  Future<void> delete(String id) async {}
  @override
  Future<void> readCheck() async {}
}

class _FakeTmuxRepo implements TmuxSessionRepository {
  @override
  Future<List<TmuxSessionReference>> forServer(String serverId) async => [];
  @override
  Future<void> save(TmuxSessionReference reference) async {}
  @override
  Future<void> delete(String serverId, String remoteName) async {}
  @override
  Future<void> deleteServer(String serverId) async {}
  @override
  Future<void> readCheck() async {}
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

  late _FakeSshConnectionService connection;
  late _FakeServerProfileRepository servers;

  setUp(() {
    connection = _FakeSshConnectionService(
      state: ConnectionState.connected,
      connectedProfileId: 'srv-1',
    );
    servers = _FakeServerProfileRepository([server]);
  });

  group('ProjectWorkspaceCoordinator', () {
    test(
        'inspectWorkspace aggregates all connected subsystem summaries cleanly',
        () async {
      final git = _FakeGitService(
        branch: 'main',
        headCommit: 'e89d1234567',
        changedFiles: [
          const GitFileChange(
            path: 'lib/app.dart',
            indexStatus: GitFileStatus.modified,
            workTreeStatus: GitFileStatus.unmodified,
          ),
          const GitFileChange(
            path: 'README.md',
            indexStatus: GitFileStatus.unmodified,
            workTreeStatus: GitFileStatus.modified,
          ),
        ],
      );

      final serverOps = _FakeServerOperationsService(
        cpuPercent: 18.5,
        memPercent: 54.0,
        diskPercent: 63.0,
        load1m: 0.42,
      );

      final files = _FakeFileService(
        connection: connection,
        serverId: 'srv-1',
        isDirectory: true,
      );

      final coordinator = ProjectWorkspaceCoordinator(
        connection: connection,
        servers: servers,
        gitService: git,
        serverOpsService: serverOps,
        fileService: files,
      );

      final snapshot = await coordinator.inspectWorkspace(project);

      expect(snapshot.isConnected, isTrue);
      expect(snapshot.isProduction, isTrue);
      expect(snapshot.server?.name, 'UNIBER-FENIX');

      // Git summary
      expect(snapshot.git, isNotNull);
      expect(snapshot.git!.branch, 'main');
      expect(snapshot.git!.shortHead, 'e89d123');
      expect(snapshot.git!.stagedCount, 1);
      expect(snapshot.git!.unstagedCount, 1);
      expect(snapshot.git!.totalChanged, 2);
      expect(snapshot.git!.isClean, isFalse);

      // Server health summary
      expect(snapshot.serverHealth, isNotNull);
      expect(snapshot.serverHealth!.cpuPercent, 18.5);
      expect(snapshot.serverHealth!.memoryPercent, 54.0);
      expect(snapshot.serverHealth!.diskPercent, 63.0);
      expect(snapshot.serverHealth!.isHealthy, isTrue);

      // Files summary
      expect(snapshot.files, isNotNull);
      expect(
          snapshot.files!.workingDirectory, '/var/docker/portal-proveedores');
      expect(snapshot.files!.exists, isTrue);

      // Informational attention item for dirty git
      expect(snapshot.attentionItems.length, 1);
      expect(snapshot.attentionItems.first.type, AttentionType.gitDirty);
      expect(snapshot.attentionItems.first.severity, AttentionSeverity.info);
    });

    test(
        'Attention priority: agent waiting user supersedes git and server issues',
        () async {
      final git = _FakeGitService(
        branch: 'feat/orders',
        changedFiles: [
          const GitFileChange(
            path: 'order.go',
            indexStatus: GitFileStatus.conflict,
            workTreeStatus: GitFileStatus.conflict,
          ),
        ],
      );

      final serverOps = _FakeServerOperationsService(
        cpuPercent: 95.0, // High server pressure
      );

      final files = _FakeFileService(
        connection: connection,
        serverId: 'srv-1',
      );

      final instanceRepo = _FakeAgentInstanceRepository([
        AgentInstance(
          id: 'ad_agent_codex_proj-1_1234',
          providerId: 'codex',
          serverId: 'srv-1',
          projectId: 'proj-1',
          tmuxSessionName: 'ad_agent_codex_proj-1_1234',
          workingDirectory: '/var/docker/portal-proveedores',
          executionState: AgentExecutionState.waitingUser,
          observation: AgentObservation(
            state: AgentExecutionState.waitingUser,
            confidence: ObservationConfidence.inferred,
            source: ObservationSource.terminalPattern,
            observedAt: DateTime.now().toUtc(),
            detail: 'Confirmation needed [y/N]',
          ),
          startedAt: DateTime.now().toUtc(),
          lastObservedAt: DateTime.now().toUtc(),
        ),
      ]);

      final agentCoordinator = AgentCoordinator(
        connection: connection,
        tmuxReferences: _FakeTmuxRepo(),
        instanceRepository: instanceRepo,
      );

      final coordinator = ProjectWorkspaceCoordinator(
        connection: connection,
        servers: servers,
        agents: agentCoordinator,
        gitService: git,
        serverOpsService: serverOps,
        fileService: files,
      );

      final snapshot = await coordinator.inspectWorkspace(project);

      expect(snapshot.agent, isNotNull);
      expect(snapshot.agent!.isWaitingUser, isTrue);
      expect(snapshot.agent!.confidence, ObservationConfidence.inferred);
      expect(snapshot.tmux?.sessionName, 'ad_agent_codex_proj-1_1234');

      // Attention ordering: 1) Agent waiting, 2) Git conflict, 3) Server pressure
      expect(snapshot.attentionItems.length, 3);
      expect(snapshot.attentionItems[0].type, AttentionType.agentWaiting);
      expect(snapshot.attentionItems[0].severity,
          AttentionSeverity.actionRequired);
      expect(snapshot.attentionItems[0].actionLabel, 'Respond');

      expect(snapshot.attentionItems[1].type, AttentionType.gitConflict);
      expect(snapshot.attentionItems[1].severity, AttentionSeverity.critical);

      expect(snapshot.attentionItems[2].type, AttentionType.serverCritical);
      expect(snapshot.attentionItems[2].severity, AttentionSeverity.warning);
    });

    test('Partial failure: Git exception does not crash workspace snapshot',
        () async {
      final git = _FakeGitService(shouldThrow: true);
      final serverOps = _FakeServerOperationsService(cpuPercent: 20.0);
      final files = _FakeFileService(connection: connection, serverId: 'srv-1');

      final coordinator = ProjectWorkspaceCoordinator(
        connection: connection,
        servers: servers,
        gitService: git,
        serverOpsService: serverOps,
        fileService: files,
      );

      final snapshot = await coordinator.inspectWorkspace(project);

      // Git failed gracefully
      expect(snapshot.git, isNotNull);
      expect(snapshot.git!.error, contains('SSH pipe broken'));

      // Server and Files succeeded
      expect(snapshot.serverHealth, isNotNull);
      expect(snapshot.serverHealth!.isHealthy, isTrue);
      expect(snapshot.files?.exists, isTrue);
    });

    test(
        'Disconnected mode returns cached state with stale timestamps and connection attention',
        () async {
      final git = _FakeGitService(branch: 'main', headCommit: '11223344');
      final serverOps = _FakeServerOperationsService(cpuPercent: 15.0);
      final files = _FakeFileService(connection: connection, serverId: 'srv-1');

      final coordinator = ProjectWorkspaceCoordinator(
        connection: connection,
        servers: servers,
        gitService: git,
        serverOpsService: serverOps,
        fileService: files,
      );

      // 1. Initial connected inspection
      final connectedSnapshot = await coordinator.inspectWorkspace(project);
      expect(connectedSnapshot.isConnected, isTrue);

      // 2. Disconnect SSH
      connection.state = ConnectionState.disconnected;
      connection.connectedProfileId = null;

      // 3. Inspect again in disconnected state
      final disconnectedSnapshot = await coordinator.inspectWorkspace(project);

      expect(disconnectedSnapshot.isConnected, isFalse);
      expect(
          disconnectedSnapshot.connectionState, ConnectionState.disconnected);

      // Retained cached Git & Server summaries
      expect(disconnectedSnapshot.git?.branch, 'main');
      expect(disconnectedSnapshot.serverHealth?.cpuPercent, 15.0);

      // Critical connectionLost item for production project
      expect(
          disconnectedSnapshot.attentionItems
              .any((a) => a.type == AttentionType.connectionLost),
          isTrue);
      expect(
        disconnectedSnapshot.attentionItems
            .firstWhere((a) => a.type == AttentionType.connectionLost)
            .severity,
        AttentionSeverity.critical,
      );
    });
  });
}
