import 'dart:async';

import 'package:flutter/material.dart' hide ConnectionState;

import '../../../core/domain/agents.dart';
import '../../../core/domain/git.dart';
import '../../../core/domain/profiles.dart';
import '../../../core/domain/server_operations.dart';
import '../../../core/domain/workspace.dart';
import '../../agents/agents_page.dart';
import '../../agents/application/agent_coordinator.dart';
import '../../connections/application/ssh_connection_service.dart';
import '../../files/application/remote_file_service.dart';
import '../../files/presentation/remote_files_page.dart';
import '../../git/presentation/git_changes_page.dart';
import '../../notifications/application/notification_coordinator.dart';
import '../../notifications/presentation/notification_badge.dart';
import '../../notifications/presentation/notification_center_page.dart';
import '../../servers/domain/server_profile_repository.dart';
import '../../servers/presentation/server_operations_page.dart';
import '../../terminal/terminal_page.dart';
import '../../tmux/application/tmux_service.dart';
import '../application/project_workspace_coordinator.dart';
import 'workspace_agent_card.dart';
import 'workspace_attention_banner.dart';
import 'workspace_git_card.dart';
import 'workspace_quick_actions.dart';
import 'workspace_server_card.dart';

/// Comprehensive mobile-first Project Workspace and Control Center.
class ProjectWorkspacePage extends StatefulWidget {
  const ProjectWorkspacePage({
    super.key,
    required this.project,
    required this.coordinator,
    this.connection,
    this.serverProfiles,
    this.agents,
    this.tmux,
    this.gitService,
    this.serverOpsService,
    this.fileService,
    this.notifications,
  });

  final ProjectProfile project;
  final ProjectWorkspaceCoordinator coordinator;
  final SshConnectionService? connection;
  final ServerProfileRepository? serverProfiles;
  final AgentCoordinator? agents;
  final TmuxService? tmux;
  final GitService? gitService;
  final ServerOperationsService? serverOpsService;
  final RemoteFileService? fileService;
  final NotificationCoordinator? notifications;

  @override
  State<ProjectWorkspacePage> createState() => _ProjectWorkspacePageState();
}

class _ProjectWorkspacePageState extends State<ProjectWorkspacePage> {
  bool _loading = false;
  ProjectWorkspaceSnapshot? _snapshot;
  String? _error;
  int _unreadCount = 0;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final snap = await widget.coordinator.inspectWorkspace(widget.project);
      if (widget.notifications != null) {
        await widget.notifications!.processWorkspaceSnapshot(snap);
        if (snap.server != null && snap.isConnected) {
          await widget.notifications!.syncCompanionEvents(snap.server!.id);
        }
        final unread = await widget.notifications!.getUnreadCount(
          projectId: widget.project.id,
        );
        if (mounted) {
          _unreadCount = unread;
        }
      }

