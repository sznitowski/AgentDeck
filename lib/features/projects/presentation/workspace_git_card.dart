import 'package:flutter/material.dart';

import '../../../core/domain/workspace.dart';

/// Workspace card displaying Git branch, status counters, conflicts, and changes CTA.
class WorkspaceGitCard extends StatelessWidget {
  const WorkspaceGitCard({
    super.key,
    required this.git,
    required this.onViewChanges,
  });

  final WorkspaceGitSummary? git;
  final VoidCallback onViewChanges;

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
                Icon(Icons.commit_outlined,
                    size: 20, color: colorScheme.primary),
                const SizedBox(width: 8),
                Text('Git Repository', style: theme.textTheme.titleMedium),
                const Spacer(),
                if (git != null) _buildHeaderStatus(git!),
              ],
            ),
            const SizedBox(height: 12),
            if (git == null) ...[
              const Text(
                'Git status unavailable or not loaded.',
                style: TextStyle(color: Colors.grey, fontSize: 13),
              ),
            ] else if (git!.isGitMissing) ...[
              const Row(
                children: [
                  Icon(Icons.info_outline, size: 16, color: Colors.grey),
                  SizedBox(width: 6),
                  Text('Git CLI is not installed on remote server.',
                      style: TextStyle(fontSize: 13, color: Colors.grey)),
                ],
              ),
            ] else if (git!.isNotRepository) ...[
              const Row(
                children: [
                  Icon(Icons.folder_outlined, size: 16, color: Colors.grey),
                  SizedBox(width: 6),
                  Text('Working directory is not a Git repository.',
                      style: TextStyle(fontSize: 13, color: Colors.grey)),
                ],
              ),
            ] else if (git!.error != null) ...[
              Text(
                'Error inspecting repository: ${git!.error}',
                style: const TextStyle(fontSize: 13, color: Colors.red),
              ),
            ] else ...[
              Row(
                children: [
                  Icon(Icons.alt_route, size: 16, color: colorScheme.primary),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      git!.branch != null
                          ? git!.branch!
                          : (git!.isDetachedHead
                              ? 'Detached HEAD'
                              : 'Unknown branch'),
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 15),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (git!.shortHead.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        git!.shortHead,
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 11,
                          color: Colors.grey,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              if (git!.isClean) ...[
                const Row(
                  children: [
                    Icon(Icons.check_circle_outline,
                        size: 16, color: Colors.green),
                    SizedBox(width: 6),
                    Text(
                      'Working tree clean',
                      style: TextStyle(
                          fontSize: 13,
                          color: Colors.green,
                          fontWeight: FontWeight.w500),
                    ),
                  ],
                ),
              ] else ...[
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    if (git!.conflictCount > 0)
                      _buildChip(
                          '${git!.conflictCount} conflict${git!.conflictCount > 1 ? 's' : ''}',
                          Colors.red),
                    if (git!.stagedCount > 0)
                      _buildChip('${git!.stagedCount} staged', Colors.teal),
                    if (git!.unstagedCount > 0)
                      _buildChip(
                          '${git!.unstagedCount} unstaged', Colors.orange),
                    if (git!.untrackedCount > 0)
                      _buildChip(
                          '${git!.untrackedCount} untracked', Colors.blueGrey),
                  ],
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: onViewChanges,
                  icon: const Icon(Icons.compare_arrows, size: 16),
                  label: Text('View Changes (${git!.totalChanged})'),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildHeaderStatus(WorkspaceGitSummary git) {
    if (git.conflictCount > 0) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: Colors.red.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: Colors.red, width: 0.8),
        ),
        child: const Text(
          'CONFLICT',
          style: TextStyle(
              color: Colors.red, fontWeight: FontWeight.bold, fontSize: 10),
        ),
      );
    }
    if (git.isClean && !git.isNotRepository && !git.isGitMissing) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: Colors.green.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: Colors.green, width: 0.8),
        ),
        child: const Text(
          'CLEAN',
          style: TextStyle(
              color: Colors.green, fontWeight: FontWeight.bold, fontSize: 10),
        ),
      );
    }
    if (!git.isClean && git.totalChanged > 0) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: Colors.orange.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: Colors.orange, width: 0.8),
        ),
        child: Text(
          '${git.totalChanged} CHANGES',
          style: const TextStyle(
              color: Colors.orange, fontWeight: FontWeight.bold, fontSize: 10),
        ),
      );
    }
    return const SizedBox.shrink();
  }

  Widget _buildChip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style:
            TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w600),
      ),
    );
  }
}
