import 'package:flutter/material.dart';

import '../../core/domain/agents.dart';
import '../../core/domain/profiles.dart';
import '../../shared/page_frame.dart';
import '../servers/domain/server_profile_repository.dart';
import 'application/agent_coordinator.dart';
import 'presentation/agent_detail_page.dart';

class AgentsPage extends StatefulWidget {
  const AgentsPage({
    super.key,
    this.coordinator,
    this.serverProfiles,
  });

  final AgentCoordinator? coordinator;
  final ServerProfileRepository? serverProfiles;

  @override
  State<AgentsPage> createState() => _AgentsPageState();
}

class _AgentsPageState extends State<AgentsPage> {
  bool _loading = false;
  List<AgentInstance> _instances = [];
  List<AgentDefinition> _definitions = [];
  Map<String, ServerProfile> _servers = {};
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final coordinator = widget.coordinator;
    if (coordinator == null) return;

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final allProfiles = widget.serverProfiles != null
          ? await widget.serverProfiles!.all()
          : <ServerProfile>[];
      final serverMap = {for (final s in allProfiles) s.id: s};

      final allInstances = await coordinator.instanceRepository.all();
      final connectedServerId = coordinator.connection.connectedProfileId;

      List<AgentDefinition> defs = [];
      if (connectedServerId != null) {
        defs = await coordinator.discoverAgents(connectedServerId);
      }

      if (mounted) {
        setState(() {
          _servers = serverMap;
          _instances = allInstances;
          _definitions = defs;
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
    final coordinator = widget.coordinator;
    if (coordinator == null) {
      return const PageFrame(
        title: 'Agents',
        subtitle: 'Coding agents run on your Linux servers',
        child: SummaryCard(
          title: 'Executions',
          value: 'No coordinator available',
          icon: Icons.smart_toy_outlined,
        ),
      );
    }

    final runningCount = _instances
        .where((i) =>
            i.executionState == AgentExecutionState.running && !i.isStale)
        .length;
    final waitingCount = _instances
        .where((i) =>
            i.executionState == AgentExecutionState.waitingUser && !i.isStale)
        .length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Agents'),
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
                  Row(
                    children: [
                      Expanded(
                        child: SummaryCard(
                          title: 'Running',
                          value: '$runningCount active',
                          icon: Icons.play_arrow,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: SummaryCard(
                          title: 'Waiting User',
                          value: '$waitingCount waiting',
                          icon: Icons.touch_app,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    'MANAGED AGENT INSTANCES',
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
                          'No agent instances registered yet. Launch agents from Projects or Servers.',
                          style: TextStyle(color: Colors.grey, fontSize: 13),
                        ),
                      ),
                    )
                  else
                    ..._instances.map(
                      (inst) {
                        final server = _servers[inst.serverId];
                        return Card(
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
                              '${server?.name ?? inst.serverId} • ${inst.isStale ? "STALE" : inst.executionState.name.toUpperCase()}',
                              style: TextStyle(
                                fontSize: 11,
                                color: _stateColor(
                                    inst.executionState, inst.isStale),
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            trailing: FilledButton.tonal(
                              onPressed: () {
                                Navigator.of(context)
                                    .push(
                                      MaterialPageRoute<void>(
                                        builder: (_) => AgentDetailPage(
                                          instance: inst,
                                          coordinator: coordinator,
                                          serverProfiles: widget.serverProfiles,
                                        ),
                                      ),
                                    )
                                    .then((_) => _load());
                              },
                              child: const Text('Open'),
                            ),
                          ),
                        );
                      },
                    ),
                  if (_definitions.isNotEmpty) ...[
                    const SizedBox(height: 24),
                    const Text(
                      'DISCOVERED PROVIDERS (CONNECTED SERVER)',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1,
                        color: Colors.grey,
                      ),
                    ),
                    const SizedBox(height: 8),
                    ..._definitions.map(
                      (def) => Card(
                        child: ListTile(
                          leading: Icon(
                            def.isAvailable
                                ? Icons.smart_toy
                                : Icons.smart_toy_outlined,
                            color: def.isAvailable ? Colors.green : Colors.grey,
                          ),
                          title: Text(def.displayName),
                          subtitle: Text(
                            def.isAvailable
                                ? 'Version: ${def.version ?? "available"}'
                                : 'Not installed',
                            style: TextStyle(
                              fontSize: 12,
                              color: def.isAvailable
                                  ? Colors.white70
                                  : Colors.grey,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
    );
  }
}
