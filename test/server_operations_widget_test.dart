import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:agentdeck/core/domain/profiles.dart';
import 'package:agentdeck/core/domain/server_operations.dart';
import 'package:agentdeck/features/servers/presentation/server_operations_page.dart';
import 'package:agentdeck/features/servers/presentation/server_processes_tab.dart';
import 'package:agentdeck/features/servers/presentation/server_services_tab.dart';

class _FakeOperationsService implements ServerOperationsService {
  ServerCapabilities capabilities = const ServerCapabilities(
    isLinux: true,
    hasProcfs: true,
    hasSystemd: true,
  );

  ServerInfo info = ServerInfo(
    hostname: 'prod-api-01',
    osName: 'Ubuntu',
    osVersion: '22.04 LTS',
    kernel: 'Linux 5.15.0-generic',
    architecture: 'x86_64',
    uptimeSeconds: 86400 * 5, // 5 days
    bootTime: DateTime.now().subtract(const Duration(days: 5)),
  );

  ServerHealthSnapshot snapshot = ServerHealthSnapshot(
    observedAt: DateTime.now(),
    loadAvg1m: 0.75,
    loadAvg5m: 0.90,
    loadAvg15m: 1.10,
    cpu: const CpuUsage(totalPercent: 25.5),
    memory: const MemoryUsage(
      totalBytes: 16 * 1024 * 1024 * 1024,
      availableBytes: 8 * 1024 * 1024 * 1024,
      usedBytes: 8 * 1024 * 1024 * 1024,
      freeBytes: 4 * 1024 * 1024 * 1024,
      cachedBytes: 4 * 1024 * 1024 * 1024,
      buffersBytes: 500 * 1024 * 1024,
      swapTotalBytes: 4 * 1024 * 1024 * 1024,
      swapUsedBytes: 1 * 1024 * 1024 * 1024,
      swapFreeBytes: 3 * 1024 * 1024 * 1024,
    ),
    disks: const [
      DiskUsage(
        filesystem: '/dev/sda1',
        mountPoint: '/',
        totalBytes: 100 * 1024 * 1024 * 1024,
        usedBytes: 45 * 1024 * 1024 * 1024,
        availableBytes: 55 * 1024 * 1024 * 1024,
        usagePercent: 45.0,
      ),
    ],
    processCount: 180,
    runningServicesCount: 42,
    failedServicesCount: 1,
  );

  List<RemoteProcess> processes = const [
    RemoteProcess(
      pid: 1,
      user: 'root',
      command: 'systemd',
      cpuPercent: 0.1,
      memoryPercent: 0.2,
      state: ProcessState.sleeping,
    ),
    RemoteProcess(
      pid: 540,
      user: 'deploy',
      command: 'node',
      cpuPercent: 18.5,
      memoryPercent: 6.2,
      state: ProcessState.running,
    ),
  ];

  List<SystemService> services = const [
    SystemService(
      name: 'nginx.service',
      description: 'Nginx Web Server',
      loadState: 'loaded',
      activeState: ServiceActiveState.active,
      subState: 'running',
    ),
    SystemService(
      name: 'broken.service',
      description: 'Failed Job Daemon',
      loadState: 'loaded',
      activeState: ServiceActiveState.failed,
      subState: 'failed',
    ),
  ];

  final List<String> started = [];
  final List<String> stopped = [];
  final List<String> restarted = [];

  @override
  Future<ServerCapabilities> discoverCapabilities() async => capabilities;

  @override
  Future<ServerInfo> getHostInfo() async => info;

  @override
  Future<ServerHealthSnapshot> getHealthSnapshot() async => snapshot;

  @override
  Future<List<RemoteProcess>> getProcesses(
          {String? sortField, bool descending = true}) async =>
      processes;

  @override
  Future<List<SystemService>> getServices() async => services;

  @override
  Future<SystemService> getServiceDetail(String serviceName) async =>
      services.firstWhere((s) => s.name == serviceName);

  @override
  Future<void> startService(String serviceName) async =>
      started.add(serviceName);

  @override
  Future<void> stopService(String serviceName) async =>
      stopped.add(serviceName);

  @override
  Future<void> restartService(String serviceName) async =>
      restarted.add(serviceName);
}

