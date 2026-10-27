import 'package:flutter/material.dart';

import '../../../core/domain/server_operations.dart';

/// Tab displaying the aggregated resource metrics, load averages, and host metadata.
class ServerOverviewTab extends StatelessWidget {
  const ServerOverviewTab({
    super.key,
    required this.snapshot,
    required this.info,
    required this.capabilities,
  });

  final ServerHealthSnapshot snapshot;
  final ServerInfo? info;
  final ServerCapabilities capabilities;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Resource Summary Cards (CPU & RAM)
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _MetricCard(
                title: 'CPU Usage',
                icon: Icons.speed,
                percentage: snapshot.cpu.totalPercent,
                valueText: '${snapshot.cpu.totalPercent.toStringAsFixed(1)}%',
                subtitle: '${snapshot.processCount} processes',
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _MetricCard(
                title: 'Memory',
                icon: Icons.memory,
                percentage: snapshot.memory.usagePercent,
                valueText:
                    '${snapshot.memory.usagePercent.toStringAsFixed(1)}%',
                subtitle:
                    '${_formatBytes(snapshot.memory.usedBytes)} / ${_formatBytes(snapshot.memory.totalBytes)}',
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),

        // Swap and Load Averages
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _MetricCard(
                title: 'Swap',
                icon: Icons.swap_horiz,
                percentage: snapshot.memory.swapUsagePercent,
                valueText:
                    '${snapshot.memory.swapUsagePercent.toStringAsFixed(1)}%',
                subtitle: snapshot.memory.swapTotalBytes > 0
                    ? '${_formatBytes(snapshot.memory.swapUsedBytes)} / ${_formatBytes(snapshot.memory.swapTotalBytes)}'
                    : 'No swap configured',
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Card(
                elevation: 1,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.query_stats,
                              size: 20, color: colorScheme.primary),
                          const SizedBox(width: 8),
                          Text('Load Average',
                              style: theme.textTheme.titleSmall),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          _LoadChip(label: '1m', value: snapshot.loadAvg1m),
                          _LoadChip(label: '5m', value: snapshot.loadAvg5m),
                          _LoadChip(label: '15m', value: snapshot.loadAvg15m),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text('Runnable / total kernel queues',
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: Colors.grey)),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),

        // Filesystem Disk Usage Card
        Card(
          elevation: 1,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.storage, size: 20, color: colorScheme.primary),
                    const SizedBox(width: 8),
                    Text('Filesystem & Disks',
                        style: theme.textTheme.titleMedium),
                  ],
                ),
                const SizedBox(height: 12),
                if (snapshot.disks.isEmpty)
                  const Text('No filesystem information reported.',
                      style: TextStyle(color: Colors.grey))
                else
                  for (final disk in snapshot.disks) ...[
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(disk.mountPoint,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold)),
                              Text(
                                '${_formatBytes(disk.usedBytes)} / ${_formatBytes(disk.totalBytes)} (${disk.usagePercent.toStringAsFixed(1)}%)',
                                style: const TextStyle(fontSize: 12),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: LinearProgressIndicator(
                              value:
                                  (disk.usagePercent / 100.0).clamp(0.0, 1.0),
                              minHeight: 8,
                              backgroundColor:
                                  colorScheme.surfaceContainerHighest,
                              color: _getUsageColor(disk.usagePercent),
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text('fs: ${disk.filesystem}',
                              style: theme.textTheme.bodySmall
                                  ?.copyWith(color: Colors.grey, fontSize: 10)),
                        ],
                      ),
                    ),
                    const Divider(height: 12),
                  ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),

        // Host Details & Uptime
        if (info != null)
          Card(
            elevation: 1,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.info_outline,
                          size: 20, color: colorScheme.primary),
                      const SizedBox(width: 8),
                      Text('System & Host Identity',
                          style: theme.textTheme.titleMedium),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _InfoRow(label: 'Hostname', value: info!.hostname),
                  _InfoRow(
                      label: 'Operating System',
                      value: '${info!.osName} ${info!.osVersion}'.trim()),
                  _InfoRow(label: 'Kernel', value: info!.kernel),
                  _InfoRow(label: 'Architecture', value: info!.architecture),
                  _InfoRow(label: 'Uptime', value: info!.formattedUptime),
                  if (info!.bootTime != null)
                    _InfoRow(
                      label: 'Boot Time',
                      value: info!.bootTime!.toLocal().toString().split('.')[0],
                    ),
                  _InfoRow(
                    label: 'Service Manager',
                    value: capabilities.hasSystemd
                        ? 'systemd'
                        : (capabilities.isAlpine
                            ? 'OpenRC / Alpine'
                            : 'Non-systemd init'),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  static String _formatBytes(int bytes) {
    if (bytes >= 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
    } else if (bytes >= 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    } else if (bytes >= 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    } else {
      return '$bytes B';
    }
  }

  static Color _getUsageColor(double percent) {
    if (percent >= 90) return Colors.red;
    if (percent >= 75) return Colors.orange;
    return Colors.teal;
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.title,
    required this.icon,
    required this.percentage,
    required this.valueText,
    required this.subtitle,
  });

  final String title;
  final IconData icon;
  final double percentage;
  final String valueText;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final color = ServerOverviewTab._getUsageColor(percentage);

    return Card(
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 20, color: colorScheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(title,
                      style: theme.textTheme.titleSmall,
                      overflow: TextOverflow.ellipsis),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(valueText,
                style: theme.textTheme.headlineSmall
                    ?.copyWith(fontWeight: FontWeight.bold, color: color)),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: (percentage / 100.0).clamp(0.0, 1.0),
                minHeight: 6,
                backgroundColor: colorScheme.surfaceContainerHighest,
                color: color,
              ),
            ),
            const SizedBox(height: 6),
            Text(subtitle,
                style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey)),
          ],
        ),
      ),
    );
  }
}

class _LoadChip extends StatelessWidget {
  const _LoadChip({required this.label, required this.value});

  final String label;
  final double value;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(label, style: const TextStyle(fontSize: 10, color: Colors.grey)),
        const SizedBox(height: 2),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            value.toStringAsFixed(2),
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
          ),
        ),
      ],
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(label,
                style: const TextStyle(color: Colors.grey, fontSize: 12)),
          ),
          Expanded(
            child: SelectableText(
              value,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }
}
