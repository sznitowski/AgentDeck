import 'package:flutter/material.dart';

import '../../../core/domain/posix_path.dart';
import '../../../core/domain/profiles.dart';
import '../application/remote_file_service.dart';
import '../domain/remote_file_models.dart';

class FileViewerPage extends StatefulWidget {
  const FileViewerPage({
    super.key,
    required this.profile,
    required this.service,
    required this.entry,
  });

  final ServerProfile profile;
  final RemoteFileService service;
  final RemoteEntry entry;

  @override
  State<FileViewerPage> createState() => _FileViewerPageState();
}

class _FileViewerPageState extends State<FileViewerPage> {
  late final TextEditingController _textController;
  bool _loading = true;
  bool _saving = false;
  bool _isDirty = false;
  String? _error;
  String _originalText = '';

  @override
  void initState() {
    super.initState();
    _textController = TextEditingController();
    _loadFile();
  }

  Future<void> _loadFile() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final content = await widget.service.readText(widget.entry.path);
      if (!mounted) return;
      _originalText = content;
      _textController.text = content;
      _isDirty = false;
      setState(() {
        _loading = false;
      });
    } on RemoteFileFailure catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.message ?? 'Failed to load file';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _saveFile() async {
    if (!_isDirty || _saving) return;

    final isProduction = widget.profile.environment == Environment.production;
    if (isProduction) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.warning, color: Colors.orange),
              SizedBox(width: 8),
              Text('PRODUCTION OVERWRITE'),
            ],
          ),
          content: Text(
              'You are saving changes to a production file:\n\n${widget.entry.path}\n\nAre you sure?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              style: FilledButton.styleFrom(backgroundColor: Colors.red),
              child: const Text('Save in Production'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
    }

    setState(() {
      _saving = true;
    });

    try {
      await widget.service
          .writeText(widget.entry.path, _textController.text, atomic: true);
      if (!mounted) return;
      _originalText = _textController.text;
      setState(() {
        _saving = false;
        _isDirty = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Saved ${PosixPath.basename(widget.entry.path)}'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to save: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isProduction = widget.profile.environment == Environment.production;
    final isSensitive = RemoteFileService.isSensitiveFile(widget.entry.path);

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.entry.name,
                style:
                    const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            Text(widget.entry.path,
                style: const TextStyle(fontSize: 11, color: Colors.grey),
                overflow: TextOverflow.ellipsis),
          ],
        ),
        actions: [
          if (isProduction)
            Container(
              margin: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
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
            icon: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.save),
            tooltip: 'Save',
            onPressed: (_isDirty && !_saving && !_loading) ? _saveFile : null,
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Reload',
            onPressed: _loading ? null : _loadFile,
          ),
        ],
      ),
      body: Column(
        children: [
          if (isSensitive)
            Container(
              width: double.infinity,
              color: Colors.amber.shade900,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: const Row(
                children: [
                  Icon(Icons.shield_outlined, color: Colors.white, size: 18),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'SENSITIVE FILE: Contains credentials or secrets. Do not expose.',
                      style: TextStyle(
                          fontSize: 12,
                          color: Colors.white,
                          fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
            ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24.0),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.error_outline,
                                  size: 48, color: Colors.red),
                              const SizedBox(height: 16),
                              Text(_error!,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(fontSize: 14)),
                              const SizedBox(height: 16),
                              FilledButton(
                                onPressed: _loadFile,
                                child: const Text('Retry'),
                              ),
                            ],
                          ),
                        ),
                      )
                    : Padding(
                        padding: const EdgeInsets.all(8.0),
                        child: TextField(
                          controller: _textController,
                          maxLines: null,
                          expands: true,
                          keyboardType: TextInputType.multiline,
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 13,
                          ),
                          decoration: const InputDecoration(
                            border: InputBorder.none,
                            contentPadding: EdgeInsets.all(8),
                          ),
                          onChanged: (text) {
                            final dirty = text != _originalText;
                            if (dirty != _isDirty) {
                              setState(() {
                                _isDirty = dirty;
                              });
                            }
                          },
                        ),
                      ),
          ),
        ],
      ),
    );
  }
}
