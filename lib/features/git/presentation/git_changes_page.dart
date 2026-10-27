import 'package:flutter/material.dart';

import '../../../core/domain/git.dart';
import '../../../core/domain/profiles.dart';
import 'git_diff_viewer_page.dart';

class GitChangesPage extends StatefulWidget {
  const GitChangesPage({
    super.key,
    required this.project,
    required this.service,
    this.initialStatus,
  });

  final ProjectProfile project;
  final GitService service;
  final GitStatus? initialStatus;

  @override
  State<GitChangesPage> createState() => _GitChangesPageState();
}

class _GitChangesPageState extends State<GitChangesPage> {
  bool _loading = false;
  GitStatus? _status;
  String? _error;
  String? _actionInProgress;

  @override
  void initState() {
    super.initState();
    _status = widget.initialStatus;
    if (_status == null) {
      _load();
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final status =
          await widget.service.getStatus(widget.project.workingDirectory);
      if (mounted) {
        setState(() {
          _status = status;
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

  Future<void> _stageFile(GitFileChange change) async {
    if (widget.project.environment == Environment.production) {
      final confirmed = await _confirmProductionAction(
        title: 'Confirm Stage in PRODUCTION',
        actionLabel: 'Stage File',
        details: 'Project: ${widget.project.name}\nFile: ${change.path}',
      );
      if (confirmed != true) return;
    }

    setState(() => _actionInProgress = change.path);
    try {
      await widget.service.stage(widget.project.workingDirectory, change.path);
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Stage failed: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _actionInProgress = null);
      }
    }
  }

  Future<void> _unstageFile(GitFileChange change) async {
    if (widget.project.environment == Environment.production) {
      final confirmed = await _confirmProductionAction(
        title: 'Confirm Unstage in PRODUCTION',
        actionLabel: 'Unstage File',
        details: 'Project: ${widget.project.name}\nFile: ${change.path}',
      );
      if (confirmed != true) return;
    }

    setState(() => _actionInProgress = change.path);
    try {
      await widget.service
          .unstage(widget.project.workingDirectory, change.path);
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Unstage failed: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _actionInProgress = null);
      }
    }
  }

  Future<void> _openCommitDialog() async {
    final controller = TextEditingController();
    final stagedFiles =
        _status?.changedFiles.where((f) => f.isStaged).toList() ?? [];

    if (stagedFiles.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No staged changes to commit.')),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            const Text('Create Commit'),
            if (widget.project.environment == Environment.production) ...[
              const SizedBox(width: 8),
              const Chip(
                label: Text('PRODUCTION',
                    style: TextStyle(
                        fontSize: 10,
                        color: Colors.red,
                        fontWeight: FontWeight.bold)),
                visualDensity: VisualDensity.compact,
              ),
            ],
          ],
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Staged Files (${stagedFiles.length}):',
                style:
                    const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
              ),
              const SizedBox(height: 4),
              Container(
                constraints: const BoxConstraints(maxHeight: 120),
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final file in stagedFiles)
                      Text(
                        file.path,
                        style: const TextStyle(
                            fontFamily: 'monospace', fontSize: 11),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: controller,
                autofocus: true,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Commit Message',
                  hintText: 'Enter a concise summary of changes...',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (controller.text.trim().isNotEmpty) {
                Navigator.of(ctx).pop(true);
              }
            },
            child: const Text('Commit'),
          ),
        ],
      ),
    );

    if (confirmed == true && controller.text.trim().isNotEmpty) {
      final msg = controller.text.trim();
      setState(() => _loading = true);
      try {
        final commit =
            await widget.service.commit(widget.project.workingDirectory, msg);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content:
                    Text('Committed ${commit.shortHash}: ${commit.subject}')),
          );
          await _load();
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
  }

  Future<bool?> _confirmProductionAction({
    required String title,
    required String actionLabel,
    required String details,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.warning, color: Colors.red),
            const SizedBox(width: 8),
            Text(title),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'You are modifying repository state on a PRODUCTION server.',
              style: TextStyle(fontWeight: FontWeight.bold, color: Colors.red),
            ),
            const SizedBox(height: 12),
            Text(
              details,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(actionLabel),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final status = _status;
    final staged = status?.changedFiles.where((f) => f.isStaged).toList() ?? [];
    final unstaged = status?.changedFiles
            .where((f) => f.isUnstaged && !f.isUntracked && !f.isConflict)
            .toList() ??
        [];
    final untracked =
        status?.changedFiles.where((f) => f.isUntracked).toList() ?? [];
    final conflicts =
        status?.changedFiles.where((f) => f.isConflict).toList() ?? [];

    return Scaffold(
      appBar: AppBar(
        title: Text('Changes — ${widget.project.name}'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loading ? null : _load,
          ),
        ],
      ),
      bottomNavigationBar: staged.isNotEmpty
          ? Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                border: Border(
                  top: BorderSide(
                    color: Theme.of(context).dividerColor,
                  ),
                ),
              ),
              child: SafeArea(
                child: FilledButton.icon(
                  onPressed: _loading ? null : _openCommitDialog,
                  icon: const Icon(Icons.check),
                  label: Text('Commit Staged Changes (${staged.length})'),
                ),
              ),
            )
          : null,
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      'Error: $_error',
                      style: const TextStyle(color: Colors.red),
                    ),
                  ),
                )
              : status == null || status.isClean
                  ? const Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.check_circle_outline,
                              size: 48, color: Colors.green),
                          SizedBox(height: 12),
                          Text(
                            'Working tree is clean',
                            style: TextStyle(
                                fontSize: 16, fontWeight: FontWeight.bold),
                          ),
                          SizedBox(height: 4),
                          Text(
                            'No modified, staged, or untracked files.',
                            style: TextStyle(color: Colors.grey, fontSize: 12),
                          ),
                        ],
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView(
                        padding: const EdgeInsets.all(12),
                        children: [
                          if (conflicts.isNotEmpty) ...[
                            _sectionHeader('MERGE CONFLICTS', Colors.red),
                            for (final file in conflicts)
                              _fileTile(file, isStagedSection: false),
                            const SizedBox(height: 16),
                          ],
                          if (staged.isNotEmpty) ...[
                            _sectionHeader('STAGED CHANGES', Colors.green),
                            for (final file in staged)
                              _fileTile(file, isStagedSection: true),
                            const SizedBox(height: 16),
                          ],
                          if (unstaged.isNotEmpty) ...[
                            _sectionHeader('UNSTAGED CHANGES', Colors.amber),
                            for (final file in unstaged)
                              _fileTile(file, isStagedSection: false),
                            const SizedBox(height: 16),
                          ],
                          if (untracked.isNotEmpty) ...[
                            _sectionHeader('UNTRACKED FILES', Colors.grey),
                            for (final file in untracked)
                              _fileTile(file, isStagedSection: false),
                          ],
                        ],
                      ),
                    ),
    );
  }

  Widget _sectionHeader(String title, Color color) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6, top: 4),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.bold,
          letterSpacing: 1,
          color: color,
        ),
      ),
    );
  }

  Widget _fileTile(GitFileChange change, {required bool isStagedSection}) {
    final busy = _actionInProgress == change.path;

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
        leading: _statusBadge(change, isStagedSection),
        title: Text(
          change.path,
          style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
        ),
        subtitle: change.oldPath != null
            ? Text(
                'renamed from ${change.oldPath}',
                style: const TextStyle(
                    fontFamily: 'monospace', fontSize: 11, color: Colors.grey),
              )
            : null,
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (busy)
              const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else if (isStagedSection)
              IconButton(
                icon: const Icon(Icons.remove_circle_outline, size: 20),
                tooltip: 'Unstage',
                onPressed: () => _unstageFile(change),
              )
            else if (!change.isConflict)
              IconButton(
                icon: const Icon(Icons.add_circle_outline, size: 20),
                tooltip: 'Stage',
                onPressed: () => _stageFile(change),
              ),
            IconButton(
              icon: const Icon(Icons.visibility_outlined, size: 20),
              tooltip: 'View Diff',
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => GitDiffViewerPage(
                      project: widget.project,
                      service: widget.service,
                      filePath: change.path,
                      staged: isStagedSection,
                    ),
                  ),
                );
              },
            ),
          ],
        ),
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => GitDiffViewerPage(
                project: widget.project,
                service: widget.service,
                filePath: change.path,
                staged: isStagedSection,
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _statusBadge(GitFileChange change, bool isStagedSection) {
    if (change.isConflict) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        decoration: BoxDecoration(
          color: Colors.red.shade900.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: Colors.red),
        ),
        child: const Text('CONFLICT',
            style: TextStyle(
                fontSize: 9, fontWeight: FontWeight.bold, color: Colors.red)),
      );
    }

    final status = isStagedSection ? change.indexStatus : change.workTreeStatus;
    String label;
    Color color;

    switch (status) {
      case GitFileStatus.added:
        label = 'A';
        color = Colors.green;
        break;
      case GitFileStatus.deleted:
        label = 'D';
        color = Colors.red;
        break;
      case GitFileStatus.renamed:
        label = 'R';
        color = Colors.cyan;
        break;
      case GitFileStatus.copied:
        label = 'C';
        color = Colors.teal;
        break;
      case GitFileStatus.untracked:
        label = '?';
        color = Colors.grey;
        break;
      case GitFileStatus.conflict:
        label = 'U';
        color = Colors.red;
        break;
      case GitFileStatus.modified:
      default:
        label = 'M';
        color = Colors.amber;
        break;
    }

    return Container(
      width: 24,
      height: 24,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.2),
        shape: BoxShape.circle,
        border: Border.all(color: color),
      ),
      child: Text(
        label,
        style:
            TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: color),
      ),
    );
  }
}
