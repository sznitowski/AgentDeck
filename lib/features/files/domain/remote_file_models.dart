import 'dart:async';

enum RemoteEntryType {
  file,
  directory,
  symlink,
  other,
}

class RemoteFilePermissions {
  const RemoteFilePermissions({
    required this.userRead,
    required this.userWrite,
    required this.userExecute,
    required this.groupRead,
    required this.groupWrite,
    required this.groupExecute,
    required this.otherRead,
    required this.otherWrite,
    required this.otherExecute,
    this.rawMode,
  });

  factory RemoteFilePermissions.fromMode(int mode) {
    return RemoteFilePermissions(
      userRead: (mode & 0x100) != 0,
      userWrite: (mode & 0x080) != 0,
      userExecute: (mode & 0x040) != 0,
      groupRead: (mode & 0x020) != 0,
      groupWrite: (mode & 0x010) != 0,
      groupExecute: (mode & 0x008) != 0,
      otherRead: (mode & 0x004) != 0,
      otherWrite: (mode & 0x002) != 0,
      otherExecute: (mode & 0x001) != 0,
      rawMode: mode,
    );
  }

  final bool userRead;
  final bool userWrite;
  final bool userExecute;
  final bool groupRead;
  final bool groupWrite;
  final bool groupExecute;
  final bool otherRead;
  final bool otherWrite;
  final bool otherExecute;
  final int? rawMode;

  String get formatted {
    final buffer = StringBuffer();
    buffer.write(userRead ? 'r' : '-');
    buffer.write(userWrite ? 'w' : '-');
    buffer.write(userExecute ? 'x' : '-');
    buffer.write(groupRead ? 'r' : '-');
    buffer.write(groupWrite ? 'w' : '-');
    buffer.write(groupExecute ? 'x' : '-');
    buffer.write(otherRead ? 'r' : '-');
    buffer.write(otherWrite ? 'w' : '-');
    buffer.write(otherExecute ? 'x' : '-');
    return buffer.toString();
  }

  int get octal {
    var val = 0;
    if (userRead) val += 0x100;
    if (userWrite) val += 0x080;
    if (userExecute) val += 0x040;
    if (groupRead) val += 0x020;
    if (groupWrite) val += 0x010;
    if (groupExecute) val += 0x008;
    if (otherRead) val += 0x004;
    if (otherWrite) val += 0x002;
    if (otherExecute) val += 0x001;
    return val;
  }
}

class RemoteEntry {
  const RemoteEntry({
    required this.name,
    required this.path,
    required this.type,
    required this.size,
    this.modifiedAt,
    this.permissions,
    this.ownerUid,
    this.groupGid,
    this.isSymlink = false,
    this.symlinkTarget,
  });

  final String name;
  final String path;
  final RemoteEntryType type;
  final int size;
  final DateTime? modifiedAt;
  final RemoteFilePermissions? permissions;
  final int? ownerUid;
  final int? groupGid;
  final bool isSymlink;
  final String? symlinkTarget;

  bool get isDirectory => type == RemoteEntryType.directory;
  bool get isFile => type == RemoteEntryType.file;
  bool get isHidden => name.startsWith('.') && name != '.' && name != '..';

  String get formattedSize => formatBytes(size);

  static String formatBytes(int bytes) {
    if (bytes < 0) return '0 B';
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) {
      final kb = bytes / 1024;
      return '${kb.toStringAsFixed(kb < 10 ? 1 : 0)} KB';
    }
    if (bytes < 1024 * 1024 * 1024) {
      final mb = bytes / (1024 * 1024);
      return '${mb.toStringAsFixed(mb < 10 ? 1 : 0)} MB';
    }
    final gb = bytes / (1024 * 1024 * 1024);
    return '${gb.toStringAsFixed(gb < 10 ? 1 : 0)} GB';
  }
}

enum RemoteFileFailureKind {
  notFound,
  permissionDenied,
  alreadyExists,
  notDirectory,
  isDirectory,
  directoryNotEmpty,
  connectionLost,
  unsupported,
  invalidPath,
  fileTooLarge,
  badMessage,
  unknown,
}

class RemoteFileFailure implements Exception {
  const RemoteFileFailure(this.kind, {this.message, this.path});
  final RemoteFileFailureKind kind;
  final String? message;
  final String? path;

  @override
  String toString() {
    final buffer = StringBuffer('RemoteFileFailure($kind');
    if (path != null) buffer.write(', path: $path');
    if (message != null) buffer.write(', message: $message');
    buffer.write(')');
    return buffer.toString();
  }
}

abstract interface class RemoteFileSystem {
  Future<List<RemoteEntry>> list(String path);
  Future<RemoteEntry> stat(String path, {bool followLinks = true});
  Future<List<int>> read(String path,
      {int? maxBytes, void Function(int bytesRead)? onProgress});
  Stream<List<int>> readStream(String path,
      {int? length, int offset = 0, void Function(int bytesRead)? onProgress});
  Future<void> write(String path, List<int> bytes,
      {bool atomic = true, void Function(int bytesWritten)? onProgress});
  Future<void> writeStream(String path, Stream<List<int>> stream,
      {int? length,
      bool atomic = true,
      void Function(int bytesWritten)? onProgress});
  Future<void> mkdir(String path);
  Future<void> rename(String oldPath, String newPath);
  Future<void> delete(String path);
  Future<void> rmdir(String path);
  Future<String> readlink(String path);
  Future<String> realpath(String path);
  Future<void> close();
}
