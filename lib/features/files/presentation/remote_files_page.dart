import 'package:flutter/material.dart';

import '../../../core/domain/posix_path.dart';
import '../../../core/domain/profiles.dart';
import '../application/remote_file_service.dart';
import '../domain/remote_file_models.dart';
import 'file_viewer_page.dart';
import 'remote_files_controller.dart';

class RemoteFilesPage extends StatefulWidget {
  const RemoteFilesPage({
    super.key,
    required this.profile,
    required this.service,
    this.initialPath = '/',
  });

  final ServerProfile profile;
  final RemoteFileService service;
  final String initialPath;

  @override
  State<RemoteFilesPage> createState() => _RemoteFilesPageState();
}

class _RemoteFilesPageState extends State<RemoteFilesPage> {
  late final RemoteFilesController _controller;

  @override
  void initState() {
    super.initState();
    _controller = RemoteFilesController(
      service: widget.service,
      initialPath: widget.initialPath,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _promptNewFolder() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('New Folder'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'Folder name',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
            child: const Text('Create'),
          ),
        ],
      ),
    );

    if (name != null && name.isNotEmpty) {
      try {
        await _controller.createDirectory(name);
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to create folder: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _promptRename(RemoteEntry entry) async {
    final controller = TextEditingController(text: entry.name);
    final newName = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Rename ${entry.isDirectory ? "Folder" : "File"}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Current: ${entry.path}',
                style: const TextStyle(fontSize: 12, color: Colors.grey)),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              autofocus: true,
              decoration: const InputDecoration(
                hintText: 'New name',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
            child: const Text('Rename'),
          ),
        ],
      ),
    );

    if (newName != null && newName.isNotEmpty && newName != entry.name) {
      try {
        await _controller.renameEntry(entry, newName);
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to rename: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _promptDelete(RemoteEntry entry) async {
    final isProduction = widget.profile.environment == Environment.production;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.delete_outline,
                color: isProduction ? Colors.red : Colors.orange),
            const SizedBox(width: 8),
            Text(isProduction ? 'PRODUCTION DELETE' : 'Confirm Delete'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (isProduction)
              Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.red.shade900.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: Colors.red),
                ),
                child: const Text(
                  'CRITICAL: This is a PRODUCTION server. Deletion is irreversible.',
                  style: TextStyle(
                      color: Colors.redAccent,
                      fontWeight: FontWeight.bold,
                      fontSize: 12),
                ),
              ),
            Text(
                'Are you sure you want to delete this ${entry.isDirectory ? "directory" : "file"}?'),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Theme.of(ctx).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(4),
              ),
              child: SelectableText(
                entry.path,
                style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 12,
                    fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(
                backgroundColor: isProduction ? Colors.red : Colors.orange),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await _controller.deleteEntry(entry);
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to delete: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _openEntry(RemoteEntry entry) {
    if (entry.isDirectory) {
      _controller.loadDirectory(entry.path);
    } else {
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (ctx) => FileViewerPage(
            profile: widget.profile,
            service: widget.service,
            entry: entry,
          ),
        ),
      );
    }
  }

  IconData _getIconForEntry(RemoteEntry entry) {
    if (entry.isSymlink) return Icons.link;
    if (entry.isDirectory) return Icons.folder;
    final ext = PosixPath.extension(entry.path).toLowerCase();
    if (ext == '.txt' ||
        ext == '.md' ||
        ext == '.json' ||
        ext == '.yaml' ||
        ext == '.yml' ||
        ext == '.dart' ||
        ext == '.ts' ||
        ext == '.js' ||
        ext == '.sh' ||
        ext == '.py' ||
        ext == '.env') {
      return Icons.description_outlined;
    }
    return Icons.insert_drive_file_outlined;
  }

  @override
  Widget build(BuildContext context) {
    final isProduction = widget.profile.environment == Environment.production;

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final status = _controller.status;
        final visibleEntries = _controller.visibleEntries;

        return Scaffold(
          appBar: AppBar(
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  PosixPath.basename(_controller.currentPath),
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.bold),
                ),
                Text(
                  _controller.currentPath,
                  style: const TextStyle(fontSize: 11, color: Colors.grey),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
            actions: [
              if (isProduction)
                Container(
                  margin:
                      const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.red.shade900,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text(
                    'PRODUCTION',
                    style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: Colors.white),
                  ),
                ),
              IconButton(
                icon: Icon(_controller.showHidden
                    ? Icons.visibility
                    : Icons.visibility_off),
                tooltip:
                    _controller.showHidden ? 'Hide dotfiles' : 'Show dotfiles',
                onPressed: _controller.toggleShowHidden,
              ),
              IconButton(
                icon: const Icon(Icons.create_new_folder_outlined),
                tooltip: 'New Folder',
                onPressed: status == RemoteFilesStatus.disconnected
                    ? null
                    : _promptNewFolder,
              ),
              IconButton(
                icon: const Icon(Icons.refresh),
                tooltip: 'Refresh',
                onPressed: _controller.refresh,
              ),
            ],
          ),
          body: Column(
            children: [
              if (status == RemoteFilesStatus.disconnected)
                Container(
                  width: double.infinity,
                  color: Colors.red.shade900,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: const Row(
                    children: [
                      Icon(Icons.link_off, color: Colors.white, size: 18),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'DISCONNECTED: SSH connection lost. Changes disabled.',
                          style: TextStyle(
                              fontSize: 12,
                              color: Colors.white,
                              fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                ),
              if (_controller.canNavigateUp)
                ListTile(
                  leading: const Icon(Icons.arrow_upward, color: Colors.grey),
                  title: const Text('.. (Parent directory)',
                      style: TextStyle(fontStyle: FontStyle.italic)),
                  onTap: _controller.navigateUp,
                  dense: true,
                ),
              Expanded(
                child: _buildBody(status, visibleEntries),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildBody(
      RemoteFilesStatus status, List<RemoteEntry> visibleEntries) {
    if (status == RemoteFilesStatus.loading && visibleEntries.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (status == RemoteFilesStatus.error && visibleEntries.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 48, color: Colors.red),
              const SizedBox(height: 16),
              Text(
                _controller.errorMessage ?? 'Failed to load directory',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 14),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _controller.refresh,
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    if (visibleEntries.isEmpty && status != RemoteFilesStatus.loading) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.folder_open, size: 48, color: Colors.grey),
            const SizedBox(height: 16),
            const Text('Empty directory',
                style: TextStyle(color: Colors.grey, fontSize: 16)),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _promptNewFolder,
              icon: const Icon(Icons.create_new_folder),
              label: const Text('New Folder'),
            ),
          ],
        ),
      );
    }

    return ListView.separated(
      itemCount: visibleEntries.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final entry = visibleEntries[index];
        final isSensitive = RemoteFileService.isSensitiveFile(entry.path);

        return ListTile(
          leading: Icon(
            _getIconForEntry(entry),
            color: entry.isDirectory
                ? Colors.amber.shade700
                : isSensitive
                    ? Colors.orange
                    : Colors.blueGrey,
          ),
          title: Row(
            children: [
              Expanded(
                child: Text(
                  entry.name,
                  style: TextStyle(
                    fontWeight:
                        entry.isDirectory ? FontWeight.bold : FontWeight.normal,
                    color: isSensitive ? Colors.orange.shade200 : null,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (isSensitive)
                const Padding(
                  padding: EdgeInsets.only(left: 4),
                  child: Icon(Icons.shield_outlined,
                      size: 14, color: Colors.orange),
                ),
            ],
          ),
          subtitle: Text(
            '${entry.isDirectory ? "Folder" : entry.formattedSize} • ${entry.permissions?.formatted ?? ''}',
            style: const TextStyle(fontSize: 11, color: Colors.grey),
          ),
          trailing: PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, size: 18),
            onSelected: (action) {
              if (action == 'rename') _promptRename(entry);
              if (action == 'delete') _promptDelete(entry);
            },
            itemBuilder: (ctx) => [
              const PopupMenuItem(
                value: 'rename',
                child: Row(
                  children: [
                    Icon(Icons.drive_file_rename_outline, size: 18),
                    SizedBox(width: 8),
                    Text('Rename'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'delete',
                child: Row(
                  children: [
                    Icon(Icons.delete_outline, size: 18, color: Colors.red),
                    SizedBox(width: 8),
                    Text('Delete', style: TextStyle(color: Colors.red)),
                  ],
                ),
              ),
            ],
          ),
          onTap: () => _openEntry(entry),
        );
      },
    );
  }
}
