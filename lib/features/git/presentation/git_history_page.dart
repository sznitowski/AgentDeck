import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/domain/git.dart';
import '../../../core/domain/profiles.dart';

class GitHistoryPage extends StatefulWidget {
  const GitHistoryPage({
    super.key,
    required this.project,
    required this.service,
  });

  final ProjectProfile project;
  final GitService service;

  @override
  State<GitHistoryPage> createState() => _GitHistoryPageState();
}

class _GitHistoryPageState extends State<GitHistoryPage> {
  bool _loading = true;
  List<GitCommit> _commits = [];
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final commits =
          await widget.service.getHistory(widget.project.workingDirectory);
      if (mounted) {
        setState(() {
          _commits = commits;
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
    return Scaffold(
      appBar: AppBar(
        title: Text('History — ${widget.project.name}'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loading ? null : _load,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      'Failed to load history: $_error',
                      style: const TextStyle(color: Colors.red),
                    ),
                  ),
                )
              : _commits.isEmpty
                  ? const Center(
                      child: Text(
                        'No commits found in this repository.',
                        style: TextStyle(color: Colors.grey),
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView.separated(
                        padding: const EdgeInsets.all(12),
                        itemCount: _commits.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final commit = _commits[index];
                          return ListTile(
                            leading: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 3),
                              decoration: BoxDecoration(
                                color: Theme.of(context)
                                    .colorScheme
                                    .surfaceContainerHighest,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                commit.shortHash,
                                style: const TextStyle(
                                  fontFamily: 'monospace',
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            title: Text(
                              commit.subject,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 14),
                            ),
                            subtitle: Text(
                              '${commit.authorName} · ${_formatDate(commit.timestamp)}',
                              style: const TextStyle(
                                  fontSize: 11, color: Colors.grey),
                            ),
                            trailing: const Icon(Icons.chevron_right, size: 18),
                            onTap: () {
                              Navigator.of(context).push(
                                MaterialPageRoute<void>(
                                  builder: (_) => GitCommitDetailPage(
                                    project: widget.project,
                                    commit: commit,
                                    service: widget.service,
                                  ),
                                ),
                              );
                            },
                          );
                        },
                      ),
                    ),
    );
  }

  String _formatDate(DateTime dt) {
    final now = DateTime.now().toUtc();
    final diff = now.difference(dt);
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 30) return '${diff.inDays}d ago';
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
  }
}

class GitCommitDetailPage extends StatelessWidget {
  const GitCommitDetailPage({
    super.key,
    required this.project,
    required this.commit,
    required this.service,
  });

  final ProjectProfile project;
  final GitCommit commit;
  final GitService service;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Commit ${commit.shortHash}'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    commit.subject,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Divider(),
                  const SizedBox(height: 8),
                  _detailRow(context, 'Full Hash', commit.hash, copyable: true),
                  _detailRow(context, 'Author',
                      '${commit.authorName}${commit.authorEmail != null ? " <${commit.authorEmail}>" : ""}'),
                  _detailRow(
                      context, 'Date', commit.timestamp.toIso8601String()),
                  if (commit.parents.isNotEmpty)
                    _detailRow(
                      context,
                      'Parents',
                      commit.parents
                          .map((p) => p.length > 7 ? p.substring(0, 7) : p)
                          .join(', '),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _detailRow(BuildContext context, String label, String value,
      {bool copyable = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 12,
                color: Colors.grey,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 12,
              ),
            ),
          ),
          if (copyable)
            IconButton(
              icon: const Icon(Icons.copy, size: 16),
              visualDensity: VisualDensity.compact,
              tooltip: 'Copy',
              onPressed: () {
                Clipboard.setData(ClipboardData(text: value));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Copied to clipboard')),
                );
              },
            ),
        ],
      ),
    );
  }
}
