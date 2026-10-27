import 'package:flutter/material.dart' hide ConnectionState;

import '../../../core/domain/agents.dart';
import '../../../core/domain/git.dart';
import '../../../core/domain/profiles.dart';
import '../../connections/application/ssh_connection_service.dart';
import '../application/git_service.dart';
import '../infrastructure/ssh_git_command_executor.dart';
import 'git_changes_page.dart';
import 'git_diff_viewer_page.dart';
import 'git_history_page.dart';

class ProjectGitPage extends StatefulWidget {
  const ProjectGitPage({
    super.key,
    required this.project,
    this.connection,
    this.service,
  });

  final ProjectProfile project;
  final SshConnectionService? connection;
  final GitService? service;

  @override
  State<ProjectGitPage> createState() => _ProjectGitPageState();
}

class _ProjectGitPageState extends State<ProjectGitPage> {
  bool _loading = false;
  GitStatus? _status;
  String? _error;
  bool _notRepository = false;
  bool _gitNotInstalled = false;

  late final GitService _service;

  @override
  void initState() {
    super.initState();
    _service = widget.service ??
        RemoteGitService(
          executor: SshGitCommandExecutor(
            connection: widget.connection!,
            serverId: widget.project.serverId,
          ),
        );
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
      _notRepository = false;
      _gitNotInstalled = false;
    });

    try {
      final isConnected = widget.connection == null ||
          (widget.connection!.state == ConnectionState.connected &&
              widget.connection!.connectedProfileId == widget.project.serverId);

      if (!isConnected) {
        if (mounted) {
          setState(() {
            _loading = false;
          });
        }
        return;
      }

      final avail = await _service.checkAvailability();
      if (!avail.isInstalled) {
        if (mounted) {
          setState(() {
            _gitNotInstalled = true;
            _loading = false;
          });
        }
        return;
      }

      final repo =
          await _service.inspectRepository(widget.project.workingDirectory);
      if (!repo.isRepository) {
        if (mounted) {
          setState(() {
            _notRepository = true;
            _loading = false;
          });
        }
        return;
      }

      final status = await _service.getStatus(widget.project.workingDirectory);

      if (mounted) {
        setState(() {
          _status = status;
          _loading = false;
        });
      }
    } on GitFailure catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          if (e.kind == GitFailureKind.notRepository) {
            _notRepository = true;
          } else if (e.kind == GitFailureKind.gitNotInstalled) {
            _gitNotInstalled = true;
          } else {
            _error = e.message ?? e.kind.name;
          }
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
    final isConnected = widget.connection == null ||
        (widget.connection!.state == ConnectionState.connected &&
            widget.connection!.connectedProfileId == widget.project.serverId);

    final isProduction = widget.project.environment == Environment.production;

    return Scaffold(
      appBar: AppBar(
        title: Text('Git — ${widget.project.name}'),
        actions: [
          if (isProduction)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 8, vertical: 12),
              child: Chip(
                label: Text('PRODUCTION',
                    style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: Colors.red)),
                visualDensity: VisualDensity.compact,
              ),
            ),
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
                  if (!isConnected)
                    Container(
                      margin: const EdgeInsets.only(bottom: 16),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Theme.of(context)
                            .colorScheme
                            .surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.link_off, size: 20),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'SSH is disconnected. Connect to the server to inspect or manage Git state.',
                              style: TextStyle(fontSize: 12),
                            ),
                          ),
                        ],
                      ),
                    ),
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
                  if (_gitNotInstalled)
                    const Card(
                      child: Padding(
                        padding: EdgeInsets.all(16),
                        child: Row(
                          children: [
                            Icon(Icons.warning, color: Colors.amber, size: 32),
                            SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Git is not installed on this server.',
                                    style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.bold),
                                  ),
                                  SizedBox(height: 4),
                                  Text(
                                    'Please install git on the remote host to enable Git operations.',
                                    style: TextStyle(
                                        fontSize: 12, color: Colors.grey),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                  else if (_notRepository)
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          children: [
                            const Icon(Icons.folder_off,
                                color: Colors.grey, size: 32),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Not a Git Repository',
                                    style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.bold),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Directory ${widget.project.workingDirectory} is not tracked by Git.',
                                    style: const TextStyle(
                                        fontSize: 12, color: Colors.grey),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                  else if (_status != null) ...[
                    _buildBranchCard(_status!),
                    const SizedBox(height: 16),
                    _buildMetricsGrid(_status!),
                    const SizedBox(height: 24),
                    _buildActionButtons(_status!, isConnected),
                  ],
                ],
              ),
            ),
    );
  }

  Widget _buildBranchCard(GitStatus status) {
    final branchName =
        status.isDetachedHead ? 'DETACHED HEAD' : (status.branch ?? 'Unknown');
    final headSha = status.headCommit != null
        ? (status.headCommit!.length > 7
            ? status.headCommit!.substring(0, 7)
            : status.headCommit!)
        : 'none';

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  status.isDetachedHead
                      ? Icons.alt_route
                      : Icons.call_split_rounded,
                  color:
                      status.isDetachedHead ? Colors.amber : Colors.blueAccent,
                ),
                const SizedBox(width: 8),
                Text(
                  branchName,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color:
                        Theme.of(context).colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    headSha,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Divider(),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  status.upstream != null
                      ? 'Upstream: ${status.upstream}'
                      : 'No upstream configured',
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
                if (status.ahead > 0 || status.behind > 0)
                  Text(
                    '+${status.ahead} / -${status.behind}',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Colors.cyan,
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMetricsGrid(GitStatus status) {
    return Row(
      children: [
        Expanded(
          child: _metricCard(
            title: 'CHANGES',
            value: status.changedFiles.length.toString(),
            color: status.changedFiles.isNotEmpty ? Colors.amber : Colors.green,
            icon: Icons.change_circle_outlined,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _metricCard(
            title: 'STAGED',
            value: status.stagedCount.toString(),
            color: status.stagedCount > 0 ? Colors.green : Colors.grey,
            icon: Icons.check_circle_outline,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _metricCard(
            title: 'UNTRACKED',
            value: status.untrackedCount.toString(),
            color: status.untrackedCount > 0 ? Colors.grey : Colors.grey,
            icon: Icons.help_outline,
          ),
        ),
        if (status.conflictCount > 0) ...[
          const SizedBox(width: 8),
          Expanded(
            child: _metricCard(
              title: 'CONFLICTS',
              value: status.conflictCount.toString(),
              color: Colors.red,
              icon: Icons.error_outline,
            ),
          ),
        ],
      ],
    );
  }

  Widget _metricCard({
    required String title,
    required String value,
    required Color color,
    required IconData icon,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
        child: Column(
          children: [
            Icon(icon, size: 20, color: color),
            const SizedBox(height: 4),
            Text(
              value,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              title,
              style: const TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.5,
                color: Colors.grey,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionButtons(GitStatus status, bool isConnected) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FilledButton.icon(
          onPressed: isConnected
              ? () {
                  Navigator.of(context)
                      .push(
                        MaterialPageRoute<void>(
                          builder: (_) => GitChangesPage(
                            project: widget.project,
                            service: _service,
                            initialStatus: status,
                          ),
                        ),
                      )
                      .then((_) => _load());
                }
              : null,
          icon: const Icon(Icons.list_alt),
          label: Text('View Changes (${status.changedFiles.length})'),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: isConnected
              ? () {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => GitHistoryPage(
                        project: widget.project,
                        service: _service,
                      ),
                    ),
                  );
                }
              : null,
          icon: const Icon(Icons.history),
          label: const Text('Commit History'),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: isConnected && status.unstagedCount > 0
                    ? () {
                        Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => GitDiffViewerPage(
                              project: widget.project,
                              service: _service,
                              staged: false,
                            ),
                          ),
                        );
                      }
                    : null,
                icon: const Icon(Icons.difference_outlined, size: 18),
                label: const Text('Unstaged Diff'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: isConnected && status.stagedCount > 0
                    ? () {
                        Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => GitDiffViewerPage(
                              project: widget.project,
                              service: _service,
                              staged: true,
                            ),
                          ),
                        );
                      }
                    : null,
                icon: const Icon(Icons.check_outlined, size: 18),
                label: const Text('Staged Diff'),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
