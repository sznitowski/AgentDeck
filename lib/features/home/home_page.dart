import 'package:flutter/material.dart';

import '../../shared/page_frame.dart';
import '../notifications/application/notification_coordinator.dart';
import '../notifications/presentation/notification_center_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key, this.notifications});

  final NotificationCoordinator? notifications;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _unreadCount = 0;
  int _actionableCount = 0;
  String _latestActivityText = 'No alerts yet';

  @override
  void initState() {
    super.initState();
    _refreshActivity();
  }

  Future<void> _refreshActivity() async {
    if (widget.notifications == null) return;
    final unread = await widget.notifications!.getUnreadCount();
    final actionable = await widget.notifications!.getActionableCount();
    final recent = await widget.notifications!.getRecentEvents(limit: 1);

    if (mounted) {
      setState(() {
        _unreadCount = unread;
        _actionableCount = actionable;
        if (recent.isNotEmpty) {
          _latestActivityText = recent.first.title;
        } else {
          _latestActivityText = 'No alerts yet';
        }
      });
    }
  }

  void _openNotificationCenter() {
    Navigator.of(context)
        .push(
          MaterialPageRoute(
            builder: (_) => NotificationCenterPage(
              coordinator: widget.notifications,
            ),
          ),
        )
        .then((_) => _refreshActivity());
  }

  @override
  Widget build(BuildContext context) {
    return PageFrame(
      title: 'AgentDeck',
      subtitle: 'Your remote workspace, one project at a time',
      child: Column(children: [
        const SummaryCard(
            title: 'Servers',
            value: 'No servers yet',
            icon: Icons.dns_outlined),
        const SummaryCard(
            title: 'Projects',
            value: 'No projects yet',
            icon: Icons.folder_outlined),
        const SummaryCard(
            title: 'Agents',
            value: 'No active agents',
            icon: Icons.smart_toy_outlined),
        InkWell(
          onTap: _openNotificationCenter,
          borderRadius: BorderRadius.circular(12),
          child: SummaryCard(
            title: _unreadCount > 0
                ? 'Recent activity ($_unreadCount unread)'
                : 'Recent activity',
            value: _latestActivityText,
            icon: _actionableCount > 0
                ? Icons.warning_amber_rounded
                : Icons.notifications_outlined,
          ),
        ),
      ]),
    );
  }
}
