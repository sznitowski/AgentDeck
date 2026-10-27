import 'package:flutter/material.dart';

import '../../../core/domain/profiles.dart';
import '../../../core/domain/server_operations.dart';

/// Tab displaying systemd services with status filtering, detail inspection, and guarded actions.
class ServerServicesTab extends StatefulWidget {
  const ServerServicesTab({
    super.key,
    required this.server,
    required this.capabilities,
    required this.services,
    required this.serviceOperations,
    required this.onRefresh,
    this.loading = false,
  });

  final ServerProfile server;
  final ServerCapabilities capabilities;
  final List<SystemService> services;
  final ServerOperationsService serviceOperations;
  final Future<void> Function() onRefresh;
  final bool loading;

  @override
  State<ServerServicesTab> createState() => _ServerServicesTabState();
}

class _ServerServicesTabState extends State<ServerServicesTab> {
  String _searchQuery = '';
  String _filter = 'all'; // 'all', 'active', 'failed', 'inactive'
  bool _actionInProgress = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (!widget.capabilities.hasSystemd) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Card(
            elevation: 1,
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.info_outline,
                      size: 40, color: Colors.blueGrey),
                  const SizedBox(height: 12),
                  Text('Systemd Not Available',
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Text(
                    widget.capabilities.isAlpine
                        ? 'This host is running Alpine Linux with OpenRC/busybox init. Systemd unit discovery is not applicable.'
                        : 'This host does not utilize systemd as its service manager (or is running inside a lightweight container).',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 13, color: Colors.grey),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'CPU, Memory, Disk, and Process monitoring remain fully functional in the other tabs.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12, color: Colors.teal),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    final activeCount = widget.services.where((s) => s.isActive).length;
    final failedCount = widget.services.where((s) => s.isFailed).length;

    final filtered = widget.services.where((s) {
      if (_filter == 'active' && !s.isActive) return false;
      if (_filter == 'failed' && !s.isFailed) return false;
      if (_filter == 'inactive' && (s.isActive || s.isFailed)) return false;

      if (_searchQuery.isEmpty) return true;
      final q = _searchQuery.toLowerCase();
      return s.name.toLowerCase().contains(q) ||
          s.description.toLowerCase().contains(q);
    }).toList();

    return Column(
      children: [
        // Search & Filter Bar
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: TextField(
            decoration: InputDecoration(
              hintText: 'Search services by name or description...',
              prefixIcon: const Icon(Icons.search, size: 20),
              isDense: true,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            onChanged: (val) => setState(() => _searchQuery = val.trim()),
          ),
        ),

        // Filter Chips
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              ChoiceChip(
                label: Text('All (${widget.services.length})'),
                selected: _filter == 'all',
                onSelected: (_) => setState(() => _filter = 'all'),
              ),
              const SizedBox(width: 8),
              ChoiceChip(
                label: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.check_circle_outline,
                        size: 14, color: Colors.teal),
                    const SizedBox(width: 4),
                    Text('Active ($activeCount)'),
                  ],
                ),
                selected: _filter == 'active',
                onSelected: (_) => setState(() => _filter = 'active'),
              ),
              const SizedBox(width: 8),
              ChoiceChip(
                label: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.error_outline,
                        size: 14, color: Colors.red),
                    const SizedBox(width: 4),
                    Text('Failed ($failedCount)'),
                  ],
                ),
                selected: _filter == 'failed',
                onSelected: (_) => setState(() => _filter = 'failed'),
              ),
              const SizedBox(width: 8),
              ChoiceChip(
                label: const Text('Inactive'),
                selected: _filter == 'inactive',
                onSelected: (_) => setState(() => _filter = 'inactive'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),

        // Services List
        Expanded(
          child: widget.loading || _actionInProgress
              ? const Center(child: CircularProgressIndicator())
              : filtered.isEmpty
                  ? Center(
                      child: Text(
                        _searchQuery.isEmpty
                            ? 'No services found for selected filter.'
                            : 'No services match "$_searchQuery".',
                        style: const TextStyle(color: Colors.grey),
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: widget.onRefresh,
                      child: ListView.separated(
                        itemCount: filtered.length,
                        separatorBuilder: (context, index) =>
                            const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final s = filtered[index];
                          return ListTile(
                            dense: true,
                            leading: _buildStatusIcon(s.activeState),
                            title: Text(
                              s.name,
                              style: const TextStyle(
                                  fontWeight: FontWeight.w600, fontSize: 13),
                            ),
                            subtitle: Text(
                              s.description.isNotEmpty
                                  ? s.description
                                  : 'Substate: ${s.subState}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontSize: 11, color: Colors.grey),
                            ),
                            trailing:
                                _buildStatusChip(s.activeState, s.subState),
                            onTap: () => _showServiceDetails(s),
                          );
                        },
                      ),
                    ),
        ),
      ],
    );
  }

  Widget _buildStatusIcon(ServiceActiveState state) {
    return switch (state) {
      ServiceActiveState.active =>
        const Icon(Icons.check_circle, color: Colors.teal, size: 20),
      ServiceActiveState.failed =>
        const Icon(Icons.cancel, color: Colors.red, size: 20),
      ServiceActiveState.activating ||
      ServiceActiveState.reloading =>
        const Icon(Icons.sync, color: Colors.orange, size: 20),
      _ =>
        const Icon(Icons.radio_button_unchecked, color: Colors.grey, size: 20),
    };
  }

  Widget _buildStatusChip(ServiceActiveState state, String subState) {
    final color = switch (state) {
      ServiceActiveState.active => Colors.teal,
      ServiceActiveState.failed => Colors.red,
      ServiceActiveState.activating ||
      ServiceActiveState.reloading =>
        Colors.orange,
      _ => Colors.grey,
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color, width: 0.5),
      ),
      child: Text(
        subState.isNotEmpty ? subState : state.name,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.bold,
          color: color,
        ),
      ),
    );
  }

  Future<void> _showServiceDetails(SystemService service) async {
    final theme = Theme.of(context);

    SystemService detailed = service;
    try {
      detailed = await widget.serviceOperations.getServiceDetail(service.name);
    } catch (_) {}

    if (!mounted) return;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _buildStatusIcon(detailed.activeState),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    detailed.name,
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            if (detailed.description.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(detailed.description,
                  style: const TextStyle(fontSize: 12, color: Colors.grey)),
            ],
            const Divider(height: 20),

            _DetailRow(label: 'Load State', value: detailed.loadState),
            _DetailRow(label: 'Active State', value: detailed.activeState.name),
            _DetailRow(label: 'Sub State', value: detailed.subState),
            if (detailed.enabledState != null)
              _DetailRow(
                  label: 'Unit File State', value: detailed.enabledState!),
            if (detailed.mainPid != null)
              _DetailRow(label: 'Main PID', value: detailed.mainPid.toString()),

            const SizedBox(height: 20),

            // Guarded Action Buttons
            Text('Service Actions',
                style: theme.textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.play_arrow, size: 16),
                    label: const Text('Start'),
                    onPressed: () {
                      Navigator.pop(ctx);
                      _confirmAndExecuteAction('start', detailed.name);
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.restart_alt, size: 16),
                    label: const Text('Restart'),
                    onPressed: () {
                      Navigator.pop(ctx);
                      _confirmAndExecuteAction('restart', detailed.name);
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.stop, size: 16, color: Colors.red),
                    label:
                        const Text('Stop', style: TextStyle(color: Colors.red)),
                    onPressed: () {
                      Navigator.pop(ctx);
                      _confirmAndExecuteAction('stop', detailed.name);
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmAndExecuteAction(
      String action, String serviceName) async {
    final isProduction = widget.server.environment == Environment.production;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            if (isProduction) ...[
              const Icon(Icons.warning, color: Colors.red),
              const SizedBox(width: 8),
            ],
            Text('${action.toUpperCase()} Service?'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (isProduction) ...[
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.red.shade900.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: Colors.red),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.shield, color: Colors.red, size: 18),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'PRODUCTION SERVER: State changes can affect live traffic.',
                        style: TextStyle(
                            color: Colors.red,
                            fontWeight: FontWeight.bold,
                            fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
            ],
            Text(
              'Are you sure you want to execute systemctl $action for:',
              style: const TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Theme.of(ctx).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                '$serviceName\non ${widget.server.name} (${widget.server.host})',
                style: const TextStyle(
                    fontFamily: 'monospace',
                    fontWeight: FontWeight.bold,
                    fontSize: 12),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: isProduction || action == 'stop'
                ? FilledButton.styleFrom(backgroundColor: Colors.red)
                : null,
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Confirm ${action.toUpperCase()}'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _actionInProgress = true);
    try {
      if (action == 'start') {
        await widget.serviceOperations.startService(serviceName);
      } else if (action == 'stop') {
        await widget.serviceOperations.stopService(serviceName);
      } else if (action == 'restart') {
        await widget.serviceOperations.restartService(serviceName);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Successfully executed $action on $serviceName.'),
            backgroundColor: Colors.teal,
          ),
        );
      }
      await widget.onRefresh();
    } on ServerOperationFailure catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              e.kind == ServerOperationFailureKind.permissionDenied
                  ? 'Permission denied: unprivileged user cannot $action $serviceName.'
                  : 'Action failed: ${e.message ?? e.kind.name}',
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _actionInProgress = false);
    }
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          SizedBox(
            width: 110,
            child: Text(label,
                style: const TextStyle(color: Colors.grey, fontSize: 12)),
          ),
          Expanded(
            child: Text(value,
                style:
                    const TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
          ),
        ],
      ),
    );
  }
}
