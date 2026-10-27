import 'package:flutter/material.dart';

import '../../../core/domain/git.dart';
import '../../../core/domain/profiles.dart';

class GitDiffViewerPage extends StatefulWidget {
  const GitDiffViewerPage({
    super.key,
    required this.project,
    required this.service,
    this.filePath,
    this.staged = false,
  });

  final ProjectProfile project;
  final GitService service;
  final String? filePath;
  final bool staged;

  @override
  State<GitDiffViewerPage> createState() => _GitDiffViewerPageState();
}

class _GitDiffViewerPageState extends State<GitDiffViewerPage> {
  bool _loading = true;
  GitDiff? _diff;
  String? _error;
  bool _revealedSensitive = false;

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
      final diff = await widget.service.getDiff(
        widget.project.workingDirectory,
        filePath: widget.filePath,
        staged: widget.staged,
      );

      if (mounted) {
        setState(() {
          _diff = diff;
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
    final title = widget.filePath != null
        ? widget.filePath!
        : (widget.staged ? 'Staged Diff' : 'Working Tree Diff');

    return Scaffold(
      appBar: AppBar(
        title: Text(
          title,
          style: const TextStyle(fontSize: 16),
          overflow: TextOverflow.ellipsis,
        ),
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
                      'Failed to load diff: $_error',
                      style: const TextStyle(color: Colors.red),
                    ),
                  ),
                )
              : _buildDiffContent(),
    );
  }

  Widget _buildDiffContent() {
    final diff = _diff!;

    if (diff.isSensitive && !_revealedSensitive) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.security, size: 48, color: Colors.amber),
              const SizedBox(height: 16),
              const Text(
                'Sensitive File Warning',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text(
                'This diff may contain secrets, private keys, or API tokens. Inspect only in a secure environment.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey, fontSize: 13),
              ),
              const SizedBox(height: 20),
              FilledButton.tonalIcon(
                onPressed: () => setState(() => _revealedSensitive = true),
                icon: const Icon(Icons.visibility),
                label: const Text('Reveal Diff'),
              ),
            ],
          ),
        ),
      );
    }

    if (diff.hunks.isEmpty && diff.rawText.trim().isEmpty) {
      return const Center(
        child: Text(
          'No changes in this diff.',
          style: TextStyle(color: Colors.grey),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Row(
          children: [
            Chip(
              label: Text(
                diff.isStaged ? 'STAGED' : 'UNSTAGED',
                style:
                    const TextStyle(fontSize: 10, fontWeight: FontWeight.bold),
              ),
              visualDensity: VisualDensity.compact,
            ),
            const SizedBox(width: 8),
            Text(
              '+${diff.additions} / -${diff.deletions}',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 12,
                color: diff.additions > 0 ? Colors.green : Colors.grey,
              ),
            ),
            if (diff.isSensitive) ...[
              const SizedBox(width: 8),
              const Chip(
                avatar: Icon(Icons.lock, size: 14, color: Colors.amber),
                label: Text('SENSITIVE', style: TextStyle(fontSize: 10)),
                visualDensity: VisualDensity.compact,
              ),
            ],
          ],
        ),
        if (diff.isTruncated)
          Container(
            margin: const EdgeInsets.symmetric(vertical: 8),
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.amber.shade900.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: Colors.amber),
            ),
            child: const Row(
              children: [
                Icon(Icons.warning_amber, size: 18, color: Colors.amber),
                SizedBox(width: 8),
                Text(
                  'Diff truncated (large output)',
                  style: TextStyle(fontSize: 12, color: Colors.amber),
                ),
              ],
            ),
          ),
        const SizedBox(height: 8),
        for (final hunk in diff.hunks) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            margin: const EdgeInsets.only(top: 8),
            decoration: BoxDecoration(
              color: Colors.grey.shade800,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              hunk.header,
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 11,
                color: Colors.cyanAccent,
              ),
            ),
          ),
          for (final line in hunk.lines)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              color: _lineBackgroundColor(line.type),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 32,
                    child: Text(
                      line.oldLineNumber?.toString() ?? '',
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 10,
                        color: Colors.grey,
                      ),
                      textAlign: TextAlign.right,
                    ),
                  ),
                  const SizedBox(width: 4),
                  SizedBox(
                    width: 32,
                    child: Text(
                      line.newLineNumber?.toString() ?? '',
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 10,
                        color: Colors.grey,
                      ),
                      textAlign: TextAlign.right,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    _linePrefix(line.type),
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: _lineTextColor(line.type),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      line.content,
                      style: TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 11,
                        color: _lineTextColor(line.type),
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ],
    );
  }

  Color _lineBackgroundColor(GitDiffLineType type) {
    switch (type) {
      case GitDiffLineType.addition:
        return Colors.green.shade900.withValues(alpha: 0.25);
      case GitDiffLineType.deletion:
        return Colors.red.shade900.withValues(alpha: 0.25);
      case GitDiffLineType.context:
      case GitDiffLineType.header:
        return Colors.transparent;
    }
  }

  Color _lineTextColor(GitDiffLineType type) {
    switch (type) {
      case GitDiffLineType.addition:
        return Colors.greenAccent;
      case GitDiffLineType.deletion:
        return Colors.redAccent;
      case GitDiffLineType.context:
      case GitDiffLineType.header:
        return Colors.white70;
    }
  }

  String _linePrefix(GitDiffLineType type) {
    switch (type) {
      case GitDiffLineType.addition:
        return '+';
      case GitDiffLineType.deletion:
        return '-';
      case GitDiffLineType.context:
      case GitDiffLineType.header:
        return ' ';
    }
  }
}
