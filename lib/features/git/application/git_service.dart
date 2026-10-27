import '../../../core/domain/git.dart';
import '../domain/git_parsers.dart';

/// Concrete implementation of [GitService] executing commands via [GitCommandExecutor].
class RemoteGitService implements GitService {
  const RemoteGitService({
    required this.executor,
  });

  final GitCommandExecutor executor;

  @override
  Future<GitAvailability> checkAvailability() async {
    try {
      final res = await executor.execute(const ['git', '--version']);
      if (res.exitCode == 0) {
        final version = _parseGitVersion(res.stdout);
        return GitAvailability(
          isInstalled: true,
          version: version,
          binaryPath: 'git',
        );
      }
      return const GitAvailability(isInstalled: false);
    } catch (_) {
      return const GitAvailability(isInstalled: false);
    }
  }

  @override
  Future<GitRepository> inspectRepository(String workingDirectory) async {
    final sanitizedDir =
        GitCommandSafety.sanitizeWorkingDirectory(workingDirectory);

    final check = await executor.execute([
      'git',
      '-C',
      sanitizedDir,
      'rev-parse',
      '--is-inside-work-tree',
    ]);

    if (check.exitCode != 0 || check.stdout.trim() != 'true') {
      return GitRepository(
        path: sanitizedDir,
        isRepository: false,
      );
    }

    String? rootPath;
    final rootRes = await executor.execute([
      'git',
      '-C',
      sanitizedDir,
      'rev-parse',
      '--show-toplevel',
    ]);
    if (rootRes.exitCode == 0) {
      rootPath = rootRes.stdout.trim();
    }

    final status = await getStatus(sanitizedDir);

    return GitRepository(
      path: sanitizedDir,
      rootPath: rootPath ?? sanitizedDir,
      isRepository: true,
      currentBranch: status.branch,
      headCommit: status.headCommit,
      isDetachedHead: status.isDetachedHead,
      upstream: status.upstream,
      ahead: status.ahead,
      behind: status.behind,
    );
  }

  @override
  Future<GitStatus> getStatus(String workingDirectory) async {
    final sanitizedDir =
        GitCommandSafety.sanitizeWorkingDirectory(workingDirectory);

    final res = await executor.execute([
      'git',
      '-C',
      sanitizedDir,
      'status',
      '--porcelain=v2',
      '--branch',
    ]);

    if (res.exitCode != 0) {
      _mapGitError(res.exitCode, res.stderr);
    }

    return GitPorcelainV2Parser.parse(res.stdout);
  }

  @override
  Future<GitDiff> getDiff(
    String workingDirectory, {
    String? filePath,
    bool staged = false,
  }) async {
    final sanitizedDir =
        GitCommandSafety.sanitizeWorkingDirectory(workingDirectory);

    final args = <String>['git', '-C', sanitizedDir, 'diff'];
    if (staged) {
      args.add('--cached');
    }
    if (filePath != null && filePath.trim().isNotEmpty) {
      args.add('--');
      args.add(filePath.trim());
    }

    final res = await executor.execute(args);
    if (res.exitCode != 0) {
      _mapGitError(res.exitCode, res.stderr);
    }

    final isSensitive =
        filePath != null && GitCommandSafety.isSensitiveFile(filePath);

    return GitDiffParser.parse(
      res.stdout,
      filePath:
          filePath ?? (staged ? 'Staged Changes' : 'Working Tree Changes'),
      isStaged: staged,
      isSensitive: isSensitive,
    );
  }

  @override
  Future<List<GitCommit>> getHistory(
    String workingDirectory, {
    int limit = 50,
  }) async {
    final sanitizedDir =
        GitCommandSafety.sanitizeWorkingDirectory(workingDirectory);
    final clampedLimit = limit.clamp(1, 100);

    final res = await executor.execute([
      'git',
      '-C',
      sanitizedDir,
      'log',
      '-n',
      clampedLimit.toString(),
      '--format=%H%x1f%h%x1f%an%x1f%ae%x1f%at%x1f%s%x1f%P',
    ]);

    if (res.exitCode != 0) {
      if (res.stderr.contains('does not have any commits yet') ||
          res.stderr.contains('fatal: your current branch')) {
        return const [];
      }
      _mapGitError(res.exitCode, res.stderr);
    }

    return GitLogParser.parse(res.stdout);
  }

