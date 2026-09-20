import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';

import '../../../core/domain/posix_path.dart';
import '../domain/remote_file_models.dart';

class DartSshSftpAdapter implements RemoteFileSystem {
  DartSshSftpAdapter(this._client);

  final SftpClient _client;
  bool _closed = false;

  void _checkOpen() {
    if (_closed) {
      throw const RemoteFileFailure(RemoteFileFailureKind.connectionLost,
          message: 'SFTP filesystem is closed');
    }
  }

  RemoteEntryType _mapType(SftpFileType type) {
    switch (type) {
      case SftpFileType.directory:
        return RemoteEntryType.directory;
      case SftpFileType.regularFile:
        return RemoteEntryType.file;
      case SftpFileType.symbolicLink:
        return RemoteEntryType.symlink;
      default:
        return RemoteEntryType.other;
    }
  }

  RemoteFileFailure _mapError(Object error, [String? path]) {
    if (error is RemoteFileFailure) return error;
    if (error is SftpStatusError) {
      final code = error.code;
      final msg = error.message.toLowerCase();
      if (code == SftpStatusCode.noSuchFile) {
        return RemoteFileFailure(RemoteFileFailureKind.notFound,
            path: path, message: error.message);
      }
      if (code == SftpStatusCode.permissionDenied) {
        return RemoteFileFailure(RemoteFileFailureKind.permissionDenied,
            path: path, message: error.message);
      }
      if (code == SftpStatusCode.connectionLost ||
          code == SftpStatusCode.noConnection) {
        return RemoteFileFailure(RemoteFileFailureKind.connectionLost,
            path: path, message: error.message);
      }
      if (code == SftpStatusCode.opUnsupported) {
        return RemoteFileFailure(RemoteFileFailureKind.unsupported,
            path: path, message: error.message);
      }
      if (code == SftpStatusCode.badMessage) {
        return RemoteFileFailure(RemoteFileFailureKind.badMessage,
            path: path, message: error.message);
      }
      if (code == SftpStatusCode.failure) {
        if (msg.contains('not empty') || msg.contains('directory not empty')) {
          return RemoteFileFailure(RemoteFileFailureKind.directoryNotEmpty,
              path: path, message: error.message);
        }
        if (msg.contains('already exists') || msg.contains('file exists')) {
          return RemoteFileFailure(RemoteFileFailureKind.alreadyExists,
              path: path, message: error.message);
        }
        if (msg.contains('is a directory')) {
          return RemoteFileFailure(RemoteFileFailureKind.isDirectory,
              path: path, message: error.message);
        }
        if (msg.contains('not a directory')) {
          return RemoteFileFailure(RemoteFileFailureKind.notDirectory,
              path: path, message: error.message);
        }
        return RemoteFileFailure(RemoteFileFailureKind.unknown,
            path: path, message: error.message);
      }
    }
    if (error is SftpError) {
      return RemoteFileFailure(RemoteFileFailureKind.unknown,
          path: path, message: error.message);
    }
    return RemoteFileFailure(RemoteFileFailureKind.connectionLost,
        path: path, message: error.toString());
  }

  @override
  Future<List<RemoteEntry>> list(String path) async {
    _checkOpen();
    final normalized = PosixPath.normalize(path);
    try {
      final names = await _client.listdir(normalized);
      final entries = <RemoteEntry>[];
      for (final item in names) {
        if (item.filename == '.' || item.filename == '..') continue;
        final itemPath = PosixPath.join(normalized, item.filename);
        final attrs = item.attr;
        final fileType = attrs.mode?.type ?? SftpFileType.unknown;
        final isLink = fileType == SftpFileType.symbolicLink;
        String? target;
        if (isLink) {
          try {
            target = await _client.readlink(itemPath);
          } catch (_) {}
        }
        final permissions = attrs.mode != null
            ? RemoteFilePermissions.fromMode(attrs.mode!.value)
            : null;
        DateTime? modified;
        if (attrs.modifyTime != null) {
          modified = DateTime.fromMillisecondsSinceEpoch(
              attrs.modifyTime! * 1000,
              isUtc: true);
        }
        entries.add(RemoteEntry(
          name: item.filename,
          path: itemPath,
          type: _mapType(fileType),
          size: attrs.size ?? 0,
          modifiedAt: modified,
          permissions: permissions,
          ownerUid: attrs.userID,
          groupGid: attrs.groupID,
          isSymlink: isLink,
          symlinkTarget: target,
        ));
      }
      return entries;
    } catch (e) {
      throw _mapError(e, normalized);
    }
  }

  @override
  Future<RemoteEntry> stat(String path, {bool followLinks = true}) async {
    _checkOpen();
    final normalized = PosixPath.normalize(path);
    try {
      final attrs = await _client.stat(normalized, followLink: followLinks);
      final fileType = attrs.mode?.type ?? SftpFileType.unknown;
      final isLink = fileType == SftpFileType.symbolicLink;
      String? target;
      if (isLink) {
        try {
          target = await _client.readlink(normalized);
        } catch (_) {}
      }
      final permissions = attrs.mode != null
          ? RemoteFilePermissions.fromMode(attrs.mode!.value)
          : null;
      DateTime? modified;
      if (attrs.modifyTime != null) {
        modified = DateTime.fromMillisecondsSinceEpoch(attrs.modifyTime! * 1000,
            isUtc: true);
      }
      return RemoteEntry(
        name: PosixPath.basename(normalized),
        path: normalized,
        type: _mapType(fileType),
        size: attrs.size ?? 0,
        modifiedAt: modified,
        permissions: permissions,
        ownerUid: attrs.userID,
        groupGid: attrs.groupID,
        isSymlink: isLink,
        symlinkTarget: target,
      );
    } catch (e) {
      throw _mapError(e, normalized);
    }
  }