void main() {
  final testServer = const ServerProfile(
    id: 'server-1',
    name: 'UNIBER-FENIX',
    host: '192.168.1.10',
    username: 'admin',
    port: 22,
    authenticationMethod: SshAuthenticationMethod.password,
    environment: Environment.production,
    credentialId: 'cred-1',
  );

  testWidgets(
      'ServerOperationsPage renders Overview, metrics, and PRODUCTION badge',
      (tester) async {
    final fakeService = _FakeOperationsService();

    await tester.pumpWidget(MaterialApp(
      home: ServerOperationsPage(
        server: testServer,
        service: fakeService,
      ),
    ));

    await tester.pumpAndSettle();

    expect(find.text('Server Ops — UNIBER-FENIX'), findsOneWidget);
    expect(find.text('PRODUCTION'), findsOneWidget);
    expect(find.text('CPU Usage'), findsOneWidget);
    expect(find.text('25.5%'), findsOneWidget);
    expect(find.text('Memory'), findsOneWidget);
    expect(find.text('50.0%'), findsOneWidget);
    expect(find.text('Load Average'), findsOneWidget);
    expect(find.text('Filesystem & Disks'), findsOneWidget);

    await tester.drag(find.byType(ListView), const Offset(0, -400));
    await tester.pumpAndSettle();
    expect(find.text('prod-api-01'), findsOneWidget);
  });

  testWidgets(
      'ServerProcessesTab renders process list, privacy banner, and search filter',
      (tester) async {
    final fakeService = _FakeOperationsService();

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ServerProcessesTab(
          processes: fakeService.processes,
          onRefresh: () async {},
        ),
      ),
    ));

    await tester.pumpAndSettle();

    expect(find.textContaining('Command arguments are masked'), findsOneWidget);
    expect(find.widgetWithText(ListTile, 'node'), findsOneWidget);
    expect(find.widgetWithText(ListTile, 'systemd'), findsOneWidget);
    expect(find.text('CPU 18.5%'), findsOneWidget);

    // Search filter
    await tester.enterText(find.byType(TextField), 'node');
    await tester.pumpAndSettle();

    expect(find.widgetWithText(ListTile, 'node'), findsOneWidget);
    expect(find.widgetWithText(ListTile, 'systemd'), findsNothing);
  });

  testWidgets(
      'ServerServicesTab renders services, details sheet, and confirmation modal',
      (tester) async {
    final fakeService = _FakeOperationsService();

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ServerServicesTab(
          server: testServer,
          capabilities: fakeService.capabilities,
          services: fakeService.services,
          serviceOperations: fakeService,
          onRefresh: () async {},
        ),
      ),
    ));

    await tester.pumpAndSettle();

    expect(find.text('nginx.service'), findsOneWidget);
    expect(find.text('broken.service'), findsOneWidget);
    expect(find.text('Active (1)'), findsOneWidget);
    expect(find.text('Failed (1)'), findsOneWidget);

    // Tap service to open details
    await tester.tap(find.text('nginx.service'));
    await tester.pumpAndSettle();

    expect(find.text('Service Actions'), findsOneWidget);
    expect(find.text('Restart'), findsOneWidget);

    // Tap restart to open confirmation dialog
    await tester.tap(find.text('Restart'));
    await tester.pumpAndSettle();

    expect(find.text('RESTART Service?'), findsOneWidget);
    expect(find.textContaining('PRODUCTION SERVER:'), findsOneWidget);

    // Confirm restart
    await tester.tap(find.text('Confirm RESTART'));
    await tester.pumpAndSettle();

    expect(fakeService.restarted, contains('nginx.service'));
  });

  testWidgets('ServerServicesTab shows informative card on non-systemd hosts',
      (tester) async {
    final fakeService = _FakeOperationsService();
    const alpineCaps = ServerCapabilities(
      isLinux: true,
      hasProcfs: true,
      hasSystemd: false,
      isAlpine: true,
    );

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ServerServicesTab(
          server: testServer,
          capabilities: alpineCaps,
          services: const [],
          serviceOperations: fakeService,
          onRefresh: () async {},
        ),
      ),
    ));

    await tester.pumpAndSettle();

    expect(find.text('Systemd Not Available'), findsOneWidget);
    expect(find.textContaining('Alpine Linux with OpenRC'), findsOneWidget);
  });
}
