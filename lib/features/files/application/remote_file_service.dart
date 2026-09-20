import 'dart:async';
import 'dart:convert';

import '../../../core/domain/posix_path.dart';
import '../../connections/application/ssh_connection_service.dart';
import '../domain/remote_file_models.dart';

class RemoteFileService {
  RemoteFileService({required this.connection, required this.serverId});

  final SshConnectionService connection;
  final String serverId;

  void _checkConnection() {
    if (connection.connectedProfileId != serverId) {
      throw const RemoteFileFailure(RemoteFileFailureKind.connectionLost,
          message: 'Server connection mismatch or not connected');
    }
  }

  /// Checks if [path] references a sensitive file such as credentials or private keys.
  static bool isSensitiveFile(String path) {
    final name = PosixPath.basename(path).toLowerCase();
    if (name == '.env' || name.startsWith('.env.')) return true;
    if (name.endsWith('.pem') ||
        name.endsWith('.key') ||
        name.endsWith('.p12') ||
        name.endsWith('.pfx') ||
        name.endsWith('.keystore')) {
      return true;
    }
    if (name.startsWith('id_rsa') ||
        name.startsWith('id_ed25519') ||
        name.startsWith('id_ecdsa') ||
        name.startsWith('id_dsa')) {
      return true;
    }
    if (name.contains('credential') || name.contains('secret')) return true;
    return false;
  }

  /// Checks if a buffer contains binary data (e.g. null bytes).
  static bool isBinary(List<int> bytes) {
    final checkLen = bytes.length < 8192 ? bytes.length : 8192;
    for (var i = 0; i < checkLen; i++) {
      if (bytes[i] == 0) return true;
    }
    return false;
  }

  Future<RemoteFileSystem> _getFs() async {
    _checkConnection();
    return connection.openSftp();
  }

  /// Lists entries in [path], sorting directories first, then files alphabetically.
  Future<List<RemoteEntry>> list(String path) async {
    final normalized = PosixPath.normalize(path);
    final fs = await _getFs();
    try {
      final entries = await fs.list(normalized);
      entries.sort((a, b) {
        if (a.isDirectory && !b.isDirectory) return -1;
        if (!a.isDirectory && b.isDirectory) return 1;
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });
      return entries;
    } finally {
      await fs.close();
    }
  }

  /// Retrieves metadata for [path].
  Future<RemoteEntry> stat(String path, {bool followLinks = true}) async {
    final normalized = PosixPath.normalize(path);
    final fs = await _getFs();
    try {
      return await fs.stat(normalized, followLinks: followLinks);
    } finally {
      await fs.close();
    }
  }

  /// Reads a text file up to [maxBytes] (default 5 MB) and decodes as UTF-8.
  /// Throws [RemoteFileFailureKind.unsupported] if binary content is detected.
  Future<String> readText(String path, {int maxBytes = 5 * 1024 * 1024}) async {
    final normalized = PosixPath.normalize(path);
    final fs = await _getFs();
    try {
      final bytes = await fs.read(normalized, maxBytes: maxBytes);
      if (isBinary(bytes)) {
        throw RemoteFileFailure(RemoteFileFailureKind.unsupported,
            path: normalized, message: 'Binary file cannot be opened as text');
      }
      try {
        return utf8.decode(bytes);
      } catch (_) {
        throw RemoteFileFailure(RemoteFileFailureKind.unsupported,
            path: normalized, message: 'File encoding is not valid UTF-8 text');
      }
    } finally {
      await fs.close();
    }
  }

  /// Writes [text] encoded as UTF-8 to [path], using atomic temporary file save by default.
  Future<void> writeText(String path, String text, {bool atomic = true}) async {
    final normalized = PosixPath.normalize(path);
    final bytes = utf8.encode(text);
    final fs = await _getFs();
    try {
      await fs.write(normalized, bytes, atomic: atomic);
    } finally {
      await fs.close();
    }
  }

  /// Creates a directory at [path].
  Future<void> mkdir(String path) async {
    final normalized = PosixPath.normalize(path);
    final name = PosixPath.basename(normalized);
    if (!PosixPath.isValidFilename(name)) {
      throw RemoteFileFailure(RemoteFileFailureKind.invalidPath,
          path: normalized, message: 'Invalid directory name: $name');
    }
    final fs = await _getFs();
    try {
      await fs.mkdir(normalized);
    } finally {
      await fs.close();
    }
  }

  /// Renames an entry from [oldPath] to [newPath].
  Future<void> rename(String oldPath, String newPath) async {
    final normOld = PosixPath.normalize(oldPath);
    final normNew = PosixPath.normalize(newPath);
    final newName = PosixPath.basename(normNew);
    if (!PosixPath.isValidFilename(newName)) {
      throw RemoteFileFailure(RemoteFileFailureKind.invalidPath,
          path: normNew, message: 'Invalid new name: $newName');
    }
    final fs = await _getFs();
    try {
      await fs.rename(normOld, normNew);
    } finally {
      await fs.close();
    }
  }

  /// Deletes a regular file at [path].
  Future<void> deleteFile(String path) async {
    final normalized = PosixPath.normalize(path);
    final fs = await _getFs();
    try {
      await fs.delete(normalized);
    } finally {
      await fs.close();
    }
  }

  /// Deletes an empty directory at [path]. Fails with [RemoteFileFailureKind.directoryNotEmpty]
  /// if directory contains entries.
  Future<void> deleteDirectory(String path) async {
    final normalized = PosixPath.normalize(path);
    final fs = await _getFs();
    try {
      await fs.rmdir(normalized);
    } finally {
      await fs.close();
    }
  }

  /// Downloads file content as a stream.
  Stream<List<int>> downloadStream(String path,
      {int? length,
      int offset = 0,
      void Function(int bytesRead)? onProgress}) async* {
    _checkConnection();
    final normalized = PosixPath.normalize(path);
    final fs = await connection.openSftp();
    try {
      await for (final chunk in fs.readStream(normalized,
          length: length, offset: offset, onProgress: onProgress)) {
        yield chunk;
      }
    } finally {
      await fs.close();
    }
  }

  /// Uploads a stream of bytes to [path].
  Future<void> uploadStream(String path, Stream<List<int>> stream,
      {int? length,
      bool atomic = true,
      void Function(int bytesWritten)? onProgress}) async {
    final normalized = PosixPath.normalize(path);
    final fs = await _getFs();
    try {
      await fs.writeStream(normalized, stream,
          length: length, atomic: atomic, onProgress: onProgress);
    } finally {
      await fs.close();
    }
  }
}
