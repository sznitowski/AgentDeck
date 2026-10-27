import 'package:flutter/material.dart';

import '../../../core/domain/agents.dart';
import '../../../core/domain/workspace.dart';

/// Workspace card presenting current agent execution state and quick CTAs.
class WorkspaceAgentCard extends StatelessWidget {
  const WorkspaceAgentCard({
    super.key,
    required this.agent,
    required this.onOpenAgent,
    required this.onOpenTerminal,
    required this.onLaunchAgent,
  });

  final WorkspaceAgentSummary? agent;
  final VoidCallback onOpenAgent;
  final VoidCallback onOpenTerminal;
  final VoidCallback onLaunchAgent;

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
                Icon(Icons.smart_toy_outlined,
                    size: 20, color: colorScheme.primary),
                const SizedBox(width: 8),
                Text('Agent Orchestration', style: theme.textTheme.titleMedium),
                const Spacer(),
                if (agent != null && agent!.state != null)
                  _buildStateBadge(agent!.state!),
              ],
            ),
            const SizedBox(height: 12),
            if (agent == null) ...[
              const Text(
                'No active background agent running for this project.',
                style: TextStyle(color: Colors.grey, fontSize: 13),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: onLaunchAgent,
                icon: const Icon(Icons.add, size: 16),
                label: const Text('Launch Agent'),
              ),
            ] else ...[
              Row(
                children: [
                  Text(
                    agent!.providerName ?? 'CLI Agent',
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 15),
                  ),
                  if (agent!.confidence != null) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        agent!.confidence!.name.toUpperCase(),
                        style:
                            const TextStyle(fontSize: 10, color: Colors.grey),
                      ),
                    ),
                  ],
                ],
              ),
              if (agent!.tmuxSessionName != null) ...[
                const SizedBox(height: 4),
                Text(
                  'Session: ${agent!.tmuxSessionName}',
                  style: const TextStyle(
                      fontSize: 12,
                      color: Colors.grey,
                      fontFamily: 'monospace'),
                ),
              ],
              const SizedBox(height: 12),
              Row(
                children: [
                  if (agent!.isWaitingUser)
                    FilledButton.icon(
                      style: FilledButton.styleFrom(
                          backgroundColor: Colors.orange),
                      onPressed: onOpenTerminal,
                      icon: const Icon(Icons.reply, size: 16),
                      label: const Text('Respond to Prompt'),
                    )
                  else
                    OutlinedButton.icon(
                      onPressed: onOpenTerminal,
                      icon: const Icon(Icons.terminal, size: 16),
                      label: const Text('Open Agent Terminal'),
                    ),
                  const SizedBox(width: 8),
                  TextButton(
                    onPressed: onOpenAgent,
                    child: const Text('Manage'),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildStateBadge(AgentExecutionState state) {
    final (color, label) = switch (state) {
      AgentExecutionState.waitingUser => (Colors.orange, 'WAITING FOR INPUT'),
      AgentExecutionState.running => (Colors.teal, 'RUNNING'),
      AgentExecutionState.starting => (Colors.blue, 'STARTING'),
      AgentExecutionState.finished => (Colors.green, 'FINISHED'),
      AgentExecutionState.failed => (Colors.red, 'FAILED'),
      AgentExecutionState.idle => (Colors.blueGrey, 'IDLE'),
      _ => (Colors.grey, state.name.toUpperCase()),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color, width: 0.8),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.bold,
          fontSize: 10,
        ),
      ),
    );
  }
}
