import 'package:flutter/material.dart';

import '../../../core/domain/workspace.dart';

/// Prominent actionable card highlighting the most urgent workspace condition.
class WorkspaceAttentionBanner extends StatelessWidget {
  const WorkspaceAttentionBanner({
    super.key,
    required this.item,
    required this.onAction,
  });

  final WorkspaceAttentionItem item;
  final void Function(String route) onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final (color, icon) = switch (item.severity) {
      AttentionSeverity.critical => (Colors.red, Icons.error_outline),
      AttentionSeverity.actionRequired => (
          Colors.orange,
          Icons.notification_important_outlined
        ),
      AttentionSeverity.warning => (Colors.amber, Icons.warning_amber_outlined),
      AttentionSeverity.info => (Colors.teal, Icons.info_outline),
    };

    return Card(
      elevation: 2,
      margin: const EdgeInsets.only(bottom: 16),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: color, width: 1.5),
      ),
      color: color.withValues(alpha: 0.1),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: color, size: 22),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    item.title,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: color,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              item.message,
              style: theme.textTheme.bodyMedium?.copyWith(fontSize: 13),
            ),
            if (item.actionLabel != null && item.actionRoute != null) ...[
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: color,
                    foregroundColor: Colors.white,
                    visualDensity: VisualDensity.compact,
                  ),
                  onPressed: () => onAction(item.actionRoute!),
                  icon: const Icon(Icons.arrow_forward, size: 16),
                  label: Text(item.actionLabel!),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
