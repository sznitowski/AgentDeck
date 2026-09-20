import 'dart:async';
import 'dart:convert';

import 'package:agentdeck/core/domain/posix_path.dart';
import 'package:agentdeck/core/domain/profiles.dart';
import 'package:agentdeck/core/domain/remote_contracts.dart';
import 'package:agentdeck/features/connections/application/ssh_connection_service.dart';
import 'package:agentdeck/features/connections/domain/ssh_models.dart';
import 'package:agentdeck/features/files/application/remote_file_service.dart';
import 'package:agentdeck/features/files/domain/remote_file_models.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeFileSystem implements RemoteFileSystem {
  final files = <String, List<int>>{};
  final directories = <String>{'/'};
  final symlinks = <String, String>{};
  bool closed = false;

  @override
  Future<List<RemoteEntry>> list(String path) async {
    final norm = PosixPath.normalize(path);
    if (!directories.contains(norm)) {
      throw RemoteFileFailure(RemoteFileFailureKind.notFound, path: norm);
    }
    final results = <RemoteEntry>[];
    for (final dir in directories) {
      if (dir != '/' && PosixPath.parent(dir) == norm) {
        results.add(RemoteEntry(
          name: PosixPath.basename(dir),
          path: dir,
          type: RemoteEntryType.directory,
          size: 4096,
          permissions: RemoteFilePermissions.fromMode(0x1ed), // 0755
        ));
      }
    }
    for (final file in files.keys) {
      if (PosixPath.parent(file) == norm) {
        results.add(RemoteEntry(
          name: PosixPath.basename(file),
          path: file,
          type: RemoteEntryType.file,
          size: files[file]!.length,
          permissions: RemoteFilePermissions.fromMode(0x1a4), // 0644
        ));
      }
    }
    for (final link in symlinks.keys) {
      if (PosixPath.parent(link) == norm) {
        results.add(RemoteEntry(
          name: PosixPath.basename(link),
          path: link,
          type: RemoteEntryType.symlink,
          size: 0,
          isSymlink: true,
          symlinkTarget: symlinks[link],
        ));
      }
    }
    return results;
  }

  @override
  Future<RemoteEntry> stat(String path, {bool followLinks = true}) async {
    final norm = PosixPath.normalize(path);
    if (directories.contains(norm)) {
      return RemoteEntry(
        name: PosixPath.basename(norm),
        path: norm,
        type: RemoteEntryType.directory,
        size: 4096,
      );
    }
    if (files.containsKey(norm)) {
      return RemoteEntry(
        name: PosixPath.basename(norm),
        path: norm,
        type: RemoteEntryType.file,
        size: files[norm]!.length,
      );
    }
    if (symlinks.containsKey(norm)) {
      if (!followLinks) {
        return RemoteEntry(
          name: PosixPath.basename(norm),
          path: norm,
          type: RemoteEntryType.symlink,
          size: 0,
          isSymlink: true,
          symlinkTarget: symlinks[norm],
        );
      }
      return stat(symlinks[norm]!);
    }
    throw RemoteFileFailure(RemoteFileFailureKind.notFound, path: norm);
  }

  @override
  Future<List<int>> read(String path,
      {int? maxBytes, void Function(int bytesRead)? onProgress}) async {
    final norm = PosixPath.normalize(path);
    if (!files.containsKey(norm)) {
      throw RemoteFileFailure(RemoteFileFailureKind.notFound, path: norm);
    }
    final data = files[norm]!;
    if (maxBytes != null && data.length > maxBytes) {
      throw RemoteFileFailure(RemoteFileFailureKind.fileTooLarge, path: norm);
    }
    onProgress?.call(data.length);
    return List.from(data);
  }

  @override
  Stream<List<int>> readStream(String path,
      {int? length,
      int offset = 0,
      void Function(int bytesRead)? onProgress}) async* {
    final bytes = await read(path);
    final slice =
        bytes.sublist(offset, length != null ? offset + length : bytes.length);
    yield slice;
    onProgress?.call(slice.length);
  }

  @override
  Future<void> write(String path, List<int> bytes,
      {bool atomic = true, void Function(int bytesWritten)? onProgress}) async {
    final norm = PosixPath.normalize(path);
    files[norm] = List.from(bytes);
    onProgress?.call(bytes.length);
  }

  @override
  Future<void> writeStream(String path, Stream<List<int>> stream,
      {int? length,
      bool atomic = true,
      void Function(int bytesWritten)? onProgress}) async {
    final collected = <int>[];
    await for (final chunk in stream) {
      collected.addAll(chunk);
      onProgress?.call(collected.length);
    }
    await write(path, collected, atomic: atomic);
  }

  @override
  Future<void> mkdir(String path) async {
    final norm = PosixPath.normalize(path);
    if (directories.contains(norm)) {
      throw RemoteFileFailure(RemoteFileFailureKind.alreadyExists, path: norm);
    }
    directories.add(norm);
  }

  @override
  Future<void> rename(String oldPath, String newPath) async {
    final nOld = PosixPath.normalize(oldPath);
    final nNew = PosixPath.normalize(newPath);
    if (files.containsKey(nOld)) {
      files[nNew] = files.remove(nOld)!;
    } else if (directories.contains(nOld)) {
      directories.remove(nOld);
      directories.add(nNew);
    } else {
      throw RemoteFileFailure(RemoteFileFailureKind.notFound, path: nOld);
    }
  }

  @override
  Future<void> delete(String path) async {
    final norm = PosixPath.normalize(path);
    if (files.remove(norm) == null) {
      throw RemoteFileFailure(RemoteFileFailureKind.notFound, path: norm);
    }
  }

  @override
  Future<void> rmdir(String path) async {
    final norm = PosixPath.normalize(path);
    if (!directories.contains(norm)) {
      throw RemoteFileFailure(RemoteFileFailureKind.notFound, path: norm);
    }
    // Check if not empty
    for (final f in files.keys) {
      if (PosixPath.parent(f) == norm) {
        throw RemoteFileFailure(RemoteFileFailureKind.directoryNotEmpty,
            path: norm);
      }
    }
    for (final d in directories) {
      if (d != norm && PosixPath.parent(d) == norm) {
        throw RemoteFileFailure(RemoteFileFailureKind.directoryNotEmpty,
            path: norm);
      }
    }
    directories.remove(norm);
  }

  @override
  Future<String> readlink(String path) async {
    final norm = PosixPath.normalize(path);
    if (symlinks.containsKey(norm)) return symlinks[norm]!;
    throw RemoteFileFailure(RemoteFileFailureKind.notFound, path: norm);
  }

  @override
  Future<String> realpath(String path) async => PosixPath.normalize(path);

  @override
  Future<void> close() async {
    closed = true;
  }
}

