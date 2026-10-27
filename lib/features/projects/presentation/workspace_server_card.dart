import 'package:flutter/material.dart';

import '../../../core/domain/workspace.dart';

/// Workspace card presenting compact CPU, RAM, Disk, Load metrics, and server ops CTA.
class WorkspaceServerCard extends StatelessWidget {
  const WorkspaceServerCard({
    super.key,
    required this.serverHealth,
    required this.onOpenServerHealth,
  });

  final WorkspaceServerSummary? serverHealth;
  final VoidCallback onOpenServerHealth;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

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
                Icon(Icons.dns_outlined, size: 20, color: colorScheme.primary),
                const SizedBox(width: 8),
                Text('Server Health', style: theme.textTheme.titleMedium),
                const Spacer(),
                if (serverHealth != null) _buildHealthBadge(serverHealth!),
              ],
            ),
            const SizedBox(height: 12),
            if (serverHealth == null) ...[
              const Text(
                'Server telemetry unavailable or not connected.',
                style: TextStyle(color: Colors.grey, fontSize: 13),
              ),
            ] else if (serverHealth!.error != null) ...[
              Text(
                'Telemetry error: ${serverHealth!.error}',
                style: const TextStyle(fontSize: 13, color: Colors.red),
              ),
            ] else ...[
              Row(
                children: [
                  Expanded(
                    child: _buildMetricTile(
                      label: 'CPU',
                      value: serverHealth!.cpuPercent != null
                          ? '${serverHealth!.cpuPercent!.toStringAsFixed(1)}%'
                          : '--',
                      fraction: (serverHealth!.cpuPercent ?? 0) / 100,
                      colorScheme: colorScheme,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _buildMetricTile(
                      label: 'RAM',
                      value: serverHealth!.memoryPercent != null
                          ? '${serverHealth!.memoryPercent!.toStringAsFixed(1)}%'
                          : '--',
                      fraction: (serverHealth!.memoryPercent ?? 0) / 100,
                      colorScheme: colorScheme,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _buildMetricTile(
                      label: 'Disk',
                      value: serverHealth!.diskPercent != null
                          ? '${serverHealth!.diskPercent!.toStringAsFixed(1)}%'
                          : '--',
                      fraction: (serverHealth!.diskPercent ?? 0) / 100,
                      colorScheme: colorScheme,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _buildMetricTile(
                      label: 'Load 1m',
                      value: serverHealth!.load1m != null
                          ? serverHealth!.load1m!.toStringAsFixed(2)
                          : '--',
                      fraction:
                          ((serverHealth!.load1m ?? 0) / 4.0).clamp(0.0, 1.0),
                      colorScheme: colorScheme,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  if (serverHealth!.observedAt != null)
                    Text(
                      'Observed ${_formatTime(serverHealth!.observedAt!)}',
                      style: const TextStyle(fontSize: 11, color: Colors.grey),
                    )
                  else
                    const SizedBox.shrink(),
                  OutlinedButton.icon(
                    onPressed: onOpenServerHealth,
                    icon: const Icon(Icons.monitor_heart_outlined, size: 16),
                    label: const Text('Server Health'),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildMetricTile({
    required String label,
    required String value,
    required double fraction,
    required ColorScheme colorScheme,
  }) {
    final isHigh = fraction > 0.85;
    final valueColor =
        isHigh ? Colors.red : (fraction > 0.70 ? Colors.orange : null);

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey)),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: valueColor,
            ),
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: LinearProgressIndicator(
              value: fraction.clamp(0.0, 1.0),
              minHeight: 4,
              backgroundColor: Colors.grey.withValues(alpha: 0.2),
              valueColor: AlwaysStoppedAnimation<Color>(
                isHigh
                    ? Colors.red
                    : (fraction > 0.70 ? Colors.orange : Colors.teal),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHealthBadge(WorkspaceServerSummary health) {
    if (health.error != null) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: Colors.red.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: Colors.red, width: 0.8),
        ),
        child: const Text(
          'ERROR',
          style: TextStyle(
              color: Colors.red, fontWeight: FontWeight.bold, fontSize: 10),
        ),
      );
    }

    if (!health.isHealthy) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: Colors.orange.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: Colors.orange, width: 0.8),
        ),
        child: const Text(
          'HIGH LOAD',
          style: TextStyle(
              color: Colors.orange, fontWeight: FontWeight.bold, fontSize: 10),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.teal.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.teal, width: 0.8),
      ),
      child: const Text(
        'HEALTHY',
        style: TextStyle(
            color: Colors.teal, fontWeight: FontWeight.bold, fontSize: 10),
      ),
    );
  }

  String _formatTime(DateTime dt) {
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    final s = dt.second.toString().padLeft(2, '0');
    return '$h:$m:$s';
  }
}