  @override
  Future<void> stage(String workingDirectory, String filePath) async {
    final sanitizedDir =
        GitCommandSafety.sanitizeWorkingDirectory(workingDirectory);
    final targetPath = filePath.trim();
    if (targetPath.isEmpty) {
      throw const GitFailure(
        GitFailureKind.invalidPath,
        message: 'File path cannot be empty',
      );
    }

    final res = await executor.execute([
      'git',
      '-C',
      sanitizedDir,
      'add',
      '--',
      targetPath,
    ]);

    if (res.exitCode != 0) {
      _mapGitError(res.exitCode, res.stderr);
    }
  }

  @override
  Future<void> unstage(String workingDirectory, String filePath) async {
    final sanitizedDir =
        GitCommandSafety.sanitizeWorkingDirectory(workingDirectory);
    final targetPath = filePath.trim();
    if (targetPath.isEmpty) {
      throw const GitFailure(
        GitFailureKind.invalidPath,
        message: 'File path cannot be empty',
      );
    }

    // Try `git restore --staged -- <path>`
    var res = await executor.execute([
      'git',
      '-C',
      sanitizedDir,
      'restore',
      '--staged',
      '--',
      targetPath,
    ]);

    // Fallback to `git reset HEAD -- <path>` for older Git installations
    if (res.exitCode != 0 &&
        (res.stderr.contains('is not a git command') ||
            res.stderr.contains('unknown option'))) {
      res = await executor.execute([
        'git',
        '-C',
        sanitizedDir,
        'reset',
        'HEAD',
        '--',
        targetPath,
      ]);
    }

    if (res.exitCode != 0) {
      _mapGitError(res.exitCode, res.stderr);
    }
  }

  @override
  Future<GitCommit> commit(String workingDirectory, String message) async {
    final sanitizedDir =
        GitCommandSafety.sanitizeWorkingDirectory(workingDirectory);
    final msg = message.trim();
    if (msg.isEmpty) {
      throw const GitFailure(
        GitFailureKind.invalidPath,
        message: 'Commit message cannot be empty',
      );
    }

    final res = await executor.execute([
      'git',
      '-C',
      sanitizedDir,
      'commit',
      '-m',
      msg,
    ]);

    if (res.exitCode != 0) {
      if (res.stdout.contains('nothing to commit') ||
          res.stderr.contains('nothing to commit')) {
        throw const GitFailure(
          GitFailureKind.operationFailed,
          message: 'Nothing to commit (stage changes first).',
        );
      }
      _mapGitError(
          res.exitCode, res.stderr.isNotEmpty ? res.stderr : res.stdout);
    }

    final history = await getHistory(sanitizedDir, limit: 1);
    if (history.isEmpty) {
      throw const GitFailure(
        GitFailureKind.operationFailed,
        message: 'Commit completed but failed to retrieve commit details.',
      );
    }
    return history.first;
  }

  void _mapGitError(int exitCode, String stderr) {
    final err = stderr.toLowerCase();
    if (err.contains('not a git repository')) {
      throw GitFailure(
        GitFailureKind.notRepository,
        message: 'Not a git repository',
        exitCode: exitCode,
        stderr: stderr,
      );
    }
    if (err.contains('permission denied')) {
      throw GitFailure(
        GitFailureKind.permissionDenied,
        message: 'Permission denied accessing repository or files',
        exitCode: exitCode,
        stderr: stderr,
      );
    }
    if (err.contains('command not found') || err.contains('git: not found')) {
      throw GitFailure(
        GitFailureKind.gitNotInstalled,
        message: 'Git is not installed on this server',
        exitCode: exitCode,
        stderr: stderr,
      );
    }
    if (err.contains('conflict') || err.contains('unmerged')) {
      throw GitFailure(
        GitFailureKind.conflict,
        message: 'Merge conflict detected',
        exitCode: exitCode,
        stderr: stderr,
      );
    }

    throw GitFailure(
      GitFailureKind.operationFailed,
      message: stderr.trim().isNotEmpty ? stderr.trim() : 'Git command failed',
      exitCode: exitCode,
      stderr: stderr,
    );
  }

  String _parseGitVersion(String rawOutput) {
    final match = RegExp(r'(\d+\.\d+(?:\.\d+)?)').firstMatch(rawOutput);
    return match?.group(1) ?? rawOutput.trim();
  }
}