class FakeSftpHandle implements SshSftpTransportHandle {
  FakeSftpHandle(this.fs);
  final FakeFileSystem fs;

  @override
  Future<RemoteFileSystem> openSftp() async => fs;

  @override
  Future<TerminalSession> openTerminal(int columns, int rows) async =>
      throw UnimplementedError();

  @override
  Future<RemoteCommandResult> run(List<String> arguments,
          {Duration timeout = const Duration(seconds: 10)}) async =>
      throw UnimplementedError();

  @override
  Future<TerminalSession> attachTmux(
          String name, int columns, int rows) async =>
      throw UnimplementedError();

  @override
  Future<void> get done => Completer<void>().future;

  @override
  Future<void> close() async {}
}

class FakeSshTransport implements SshTransport {
  FakeSshTransport(this.fs);
  final FakeFileSystem fs;

  @override
  Future<SshTransportHandle> open(
    ServerProfile profile,
    SshCredential credential,
    Future<bool> Function(String algorithm, String fingerprint) verifyHostKey,
    SshTimeouts timeouts,
  ) async {
    await verifyHostKey('ssh-ed25519', 'SHA256:' + 'A' * 43);
    return FakeSftpHandle(fs);
  }
}

class FakeCredentials implements SecureCredentialStore {
  @override
  Future<List<int>?> get(String reference) async => utf8.encode('secret');
  @override
  Future<void> put(String reference, List<int> secret) async {}
  @override
  Future<void> delete(String reference) async {}
}

class FakeKnownHosts implements KnownHostRepository {
  @override
  Future<KnownHost?> find(String hostname, int port) async => null;
  @override
  Future<void> markSeen(String hostname, int port, DateTime at) async {}
  @override
  Future<void> trust(KnownHost host) async {}
  @override
  Future<void> revoke(String hostname, int port) async {}
  @override
  Future<void> replace(KnownHost host) async {}
  @override
  Future<void> delete(String hostname, int port) async {}
}