  @override
  Future<List<int>> read(String path,
      {int? maxBytes, void Function(int bytesRead)? onProgress}) async {
    _checkOpen();
    final normalized = PosixPath.normalize(path);
    try {
      final file = await _client.open(normalized, mode: SftpFileOpenMode.read);
      try {
        final stat = await file.stat();
        final size = stat.size ?? 0;
        if (maxBytes != null && size > maxBytes) {
          throw RemoteFileFailure(RemoteFileFailureKind.fileTooLarge,
              path: normalized,
              message:
                  'File size ($size bytes) exceeds maximum ($maxBytes bytes)');
        }
        final bytes = await file.readBytes();
        onProgress?.call(bytes.length);
        return bytes;
      } finally {
        await file.close();
      }
    } catch (e) {
      throw _mapError(e, normalized);
    }
  }

  @override
  Stream<List<int>> readStream(String path,
      {int? length,
      int offset = 0,
      void Function(int bytesRead)? onProgress}) async* {
    _checkOpen();
    final normalized = PosixPath.normalize(path);
    SftpFile? file;
    try {
      file = await _client.open(normalized, mode: SftpFileOpenMode.read);
      await for (final chunk in file.read(
          length: length, offset: offset, onProgress: onProgress)) {
        yield chunk;
      }
    } catch (e) {
      throw _mapError(e, normalized);
    } finally {
      if (file != null) {
        try {
          await file.close();
        } catch (_) {}
      }
    }
  }

  String _tempPath(String targetPath) {
    final parent = PosixPath.parent(targetPath);
    final base = PosixPath.basename(targetPath);
    final rng = Random.secure();
    final nonce = List.generate(
        6, (_) => rng.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
    return PosixPath.join(parent, '.agentdeck_tmp_${nonce}_$base');
  }

  @override
  Future<void> write(String path, List<int> bytes,
      {bool atomic = true, void Function(int bytesWritten)? onProgress}) async {
    _checkOpen();
    final normalized = PosixPath.normalize(path);
    final u8 = Uint8List.fromList(bytes);
    if (!atomic) {
      try {
        final file = await _client.open(normalized,
            mode: SftpFileOpenMode.write |
                SftpFileOpenMode.create |
                SftpFileOpenMode.truncate);
        try {
          await file.writeBytes(u8);
          onProgress?.call(u8.length);
        } finally {
          await file.close();
        }
      } catch (e) {
        throw _mapError(e, normalized);
      }
      return;
    }

    final temp = _tempPath(normalized);
    try {
      final file = await _client.open(temp,
          mode: SftpFileOpenMode.write |
              SftpFileOpenMode.create |
              SftpFileOpenMode.truncate);
      try {
        await file.writeBytes(u8);
        onProgress?.call(u8.length);
      } finally {
        await file.close();
      }
      await _client.rename(temp, normalized);
    } catch (e) {
      try {
        await _client.remove(temp);
      } catch (_) {}
      throw _mapError(e, normalized);
    }
  }

  @override
  Future<void> writeStream(String path, Stream<List<int>> stream,
      {int? length,
      bool atomic = true,
      void Function(int bytesWritten)? onProgress}) async {
    _checkOpen();
    final normalized = PosixPath.normalize(path);
    final writeTarget = atomic ? _tempPath(normalized) : normalized;

    try {
      final file = await _client.open(writeTarget,
          mode: SftpFileOpenMode.write |
              SftpFileOpenMode.create |
              SftpFileOpenMode.truncate);
      try {
        final writer = file.write(stream.map((b) => Uint8List.fromList(b)),
            onProgress: onProgress);
        await writer.done;
      } finally {
        await file.close();
      }
      if (atomic) {
        await _client.rename(writeTarget, normalized);
      }
    } catch (e) {
      if (atomic) {
        try {
          await _client.remove(writeTarget);
        } catch (_) {}
      }
      throw _mapError(e, normalized);
    }
  }

  @override
  Future<void> mkdir(String path) async {
    _checkOpen();
    final normalized = PosixPath.normalize(path);
    try {
      await _client.mkdir(normalized);
    } catch (e) {
      throw _mapError(e, normalized);
    }
  }

  @override
  Future<void> rename(String oldPath, String newPath) async {
    _checkOpen();
    final normOld = PosixPath.normalize(oldPath);
    final normNew = PosixPath.normalize(newPath);
    try {
      await _client.rename(normOld, normNew);
    } catch (e) {
      throw _mapError(e, normOld);
    }
  }

  @override
  Future<void> delete(String path) async {
    _checkOpen();
    final normalized = PosixPath.normalize(path);
    try {
      await _client.remove(normalized);
    } catch (e) {
      throw _mapError(e, normalized);
    }
  }

  @override
  Future<void> rmdir(String path) async {
    _checkOpen();
    final normalized = PosixPath.normalize(path);
    try {
      await _client.rmdir(normalized);
    } catch (e) {
      throw _mapError(e, normalized);
    }
  }

  @override
  Future<String> readlink(String path) async {
    _checkOpen();
    final normalized = PosixPath.normalize(path);
    try {
      return await _client.readlink(normalized);
    } catch (e) {
      throw _mapError(e, normalized);
    }
  }

  @override
  Future<String> realpath(String path) async {
    _checkOpen();
    final normalized = PosixPath.normalize(path);
    try {
      return await _client.absolute(normalized);
    } catch (e) {
      throw _mapError(e, normalized);
    }
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    try {
      await _client.close();
    } catch (_) {}
  }
}
