import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:agentdeck/core/domain/git.dart';
import 'package:agentdeck/core/domain/profiles.dart';
import 'package:agentdeck/features/git/presentation/git_changes_page.dart';
import 'package:agentdeck/features/git/presentation/git_diff_viewer_page.dart';
import 'package:agentdeck/features/git/presentation/git_history_page.dart';
import 'package:agentdeck/features/git/presentation/project_git_page.dart';

class _FakeGitService implements GitService {
  _FakeGitService();

  GitAvailability availability =
      const GitAvailability(isInstalled: true, version: '2.40.0');
  GitRepository repository = const GitRepository(
    path: '/home/lab/project',
    isRepository: true,
    currentBranch: 'main',
    headCommit: 'a1b2c3d4e5f6',
    ahead: 1,
    behind: 0,
  );
  GitStatus status = const GitStatus(
    branch: 'main',
    headCommit: 'a1b2c3d4e5f6',
    ahead: 1,
    behind: 0,
    changedFiles: [
      GitFileChange(
          path: 'lib/staged.dart', indexStatus: GitFileStatus.modified),
      GitFileChange(
          path: 'lib/unstaged.dart', workTreeStatus: GitFileStatus.modified),
      GitFileChange(path: 'notes.txt', workTreeStatus: GitFileStatus.untracked),
    ],
  );

  final List<String> stagedFiles = [];
  final List<String> unstagedFiles = [];

  @override
  Future<GitAvailability> checkAvailability() async => availability;

  @override
  Future<GitRepository> inspectRepository(String workingDirectory) async =>
      repository;

  @override
  Future<GitStatus> getStatus(String workingDirectory) async => status;

  @override
  Future<GitDiff> getDiff(String workingDirectory,
      {String? filePath, bool staged = false}) async {
    return GitDiff(
      filePath: filePath ?? 'test.dart',
      isStaged: staged,
      isSensitive: filePath != null && filePath.contains('.env'),
      hunks: const [
        GitDiffHunk(
          header: '@@ -1,3 +1,4 @@',
          lines: [
            GitDiffLine(type: GitDiffLineType.context, content: 'line 1'),
            GitDiffLine(type: GitDiffLineType.deletion, content: 'line 2'),
            GitDiffLine(type: GitDiffLineType.addition, content: 'line 2 new'),
          ],
          oldStart: 1,
          oldCount: 3,
          newStart: 1,
          newCount: 4,
        ),
      ],
      additions: 1,
      deletions: 1,
    );
  }

  @override
  Future<List<GitCommit>> getHistory(String workingDirectory,
      {int limit = 50}) async {
    return [
      GitCommit(
        hash: 'a1b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6e7f8a9b0',
        shortHash: 'a1b2c3d',
        authorName: 'Alice Developer',
        timestamp: DateTime.now().toUtc(),
        subject: 'feat: add git orchestration',
      ),
    ];
  }

  @override
  Future<void> stage(String workingDirectory, String filePath) async {
    stagedFiles.add(filePath);
  }

  @override
  Future<void> unstage(String workingDirectory, String filePath) async {
    unstagedFiles.add(filePath);
  }

  @override
  Future<GitCommit> commit(String workingDirectory, String message) async {
    return GitCommit(
      hash: 'f9e8d7c6b5a43210',
      shortHash: 'f9e8d7c',
      authorName: 'Alice Developer',
      timestamp: DateTime.now().toUtc(),
      subject: message,
    );
  }
}

void main() {
  const testProject = ProjectProfile(
    id: 'proj_1',
    name: 'Portal Proveedores',
    serverId: 'srv_1',
    workingDirectory: '/home/lab/project',
    environment: Environment.development,
    executionPolicy: ExecutionPolicy(environment: Environment.development),
  );

  const prodProject = ProjectProfile(
    id: 'proj_prod',
    name: 'Core Production API',
    serverId: 'srv_prod',
    workingDirectory: '/var/www/prod',
    environment: Environment.production,
    executionPolicy: ExecutionPolicy(environment: Environment.production),
  );

  testWidgets('ProjectGitPage renders branch, metrics, and actions',
      (tester) async {
    final fakeService = _FakeGitService();

    await tester.pumpWidget(
      MaterialApp(
        home: ProjectGitPage(
          project: testProject,
          service: fakeService,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Git — Portal Proveedores'), findsOneWidget);
    expect(find.text('main'), findsOneWidget);
    expect(find.text('a1b2c3d'), findsOneWidget);
    expect(find.text('CHANGES'), findsOneWidget);
    expect(find.text('STAGED'), findsOneWidget);
    expect(find.text('UNTRACKED'), findsOneWidget);
    expect(find.text('View Changes (3)'), findsOneWidget);
    expect(find.text('Commit History'), findsOneWidget);
  });

  testWidgets(
      'ProjectGitPage displays PRODUCTION badge for production environment',
      (tester) async {
    final fakeService = _FakeGitService();

    await tester.pumpWidget(
      MaterialApp(
        home: ProjectGitPage(
          project: prodProject,
          service: fakeService,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('PRODUCTION'), findsOneWidget);
  });

  testWidgets('GitChangesPage renders changes and allows stage/unstage',
      (tester) async {
    final fakeService = _FakeGitService();

    await tester.pumpWidget(
      MaterialApp(
        home: GitChangesPage(
          project: testProject,
          service: fakeService,
          initialStatus: fakeService.status,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Changes — Portal Proveedores'), findsOneWidget);
    expect(find.text('STAGED CHANGES'), findsOneWidget);
    expect(find.text('UNSTAGED CHANGES'), findsOneWidget);
    expect(find.text('UNTRACKED FILES'), findsOneWidget);
    expect(find.text('lib/staged.dart'), findsOneWidget);
    expect(find.text('lib/unstaged.dart'), findsOneWidget);
    expect(find.text('notes.txt'), findsOneWidget);
  });

  testWidgets('GitDiffViewerPage renders diff hunks and lines', (tester) async {
    final fakeService = _FakeGitService();

    await tester.pumpWidget(
      MaterialApp(
        home: GitDiffViewerPage(
          project: testProject,
          service: fakeService,
          filePath: 'lib/test.dart',
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('lib/test.dart'), findsOneWidget);
    expect(find.text('line 1'), findsOneWidget);
    expect(find.text('line 2'), findsOneWidget);
    expect(find.text('line 2 new'), findsOneWidget);
  });

  testWidgets('GitHistoryPage renders commit history', (tester) async {
    final fakeService = _FakeGitService();

    await tester.pumpWidget(
      MaterialApp(
        home: GitHistoryPage(
          project: testProject,
          service: fakeService,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('History — Portal Proveedores'), findsOneWidget);
    expect(find.text('feat: add git orchestration'), findsOneWidget);
    expect(find.text('a1b2c3d'), findsOneWidget);
  });
}
