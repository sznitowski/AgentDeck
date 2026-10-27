import 'package:flutter/material.dart';

import '../../../core/domain/events.dart';
import '../application/notification_coordinator.dart';
import '../domain/notification_policy.dart';
import 'notification_badge.dart';

/// Interactive Notification & Activity Center page.
class NotificationCenterPage extends StatefulWidget {
  const NotificationCenterPage({
    super.key,
    this.coordinator,
    this.initialProjectId,
    this.onNavigateDestination,
  });

  final NotificationCoordinator? coordinator;
  final String? initialProjectId;
  final void Function(NotificationDestination destination)?
      onNavigateDestination;

  @override
  State<NotificationCenterPage> createState() => _NotificationCenterPageState();
}

enum _NotificationFilter {
  all,
  unread,
  actionable,
}

class _NotificationCenterPageState extends State<NotificationCenterPage> {
  _NotificationFilter _activeFilter = _NotificationFilter.all;
  NotificationPrivacyMode _privacyMode = NotificationPrivacyMode.full;

  List<AgentDeckEvent> _events = [];
  int _unreadCount = 0;
  int _actionableCount = 0;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadEvents();
  }

  Future<void> _loadEvents() async {
    if (widget.coordinator == null) {
      setState(() => _isLoading = false);
      return;
    }

    final events = await widget.coordinator!.getRecentEvents(
      limit: 100,
      filterProjectId: widget.initialProjectId,
    );
    final unread = await widget.coordinator!.getUnreadCount(
      projectId: widget.initialProjectId,
    );
    final actionable = await widget.coordinator!.getActionableCount(
      projectId: widget.initialProjectId,
    );

    if (mounted) {
      setState(() {
        _events = events;
        _unreadCount = unread;
        _actionableCount = actionable;
        _isLoading = false;
      });
    }
  }

  Future<void> _markAllAsRead() async {
    if (widget.coordinator == null) return;
    await widget.coordinator!.markAllRead(projectId: widget.initialProjectId);
    await _loadEvents();
  }

  Future<void> _clearHistory() async {
    if (widget.coordinator == null) return;
    await widget.coordinator!.clearHistory(projectId: widget.initialProjectId);
    await _loadEvents();
  }

  Future<void> _handleEventAction(AgentDeckEvent event) async {
    if (widget.coordinator != null && event.isUnread) {
      await widget.coordinator!.markRead(event.id);
      _loadEvents();
    }

    if (event.destination != null && widget.onNavigateDestination != null) {
      widget.onNavigateDestination!(event.destination!);
    }
  }

  List<AgentDeckEvent> get _filteredEvents {
    switch (_activeFilter) {
      case _NotificationFilter.all:
        return _events;
      case _NotificationFilter.unread:
        return _events.where((e) => e.isUnread).toList();
      case _NotificationFilter.actionable:
        return _events.where((e) => e.isActionable).toList();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final policy = widget.coordinator?.policy ?? NotificationPolicy();

    return Scaffold(
      backgroundColor: const Color(0xFF0B1020),
      appBar: AppBar(
        title: Row(
          children: [
            const Text(
              'Activity & Alerts',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(width: 8),
            if (_unreadCount > 0)
              NotificationBadge(
                count: _unreadCount,
                isActionable: _actionableCount > 0,
              ),
          ],
        ),
        backgroundColor: const Color(0xFF131B30),
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.done_all, size: 20),
            tooltip: 'Mark all as read',
            onPressed: _unreadCount > 0 ? _markAllAsRead : null,
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, size: 20),
            onSelected: (value) {
              if (value == 'clear') _clearHistory();
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'clear',
                child: Row(
                  children: [
                    Icon(Icons.delete_outline,
                        size: 18, color: Colors.redAccent),
                    SizedBox(width: 8),
                    Text('Clear history',
                        style: TextStyle(color: Colors.redAccent)),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          // Filter & Privacy Mode Controls Bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: const Color(0xFF131B30),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Filter Segmented Buttons
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _buildFilterChip(
                          'All (${_events.length})', _NotificationFilter.all),
                      const SizedBox(width: 8),
                      _buildFilterChip(
                          'Unread ($_unreadCount)', _NotificationFilter.unread),
                      const SizedBox(width: 8),
                      _buildFilterChip('Actionable ($_actionableCount)',
                          _NotificationFilter.actionable),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                // Privacy preview toggle
                Row(
                  children: [
                    const Icon(Icons.visibility_outlined,
                        size: 14, color: Colors.white54),
                    const SizedBox(width: 6),
                    const Text('Preview:',
                        style: TextStyle(fontSize: 12, color: Colors.white54)),
                    const SizedBox(width: 6),
                    _buildPrivacyChip('Full', NotificationPrivacyMode.full),
                    const SizedBox(width: 4),
                    _buildPrivacyChip(
                        'Project Only', NotificationPrivacyMode.projectOnly),
                    const SizedBox(width: 4),
                    _buildPrivacyChip(
                        'Generic', NotificationPrivacyMode.generic),
                  ],
                ),
              ],
            ),
          ),

          // Notification list
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _filteredEvents.isEmpty
                    ? _buildEmptyState()
                    : RefreshIndicator(
                        onRefresh: _loadEvents,
                        child: ListView.separated(
                          padding: const EdgeInsets.all(16),
                          itemCount: _filteredEvents.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 10),
                          itemBuilder: (context, index) {
                            final event = _filteredEvents[index];
                            final payload = policy.sanitizeForPreview(
                              event,
                              overrideMode: _privacyMode,
                            );
                            return _buildNotificationCard(
                                event, payload, theme);
                          },
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String label, _NotificationFilter filter) {
    final isSelected = _activeFilter == filter;
    return ChoiceChip(
      label: Text(label,
          style: TextStyle(
              fontSize: 12, color: isSelected ? Colors.white : Colors.white70)),
      selected: isSelected,
      selectedColor: const Color(0xFF536CFF),
      backgroundColor: const Color(0xFF1E2846),
      padding: const EdgeInsets.symmetric(horizontal: 4),
      onSelected: (_) => setState(() => _activeFilter = filter),
    );
  }

  Widget _buildPrivacyChip(String label, NotificationPrivacyMode mode) {
    final isSelected = _privacyMode == mode;
    return InkWell(
      onTap: () => setState(() => _privacyMode = mode),
      borderRadius: BorderRadius.circular(4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF3B82F6) : Colors.transparent,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: isSelected ? const Color(0xFF60A5FA) : Colors.white24,
            width: 1,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: isSelected ? Colors.white : Colors.white60,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
  }

  Widget _buildNotificationCard(
    AgentDeckEvent event,
    SanitizedNotificationPayload payload,
    ThemeData theme,
  ) {
    final isUnread = event.isUnread;
    final isActionable = event.isActionable;

    Color borderColor = Colors.white10;
    if (isUnread) {
      borderColor = isActionable
          ? const Color(0xFFEF4444).withValues(alpha: 0.5)
          : const Color(0xFF536CFF).withValues(alpha: 0.5);
    }

    return Card(
      color: isUnread ? const Color(0xFF161F38) : const Color(0xFF11172A),
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: borderColor, width: isUnread ? 1.5 : 1),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top row: Source Icon, Environment Badge, Relative Timestamp, Unread dot
            Row(
              children: [
                _buildSourceIcon(event.source, event.severity),
                const SizedBox(width: 8),
                if (payload.isProduction)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    margin: const EdgeInsets.only(right: 8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEF4444).withValues(alpha: 0.2),
                      border: Border.all(color: const Color(0xFFEF4444)),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Text(
                      'PRODUCTION',
                      style: TextStyle(
                        color: Color(0xFFEF4444),
                        fontSize: 9,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                Expanded(
                  child: Text(
                    _formatRelativeTime(event.detectedAt),
                    style: const TextStyle(color: Colors.white38, fontSize: 11),
                  ),
                ),
                if (isUnread)
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: isActionable
                          ? const Color(0xFFEF4444)
                          : const Color(0xFF536CFF),
                      shape: BoxShape.circle,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),

            // Title
            Text(
              payload.title,
              style: TextStyle(
                color: isUnread ? Colors.white : Colors.white70,
                fontSize: 14,
                fontWeight: isUnread ? FontWeight.bold : FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),

            // Message
            Text(
              payload.message,
              style: const TextStyle(
                color: Colors.white60,
                fontSize: 12,
                height: 1.3,
              ),
            ),

            // Action button if actionable
            if (event.actionLabel != null) ...[
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton.tonal(
                  onPressed: () => _handleEventAction(event),
                  style: FilledButton.styleFrom(
                    backgroundColor: isActionable
                        ? const Color(0xFFEF4444).withValues(alpha: 0.2)
                        : const Color(0xFF536CFF).withValues(alpha: 0.2),
                    foregroundColor: isActionable
                        ? const Color(0xFFF87171)
                        : const Color(0xFF818CF8),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    minimumSize: const Size(60, 32),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        event.actionLabel!,
                        style: const TextStyle(
                            fontSize: 12, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(width: 4),
                      const Icon(Icons.arrow_forward, size: 14),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildSourceIcon(EventSource source, EventSeverity severity) {
    IconData icon;
    Color color;

    switch (severity) {
      case EventSeverity.critical:
        color = const Color(0xFFEF4444);
        break;
      case EventSeverity.actionRequired:
        color = const Color(0xFFF59E0B);
        break;
      case EventSeverity.warning:
        color = const Color(0xFFFBBF24);
        break;
      case EventSeverity.info:
        color = const Color(0xFF3B82F6);
        break;
    }

    switch (source) {
      case EventSource.agent:
        icon = Icons.smart_toy_outlined;
        break;
      case EventSource.git:
        icon = Icons.merge_type;
        break;
      case EventSource.connection:
        icon = Icons.wifi_off;
        break;
      case EventSource.server:
        icon = Icons.speed;
        break;
      case EventSource.tmux:
        icon = Icons.terminal;
        break;
      case EventSource.files:
        icon = Icons.folder_open;
        break;
      case EventSource.workspace:
        icon = Icons.dashboard_outlined;
        break;
    }

    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Icon(icon, size: 16, color: color),
    );
  }

  String _formatRelativeTime(DateTime timestamp) {
    final diff = DateTime.now().difference(timestamp);
    if (diff.inSeconds < 60) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            _activeFilter == _NotificationFilter.unread
                ? Icons.mark_email_read_outlined
                : Icons.notifications_none,
            size: 48,
            color: Colors.white24,
          ),
          const SizedBox(height: 12),
          Text(
            _activeFilter == _NotificationFilter.unread
                ? 'All caught up!'
                : 'No notifications or activity to display.',
            style: const TextStyle(color: Colors.white54, fontSize: 14),
          ),
        ],
      ),
    );
  }
}
