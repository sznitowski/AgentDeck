import 'package:agentdeck/core/domain/events.dart';
import 'package:agentdeck/features/notifications/application/notification_coordinator.dart';
import 'package:agentdeck/features/notifications/domain/event_repository.dart';
import 'package:agentdeck/features/notifications/presentation/notification_center_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeEventRepository implements EventRepository {
  _FakeEventRepository([List<AgentDeckEvent>? initial])
      : _events = List.from(initial ?? []);

  final List<AgentDeckEvent> _events;

  @override
  Future<List<AgentDeckEvent>> all({
    int limit = 200,
    EventReadState? filterReadState,
    String? filterProjectId,
  }) async {
    var list = List<AgentDeckEvent>.from(_events);
    if (filterReadState != null) {
      list = list.where((e) => e.readState == filterReadState).toList();
    }
    if (filterProjectId != null) {
      list = list.where((e) => e.projectId == filterProjectId).toList();
    }
    list.sort((a, b) => b.detectedAt.compareTo(a.detectedAt));
    if (list.length > limit) {
      list = list.sublist(0, limit);
    }
    return list;
  }

  @override
  Future<AgentDeckEvent?> getById(String id) async {
    return _events.cast<AgentDeckEvent?>().firstWhere(
          (e) => e?.id == id,
          orElse: () => null,
        );
  }

  @override
  Future<void> save(AgentDeckEvent event) async {
    final idx = _events.indexWhere((e) => e.id == event.id);
    if (idx != -1) {
      _events[idx] = event;
    } else {
      _events.add(event);
    }
  }

  @override
  Future<void> saveAll(List<AgentDeckEvent> events) async {
    for (final e in events) {
      await save(e);
    }
  }

  @override
  Future<void> markRead(String id) async {
    final idx = _events.indexWhere((e) => e.id == id);
    if (idx != -1) {
      _events[idx] = _events[idx].copyWith(readState: EventReadState.read);
    }
  }

  @override
  Future<void> markAllRead({String? projectId}) async {
    for (int i = 0; i < _events.length; i++) {
      if (projectId == null || _events[i].projectId == projectId) {
        _events[i] = _events[i].copyWith(readState: EventReadState.read);
      }
    }
  }

  @override
  Future<void> delete(String id) async {
    _events.removeWhere((e) => e.id == id);
  }

  @override
  Future<void> clear({String? projectId}) async {
    if (projectId == null) {
      _events.clear();
    } else {
      _events.removeWhere((e) => e.projectId == projectId);
    }
  }

  @override
  Future<int> unreadCount({String? projectId}) async {
    return _events.where((e) {
      final matchesProj = projectId == null || e.projectId == projectId;
      return matchesProj && e.isUnread;
    }).length;
  }

  @override
  Future<int> actionableCount({String? projectId}) async {
    return _events.where((e) {
      final matchesProj = projectId == null || e.projectId == projectId;
      return matchesProj && e.isUnread && e.isActionable;
    }).length;
  }

  @override
  Future<void> readCheck() async {}
}