void main() {
  const profile = ServerProfile(
    id: 'test-server',
    name: 'Lab Server',
    host: '127.0.0.1',
    port: 22,
    username: 'lab',
    credentialId: 'lab',
  );

  late FakeFileSystem fs;
  late SshConnectionService connection;
  late RemoteFileService service;

  setUp(() async {
    fs = FakeFileSystem();
    fs.directories.addAll(['/var', '/var/docker', '/var/docker/project']);
    fs.files['/var/docker/project/README.md'] =
        utf8.encode('# Project\nHello World');
    fs.files['/var/docker/project/.env'] = utf8.encode('SECRET=123');
    fs.files['/var/docker/project/app.bin'] = [0x00, 0x01, 0x02, 0x03];

    connection = SshConnectionService(
      credentials: FakeCredentials(),
      knownHosts: FakeKnownHosts(),
      transport: FakeSshTransport(fs),
    );
    await connection.connect(profile, approve: (_, __) async => true);
    service = RemoteFileService(connection: connection, serverId: profile.id);
  });

  tearDown(() async {
    await connection.dispose();
  });

  test('list returns entries with directories sorted first', () async {
    final entries = await service.list('/var/docker/project');
    expect(entries.length, 3);
    expect(entries.map((e) => e.name).toList(),
        containsAll(['.env', 'README.md', 'app.bin']));
  });

  test('stat returns entry metadata', () async {
    final entry = await service.stat('/var/docker/project/README.md');
    expect(entry.name, 'README.md');
    expect(entry.isFile, isTrue);
    expect(entry.size, 21);
  });

  test('readText reads UTF-8 text and detects binary', () async {
    final content = await service.readText('/var/docker/project/README.md');
    expect(content, '# Project\nHello World');

    // Binary file check
    expect(
        () => service.readText('/var/docker/project/app.bin'),
        throwsA(isA<RemoteFileFailure>()
            .having((e) => e.kind, 'kind', RemoteFileFailureKind.unsupported)));
  });

  test('writeText writes text atomically', () async {
    await service.writeText('/var/docker/project/new.txt', 'New Content');
    final readBack = await service.readText('/var/docker/project/new.txt');
    expect(readBack, 'New Content');
  });

  test('mkdir creates directory with validation', () async {
    await service.mkdir('/var/docker/project/src');
    expect(fs.directories.contains('/var/docker/project/src'), isTrue);

    // Invalid directory names
    expect(() => service.mkdir('/var/docker/project/'),
        throwsA(isA<RemoteFileFailure>()));
    expect(() => service.mkdir('/var/docker/project/..'),
        throwsA(isA<RemoteFileFailure>()));
  });

  test('rename changes entry path', () async {
    await service.rename(
        '/var/docker/project/README.md', '/var/docker/project/README_OLD.md');
    expect(fs.files.containsKey('/var/docker/project/README_OLD.md'), isTrue);
    expect(fs.files.containsKey('/var/docker/project/README.md'), isFalse);
  });

  test('deleteFile removes regular file', () async {
    await service.deleteFile('/var/docker/project/README.md');
    expect(fs.files.containsKey('/var/docker/project/README.md'), isFalse);
  });

  test('deleteDirectory deletes empty dir and blocks non-empty dir', () async {
    await service.mkdir('/var/docker/project/empty');
    await service.deleteDirectory('/var/docker/project/empty');
    expect(fs.directories.contains('/var/docker/project/empty'), isFalse);

    // Non-empty deletion fails safely
    expect(
        () => service.deleteDirectory('/var/docker/project'),
        throwsA(isA<RemoteFileFailure>().having(
            (e) => e.kind, 'kind', RemoteFileFailureKind.directoryNotEmpty)));
  });

  test('isSensitiveFile identifies credentials and keys', () {
    expect(RemoteFileService.isSensitiveFile('/var/.env'), isTrue);
    expect(RemoteFileService.isSensitiveFile('/var/.env.production'), isTrue);
    expect(RemoteFileService.isSensitiveFile('/home/lab/.ssh/id_rsa'), isTrue);
    expect(
        RemoteFileService.isSensitiveFile('/home/lab/.ssh/id_ed25519'), isTrue);
    expect(RemoteFileService.isSensitiveFile('/etc/ssl/server.key'), isTrue);
    expect(RemoteFileService.isSensitiveFile('/etc/ssl/cert.pem'), isTrue);
    expect(RemoteFileService.isSensitiveFile('/var/docker/README.md'), isFalse);
    expect(RemoteFileService.isSensitiveFile('/var/docker/main.dart'), isFalse);
  });
}