      if (mounted) {
        setState(() {
          _snapshot = snap;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  void _handleAttentionAction(String route) {
    switch (route) {
      case 'agent_terminal':
      case 'terminal':
        _openTerminal(attachedSession: _snapshot?.agent?.tmuxSessionName);
        break;
      case 'agent':
        _openAgents();
        break;
      case 'git':
        _openGit();
        break;
      case 'server':
        _openServer();
        break;
      case 'files':
        _openFiles();
        break;
      case 'connection':
        _connectServer();
        break;
      default:
        break;
    }
  }

  Future<void> _connectServer() async {
    final server = _snapshot?.server;
    final conn = widget.connection;
    if (server == null || conn == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content:
                Text('Cannot initiate connection: Server profile missing.')),
      );
      return;
    }

    try {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Connecting to ${server.name}...')),
      );
      await conn.connect(server);
      await _refresh();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Connection failed: $e'),
              backgroundColor: Colors.red),
        );
      }
    }
  }

  void _openTerminal({String? attachedSession}) {
    final server = _snapshot?.server;
    final conn = widget.connection;
    if (server == null || conn == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content:
                Text('Server profile or SSH connection service unavailable.')),
      );
      return;
    }

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => TerminalPage(
          profile: server,
          connection: conn,
          tmux: attachedSession != null ? widget.tmux : null,
          sessionName: attachedSession,
        ),
      ),
    );
  }

  void _openFiles() {
    final server = _snapshot?.server;
    final files = widget.fileService;
    if (server == null || files == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content:
                Text('Remote file service unavailable or server not loaded.')),
      );
      return;
    }

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => RemoteFilesPage(
          profile: server,
          service: files,
          initialPath: widget.project.workingDirectory,
        ),
      ),
    );
  }

  void _openGit() {
    final git = widget.gitService;
    if (git == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Git service unavailable.')),
      );
      return;
    }

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => GitChangesPage(
          project: widget.project,
          service: git,
        ),
      ),
    );
  }

  void _openServer() {
    final server = _snapshot?.server;
    if (server == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Server profile unavailable.')),
      );
      return;
    }

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ServerOperationsPage(
          server: server,
          connection: widget.connection,
          service: widget.serverOpsService,
        ),
      ),
    );
  }

  void _openAgents() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AgentsPage(
          coordinator: widget.agents,
          serverProfiles: widget.serverProfiles,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isProd = widget.project.environment == Environment.production;

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.project.name,
                style:
                    const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            if (isProd)
              const Text(
                'PRODUCTION ENVIRONMENT',
                style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: Colors.orangeAccent),
              ),
          ],
        ),
        actions: [
          IconButton(
            icon: Stack(
              clipBehavior: Clip.none,
              children: [
                const Icon(Icons.notifications_outlined),
                if (_unreadCount > 0)
                  Positioned(
                    top: -4,
                    right: -4,
                    child: NotificationBadge(count: _unreadCount),
                  ),
              ],
            ),
            tooltip: 'Activity & Alerts',
            onPressed: () {
              Navigator.of(context)
                  .push(
                    MaterialPageRoute(
                      builder: (_) => NotificationCenterPage(
                        coordinator: widget.notifications,
                        initialProjectId: widget.project.id,
                      ),
                    ),
                  )
                  .then((_) => _refresh());
            },
          ),
          if (_loading)
            const Center(
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            )
          else
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: 'Refresh Workspace',
              onPressed: _refresh,
            ),
        ],
      ),
      body: _error != null
          ? _buildErrorView()
          : _snapshot == null && _loading
              ? const Center(child: CircularProgressIndicator())
              : _buildWorkspaceBody(theme, colorScheme),
    );
  }

  Widget _buildErrorView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 48, color: Colors.red),
            const SizedBox(height: 16),
            const Text(
              'Failed to load workspace snapshot',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              _error ?? 'Unknown error',
              style: const TextStyle(color: Colors.grey, fontSize: 13),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: _refresh,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWorkspaceBody(ThemeData theme, ColorScheme colorScheme) {
    final snap = _snapshot!;
    final server = snap.server;
    final topAttention = snap.topAttentionItem;

    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // 1. Connection & Server Header
          _buildConnectionHeader(snap, server, colorScheme),
          const SizedBox(height: 16),

          // 2. Urgent Actionable Attention Banner (Top Priority)
          if (topAttention != null)
            WorkspaceAttentionBanner(
              item: topAttention,
              onAction: _handleAttentionAction,
            ),

          // 3. Quick Action Toolbar
          WorkspaceQuickActions(
            onOpenTerminal: () =>
                _openTerminal(attachedSession: snap.agent?.tmuxSessionName),
            onOpenFiles: _openFiles,
            onOpenGit: _openGit,
            onOpenServer: _openServer,
            onOpenAgents: _openAgents,
          ),
          const SizedBox(height: 16),

          // 4. Agent Orchestration Card
          WorkspaceAgentCard(
            agent: snap.agent,
            onOpenAgent: _openAgents,
            onOpenTerminal: () =>
                _openTerminal(attachedSession: snap.agent?.tmuxSessionName),
            onLaunchAgent: _openAgents,
          ),

          // 5. Git Repository Card
          WorkspaceGitCard(
            git: snap.git,
            onViewChanges: _openGit,
          ),

          // 6. Server Health Card
          WorkspaceServerCard(
            serverHealth: snap.serverHealth,
            onOpenServerHealth: _openServer,
          ),

          // 7. Working Directory / Files Card
          _buildFilesCard(snap.files, theme, colorScheme),

          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildConnectionHeader(
    ProjectWorkspaceSnapshot snap,
    ServerProfile? server,
    ColorScheme colorScheme,
  ) {
    final isConnected = snap.isConnected;
    final (statusColor, statusText) = switch (snap.connectionState) {
      ConnectionState.connected => (Colors.green, 'CONNECTED'),
      ConnectionState.connecting => (Colors.blue, 'CONNECTING'),
      ConnectionState.reconnecting => (Colors.amber, 'RECONNECTING'),
      ConnectionState.disconnected => (Colors.grey, 'DISCONNECTED'),
      ConnectionState.failed => (Colors.red, 'FAILED'),
    };

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: colorScheme.outlineVariant.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: statusColor,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            statusText,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: statusColor,
            ),
          ),
          const SizedBox(width: 8),
          const Text('•', style: TextStyle(color: Colors.grey)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              server != null
                  ? '${server.name} (${server.host})'
                  : 'Unknown Server',
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (!isConnected)
            TextButton(
              onPressed: _connectServer,
              child: const Text('Connect'),
            ),
        ],
      ),
    );
  }

  Widget _buildFilesCard(
    WorkspaceFilesSummary? files,
    ThemeData theme,
    ColorScheme colorScheme,
  ) {
    return Card(
      elevation: 1,
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.folder_outlined,
                    size: 20, color: colorScheme.primary),
                const SizedBox(width: 8),
                Text('Working Directory', style: theme.textTheme.titleMedium),
                const Spacer(),
                if (files != null)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: files.exists
                          ? Colors.teal.withValues(alpha: 0.15)
                          : Colors.orange.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: files.exists ? Colors.teal : Colors.orange,
                        width: 0.8,
                      ),
                    ),
                    child: Text(
                      files.exists ? 'VERIFIED' : 'UNVERIFIED',
                      style: TextStyle(
                        color: files.exists ? Colors.teal : Colors.orange,
                        fontWeight: FontWeight.bold,
                        fontSize: 10,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              widget.project.workingDirectory,
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _openFiles,
              icon: const Icon(Icons.folder_open, size: 16),
              label: const Text('Browse Files'),
            ),
          ],
        ),
      ),
    );
  }
}
