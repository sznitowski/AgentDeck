import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:agentdeck/core/domain/agents.dart';
import 'package:agentdeck/core/domain/git.dart';
import 'package:agentdeck/core/domain/profiles.dart';
import 'package:agentdeck/core/domain/remote_contracts.dart';
import 'package:agentdeck/features/connections/application/ssh_connection_service.dart';
import 'package:agentdeck/features/connections/domain/ssh_models.dart';
import 'package:agentdeck/features/connections/infrastructure/dart_ssh_transport.dart';
import 'package:agentdeck/features/git/application/git_service.dart';
import 'package:agentdeck/features/git/infrastructure/ssh_git_command_executor.dart';

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

void main() async {
  final host = Platform.environment['AGENTDECK_TEST_SSH_HOST'] ?? '127.0.0.1';
  final portStr = Platform.environment['AGENTDECK_TEST_SSH_PORT'];
  final password = Platform.environment['AGENTDECK_TEST_SSH_PASSWORD'];
  final fingerprint = Platform.environment['AGENTDECK_TEST_SSH_FINGERPRINT'];

  if (portStr == null || password == null || fingerprint == null) {
    stderr.writeln('Environment variables missing for Git integration lab');
    exit(1);
  }

  final port = int.parse(portStr);
  final credentials = _Secrets(utf8.encode(password));
  final knownHosts = _Hosts(KnownHost(
    hostname: host,
    port: port,
    identity: HostIdentity('ssh-ed25519', fingerprint),
    firstSeenAt: DateTime.now().toUtc(),
    lastSeenAt: DateTime.now().toUtc(),
  ));
  final transport = const DartSshTransport();

  const credId = 'cred_lab';

  final server = ServerProfile(
    id: 'srv_git_lab',
    name: 'Git Lab Server',
    host: host,
    port: port,
    username: 'lab',
    credentialId: credId,
    authenticationMethod: SshAuthenticationMethod.password,
    environment: Environment.development,
  );

  final connection = SshConnectionService(
    credentials: credentials,
    knownHosts: knownHosts,
    transport: transport,
  );

  stdout.writeln('--- M6 Git Operations Integration Lab ---');

  try {
    // 0. Connect SSH
    stdout.writeln('Connecting SSH to $host:$port...');
    await connection.connect(server, approve: (_, __) async => true);
    if (connection.state != ConnectionState.connected) {
      throw Exception('Failed to connect SSH');
    }
    stdout.writeln('SSH Connected.');

    final executor = SshGitCommandExecutor(
      connection: connection,
      serverId: server.id,
    );
    final service = RemoteGitService(executor: executor);

    // Scenario A: Git Detection
    stdout.writeln('\n[Scenario A] Git detection...');
    final avail = await service.checkAvailability();
    if (!avail.isInstalled || avail.version == null) {
      throw Exception('Scenario A failed: Git not detected as installed.');
    }
    stdout.writeln('  PASS: Git version ${avail.version} detected.');

    // Prepare remote test git repository in /home/lab/project
    stdout.writeln('\nPreparing remote Git repository fixture...');
    await connection.runRemoteCommand(
        ['rm', '-rf', '/home/lab/project', '/home/lab/not_a_repo']);
    await connection.runRemoteCommand(
        ['mkdir', '-p', '/home/lab/project', '/home/lab/not_a_repo']);

    // Configure git user on test repo
    await connection.runRemoteCommand(
        ['git', 'config', '--global', 'user.name', 'Lab User']);
    await connection.runRemoteCommand(
        ['git', 'config', '--global', 'user.email', 'lab@example.com']);
    await connection.runRemoteCommand(
        ['git', 'config', '--global', 'init.defaultBranch', 'main']);

    // Init repository
    await connection
        .runRemoteCommand(['git', '-C', '/home/lab/project', 'init']);
    await connection.runRemoteCommand(
        ['sh', '-c', "printf 'initial\\n' > /home/lab/project/README.md"]);
    await connection.runRemoteCommand([
      'sh',
      '-c',
      "printf 'line 1\\nline 2\\n' > /home/lab/project/tracked.txt"
    ]);
    await connection.runRemoteCommand([
      'sh',
      '-c',
      "printf 'to be staged\\n' > /home/lab/project/staged.txt"
    ]);
    await connection.runRemoteCommand([
      'sh',
      '-c',
      "printf 'to be renamed\\n' > /home/lab/project/rename_old.txt"
    ]);
    await connection.runRemoteCommand([
      'sh',
      '-c',
      "printf 'to be deleted\\n' > /home/lab/project/to_delete.txt"
    ]);
    await connection.runRemoteCommand([
      'sh',
      '-c',
      "printf 'utf8 content\\n' > '/home/lab/project/archivo-ñ-漢字.txt'"
    ]);
    await connection.runRemoteCommand([
      'sh',
      '-c',
      "printf 'leading dash\\n' > '/home/lab/project/-leading-option.txt'"
    ]);
    await connection
        .runRemoteCommand(['git', '-C', '/home/lab/project', 'add', '.']);
    await connection.runRemoteCommand(
        ['git', '-C', '/home/lab/project', 'commit', '-m', 'initial commit']);

    // Make various changes for status testing
    await connection.runRemoteCommand([
      'sh',
      '-c',
      "printf 'line 3 added\\n' >> /home/lab/project/tracked.txt"
    ]); // unstaged modified
    await connection.runRemoteCommand([
      'sh',
      '-c',
      "printf 'staged modification\\n' >> /home/lab/project/staged.txt"
    ]);
    await connection.runRemoteCommand([
      'git',
      '-C',
      '/home/lab/project',
      'add',
      'staged.txt'
    ]); // staged modified
    await connection.runRemoteCommand([
      'git',
      '-C',
      '/home/lab/project',
      'mv',
      'rename_old.txt',
      'rename_new.txt'
    ]); // staged rename
    await connection.runRemoteCommand([
      'git',
      '-C',
      '/home/lab/project',
      'rm',
      'to_delete.txt'
    ]); // staged delete
    await connection.runRemoteCommand([
      'sh',
      '-c',
      "printf 'modified utf8\\n' >> '/home/lab/project/archivo-ñ-漢字.txt'"
    ]); // unstaged utf8
    await connection.runRemoteCommand([
      'sh',
      '-c',
      "printf 'untracked content\\n' > /home/lab/project/untracked_new.txt"
    ]); // untracked

    // Scenario B: Repository Detection
    stdout.writeln('\n[Scenario B] Repository detection...');
    final repo = await service.inspectRepository('/home/lab/project');
    if (!repo.isRepository) {
      throw Exception('Scenario B failed: Repository not detected.');
    }
    stdout.writeln(
        '  PASS: Repository detected at ${repo.path} (root: ${repo.rootPath}).');

    // Scenario C: Branch
    stdout.writeln('\n[Scenario C] Branch detection...');
    if (repo.currentBranch != 'main' || repo.isDetachedHead) {
      throw Exception(
          'Scenario C failed: Expected branch main, got ${repo.currentBranch}.');
    }
    stdout.writeln('  PASS: Branch is ${repo.currentBranch}.');

    // Scenario D: Status parsing
    stdout.writeln('\n[Scenario D] Status parsing...');
    final status = await service.getStatus('/home/lab/project');
    stdout.writeln(
        '  Status: Total ${status.changedFiles.length} changes (Staged: ${status.stagedCount}, Unstaged: ${status.unstagedCount}, Untracked: ${status.untrackedCount}).');

    final stagedFile =
        status.changedFiles.firstWhere((f) => f.path == 'staged.txt');
    if (!stagedFile.isStaged) {
      throw Exception('Scenario D failed: staged.txt should be staged.');
    }

    final unstagedFile =
        status.changedFiles.firstWhere((f) => f.path == 'tracked.txt');
    if (!unstagedFile.isUnstaged) {
      throw Exception(
          'Scenario D failed: tracked.txt should be unstaged modified.');
    }

    final renamedFile =
        status.changedFiles.firstWhere((f) => f.path == 'rename_new.txt');
    if (!renamedFile.isRenamed || renamedFile.oldPath != 'rename_old.txt') {
      throw Exception(
          'Scenario D failed: rename_new.txt should reflect rename from rename_old.txt.');
    }

    final deletedFile =
        status.changedFiles.firstWhere((f) => f.path == 'to_delete.txt');
    if (!deletedFile.isDeleted) {
      throw Exception('Scenario D failed: to_delete.txt should be deleted.');
    }
    stdout.writeln(
        '  PASS: Staged, unstaged, renamed, deleted, and untracked records correctly parsed.');

    // Scenario E: HEAD
    stdout.writeln('\n[Scenario E] HEAD commit inspection...');
    if (status.headCommit == null || status.headCommit!.length != 40) {
      throw Exception(
          'Scenario E failed: Invalid HEAD hash ${status.headCommit}.');
    }
    stdout.writeln('  PASS: HEAD commit SHA ${status.headCommit}.');

    // Scenario F: Commit History
    stdout.writeln('\n[Scenario F] History inspection...');
    final history = await service.getHistory('/home/lab/project');
    if (history.isEmpty || history.first.subject != 'initial commit') {
      throw Exception(
          'Scenario F failed: History missing expected initial commit.');
    }
    stdout.writeln(
        '  PASS: History parsed (${history.length} commits), author: ${history.first.authorName}.');

    // Scenario G: Unstaged Diff
    stdout.writeln('\n[Scenario G] Unstaged diff...');
    final unstagedDiff = await service.getDiff('/home/lab/project',
        filePath: 'tracked.txt', staged: false);
    if (unstagedDiff.isStaged ||
        unstagedDiff.additions < 1 ||
        unstagedDiff.hunks.isEmpty) {
      throw Exception(
          'Scenario G failed: Unstaged diff for tracked.txt failed.');
    }
    stdout.writeln(
        '  PASS: Unstaged diff parsed (+${unstagedDiff.additions} / -${unstagedDiff.deletions}).');

    // Scenario H: Staged Diff
    stdout.writeln('\n[Scenario H] Staged diff...');
    final stagedDiff = await service.getDiff('/home/lab/project',
        filePath: 'staged.txt', staged: true);
    if (!stagedDiff.isStaged ||
        stagedDiff.additions < 1 ||
        stagedDiff.hunks.isEmpty) {
      throw Exception('Scenario H failed: Staged diff for staged.txt failed.');
    }
    stdout.writeln(
        '  PASS: Staged diff parsed (+${stagedDiff.additions} / -${stagedDiff.deletions}).');

    // Scenario I: UTF-8 Filename
    stdout.writeln('\n[Scenario I] UTF-8 filename handling...');
    final utf8File =
        status.changedFiles.firstWhere((f) => f.path == 'archivo-ñ-漢字.txt');
    if (!utf8File.isUnstaged) {
      throw Exception('Scenario I failed: archivo-ñ-漢字.txt not detected.');
    }
    final utf8Diff = await service.getDiff('/home/lab/project',
        filePath: 'archivo-ñ-漢字.txt');
    if (utf8Diff.hunks.isEmpty) {
      throw Exception('Scenario I failed: UTF-8 diff failed to parse.');
    }
    stdout.writeln('  PASS: UTF-8 filename and diff handled cleanly.');

    // Scenario J: Path beginning with dash
    stdout.writeln('\n[Scenario J] Path beginning with dash...');
    await connection.runRemoteCommand([
      'sh',
      '-c',
      "echo 'dash modified' >> '/home/lab/project/-leading-option.txt'"
    ]);
    await service.stage('/home/lab/project', '-leading-option.txt');
    final afterDashStage = await service.getStatus('/home/lab/project');
    final dashFile = afterDashStage.changedFiles
        .firstWhere((f) => f.path == '-leading-option.txt');
    if (!dashFile.isStaged) {
      throw Exception(
          'Scenario J failed: -leading-option.txt failed to stage safely.');
    }
    await service.unstage('/home/lab/project', '-leading-option.txt');
    stdout.writeln(
        '  PASS: Path starting with dash executed safely without option injection.');

    // Scenario K: Stage File
    stdout.writeln('\n[Scenario K] Staging untracked file...');
    await service.stage('/home/lab/project', 'untracked_new.txt');
    final statusAfterStage = await service.getStatus('/home/lab/project');
    final newlyStaged = statusAfterStage.changedFiles
        .firstWhere((f) => f.path == 'untracked_new.txt');
    if (!newlyStaged.isStaged) {
      throw Exception('Scenario K failed: untracked_new.txt was not staged.');
    }
    stdout.writeln('  PASS: Stage successful.');

    // Scenario L: Unstage File
    stdout.writeln('\n[Scenario L] Unstaging file...');
    await service.unstage('/home/lab/project', 'untracked_new.txt');
    final statusAfterUnstage = await service.getStatus('/home/lab/project');
    final newlyUnstaged = statusAfterUnstage.changedFiles
        .firstWhere((f) => f.path == 'untracked_new.txt');
    if (newlyUnstaged.isStaged) {
      throw Exception('Scenario L failed: untracked_new.txt remains staged.');
    }
    stdout.writeln('  PASS: Unstage successful.');

    // Scenario M: Merge Conflict Detection
    stdout.writeln('\n[Scenario M] Conflict detection...');
    // Create conflict branch and force conflict
    await connection.runRemoteCommand([
      'git',
      '-C',
      '/home/lab/project',
      'checkout',
      '-b',
      'conflict-branch'
    ]);
    await connection.runRemoteCommand([
      'sh',
      '-c',
      "echo 'conflict branch change' > /home/lab/project/conflict_file.txt"
    ]);
    await connection.runRemoteCommand(
        ['git', '-C', '/home/lab/project', 'add', 'conflict_file.txt']);
    await connection.runRemoteCommand(
        ['git', '-C', '/home/lab/project', 'commit', '-m', 'conflict commit']);

    await connection.runRemoteCommand(
        ['git', '-C', '/home/lab/project', 'checkout', 'main']);
    await connection.runRemoteCommand([
      'sh',
      '-c',
      "echo 'main branch change' > /home/lab/project/conflict_file.txt"
    ]);
    await connection.runRemoteCommand(
        ['git', '-C', '/home/lab/project', 'add', 'conflict_file.txt']);
    await connection.runRemoteCommand([
      'git',
      '-C',
      '/home/lab/project',
      'commit',
      '-m',
      'main change commit'
    ]);

    // Merge conflict-branch (will create conflict)
    await connection.runRemoteCommand(
        ['git', '-C', '/home/lab/project', 'merge', 'conflict-branch']);

    final conflictStatus = await service.getStatus('/home/lab/project');
    if (conflictStatus.conflictCount == 0) {
      throw Exception('Scenario M failed: Conflict was not detected.');
    }
    final conflictedFile = conflictStatus.changedFiles
        .firstWhere((f) => f.path == 'conflict_file.txt');
    if (!conflictedFile.isConflict) {
      throw Exception(
          'Scenario M failed: conflict_file.txt is not marked as conflict.');
    }
    stdout.writeln(
        '  PASS: Conflict detected (${conflictStatus.conflictCount} conflicts) without auto-resolution.');

    // Scenario N: Non-Repository
    stdout.writeln('\n[Scenario N] Non-repository handling...');
    final nonRepo = await service.inspectRepository('/home/lab/not_a_repo');
    if (nonRepo.isRepository) {
      throw Exception(
          'Scenario N failed: /home/lab/not_a_repo marked as repository.');
    }
    try {
      await service.getStatus('/home/lab/not_a_repo');
      throw Exception(
          'Scenario N failed: getStatus on non-repo did not throw.');
    } on GitFailure catch (e) {
      if (e.kind != GitFailureKind.notRepository) {
        throw Exception(
            'Scenario N failed: Expected notRepository failure, got ${e.kind}.');
      }
    }
    stdout.writeln('  PASS: Non-repository correctly classified.');

    stdout.writeln('\n=========================================');
    stdout.writeln('ALL SCENARIOS A through N PASSED.');
    stdout.writeln('=========================================');
  } finally {
    await connection.dispose();
  }
}
