import 'package:flutter/material.dart' hide ConnectionState;

import '../../../core/domain/agents.dart';
import '../../../core/domain/profiles.dart';
import '../../../core/domain/server_operations.dart';
import '../../connections/application/ssh_connection_service.dart';
import '../application/server_operations_service.dart';
import '../infrastructure/ssh_server_command_executor.dart';
import 'server_overview_tab.dart';
import 'server_processes_tab.dart';
import 'server_services_tab.dart';

/// Main server operations and observability dashboard.
class ServerOperationsPage extends StatefulWidget {
  const ServerOperationsPage({
    super.key,
    required this.server,
    this.connection,
    this.service,
  });

  final ServerProfile server;
  final SshConnectionService? connection;
  final ServerOperationsService? service;

  @override
  State<ServerOperationsPage> createState() => _ServerOperationsPageState();
}

class _ServerOperationsPageState extends State<ServerOperationsPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  late final ServerOperationsService _service;

  bool _loading = false;
  String? _error;

  ServerCapabilities? _capabilities;
  ServerInfo? _info;
  ServerHealthSnapshot? _snapshot;
  List<RemoteProcess> _processes = [];
  List<SystemService> _services = [];
  DateTime? _lastObserved;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _service = widget.service ??
        RemoteServerOperationsService(
          executor: SshServerCommandExecutor(
            connection: widget.connection!,
            serverId: widget.server.id,
          ),
        );
    _loadAll();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadAll() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    final isConnected = widget.connection == null ||
        (widget.connection!.state == ConnectionState.connected &&
            widget.connection!.connectedProfileId == widget.server.id);

    if (!isConnected) {
      if (mounted) {
        setState(() => _loading = false);
      }
      return;
    }

    try {
      final caps = await _service.discoverCapabilities();
      final info = await _service.getHostInfo();
      final snapshot = await _service.getHealthSnapshot();
      final processes = await _service.getProcesses();
      final services =
          caps.hasSystemd ? await _service.getServices() : <SystemService>[];

      if (mounted) {
        setState(() {
          _capabilities = caps;
          _info = info;
          _snapshot = snapshot;
          _processes = processes;
          _services = services;
          _lastObserved = DateTime.now();
          _loading = false;
        });
      }
    } on ServerOperationFailure catch (e) {
      if (mounted) {
        setState(() {
          _error = e.message ?? e.kind.name;
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isProduction = widget.server.environment == Environment.production;

    final isConnected = widget.connection == null ||
        (widget.connection!.state == ConnectionState.connected &&
            widget.connection!.connectedProfileId == widget.server.id);

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Server Ops — ${widget.server.name}'),
            Text(
              '${widget.server.host}:${widget.server.port}',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: Colors.grey, fontSize: 11),
            ),
          ],
        ),
        actions: [
          if (isProduction)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 8, vertical: 12),
              child: Chip(
                label: Text(
                  'PRODUCTION',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: Colors.red,
                  ),
                ),
                visualDensity: VisualDensity.compact,
              ),
            ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loading ? null : _loadAll,
            tooltip: 'Refresh metrics',
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(icon: Icon(Icons.dashboard_outlined), text: 'Overview'),
            Tab(icon: Icon(Icons.terminal_outlined), text: 'Processes'),
            Tab(icon: Icon(Icons.settings_suggest_outlined), text: 'Services'),
          ],
        ),
      ),
      body: Column(
        children: [
          // Disconnected or Last-Observed Notification Banner
          if (!isConnected)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              color: Colors.amber.shade900.withValues(alpha: 0.2),
              child: Row(
                children: [
                  const Icon(Icons.cloud_off, size: 18, color: Colors.amber),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _lastObserved != null
                          ? 'DISCONNECTED — Displaying last observed state from ${_lastObserved!.toLocal().toString().split('.')[0]}.'
                          : 'SSH is disconnected. Connect to the server to observe metrics.',
                      style: const TextStyle(fontSize: 11, color: Colors.amber),
                    ),
                  ),
                ],
              ),
            ),

          if (_error != null)
            Container(
              margin: const EdgeInsets.all(16),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red.shade900.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.red),
              ),
              child: Row(
                children: [
                  const Icon(Icons.error_outline, color: Colors.red),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(_error!,
                        style: const TextStyle(color: Colors.redAccent)),
                  ),
                ],
              ),
            ),

          Expanded(
            child: _loading && _snapshot == null
                ? const Center(child: CircularProgressIndicator())
                : _snapshot == null
                    ? Center(
                        child: Text(
                          !isConnected
                              ? 'Server is disconnected. Tap Connect from Servers list.'
                              : 'No observation data available.',
                          style: const TextStyle(color: Colors.grey),
                        ),
                      )
                    : TabBarView(
                        controller: _tabController,
                        children: [
                          ServerOverviewTab(
                            snapshot: _snapshot!,
                            info: _info,
                            capabilities: _capabilities ??
                                const ServerCapabilities(
                                    isLinux: true,
                                    hasProcfs: true,
                                    hasSystemd: true),
                          ),
                          ServerProcessesTab(
                            processes: _processes,
                            onRefresh: _loadAll,
                            loading: _loading,
                          ),
                          ServerServicesTab(
                            server: widget.server,
                            capabilities: _capabilities ??
                                const ServerCapabilities(
                                    isLinux: true,
                                    hasProcfs: true,
                                    hasSystemd: true),
                            services: _services,
                            serviceOperations: _service,
                            onRefresh: _loadAll,
                            loading: _loading,
                          ),
                        ],
                      ),
          ),
        ],
      ),
    );
  }
}
