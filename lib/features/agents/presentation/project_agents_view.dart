import 'package:flutter/material.dart';

import '../../../core/domain/agents.dart';
import '../../../core/domain/profiles.dart';
import '../../servers/domain/server_profile_repository.dart';
import '../application/agent_coordinator.dart';
import 'agent_detail_page.dart';

class ProjectAgentsView extends StatefulWidget {
  const ProjectAgentsView({
    super.key,
    required this.server,
    required this.project,
    required this.coordinator,
    this.serverProfiles,
  });

  final ServerProfile server;
  final ProjectProfile project;
  final AgentCoordinator coordinator;
  final ServerProfileRepository? serverProfiles;

  @override
  State<ProjectAgentsView> createState() => _ProjectAgentsViewState();
}

class _ProjectAgentsViewState extends State<ProjectAgentsView> {
  bool _loading = false;
  List<AgentDefinition> _definitions = [];
  List<AgentInstance> _instances = [];
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final defs = await widget.coordinator.discoverAgents(widget.server.id);
      final insts = await widget.coordinator.listInstances(
        serverId: widget.server.id,
        projectId: widget.project.id,
        refresh: true,
      );

      if (mounted) {
        setState(() {
          _definitions = defs;
          _instances = insts;
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

  Future<void> _launchAgent(AgentDefinition def) async {
    final provider = widget.coordinator.getProvider(def.providerId);
    if (provider == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Launch ${provider.displayName}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Project: ${widget.project.name}'),
            const SizedBox(height: 4),
            Text(
              'Directory: ${widget.project.workingDirectory}',
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            ),
            const SizedBox(height: 12),
            const Text(
              'The agent will start in a persistent tmux session on the server.',
              style: TextStyle(fontSize: 12, color: Colors.grey),
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
            child: const Text('Launch Agent'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      setState(() => _loading = true);
      try {
        final instance = await widget.coordinator.launch(
          server: widget.server,
          project: widget.project,
          provider: provider,
        );

        if (mounted) {
          await _load();
          if (mounted) {
            Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => AgentDetailPage(
                  instance: instance,
                  coordinator: widget.coordinator,
                  serverProfiles: widget.serverProfiles,
                ),
              ),
            );
          }
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
        widget.coordinator.connection.connectedProfileId == widget.server.id;

    return Scaffold(
      appBar: AppBar(
        title: Text('Agents — ${widget.project.name}'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loading ? null : _load,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  if (_error != null)
                    Container(
                      margin: const EdgeInsets.only(bottom: 16),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.red.shade900.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.red),
                      ),
                      child: Text(_error!,
                          style: const TextStyle(color: Colors.redAccent)),
                    ),
                  if (!isConnected)
                    Container(
                      margin: const EdgeInsets.only(bottom: 16),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Theme.of(context)
                            .colorScheme
                            .surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.link_off, size: 20),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'SSH is disconnected. Connect to the server to launch or inspect agents.',
                              style: TextStyle(fontSize: 12),
                            ),
                          ),
                        ],
                      ),
                    ),
                  const Text(
                    'ACTIVE INSTANCES',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1,
                      color: Colors.grey,
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (_instances.isEmpty)
                    const Card(
                      child: Padding(
                        padding: EdgeInsets.all(16),
                        child: Text(
                          'No agents currently running for this project.',
                          style: TextStyle(color: Colors.grey, fontSize: 13),
                        ),
                      ),
                    )
                  else
                    ..._instances.map(
                      (inst) => Card(
                        child: ListTile(
                          leading: Container(
                            width: 10,
                            height: 10,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: _stateColor(
                                  inst.executionState, inst.isStale),
                            ),
                          ),
                          title: Text(inst.displayName ?? inst.providerId),
                          subtitle: Text(
                            inst.isStale
                                ? 'STALE'
                                : inst.executionState.name.toUpperCase(),
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: _stateColor(
                                  inst.executionState, inst.isStale),
                            ),
                          ),
                          trailing: FilledButton.tonal(
                            onPressed: () {
                              Navigator.of(context)
                                  .push(
                                    MaterialPageRoute<void>(
                                      builder: (_) => AgentDetailPage(
                                        instance: inst,
                                        coordinator: widget.coordinator,
                                        serverProfiles: widget.serverProfiles,
                                      ),
                                    ),
                                  )
                                  .then((_) => _load());
                            },
                            child: const Text('Resume'),
                          ),
                        ),
                      ),
                    ),
                  const SizedBox(height: 24),
                  const Text(
                    'AVAILABLE PROVIDERS',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1,
                      color: Colors.grey,
                    ),
                  ),
                  const SizedBox(height: 8),
                  ..._definitions.map(
                    (def) {
                      final isPreferred =
                          widget.project.preferredAgentId == def.providerId;
                      return Card(
                        child: ListTile(
                          leading: Icon(
                            def.isAvailable
                                ? Icons.smart_toy
                                : Icons.smart_toy_outlined,
                            color: def.isAvailable ? Colors.green : Colors.grey,
                          ),
                          title: Row(
                            children: [
                              Text(def.displayName),
                              if (isPreferred) ...[
                                const SizedBox(width: 8),
                                const Chip(
                                  label: Text('PREFERRED',
                                      style: TextStyle(fontSize: 9)),
                                  padding: EdgeInsets.zero,
                                  visualDensity: VisualDensity.compact,
                                ),
                              ],
                            ],
                          ),
                          subtitle: Text(
                            def.isAvailable
                                ? 'Version: ${def.version ?? "installed"}'
                                : 'Not installed on server',
                            style: TextStyle(
                              fontSize: 12,
                              color: def.isAvailable
                                  ? Colors.white70
                                  : Colors.grey,
                            ),
                          ),
                          trailing: FilledButton(
                            onPressed: isConnected && def.isAvailable
                                ? () => _launchAgent(def)
                                : null,
                            child: const Text('Launch'),
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
    );
  }
}
