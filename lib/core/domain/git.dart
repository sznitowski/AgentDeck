/// File status within Git index or working tree.
enum GitFileStatus {
  unmodified,
  modified,
  added,
  deleted,
  renamed,
  copied,
  untracked,
  conflict,
  ignored,
}

/// A changed file record inside a Git repository.
class GitFileChange {
  const GitFileChange({
    required this.path,
    this.oldPath,
    this.indexStatus = GitFileStatus.unmodified,
    this.workTreeStatus = GitFileStatus.unmodified,
  });

  final String path;
  final String? oldPath;
  final GitFileStatus indexStatus;
  final GitFileStatus workTreeStatus;

  bool get isUntracked =>
      indexStatus == GitFileStatus.untracked ||
      workTreeStatus == GitFileStatus.untracked;

  bool get isConflict =>
      indexStatus == GitFileStatus.conflict ||
      workTreeStatus == GitFileStatus.conflict;

  bool get isStaged =>
      indexStatus != GitFileStatus.unmodified &&
      indexStatus != GitFileStatus.untracked &&
      indexStatus != GitFileStatus.ignored;

  bool get isUnstaged =>
      workTreeStatus != GitFileStatus.unmodified &&
      workTreeStatus != GitFileStatus.untracked &&
      workTreeStatus != GitFileStatus.ignored;

  bool get isDeleted =>
      indexStatus == GitFileStatus.deleted ||
      workTreeStatus == GitFileStatus.deleted;

  bool get isRenamed =>
      indexStatus == GitFileStatus.renamed ||
      workTreeStatus == GitFileStatus.renamed;
}

/// Parsed status of a Git repository.
class GitStatus {
  const GitStatus({
    this.branch,
    this.headCommit,
    this.isDetachedHead = false,
    this.upstream,
    this.ahead = 0,
    this.behind = 0,
    this.changedFiles = const [],
  });

  final String? branch;
  final String? headCommit;
  final bool isDetachedHead;
  final String? upstream;
  final int ahead;
  final int behind;
  final List<GitFileChange> changedFiles;

  bool get isClean => changedFiles.isEmpty;
  int get stagedCount => changedFiles.where((f) => f.isStaged).length;
  int get unstagedCount => changedFiles.where((f) => f.isUnstaged).length;
  int get untrackedCount => changedFiles.where((f) => f.isUntracked).length;
  int get conflictCount => changedFiles.where((f) => f.isConflict).length;
}

/// Metadata describing a Git repository.
class GitRepository {
  const GitRepository({
    required this.path,
    this.rootPath,
    this.isRepository = true,
    this.currentBranch,
    this.headCommit,
    this.isDetachedHead = false,
    this.upstream,
    this.ahead = 0,
    this.behind = 0,
  });

  final String path;
  final String? rootPath;
  final bool isRepository;
  final String? currentBranch;
  final String? headCommit;
  final bool isDetachedHead;
  final String? upstream;
  final int ahead;
  final int behind;
}

/// A single Git commit in log history.
class GitCommit {
  const GitCommit({
    required this.hash,
    required this.shortHash,
    required this.authorName,
    this.authorEmail,
    required this.timestamp,
    required this.subject,
    this.parents = const [],
  });

  final String hash;
  final String shortHash;
  final String authorName;
  final String? authorEmail;
  final DateTime timestamp;
  final String subject;
  final List<String> parents;
}

enum GitDiffLineType {
  header,
  context,
  addition,
  deletion,
}

class GitDiffLine {
  const GitDiffLine({
    required this.type,
    required this.content,
    this.oldLineNumber,
    this.newLineNumber,
  });

  final GitDiffLineType type;
  final String content;
  final int? oldLineNumber;
  final int? newLineNumber;
}

class GitDiffHunk {
  const GitDiffHunk({
    required this.header,
    required this.lines,
    required this.oldStart,
    required this.oldCount,
    required this.newStart,
    required this.newCount,
  });

  final String header;
  final List<GitDiffLine> lines;
  final int oldStart;
  final int oldCount;
  final int newStart;
  final int newCount;
}

/// Representation of a parsed unified diff.
class GitDiff {
  const GitDiff({
    required this.filePath,
    this.isStaged = false,
    this.isSensitive = false,
    this.rawText = '',
    this.hunks = const [],
    this.additions = 0,
    this.deletions = 0,
    this.isTruncated = false,
  });

  final String filePath;
  final bool isStaged;
  final bool isSensitive;
  final String rawText;
  final List<GitDiffHunk> hunks;
  final int additions;
  final int deletions;
  final bool isTruncated;
}

/// Remote Git tool availability on server.
class GitAvailability {
  const GitAvailability({
    required this.isInstalled,
    this.version,
    this.binaryPath,
  });

  final bool isInstalled;
  final String? version;
  final String? binaryPath;
}

enum GitRepositoryState {
  repository,
  notRepository,
  unavailable,
  permissionDenied,
  gitNotInstalled,
}

enum GitFailureKind {
  notRepository,
  gitNotInstalled,
  permissionDenied,
  conflict,
  invalidPath,
  operationFailed,
  timeout,
  disconnected,
}

class GitFailure implements Exception {
  const GitFailure(
    this.kind, {
    this.message,
    this.exitCode,
    this.stderr,
  });

  final GitFailureKind kind;
  final String? message;
  final int? exitCode;
  final String? stderr;

  @override
  String toString() =>
      'GitFailure($kind${message != null ? ': $message' : ''})';
}

/// Abstract contract for executing raw remote commands for Git.
abstract interface class GitCommandExecutor {
  Future<RemoteCommandOutput> execute(
    List<String> arguments, {
    Duration timeout = const Duration(seconds: 15),
  });
}

/// Result of a remote command execution.
class RemoteCommandOutput {
  const RemoteCommandOutput(this.exitCode, this.stdout, this.stderr);
  final int exitCode;
  final String stdout;
  final String stderr;
}

/// High-level domain service interface for remote Git operations.
abstract interface class GitService {
  Future<GitAvailability> checkAvailability();
  Future<GitRepository> inspectRepository(String workingDirectory);
  Future<GitStatus> getStatus(String workingDirectory);
  Future<GitDiff> getDiff(
    String workingDirectory, {
    String? filePath,
    bool staged = false,
  });
  Future<List<GitCommit>> getHistory(
    String workingDirectory, {
    int limit = 50,
  });
  Future<void> stage(String workingDirectory, String filePath);
  Future<void> unstage(String workingDirectory, String filePath);
  Future<GitCommit> commit(String workingDirectory, String message);
}
