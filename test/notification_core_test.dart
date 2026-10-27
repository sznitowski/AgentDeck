import 'dart:io';

import 'package:agentdeck/core/domain/agents.dart';
import 'package:agentdeck/core/domain/events.dart';
import 'package:agentdeck/core/domain/profiles.dart';
import 'package:agentdeck/core/domain/workspace.dart';
import 'package:agentdeck/core/infrastructure/json_file_store.dart';
import 'package:agentdeck/features/notifications/application/app_lifecycle_coordinator.dart';
import 'package:agentdeck/features/notifications/application/event_deduplicator.dart';
import 'package:agentdeck/features/notifications/application/notification_coordinator.dart';
import 'package:agentdeck/features/notifications/application/notification_delivery_service.dart';
import 'package:agentdeck/features/notifications/application/state_transition_detector.dart';
import 'package:agentdeck/features/notifications/domain/notification_policy.dart';
import 'package:agentdeck/features/notifications/infrastructure/file_event_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('StateTransitionDetector Tests', () {
    late StateTransitionDetector detector;

    setUp(() {
      detector = StateTransitionDetector(
        disconnectDebounce: const Duration(seconds: 2),
      );
    });

    const testProject = ProjectProfile(
      id: 'p1',
      name: 'Portal Proveedores',
      serverId: 's1',
      workingDirectory: '/var/www/portal',
      environment: Environment.production,
      executionPolicy: ExecutionPolicy(environment: Environment.production),
    );

    const testServer = ServerProfile(
      id: 's1',
      name: 'prod-app-01',
      host: '192.168.1.10',
      port: 22,
      username: 'deploy',
      credentialId: 'c1',
    );

    test(
        'Agent: running -> waitingUser emits 1 event; repeated waitingUser emits 0',
        () {
      final t0 = DateTime(2026, 9, 20, 10, 0, 0);

      // Snapshot 1: Agent running
      final snapRunning = ProjectWorkspaceSnapshot(
        project: testProject,
        server: testServer,
        connectionState: ConnectionState.connected,
        observedAt: t0,
        agent: const WorkspaceAgentSummary(
          instanceId: 'inst-1',
          providerName: 'Codex',
          state: AgentExecutionState.running,
          isRunning: true,
        ),
      );

      final events1 = detector.evaluateWorkspaceSnapshot(snapRunning, now: t0);
      expect(events1, isEmpty);

      // Snapshot 2: Agent transitions to waitingUser
      final t1 = t0.add(const Duration(seconds: 5));
      final snapWaiting = ProjectWorkspaceSnapshot(
        project: testProject,
        server: testServer,
        connectionState: ConnectionState.connected,
        observedAt: t1,
        agent: const WorkspaceAgentSummary(
          instanceId: 'inst-1',
          providerName: 'Codex',
          state: AgentExecutionState.waitingUser,
          isWaitingUser: true,
        ),
      );

      final events2 = detector.evaluateWorkspaceSnapshot(snapWaiting, now: t1);
      expect(events2.length, 1);
      expect(events2.first.type, EventType.agentWaitingUser);
      expect(events2.first.severity, EventSeverity.actionRequired);
      expect(events2.first.actionLabel, 'Respond');

      // Snapshot 3: Agent remains waitingUser (no transition)
      final t2 = t1.add(const Duration(seconds: 5));
      final events3 = detector.evaluateWorkspaceSnapshot(snapWaiting, now: t2);
      expect(events3, isEmpty,
          reason: 'Consecutive waitingUser polls must emit zero events');
    });

    test(
        'Agent: running -> failed emits critical event; running -> finished emits info',
        () {
      final t0 = DateTime(2026, 9, 20, 10, 0, 0);

      final snapRunning = ProjectWorkspaceSnapshot(
        project: testProject,
        server: testServer,
        connectionState: ConnectionState.connected,
        observedAt: t0,
        agent: const WorkspaceAgentSummary(
          instanceId: 'inst-1',
          providerName: 'Claude',
          state: AgentExecutionState.running,
          isRunning: true,
        ),
      );
      detector.evaluateWorkspaceSnapshot(snapRunning, now: t0);

      final t1 = t0.add(const Duration(seconds: 5));
      final snapFailed = ProjectWorkspaceSnapshot(
        project: testProject,
        server: testServer,
        connectionState: ConnectionState.connected,
        observedAt: t1,
        agent: const WorkspaceAgentSummary(
          instanceId: 'inst-1',
          providerName: 'Claude',
          state: AgentExecutionState.failed,
          isFailed: true,
        ),
      );

      final eventsFail =
          detector.evaluateWorkspaceSnapshot(snapFailed, now: t1);
      expect(eventsFail.length, 1);
      expect(eventsFail.first.type, EventType.agentFailed);
      expect(eventsFail.first.severity, EventSeverity.critical);
      expect(eventsFail.first.actionLabel, 'Inspect');
    });

    test(
        'Git: 0 -> 2 conflicts emits detected; 2 -> 0 emits resolved; repeated 2 emits 0',
        () {
      final t0 = DateTime(2026, 9, 20, 10, 0, 0);

      // Clean
      final snapClean = ProjectWorkspaceSnapshot(
        project: testProject,
        server: testServer,
        connectionState: ConnectionState.connected,
        observedAt: t0,
        git: const WorkspaceGitSummary(conflictCount: 0, isClean: true),
      );
      expect(detector.evaluateWorkspaceSnapshot(snapClean, now: t0), isEmpty);

      // Conflicts appear
      final t1 = t0.add(const Duration(seconds: 5));
      final snapConflict = ProjectWorkspaceSnapshot(
        project: testProject,
        server: testServer,
        connectionState: ConnectionState.connected,
        observedAt: t1,
        git: const WorkspaceGitSummary(conflictCount: 2, isClean: false),
      );
      final eventsConflict =
          detector.evaluateWorkspaceSnapshot(snapConflict, now: t1);
      expect(eventsConflict.length, 1);
      expect(eventsConflict.first.type, EventType.gitConflictDetected);
      expect(eventsConflict.first.severity, EventSeverity.critical);
      expect(eventsConflict.first.actionLabel, 'View Conflicts');

      // Repeated conflicts
      final t2 = t1.add(const Duration(seconds: 5));
      expect(
          detector.evaluateWorkspaceSnapshot(snapConflict, now: t2), isEmpty);

      // Resolved
      final t3 = t2.add(const Duration(seconds: 5));
      final eventsResolved =
          detector.evaluateWorkspaceSnapshot(snapClean, now: t3);
      expect(eventsResolved.length, 1);
      expect(eventsResolved.first.type, EventType.gitConflictResolved);
      expect(eventsResolved.first.severity, EventSeverity.info);
    });

    test('SSH: Disconnect debounce & reconnect restoration', () {
      final t0 = DateTime(2026, 9, 20, 10, 0, 0);

      final snapConnected = ProjectWorkspaceSnapshot(
        project: testProject,
        server: testServer,
        connectionState: ConnectionState.connected,
        observedAt: t0,
      );
      detector.evaluateWorkspaceSnapshot(snapConnected, now: t0);

      // Disconnect at t0+1s (within 2s debounce window)
      final t1 = t0.add(const Duration(seconds: 1));
      final snapDisconnected = ProjectWorkspaceSnapshot(
        project: testProject,
        server: testServer,
        connectionState: ConnectionState.disconnected,
        observedAt: t1,
      );
      final eventsTransient =
          detector.evaluateWorkspaceSnapshot(snapDisconnected, now: t1);
      expect(eventsTransient, isEmpty,
          reason: 'Transient disconnect under debounce should not alert');

      // Disconnect sustained past debounce (t0+3s)
      final t2 = t0.add(const Duration(seconds: 3));
      final eventsSustained =
          detector.evaluateWorkspaceSnapshot(snapDisconnected, now: t2);
      expect(eventsSustained.length, 1);
      expect(eventsSustained.first.type, EventType.connectionLost);

      // Reconnect at t0+10s
      final t3 = t0.add(const Duration(seconds: 10));
      final eventsRestored =
          detector.evaluateWorkspaceSnapshot(snapConnected, now: t3);
      expect(eventsRestored.length, 1);
      expect(eventsRestored.first.type, EventType.connectionRestored);
    });

    test('Server Metrics: Hysteresis prevents thrashing between 89% and 91%',
        () {
      final t0 = DateTime(2026, 9, 20, 10, 0, 0);

      // Normal 60%
      final snap60 = ProjectWorkspaceSnapshot(
        project: testProject,
        server: testServer,
        connectionState: ConnectionState.connected,
        observedAt: t0,
        serverHealth: const WorkspaceServerSummary(memoryPercent: 60.0),
      );
      expect(detector.evaluateWorkspaceSnapshot(snap60, now: t0), isEmpty);

      // Spike to 91% (critical)
      final t1 = t0.add(const Duration(seconds: 5));
      final snap91 = ProjectWorkspaceSnapshot(
        project: testProject,
        server: testServer,
        connectionState: ConnectionState.connected,
        observedAt: t1,
        serverHealth: const WorkspaceServerSummary(memoryPercent: 91.0),
      );
      final events91 = detector.evaluateWorkspaceSnapshot(snap91, now: t1);
      expect(events91.length, 1);
      expect(events91.first.type, EventType.serverResourceCritical);

      // Drops to 88% (hysteresis keeps it in critical state because > 85%)
      final t2 = t1.add(const Duration(seconds: 5));
      final snap88 = ProjectWorkspaceSnapshot(
        project: testProject,
        server: testServer,
        connectionState: ConnectionState.connected,
        observedAt: t2,
        serverHealth: const WorkspaceServerSummary(memoryPercent: 88.0),
      );
      expect(detector.evaluateWorkspaceSnapshot(snap88, now: t2), isEmpty);

      // Spikes back to 91% (no duplicate critical event emitted because already critical)
      final t3 = t2.add(const Duration(seconds: 5));
      expect(detector.evaluateWorkspaceSnapshot(snap91, now: t3), isEmpty);

      // Drops to 65% (fully recovers below 70%)
      final t4 = t3.add(const Duration(seconds: 5));
      final snap65 = ProjectWorkspaceSnapshot(
        project: testProject,
        server: testServer,
        connectionState: ConnectionState.connected,
        observedAt: t4,
        serverHealth: const WorkspaceServerSummary(memoryPercent: 65.0),
      );
      final eventsRecovered =
          detector.evaluateWorkspaceSnapshot(snap65, now: t4);
      expect(eventsRecovered.length, 1);
      expect(eventsRecovered.first.type, EventType.serverResourceRecovered);
    });
  });

  group('EventDeduplicator Tests', () {
    test('100 identical raw observations produce exactly 1 emitted event', () {
      final dedup = EventDeduplicator(window: const Duration(minutes: 5));
      final now = DateTime(2026, 9, 20, 12, 0, 0);

      final event = AgentDeckEvent(
        id: 'e1',
        type: EventType.agentWaitingUser,
        detectedAt: now,
        severity: EventSeverity.actionRequired,
        source: EventSource.agent,
        fingerprint: 'agent_waiting:proj_1:inst_1',
        title: 'Agent is waiting',
        message: 'Respond to prompt',
      );

      final passed = <AgentDeckEvent>[];
      for (int i = 0; i < 100; i++) {
        if (!dedup.isDuplicate(event, now: now.add(Duration(seconds: i)))) {
          passed.add(event);
        }
      }

      expect(passed.length, 1);
    });

    test('Events with different fingerprints are preserved', () {
      final dedup = EventDeduplicator();
      final now = DateTime(2026, 9, 20, 12, 0, 0);

      final e1 = AgentDeckEvent(
        id: 'e1',
        type: EventType.agentWaitingUser,
        detectedAt: now,
        severity: EventSeverity.actionRequired,
        source: EventSource.agent,
        fingerprint: 'fp_1',
        title: 'Alert 1',
        message: 'Msg 1',
      );

      final e2 = AgentDeckEvent(
        id: 'e2',
        type: EventType.gitConflictDetected,
        detectedAt: now,
        severity: EventSeverity.critical,
        source: EventSource.git,
        fingerprint: 'fp_2',
        title: 'Alert 2',
        message: 'Msg 2',
      );

      final filtered = dedup.filterDuplicates([e1, e2], now: now);
      expect(filtered.length, 2);
    });
  });

  group('FileEventRepository & Retention Tests', () {
    late Directory tempDir;
    late FileEventRepository repo;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('agentdeck_events_test_');
      final file =
          File('${tempDir.path}${Platform.pathSeparator}test_events.json');
      repo = FileEventRepository(JsonFileStore(file), maxRetention: 5);
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('Atomic save, read, markRead, and FIFO bounded retention', () async {
      final now = DateTime(2026, 9, 20, 10, 0, 0);

      // Save 8 events into maxRetention: 5 store
      for (int i = 1; i <= 8; i++) {
        await repo.save(AgentDeckEvent(
          id: 'evt_$i',
          type: EventType.agentWaitingUser,
          detectedAt: now.add(Duration(minutes: i)),
          severity: EventSeverity.actionRequired,
          source: EventSource.agent,
          fingerprint: 'fp_$i',
          title: 'Event $i',
          message: 'Message $i',
          projectId: 'proj_1',
        ));
      }

      final allEvents = await repo.all(limit: 50);
      expect(allEvents.length, 5,
          reason: 'Must cap strictly to maxRetention of 5');
      // Verify newest 5 (evt_8, evt_7, evt_6, evt_5, evt_4) are preserved in order
      expect(allEvents.map((e) => e.id).toList(),
          ['evt_8', 'evt_7', 'evt_6', 'evt_5', 'evt_4']);

      // Unread & actionable count
      expect(await repo.unreadCount(), 5);
      expect(await repo.actionableCount(), 5);

      // Mark single read
      await repo.markRead('evt_8');
      expect(await repo.unreadCount(), 4);

      // Mark all read
      await repo.markAllRead();
      expect(await repo.unreadCount(), 0);
      expect(await repo.actionableCount(), 0);
    });

    test('Secret and sensitive payload sanitization on storage', () async {
      final event = AgentDeckEvent(
        id: 'evt_sec',
        type: EventType.agentWaitingUser,
        detectedAt: DateTime.now(),
        severity: EventSeverity.actionRequired,
        source: EventSource.agent,
        fingerprint: 'fp_sec',
        title: 'Agent needs input',
        message: 'Confirmation required',
        metadata: {
          'provider': 'codex',
          'instanceId': 'i1',
          'password': 'SUPER_SECRET_PASSWORD',
          'apiKey': 'sk-1234567890',
          'terminalStdout': 'full command prompt text with passwords',
          'diffBody': '--- a/secret.env\n+++ b/secret.env',
        },
      );

      await repo.save(event);
      final stored = await repo.getById('evt_sec');
      expect(stored, isNotNull);
      expect(stored!.metadata.containsKey('provider'), isTrue);
      expect(stored.metadata.containsKey('instanceId'), isTrue);
      expect(stored.metadata.containsKey('password'), isFalse,
          reason: 'Passwords must never be stored');
      expect(stored.metadata.containsKey('apiKey'), isFalse,
          reason: 'API keys must never be stored');
      expect(stored.metadata.containsKey('terminalStdout'), isFalse);
      expect(stored.metadata.containsKey('diffBody'), isFalse);
    });
  });

  group('NotificationPolicy & Privacy Tests', () {
    final policy = NotificationPolicy();

    final waitingEvent = AgentDeckEvent(
      id: 'e1',
      type: EventType.agentWaitingUser,
      detectedAt: DateTime.now(),
      severity: EventSeverity.actionRequired,
      source: EventSource.agent,
      fingerprint: 'fp1',
      title: 'Codex is waiting for input',
      message: 'Interactive CLI prompt requires response.',
      projectName: 'Portal Proveedores',
      isProduction: true,
    );

    test('Policy decisions based on preferences', () {
      expect(policy.shouldNotify(waitingEvent), isTrue);

      final finishedEvent = waitingEvent.copyWith(
        type: EventType.agentFinished,
        severity: EventSeverity.info,
      );
      // Default notifyAgentFinished is false
      expect(policy.shouldNotify(finishedEvent), isFalse);
    });

    test('Privacy preview mode sanitization', () {
      // Full
      final full = policy.sanitizeForPreview(waitingEvent,
          overrideMode: NotificationPrivacyMode.full);
      expect(full.title,
          'PRODUCTION • Portal Proveedores: Codex is waiting for input');
      expect(full.message, 'Interactive CLI prompt requires response.');

      // Project Only
      final projOnly = policy.sanitizeForPreview(waitingEvent,
          overrideMode: NotificationPrivacyMode.projectOnly);
      expect(projOnly.title, 'PRODUCTION • Portal Proveedores');
      expect(projOnly.message, 'Remote agent is waiting for input.');

      // Generic
      final generic = policy.sanitizeForPreview(waitingEvent,
          overrideMode: NotificationPrivacyMode.generic);
      expect(generic.title, 'PRODUCTION Alert');
      expect(generic.message, 'An item requires your attention.');
    });
  });

  group('AppLifecycleCoordinator Tests', () {
    test('Handles resumed and paused lifecycle events', () async {
      bool resumedCalled = false;
      bool backgroundedCalled = false;

      final coordinator = AppLifecycleCoordinator(
        onAppResumed: () => resumedCalled = true,
        onAppBackgrounded: () => backgroundedCalled = true,
      );

      await coordinator.handleLifecycleChange(AppLifecycleStatus.paused);
      expect(coordinator.isForeground, isFalse);
      expect(backgroundedCalled, isTrue);

      await coordinator.handleLifecycleChange(AppLifecycleStatus.resumed);
      expect(coordinator.isForeground, isTrue);
      expect(resumedCalled, isTrue);

      coordinator.dispose();
    });
  });

  group('NotificationCoordinator End-to-End Tests', () {
    late Directory tempDir;
    late NotificationCoordinator coord;
    late InAppNotificationDelivery delivery;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('agentdeck_coord_test_');
      final file = File('${tempDir.path}${Platform.pathSeparator}events.json');
      delivery = InAppNotificationDelivery();
      coord = NotificationCoordinator(
        repository: FileEventRepository(JsonFileStore(file)),
        deliveryService: delivery,
      );
    });

    tearDown(() async {
      await coord.dispose();
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('Processes snapshot and delivers live events', () async {
      const project = ProjectProfile(
        id: 'p1',
        name: 'Fenix IA',
        serverId: 's1',
        workingDirectory: '/home/fenix',
        environment: Environment.development,
        executionPolicy: ExecutionPolicy(environment: Environment.development),
      );

      final t0 = DateTime(2026, 9, 20, 14, 0, 0);

      // First snapshot: running
      await coord.processWorkspaceSnapshot(
        ProjectWorkspaceSnapshot(
          project: project,
          connectionState: ConnectionState.connected,
          observedAt: t0,
          agent: const WorkspaceAgentSummary(
            instanceId: 'i1',
            providerName: 'OpenCode',
            state: AgentExecutionState.running,
          ),
        ),
        now: t0,
      );

      expect(await coord.getUnreadCount(), 0);

      // Second snapshot: waiting
      final t1 = t0.add(const Duration(seconds: 5));
      final emitted = await coord.processWorkspaceSnapshot(
        ProjectWorkspaceSnapshot(
          project: project,
          connectionState: ConnectionState.connected,
          observedAt: t1,
          agent: const WorkspaceAgentSummary(
            instanceId: 'i1',
            providerName: 'OpenCode',
            state: AgentExecutionState.waitingUser,
          ),
        ),
        now: t1,
      );

      expect(emitted.length, 1);
      expect(await coord.getUnreadCount(), 1);
      expect(await coord.getActionableCount(), 1);
    });
  });
}
