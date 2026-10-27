import 'package:flutter/material.dart';

import '../../../core/domain/server_operations.dart';

/// Tab displaying the running processes with sorting, filtering, and argument privacy.
class ServerProcessesTab extends StatefulWidget {
  const ServerProcessesTab({
    super.key,
    required this.processes,
    required this.onRefresh,
    this.loading = false,
  });

  final List<RemoteProcess> processes;
  final Future<void> Function() onRefresh;
  final bool loading;

  @override
  State<ServerProcessesTab> createState() => _ServerProcessesTabState();
}

class _ServerProcessesTabState extends State<ServerProcessesTab> {
  String _searchQuery = '';
  String _sortField = 'cpu'; // 'cpu', 'memory', 'pid', 'name'
  bool _descending = true;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final filtered = widget.processes.where((p) {
      if (_searchQuery.isEmpty) return true;
      final q = _searchQuery.toLowerCase();
      return p.command.toLowerCase().contains(q) ||
          p.pid.toString().contains(q) ||
          (p.user?.toLowerCase().contains(q) ?? false);
    }).toList();

    filtered.sort((a, b) {
      final cmp = switch (_sortField) {
        'cpu' => a.cpuPercent.compareTo(b.cpuPercent),
        'memory' => a.memoryPercent.compareTo(b.memoryPercent),
        'pid' => a.pid.compareTo(b.pid),
        'name' => a.command.toLowerCase().compareTo(b.command.toLowerCase()),
        _ => a.cpuPercent.compareTo(b.cpuPercent),
      };
      return _descending ? -cmp : cmp;
    });

    return Column(
      children: [
        // Privacy Banner & Controls
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
          child: Row(
            children: [
              const Icon(Icons.shield_outlined, size: 16, color: Colors.teal),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Command arguments are masked to protect credentials and API tokens.',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(fontSize: 11, color: Colors.grey.shade400),
                ),
              ),
            ],
          ),
        ),

        // Search and Sort Bar
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  decoration: InputDecoration(
                    hintText: 'Search processes (name, PID, user)...',
                    prefixIcon: const Icon(Icons.search, size: 20),
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  onChanged: (val) => setState(() => _searchQuery = val.trim()),
                ),
              ),
              const SizedBox(width: 8),
              PopupMenuButton<String>(
                icon: const Icon(Icons.sort),
                tooltip: 'Sort by',
                initialValue: _sortField,
                onSelected: (field) {
                  setState(() {
                    if (_sortField == field) {
                      _descending = !_descending;
                    } else {
                      _sortField = field;
                      _descending = true;
                    }
                  });
                },
                itemBuilder: (context) => [
                  const PopupMenuItem(
                      value: 'cpu', child: Text('Sort by CPU %')),
                  const PopupMenuItem(
                      value: 'memory', child: Text('Sort by Memory %')),
                  const PopupMenuItem(value: 'pid', child: Text('Sort by PID')),
                  const PopupMenuItem(
                      value: 'name', child: Text('Sort by Name')),
                ],
              ),
            ],
          ),
        ),

        // Process List Header
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Row(
            children: [
              Text(
                '${filtered.length} processes (sorted by ${_sortField.toUpperCase()} ${_descending ? '↓' : '↑'})',
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ],
          ),
        ),

        // Process List
        Expanded(
          child: widget.loading
              ? const Center(child: CircularProgressIndicator())
              : filtered.isEmpty
                  ? Center(
                      child: Text(
                        _searchQuery.isEmpty
                            ? 'No processes observed.'
                            : 'No processes match "$_searchQuery".',
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
                          final p = filtered[index];
                          return ListTile(
                            dense: true,
                            leading: Container(
                              width: 50,
                              alignment: Alignment.centerLeft,
                              child: Text(
                                '${p.pid}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                  fontFamily: 'monospace',
                                ),
                              ),
                            ),
                            title: Text(
                              p.command,
                              style: const TextStyle(
                                  fontWeight: FontWeight.w600, fontSize: 13),
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Text(
                              'User: ${p.user ?? 'unknown'} · State: ${p.state.name}',
                              style: const TextStyle(
                                  fontSize: 11, color: Colors.grey),
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                _ResourceBadge(
                                  label: 'CPU',
                                  value: '${p.cpuPercent.toStringAsFixed(1)}%',
                                  highlight: p.cpuPercent > 10.0,
                                ),
                                const SizedBox(width: 6),
                                _ResourceBadge(
                                  label: 'MEM',
                                  value:
                                      '${p.memoryPercent.toStringAsFixed(1)}%',
                                  highlight: p.memoryPercent > 10.0,
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
        ),
      ],
    );
  }
}

class _ResourceBadge extends StatelessWidget {
  const _ResourceBadge({
    required this.label,
    required this.value,
    this.highlight = false,
  });

  final String label;
  final String value;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: highlight
            ? Colors.orange.withValues(alpha: 0.2)
            : Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(4),
        border: highlight ? Border.all(color: Colors.orange, width: 0.5) : null,
      ),
      child: Text(
        '$label $value',
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.bold,
          color: highlight ? Colors.orange : null,
          fontFamily: 'monospace',
        ),
      ),
    );
  }
}
