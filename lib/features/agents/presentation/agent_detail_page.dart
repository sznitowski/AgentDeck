import 'package:flutter/material.dart';

import '../../../core/domain/agents.dart';
import '../../../core/domain/profiles.dart';
import '../../servers/domain/server_profile_repository.dart';
import '../../terminal/terminal_page.dart';
import '../../tmux/application/tmux_service.dart';
import '../application/agent_coordinator.dart';

class AgentDetailPage extends StatefulWidget {
  const AgentDetailPage({
    super.key,
    required this.instance,
    required this.coordinator,
    this.serverProfiles,
  });

  final AgentInstance instance;
  final AgentCoordinator coordinator;
  final ServerProfileRepository? serverProfiles;

  @override
  State<AgentDetailPage> createState() => _AgentDetailPageState();
}

class _AgentDetailPageState extends State<AgentDetailPage> {
  late AgentInstance _instance;
  ServerProfile? _server;
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _instance = widget.instance;
    _loadServer();
    _refresh();
  }

  Future<void> _loadServer() async {
    if (widget.serverProfiles != null) {
      final s = await widget.serverProfiles!.find(_instance.serverId);
      if (mounted) setState(() => _server = s);
    }
  }

  Future<void> _refresh() async {
    setState(() => _loading = true);
    try {
      final updated = await widget.coordinator.refreshInstance(_instance);
      if (mounted) {
        setState(() {
          _instance = updated;
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

  void _openTerminal() {
    final tmux = TmuxService(
      connection: widget.coordinator.connection,
      references: widget.coordinator.tmuxReferences,
      serverId: _instance.serverId,
    );

    final profile = _server ??
        ServerProfile(
          id: _instance.serverId,
          name: _instance.serverId,
          host: 'unknown',
          port: 22,
          username: 'unknown',
          credentialId: '',
        );

    Navigator.of(context)
        .push(
          MaterialPageRoute<void>(
            builder: (_) => TerminalPage(
              profile: profile,
              connection: widget.coordinator.connection,
              tmux: tmux,
              sessionName: _instance.tmuxSessionName,
            ),
          ),
        )
        .then((_) => _refresh());
  }

  Future<void> _confirmTerminate() async {
    final isProduction = _server?.environment == Environment.production;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Terminate Agent'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (isProduction)
              Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.red.shade900.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: Colors.red),
                ),
                child: const Text(
                  'CRITICAL: This is a PRODUCTION server.',
                  style: TextStyle(
                      color: Colors.redAccent,
                      fontWeight: FontWeight.bold,
                      fontSize: 12),
                ),
              ),
            Text(
                'Are you sure you want to terminate "${_instance.displayName ?? _instance.providerId}"?'),
            const SizedBox(height: 8),
            Text(
              'Session: ${_instance.tmuxSessionName}',
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Terminate'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      await widget.coordinator.terminateInstance(_instance, server: _server);
      if (mounted) {
        Navigator.of(context).pop();
      }
    }
  }

  Color _stateColor(AgentExecutionState state, bool isStale) {
    if (isStale) return Colors.grey;
    switch (state) {
      case AgentExecutionState.running:
        return Colors.green;
      case AgentExecutionState.waitingUser:
        return Colors.amber;
      case AgentExecutionState.finished:
        return Colors.blue;
      case AgentExecutionState.failed:
        return Colors.red;
      case AgentExecutionState.starting:
        return Colors.cyan;
      case AgentExecutionState.idle:
      case AgentExecutionState.unknown:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isConnected =
        widget.coordinator.connection.connectedProfileId == _instance.serverId;

    return Scaffold(
      appBar: AppBar(
        title: Text(_instance.displayName ?? _instance.providerId),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loading ? null : _refresh,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_server?.environment == Environment.production)
            Container(
              margin: const EdgeInsets.only(bottom: 16),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.red.shade900.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: Colors.red),
              ),
              child: const Row(
                children: [
                  Icon(Icons.warning, color: Colors.redAccent, size: 16),
                  SizedBox(width: 8),
                  Text(
                    'PRODUCTION SERVER',
                    style: TextStyle(
                        color: Colors.redAccent,
                        fontWeight: FontWeight.bold,
                        fontSize: 12),
                  ),
                ],
              ),
            ),
          if (_error != null)
            Container(
              margin: const EdgeInsets.only(bottom: 16),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.red.shade900.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: Colors.red.shade700),
              ),
              child: Row(
                children: [
                  const Icon(Icons.error_outline,
                      color: Colors.redAccent, size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _error!,
                      style: const TextStyle(
                          color: Colors.redAccent, fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: _stateColor(
                              _instance.executionState, _instance.isStale),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _instance.isStale
                            ? 'STALE (Session missing)'
                            : _instance.executionState.name.toUpperCase(),
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: _stateColor(
                              _instance.executionState, _instance.isStale),
                        ),
                      ),
                      const Spacer(),
                      if (_instance.observation != null)
                        Chip(
                          label: Text(
                            _instance.observation!.confidence.name
                                .toUpperCase(),
                            style: const TextStyle(fontSize: 10),
                          ),
                          padding: EdgeInsets.zero,
                          visualDensity: VisualDensity.compact,
                        ),
                    ],
                  ),
                  if (_instance.executionState ==
                          AgentExecutionState.waitingUser &&
                      !_instance.isStale) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.amber.shade900.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: Colors.amber),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.touch_app, color: Colors.amber, size: 18),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Agent is waiting for user input or approval.',
                              style: TextStyle(
                                  color: Colors.amber,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 12),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const Divider(height: 24),
                  _buildDetailRow(
                      'Server', _server?.name ?? _instance.serverId),
                  _buildDetailRow('Project ID', _instance.projectId),
                  _buildDetailRow('Working Dir', _instance.workingDirectory),
                  _buildDetailRow('Tmux Session', _instance.tmuxSessionName),
                  if (_instance.exitCode != null)
                    _buildDetailRow('Exit Code', '${_instance.exitCode}'),
                  if (_instance.observation?.detail != null)
                    _buildDetailRow(
                        'Observation', _instance.observation!.detail!),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          if (!isConnected)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Row(
                children: [
                  Icon(Icons.link_off, size: 20),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'SSH connection to server is currently disconnected. Remote agent continues in background.',
                      style: TextStyle(fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed:
                      isConnected && !_instance.isStale ? _openTerminal : null,
                  icon: const Icon(Icons.terminal),
                  label: const Text('Open Terminal'),
                ),
              ),
              const SizedBox(width: 12),
              OutlinedButton.icon(
                onPressed: isConnected && !_instance.isStale
                    ? _confirmTerminate
                    : null,
                style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
                icon: const Icon(Icons.stop),
                label: const Text('Terminate'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: const TextStyle(
                  color: Colors.grey,
                  fontSize: 12,
                  fontWeight: FontWeight.w500),
            ),
          ),
          Expanded(
            child: SelectableText(
              value,
              style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 12,
                  fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }
}
