import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../core/domain/agents.dart';
import '../../../core/domain/posix_path.dart';
import '../application/remote_file_service.dart';
import '../domain/remote_file_models.dart';

enum RemoteFilesStatus {
  initial,
  loading,
  loaded,
  empty,
  error,
  disconnected,
}

class RemoteFilesController extends ChangeNotifier {
  RemoteFilesController({
    required this.service,
    required this.initialPath,
    this.showHidden = true,
  }) : currentPath = PosixPath.normalize(initialPath) {
    _init();
  }

  final RemoteFileService service;
  final String initialPath;

  String currentPath;
  bool showHidden;
  RemoteFilesStatus status = RemoteFilesStatus.initial;
  List<RemoteEntry> entries = const [];
  String? errorMessage;
  RemoteFileFailure? failure;

  final List<String> _history = [];
  StreamSubscription<ConnectionState>? _connectionSub;
  bool _disposed = false;

  void _init() {
    _connectionSub = service.connection.states.listen((state) {
      if (state != ConnectionState.connected &&
          status != RemoteFilesStatus.disconnected) {
        status = RemoteFilesStatus.disconnected;
        if (!_disposed) notifyListeners();
      }
    });
    loadDirectory(currentPath, addToHistory: false);
  }

  bool get canNavigateUp => currentPath != '/' && currentPath != '.';

  List<RemoteEntry> get visibleEntries {
    if (showHidden) return entries;
    return entries.where((e) => !e.isHidden).toList();
  }

  void toggleShowHidden() {
    showHidden = !showHidden;
    notifyListeners();
  }

  Future<void> loadDirectory(String path, {bool addToHistory = true}) async {
    final target = PosixPath.normalize(path);
    if (addToHistory && currentPath != target) {
      _history.add(currentPath);
    }
    currentPath = target;
    status = RemoteFilesStatus.loading;
    errorMessage = null;
    failure = null;
    notifyListeners();

    try {
      final list = await service.list(target);
      entries = list;
      status =
          list.isEmpty ? RemoteFilesStatus.empty : RemoteFilesStatus.loaded;
    } on RemoteFileFailure catch (e) {
      failure = e;
      errorMessage = _formatErrorMessage(e);
      status = RemoteFilesStatus.error;
    } catch (e) {
      errorMessage = e.toString();
      status = RemoteFilesStatus.error;
    }

    if (!_disposed) notifyListeners();
  }

  Future<void> refresh() => loadDirectory(currentPath, addToHistory: false);

  Future<void> navigateUp() async {
    if (!canNavigateUp) return;
    final parent = PosixPath.parent(currentPath);
    await loadDirectory(parent);
  }

  Future<void> navigateBack() async {
    if (_history.isNotEmpty) {
      final prev = _history.removeLast();
      await loadDirectory(prev, addToHistory: false);
    } else {
      await navigateUp();
    }
  }

  Future<void> createDirectory(String name) async {
    final target = PosixPath.join(currentPath, name);
    try {
      await service.mkdir(target);
      await refresh();
    } on RemoteFileFailure catch (e) {
      failure = e;
      errorMessage = _formatErrorMessage(e);
      notifyListeners();
      rethrow;
    }
  }

  Future<void> renameEntry(RemoteEntry entry, String newName) async {
    final target = PosixPath.join(currentPath, newName);
    try {
      await service.rename(entry.path, target);
      await refresh();
    } on RemoteFileFailure catch (e) {
      failure = e;
      errorMessage = _formatErrorMessage(e);
      notifyListeners();
      rethrow;
    }
  }

  Future<void> deleteEntry(RemoteEntry entry) async {
    try {
      if (entry.isDirectory) {
        await service.deleteDirectory(entry.path);
      } else {
        await service.deleteFile(entry.path);
      }
      await refresh();
    } on RemoteFileFailure catch (e) {
      failure = e;
      errorMessage = _formatErrorMessage(e);
      notifyListeners();
      rethrow;
    }
  }

  String _formatErrorMessage(RemoteFileFailure error) {
    switch (error.kind) {
      case RemoteFileFailureKind.notFound:
        return 'File or directory not found (${error.path ?? currentPath})';
      case RemoteFileFailureKind.permissionDenied:
        return 'Permission denied (${error.path ?? currentPath})';
      case RemoteFileFailureKind.alreadyExists:
        return 'An item with that name already exists';
      case RemoteFileFailureKind.directoryNotEmpty:
        return 'Cannot delete directory: Directory is not empty';
      case RemoteFileFailureKind.connectionLost:
        return 'SSH connection lost';
      case RemoteFileFailureKind.unsupported:
        return error.message ?? 'Operation unsupported';
      case RemoteFileFailureKind.invalidPath:
        return error.message ?? 'Invalid path';
      case RemoteFileFailureKind.fileTooLarge:
        return error.message ?? 'File too large';
      default:
        return error.message ?? 'Remote file operation failed';
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _connectionSub?.cancel();
    super.dispose();
  }
}
