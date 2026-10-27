import 'package:flutter_test/flutter_test.dart';
import 'package:agentdeck/core/domain/git.dart';
import 'package:agentdeck/features/git/application/git_service.dart';

class _FakeGitCommandExecutor implements GitCommandExecutor {
  final Map<String, RemoteCommandOutput> responses = {};
  final List<List<String>> executedCommands = [];

  void when(List<String> command, RemoteCommandOutput output) {
    responses[command.join(' ')] = output;
  }

  @override
  Future<RemoteCommandOutput> execute(
    List<String> arguments, {
    Duration timeout = const Duration(seconds: 15),
  }) async {
    executedCommands.add(arguments);
    final key = arguments.join(' ');
    if (responses.containsKey(key)) {
      return responses[key]!;
    }
    // Default fallback
    return const RemoteCommandOutput(0, '', '');
  }
}

void main() {
  late _FakeGitCommandExecutor executor;
  late RemoteGitService service;

  setUp(() {
    executor = _FakeGitCommandExecutor();
    service = RemoteGitService(executor: executor);
  });

  group('RemoteGitService', () {
    test('checkAvailability returns installed version when git exists',
        () async {
      executor.when(
        ['git', '--version'],
        const RemoteCommandOutput(0, 'git version 2.39.2 (Linux)\n', ''),
      );

      final avail = await service.checkAvailability();

      expect(avail.isInstalled, isTrue);
      expect(avail.version, '2.39.2');
      expect(avail.binaryPath, 'git');
    });

    test('checkAvailability returns false when git command fails', () async {
      executor.when(
        ['git', '--version'],
        const RemoteCommandOutput(127, '', 'git: command not found\n'),
      );

      final avail = await service.checkAvailability();

      expect(avail.isInstalled, isFalse);
    });

    test('inspectRepository returns isRepository true on valid worktree',
        () async {
      executor.when(
        [
          'git',
          '-C',
          '/home/lab/project',
          'rev-parse',
          '--is-inside-work-tree'
        ],
        const RemoteCommandOutput(0, 'true\n', ''),
      );
      executor.when(
        ['git', '-C', '/home/lab/project', 'rev-parse', '--show-toplevel'],
        const RemoteCommandOutput(0, '/home/lab/project\n', ''),
      );
      executor.when(
        [
          'git',
          '-C',
          '/home/lab/project',
          'status',
          '--porcelain=v2',
          '--branch'
        ],
        const RemoteCommandOutput(
            0, '# branch.oid a1b2c3d4e5f6\n# branch.head main\n', ''),
      );

      final repo = await service.inspectRepository('/home/lab/project');

      expect(repo.isRepository, isTrue);
      expect(repo.rootPath, '/home/lab/project');
      expect(repo.currentBranch, 'main');
      expect(repo.headCommit, 'a1b2c3d4e5f6');
    });

    test(
        'inspectRepository returns isRepository false on non-repository directory',
        () async {
      executor.when(
        [
          'git',
          '-C',
          '/home/lab/plain_dir',
          'rev-parse',
          '--is-inside-work-tree'
        ],
        const RemoteCommandOutput(128, '',
            'fatal: not a git repository (or any of the parent directories): .git\n'),
      );

      final repo = await service.inspectRepository('/home/lab/plain_dir');

      expect(repo.isRepository, isFalse);
      expect(repo.path, '/home/lab/plain_dir');
    });

    test('getStatus maps error conditions into typed GitFailure', () async {
      executor.when(
        [
          'git',
          '-C',
          '/home/lab/non_repo',
          'status',
          '--porcelain=v2',
          '--branch'
        ],
        const RemoteCommandOutput(128, '', 'fatal: not a git repository\n'),
      );

      expect(
        () => service.getStatus('/home/lab/non_repo'),
        throwsA(isA<GitFailure>()
            .having((e) => e.kind, 'kind', GitFailureKind.notRepository)),
      );

      executor.when(
        [
          'git',
          '-C',
          '/home/lab/denied',
          'status',
          '--porcelain=v2',
          '--branch'
        ],
        const RemoteCommandOutput(128, '', 'fatal: Permission denied\n'),
      );

      expect(
        () => service.getStatus('/home/lab/denied'),
        throwsA(isA<GitFailure>()
            .having((e) => e.kind, 'kind', GitFailureKind.permissionDenied)),
      );
    });

    test('stage executes git add -- <path>', () async {
      executor.when(
        ['git', '-C', '/home/lab/project', 'add', '--', 'lib/main.dart'],
        const RemoteCommandOutput(0, '', ''),
      );

      await service.stage('/home/lab/project', 'lib/main.dart');

      expect(executor.executedCommands.last, [
        'git',
        '-C',
        '/home/lab/project',
        'add',
        '--',
        'lib/main.dart',
      ]);
    });

    test('unstage executes git restore --staged -- <path>', () async {
      executor.when(
        [
          'git',
          '-C',
          '/home/lab/project',
          'restore',
          '--staged',
          '--',
          'lib/main.dart'
        ],
        const RemoteCommandOutput(0, '', ''),
      );

      await service.unstage('/home/lab/project', 'lib/main.dart');

      expect(executor.executedCommands.last, [
        'git',
        '-C',
        '/home/lab/project',
        'restore',
        '--staged',
        '--',
        'lib/main.dart',
      ]);
    });

    test('commit requires message and executes git commit -m <msg>', () async {
      expect(
        () => service.commit('/home/lab/project', '   '),
        throwsA(isA<GitFailure>()
            .having((e) => e.kind, 'kind', GitFailureKind.invalidPath)),
      );

      executor.when(
        ['git', '-C', '/home/lab/project', 'commit', '-m', 'feat: initial'],
        const RemoteCommandOutput(
            0, '[main a1b2c3d] feat: initial\n 1 file changed\n', ''),
      );
      executor.when(
        [
          'git',
          '-C',
          '/home/lab/project',
          'log',
          '-n',
          '1',
          '--format=%H%x1f%h%x1f%an%x1f%ae%x1f%at%x1f%s%x1f%P'
        ],
        const RemoteCommandOutput(
            0,
            'a1b2c3d4e5f6\x1fa1b2c3d\x1fDev\x1fdev@lab.org\x1f1774094400\x1ffeat: initial\x1f\n',
            ''),
      );

      final commit = await service.commit('/home/lab/project', 'feat: initial');

      expect(commit.shortHash, 'a1b2c3d');
      expect(commit.subject, 'feat: initial');
    });

    test('getDiff flags sensitive files and parses additions/deletions',
        () async {
      executor.when(
        ['git', '-C', '/home/lab/project', 'diff', '--', '.env.production'],
        const RemoteCommandOutput(
            0, '@@ -1,1 +1,2 @@\n-OLD_KEY=1\n+NEW_KEY=2\n+EXTRA=3\n', ''),
      );

      final diff = await service.getDiff(
        '/home/lab/project',
        filePath: '.env.production',
        staged: false,
      );

      expect(diff.filePath, '.env.production');
      expect(diff.isSensitive, isTrue);
      expect(diff.additions, 2);
      expect(diff.deletions, 1);
    });
  });
}
