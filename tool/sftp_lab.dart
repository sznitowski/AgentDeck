// Disposable loopback OpenSSH + SFTP integration lab.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:agentdeck/core/domain/profiles.dart';
import 'package:agentdeck/core/domain/remote_contracts.dart';
import 'package:agentdeck/features/connections/application/ssh_connection_service.dart';
import 'package:agentdeck/features/connections/domain/ssh_models.dart';
import 'package:agentdeck/features/connections/infrastructure/dart_ssh_transport.dart';
import 'package:agentdeck/features/files/domain/remote_file_models.dart';

class _Secrets implements SecureCredentialStore {
  _Secrets(this.secret);
  final List<int> secret;
  @override
  Future<List<int>?> get(String reference) async => secret;
  @override
  Future<void> put(String reference, List<int> value) async =>
      throw UnsupportedError('Lab');
  @override
  Future<void> delete(String reference) async => throw UnsupportedError('Lab');
}

class _Hosts implements KnownHostRepository {
  _Hosts(this.host);
  final KnownHost host;
  @override
  Future<KnownHost?> find(String hostname, int port) async => host;
  @override
  Future<void> markSeen(String hostname, int port, DateTime at) async {}
  @override
  Future<void> trust(KnownHost host) async => throw UnsupportedError('Lab');
  @override
  Future<void> revoke(String hostname, int port) async =>
      throw UnsupportedError('Lab');
  @override
  Future<void> replace(KnownHost host) async => throw UnsupportedError('Lab');
  @override
  Future<void> delete(String hostname, int port) async =>
      throw UnsupportedError('Lab');
}

class _DigestSink implements Sink<Digest> {
  Digest? value;
  @override
  void add(Digest data) => value = data;
  @override
  void close() {}
}