void main() {
  group('NotificationCenterPage Widget Tests', () {
    late _FakeEventRepository repository;
    late NotificationCoordinator coordinator;

    setUp(() {
      repository = _FakeEventRepository();
      coordinator = NotificationCoordinator(repository: repository);
    });

    tearDown(() async {
      await coordinator.dispose();
    });

    Widget createWidgetUnderTest({
      void Function(NotificationDestination)? onNavigate,
      String? projectId,
    }) {
      return MaterialApp(
        theme: ThemeData.dark(),
        home: NotificationCenterPage(
          coordinator: coordinator,
          initialProjectId: projectId,
          onNavigateDestination: onNavigate,
        ),
      );
    }

    testWidgets('Renders empty state when no events exist', (tester) async {
      await tester.pumpWidget(createWidgetUnderTest());
      await tester.pump();
      await tester.pumpAndSettle();

      expect(find.text('Activity & Alerts'), findsOneWidget);
      expect(find.text('No notifications or activity to display.'),
          findsOneWidget);
    });

    testWidgets(
        'Renders notifications with PRODUCTION badge, severity and action button',
        (tester) async {
      final event1 = AgentDeckEvent(
        id: 'evt_1',
        type: EventType.agentWaitingUser,
        detectedAt: DateTime.now().subtract(const Duration(minutes: 2)),
        severity: EventSeverity.actionRequired,
        source: EventSource.agent,
        fingerprint: 'fp1',
        title: 'Codex is waiting for input',
        message: 'Interactive CLI prompt requires response.',
        projectName: 'Portal Proveedores',
        isProduction: true,
        actionLabel: 'Respond',
        destination: const NotificationDestination(
          route: 'agent_terminal',
          projectId: 'p1',
        ),
      );

      final event2 = AgentDeckEvent(
        id: 'evt_2',
        type: EventType.gitConflictDetected,
        detectedAt: DateTime.now().subtract(const Duration(minutes: 10)),
        severity: EventSeverity.critical,
        source: EventSource.git,
        fingerprint: 'fp2',
        title: 'Git Merge Conflicts Detected',
        message: '2 file(s) contain unresolved merge conflicts.',
        projectName: 'Fenix IA',
        isProduction: false,
        actionLabel: 'View Conflicts',
        destination: const NotificationDestination(
          route: 'git',
          projectId: 'p2',
        ),
      );

      await repository.saveAll([event1, event2]);

      await tester.pumpWidget(createWidgetUnderTest());
      await tester.pump();
      await tester.pumpAndSettle();

      // Check header counts
      expect(find.text('Activity & Alerts'), findsOneWidget);
      expect(find.text('PRODUCTION'), findsOneWidget);
      expect(
          find.text(
              'PRODUCTION • Portal Proveedores: Codex is waiting for input'),
          findsOneWidget);
      expect(
          find.text('Fenix IA: Git Merge Conflicts Detected'), findsOneWidget);
      expect(find.text('Respond'), findsOneWidget);
      expect(find.text('View Conflicts'), findsOneWidget);
    });

    testWidgets('Tapping action button triggers navigation and marks as read',
        (tester) async {
      NotificationDestination? navigatedDest;

      final event = AgentDeckEvent(
        id: 'evt_nav',
        type: EventType.agentWaitingUser,
        detectedAt: DateTime.now(),
        severity: EventSeverity.actionRequired,
        source: EventSource.agent,
        fingerprint: 'fp_nav',
        title: 'Codex needs input',
        message: 'Interactive CLI prompt',
        projectName: 'Portal',
        actionLabel: 'Respond',
        destination: const NotificationDestination(
          route: 'agent_terminal',
          projectId: 'p1',
        ),
      );

      await repository.save(event);

      await tester.pumpWidget(createWidgetUnderTest(
        onNavigate: (dest) => navigatedDest = dest,
      ));
      await tester.pump();
      await tester.pumpAndSettle();

      expect(await repository.unreadCount(), 1);

      await tester.tap(find.text('Respond'));
      await tester.pump();
      await tester.pumpAndSettle();

      expect(navigatedDest, isNotNull);
      expect(navigatedDest!.route, 'agent_terminal');
      expect(navigatedDest!.projectId, 'p1');
      expect(await repository.unreadCount(), 0);
    });

    testWidgets(
        'Switching privacy preview mode transforms notification text live',
        (tester) async {
      final event = AgentDeckEvent(
        id: 'evt_priv',
        type: EventType.agentWaitingUser,
        detectedAt: DateTime.now(),
        severity: EventSeverity.actionRequired,
        source: EventSource.agent,
        fingerprint: 'fp_priv',
        title: 'Codex is waiting for input',
        message: 'Interactive CLI prompt requires response.',
        projectName: 'Portal Proveedores',
        isProduction: true,
      );

      await repository.save(event);

      await tester.pumpWidget(createWidgetUnderTest());
      await tester.pump();
      await tester.pumpAndSettle();

      // Default: Full
      expect(
          find.text(
              'PRODUCTION • Portal Proveedores: Codex is waiting for input'),
          findsOneWidget);

      // Switch to Project Only
      await tester.tap(find.text('Project Only'));
      await tester.pump();
      await tester.pumpAndSettle();
      expect(find.text('PRODUCTION • Portal Proveedores'), findsOneWidget);
      expect(find.text('Remote agent is waiting for input.'), findsOneWidget);

      // Switch to Generic
      await tester.tap(find.text('Generic'));
      await tester.pump();
      await tester.pumpAndSettle();
      expect(find.text('PRODUCTION Alert'), findsOneWidget);
      expect(find.text('An item requires your attention.'), findsOneWidget);
    });
  });
}
