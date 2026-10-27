import 'package:flutter/material.dart';

/// Quick navigation action buttons bar for a project workspace.
class WorkspaceQuickActions extends StatelessWidget {
  const WorkspaceQuickActions({
    super.key,
    required this.onOpenTerminal,
    required this.onOpenFiles,
    required this.onOpenGit,
    required this.onOpenServer,
    this.onOpenAgents,
  });

  final VoidCallback onOpenTerminal;
  final VoidCallback onOpenFiles;
  final VoidCallback onOpenGit;
  final VoidCallback onOpenServer;
  final VoidCallback? onOpenAgents;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          _ActionButton(
            icon: Icons.terminal,
            label: 'Terminal',
            onTap: onOpenTerminal,
          ),
          const SizedBox(width: 8),
          _ActionButton(
            icon: Icons.folder_open,
            label: 'Files',
            onTap: onOpenFiles,
          ),
          const SizedBox(width: 8),
          _ActionButton(
            icon: Icons.commit,
            label: 'Git',
            onTap: onOpenGit,
          ),
          const SizedBox(width: 8),
          _ActionButton(
            icon: Icons.dns_outlined,
            label: 'Server',
            onTap: onOpenServer,
          ),
          if (onOpenAgents != null) ...[
            const SizedBox(width: 8),
            _ActionButton(
              icon: Icons.smart_toy_outlined,
              label: 'Agents',
              onTap: onOpenAgents!,
            ),
          ],
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
              color: colorScheme.outlineVariant.withValues(alpha: 0.4)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18, color: colorScheme.primary),
            const SizedBox(width: 6),
            Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