Future<void> main() async {
  final env = Platform.environment;
  final host = env['AGENTDECK_TEST_SSH_HOST'];
  final port = int.tryParse(env['AGENTDECK_TEST_SSH_PORT'] ?? '');
  final password = env['AGENTDECK_TEST_SSH_PASSWORD'];
  final fingerprint = env['AGENTDECK_TEST_SSH_FINGERPRINT'];
  if (host == null ||
      !{'127.0.0.1', 'localhost', '::1'}.contains(host) ||
      port == null ||
      port < 1 ||
      port > 65535 ||
      password == null ||
      fingerprint == null) {
    stderr.writeln(
        'Disposable loopback SSH credentials and pinned fingerprint required.');
    exitCode = 2;
    return;
  }
  final profile = ServerProfile(
      id: 'sftp-lab',
      name: 'SFTP Lab',
      host: host,
      port: port,
      username: 'lab',
      credentialId: 'lab',
      authenticationMethod: SshAuthenticationMethod.password);
  final now = DateTime.now().toUtc();
  final known = KnownHost(
      hostname: host,
      port: port,
      identity: HostIdentity('ssh-ed25519', fingerprint),
      firstSeenAt: now,
      lastSeenAt: now);
  final connection = SshConnectionService(
      credentials: _Secrets(utf8.encode(password)),
      knownHosts: _Hosts(known),
      transport: const DartSshTransport());

  RemoteFileSystem? fs;

  try {
    // -------------------------------------------------------------
    // Scenario A: Connect & SFTP Open
    // -------------------------------------------------------------
    await connection.connect(profile);
    fs = await connection.openSftp();
    stdout.writeln('A SFTP connect and open: PASS');

    // -------------------------------------------------------------
    // Scenario B: List directory
    // -------------------------------------------------------------
    final homeEntries = await fs.list('/home/lab');
    stdout.writeln(
        'B list directory (/home/lab, ${homeEntries.length} items): PASS');

    // -------------------------------------------------------------
    // Scenario C: mkdir
    // -------------------------------------------------------------
    const testDir = '/tmp/agentdeck-sftp-test';
    try {
      await fs.delete(testDir);
    } catch (_) {}
    try {
      await fs.rmdir(testDir);
    } catch (_) {}

    await fs.mkdir(testDir);
    final tmpEntries = await fs.list('/tmp');
    if (!tmpEntries
        .any((e) => e.name == 'agentdeck-sftp-test' && e.isDirectory)) {
      throw StateError('C: mkdir verification failed');
    }
    stdout.writeln('C mkdir ($testDir): PASS');

    // -------------------------------------------------------------
    // Scenario D: Upload UTF-8 file
    // -------------------------------------------------------------
    const fileD = '$testDir/hello.txt';
    const contentD = 'Hello AgentDeck SFTP!\nLine 2: 🚀 ñ á 漢字\nEnd of test.\n';
    final bytesD = utf8.encode(contentD);
    await fs.write(fileD, bytesD, atomic: true);
    stdout.writeln('D upload UTF-8 text file: PASS');

    // -------------------------------------------------------------
    // Scenario E: Stat metadata
    // -------------------------------------------------------------
    final statD = await fs.stat(fileD);
    if (statD.name != 'hello.txt' ||
        statD.size != bytesD.length ||
        statD.type != RemoteEntryType.file ||
        statD.modifiedAt == null) {
      throw StateError('E: stat mismatch: ${statD.toString()}');
    }
    stdout.writeln('E stat metadata check: PASS');

    // -------------------------------------------------------------
    // Scenario F: Download & SHA-256 match
    // -------------------------------------------------------------
    final downloadedD = await fs.read(fileD);
    final hashLocalD = sha256.convert(bytesD).toString();
    final hashRemoteD = sha256.convert(downloadedD).toString();
    if (hashLocalD != hashRemoteD || utf8.decode(downloadedD) != contentD) {
      throw StateError('F: SHA-256 download mismatch');
    }
    stdout.writeln('F download and SHA-256 integrity: PASS');

    // -------------------------------------------------------------
    // Scenario G: UTF-8 filename
    // -------------------------------------------------------------
    const utf8Name = 'archivo-ñ-漢字.txt';
    const fileG = '$testDir/$utf8Name';
    const contentG = 'Contenido con caracteres especiales: áéíóú ñ 漢字 🧪';
    await fs.write(fileG, utf8.encode(contentG), atomic: true);
    final entriesG = await fs.list(testDir);
    if (!entriesG.any((e) => e.name == utf8Name)) {
      throw StateError('G: UTF-8 filename not listed');
    }
    final statG = await fs.stat(fileG);
    if (statG.name != utf8Name || statG.size != utf8.encode(contentG).length) {
      throw StateError('G: stat on UTF-8 filename failed');
    }
    final readG = await fs.read(fileG);
    if (utf8.decode(readG) != contentG) {
      throw StateError('G: read content mismatch on UTF-8 filename');
    }
    stdout.writeln('G UTF-8 filename ($utf8Name): PASS');

    // -------------------------------------------------------------
    // Scenario H: Rename
    // -------------------------------------------------------------
    const renamedName = 'renamed-utf8-漢字.txt';
    const fileH = '$testDir/$renamedName';
    await fs.rename(fileG, fileH);
    final entriesH = await fs.list(testDir);
    if (entriesH.any((e) => e.name == utf8Name)) {
      throw StateError('H: old filename still exists after rename');
    }
    if (!entriesH.any((e) => e.name == renamedName)) {
      throw StateError('H: renamed file not found');
    }
    final readH = await fs.read(fileH);
    if (utf8.decode(readH) != contentG) {
      throw StateError('H: content corrupted after rename');
    }
    stdout.writeln('H rename: PASS');

    // -------------------------------------------------------------
    // Scenario I: Permissions error handling
    // -------------------------------------------------------------
    bool permDeniedCaught = false;
    try {
      // Writing to /etc/agentdeck_perm_test as unprivileged user 'lab'
      await fs.write('/etc/agentdeck_perm_test', utf8.encode('fail'));
    } on RemoteFileFailure catch (e) {
      if (e.kind == RemoteFileFailureKind.permissionDenied) {
        permDeniedCaught = true;
      } else {
        throw StateError(
            'I: Unexpected failure kind: ${e.kind} (${e.message})');
      }
    }
    if (!permDeniedCaught) {
      throw StateError('I: Permission denied was not thrown');
    }
    stdout.writeln('I permissions error handling: PASS');

    // -------------------------------------------------------------
    // Scenario J: Delete file
    // -------------------------------------------------------------
    await fs.delete(fileD);
    bool notFoundCaught = false;
    try {
      await fs.stat(fileD);
    } on RemoteFileFailure catch (e) {
      if (e.kind == RemoteFileFailureKind.notFound) {
        notFoundCaught = true;
      }
    }
    if (!notFoundCaught) {
      throw StateError('J: file still exists after delete');
    }
    stdout.writeln('J delete file: PASS');

    // -------------------------------------------------------------
    // Scenario K: Non-empty directory delete rejection
    // -------------------------------------------------------------
    const subDirK = '$testDir/subfolder_with_content';
    await fs.mkdir(subDirK);
    await fs.write('$subDirK/nested.txt', utf8.encode('nested file content'));
    bool rmdirFailed = false;
    try {
      await fs.rmdir(subDirK);
    } on RemoteFileFailure {
      rmdirFailed = true;
    }
    if (!rmdirFailed) {
      throw StateError('K: rmdir should have failed on non-empty directory');
    }
    // Clean up nested file and directory
    await fs.delete('$subDirK/nested.txt');
    await fs.rmdir(subDirK);
    await fs.delete(fileH);
    stdout.writeln('K non-empty directory delete protection: PASS');

    // -------------------------------------------------------------
    // Scenario L: Cleanup test directory
    // -------------------------------------------------------------
    await fs.rmdir(testDir);
    final entriesL = await fs.list('/tmp');
    if (entriesL.any((e) => e.name == 'agentdeck-sftp-test')) {
      throw StateError('L: directory still present after cleanup');
    }
    stdout.writeln('L cleanup: PASS');

    // -------------------------------------------------------------
    // Scenario M: Large streaming transfer (25 MB)
    // -------------------------------------------------------------
    const largeFilePath = '/tmp/agentdeck-large-test.bin';
    const totalBytes = 25 * 1024 * 1024; // 25 MB
    const chunkSize = 64 * 1024; // 64 KB chunks
    final chunkCount = totalBytes ~/ chunkSize;

    // Seeded pseudo-random data generator for deterministic SHA-256
    final localDigestSink = _DigestSink();
    final localByteSink = sha256.startChunkedConversion(localDigestSink);

    final randomSeed = Random(42);
    final patternChunk = Uint8List(chunkSize);
    for (int i = 0; i < chunkSize; i++) {
      patternChunk[i] = randomSeed.nextInt(256);
    }

    Stream<List<int>> generateUploadStream() async* {
      for (int i = 0; i < chunkCount; i++) {
        localByteSink.add(patternChunk);
        yield patternChunk;
      }
      localByteSink.close();
    }

    int bytesUploaded = 0;
    await fs.writeStream(
      largeFilePath,
      generateUploadStream(),
      length: totalBytes,
      atomic: true,
      onProgress: (written) => bytesUploaded = written,
    );

    if (bytesUploaded != totalBytes) {
      throw StateError(
          'M: bytesUploaded ($bytesUploaded) did not match totalBytes ($totalBytes)');
    }

    final localSha256 = localDigestSink.value.toString();

    // Verify stat size
    final largeStat = await fs.stat(largeFilePath);
    if (largeStat.size != totalBytes) {
      throw StateError(
          'M: large file size mismatch: expected $totalBytes, got ${largeStat.size}');
    }

    // Stream download and compute SHA-256
    final downloadDigestSink = _DigestSink();
    final downloadByteSink = sha256.startChunkedConversion(downloadDigestSink);
    int bytesDownloaded = 0;

    await for (final chunk in fs.readStream(largeFilePath)) {
      downloadByteSink.add(chunk);
      bytesDownloaded += chunk.length;
    }
    downloadByteSink.close();

    final remoteSha256 = downloadDigestSink.value.toString();

    if (bytesDownloaded != totalBytes || localSha256 != remoteSha256) {
      throw StateError(
          'M: SHA-256 mismatch on 25 MB stream (local=$localSha256, remote=$remoteSha256)');
    }

    await fs.delete(largeFilePath);
    stdout.writeln(
        'M 25 MB streaming transfer & SHA-256 match ($localSha256): PASS');

    // -------------------------------------------------------------
    // Scenario N: 1000-entry directory listing
    // -------------------------------------------------------------
    const perfDir = '/tmp/agentdeck-1000-test';
    await fs.mkdir(perfDir);

    // Fast batch creation of 1000 files using parallel futures with modest concurrency
    final futures = <Future<void>>[];
    const entryCount = 1000;
    for (int i = 0; i < entryCount; i++) {
      final name = 'entry_${i.toString().padLeft(4, '0')}.txt';
      futures
          .add(fs.write('$perfDir/$name', utf8.encode('e$i'), atomic: false));
      if (futures.length >= 50) {
        await Future.wait(futures);
        futures.clear();
      }
    }
    if (futures.isNotEmpty) {
      await Future.wait(futures);
      futures.clear();
    }

    final stopwatch = Stopwatch()..start();
    final perfEntries = await fs.list(perfDir);
    stopwatch.stop();

    if (perfEntries.length != entryCount) {
      throw StateError(
          'N: 1000 entry count mismatch: expected $entryCount, got ${perfEntries.length}');
    }

    // Cleanup 1000 files
    for (int i = 0; i < entryCount; i++) {
      final name = 'entry_${i.toString().padLeft(4, '0')}.txt';
      futures.add(fs.delete('$perfDir/$name'));
      if (futures.length >= 50) {
        await Future.wait(futures);
        futures.clear();
      }
    }
    if (futures.isNotEmpty) {
      await Future.wait(futures);
    }
    await fs.rmdir(perfDir);

    stdout.writeln(
        'N 1000-entry directory listing (${perfEntries.length} items in ${stopwatch.elapsedMilliseconds}ms): PASS');
  } catch (error, stack) {
    stderr.writeln('M4 SFTP lab failed: $error');
    stderr.writeln(stack);
    exitCode = 1;
  } finally {
    if (fs != null) {
      try {
        await fs.close();
      } catch (_) {}
    }
    await connection.dispose();
  }
}
