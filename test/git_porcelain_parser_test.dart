import 'package:flutter_test/flutter_test.dart';
import 'package:agentdeck/core/domain/git.dart';
import 'package:agentdeck/features/git/domain/git_parsers.dart';

void main() {
  group('GitPorcelainV2Parser', () {
    test('parses branch headers, ahead/behind, and detached head', () {
      const output = '''# branch.oid 3a5f6e8d1c2b4a7e9f0a1b2c3d4e5f6a7b8c9d0e
# branch.head feature/mobile-git
# branch.upstream origin/feature/mobile-git
# branch.ab +3 -1
''';

      final status = GitPorcelainV2Parser.parse(output);

      expect(status.branch, 'feature/mobile-git');
      expect(status.headCommit, '3a5f6e8d1c2b4a7e9f0a1b2c3d4e5f6a7b8c9d0e');
      expect(status.isDetachedHead, isFalse);
      expect(status.upstream, 'origin/feature/mobile-git');
      expect(status.ahead, 3);
      expect(status.behind, 1);
      expect(status.isClean, isTrue);
      expect(status.changedFiles, isEmpty);
    });

    test('parses detached HEAD correctly', () {
      const output = '''# branch.oid a1b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6e7f8a9b0
# branch.head (detached)
''';

      final status = GitPorcelainV2Parser.parse(output);

      expect(status.isDetachedHead, isTrue);
      expect(status.branch, isNull);
      expect(status.headCommit, 'a1b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6e7f8a9b0');
    });

    test('parses ordinary modified, added, deleted, staged, and unstaged files',
        () {
      const output = '''# branch.oid 1111111111111111111111111111111111111111
# branch.head main
1 M. N... 100644 100644 100644 aaaaaaa bbbbbbb lib/staged_modified.dart
1 .M N... 100644 100644 100644 aaaaaaa bbbbbbb lib/unstaged_modified.dart
1 MM N... 100644 100644 100644 aaaaaaa bbbbbbb lib/both_modified.dart
1 A. N... 000000 100644 100644 0000000 aaaaaaa lib/new_staged.dart
1 D. N... 100644 000000 000000 aaaaaaa 0000000 lib/deleted_staged.dart
1 .D N... 100644 100644 000000 aaaaaaa 0000000 lib/deleted_unstaged.dart
''';

      final status = GitPorcelainV2Parser.parse(output);

      expect(status.changedFiles.length, 6);
      expect(status.stagedCount, 4); // M., MM, A., D.
      expect(status.unstagedCount, 3); // .M, MM, .D

      final stagedMod = status.changedFiles[0];
      expect(stagedMod.path, 'lib/staged_modified.dart');
      expect(stagedMod.indexStatus, GitFileStatus.modified);
      expect(stagedMod.workTreeStatus, GitFileStatus.unmodified);
      expect(stagedMod.isStaged, isTrue);
      expect(stagedMod.isUnstaged, isFalse);

      final unstagedMod = status.changedFiles[1];
      expect(unstagedMod.path, 'lib/unstaged_modified.dart');
      expect(unstagedMod.indexStatus, GitFileStatus.unmodified);
      expect(unstagedMod.workTreeStatus, GitFileStatus.modified);
      expect(unstagedMod.isStaged, isFalse);
      expect(unstagedMod.isUnstaged, isTrue);

      final added = status.changedFiles[3];
      expect(added.path, 'lib/new_staged.dart');
      expect(added.indexStatus, GitFileStatus.added);
      expect(added.isStaged, isTrue);

      final deleted = status.changedFiles[4];
      expect(deleted.path, 'lib/deleted_staged.dart');
      expect(deleted.indexStatus, GitFileStatus.deleted);
      expect(deleted.isDeleted, isTrue);
    });

    test('parses renamed, untracked, and merge conflict entries', () {
      const output = '''# branch.oid 2222222222222222222222222222222222222222
# branch.head main
2 R. N... 100644 100644 100644 aaaaaaa bbbbbbb R100 lib/new_name.dart\tlib/old_name.dart
u UU N... 100644 100644 100644 100644 aaaaaaa bbbbbbb ccccccc lib/conflicted.dart
? lib/untracked_file.dart
! ignored_dir/
''';

      final status = GitPorcelainV2Parser.parse(output);

      expect(status.changedFiles.length, 4);

      final renamed = status.changedFiles[0];
      expect(renamed.path, 'lib/new_name.dart');
      expect(renamed.oldPath, 'lib/old_name.dart');
      expect(renamed.indexStatus, GitFileStatus.renamed);
      expect(renamed.isRenamed, isTrue);

      final conflict = status.changedFiles[1];
      expect(conflict.path, 'lib/conflicted.dart');
      expect(conflict.isConflict, isTrue);

      final untracked = status.changedFiles[2];
      expect(untracked.path, 'lib/untracked_file.dart');
      expect(untracked.isUntracked, isTrue);
      expect(untracked.isStaged, isFalse);

      final ignored = status.changedFiles[3];
      expect(ignored.path, 'ignored_dir/');
      expect(ignored.indexStatus, GitFileStatus.ignored);
    });

    test('parses UTF-8 and quoted path names correctly', () {
      const output = '''# branch.oid 3333333333333333333333333333333333333333
# branch.head main
1 .M N... 100644 100644 100644 aaaaaaa bbbbbbb docs/archivo-ñ-漢字.txt
? "path with spaces/file name.txt"
''';

      final status = GitPorcelainV2Parser.parse(output);

      expect(status.changedFiles.length, 2);
      expect(status.changedFiles[0].path, 'docs/archivo-ñ-漢字.txt');
      expect(status.changedFiles[1].path, 'path with spaces/file name.txt');
    });
  });

  group('GitLogParser', () {
    test('parses log records with ASCII unit separator correctly', () {
      const output =
          'f1a2b3c4d5e6f7a8b9c0d1e2f3a4b5c6d7e8f9a0\x1ff1a2b3c\x1fAlice Dev\x1falice@example.com\x1f1774094400\x1ffeat: add remote git orchestration\x1f0000000000000000000000000000000000000000\n'
          'a1b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6e7f8a9b0\x1fa1b2c3d\x1fBob Ops\x1f\x1f1774008000\x1fchore: initial commit\x1f\n';

      final commits = GitLogParser.parse(output);

      expect(commits.length, 2);

      expect(commits[0].hash, 'f1a2b3c4d5e6f7a8b9c0d1e2f3a4b5c6d7e8f9a0');
      expect(commits[0].shortHash, 'f1a2b3c');
      expect(commits[0].authorName, 'Alice Dev');
      expect(commits[0].authorEmail, 'alice@example.com');
      expect(commits[0].timestamp,
          DateTime.fromMillisecondsSinceEpoch(1774094400 * 1000, isUtc: true));
      expect(commits[0].subject, 'feat: add remote git orchestration');
      expect(commits[0].parents, ['0000000000000000000000000000000000000000']);

      expect(commits[1].shortHash, 'a1b2c3d');
      expect(commits[1].authorName, 'Bob Ops');
      expect(commits[1].authorEmail, isNull);
      expect(commits[1].subject, 'chore: initial commit');
      expect(commits[1].parents, isEmpty);
    });
  });

  group('GitDiffParser', () {
    test('parses unified diff text into hunks and line types', () {
      const diffText = '''diff --git a/lib/test.dart b/lib/test.dart
index 1111111..2222222 100644
--- a/lib/test.dart
+++ b/lib/test.dart
@@ -1,5 +1,6 @@
 import 'package:flutter/material.dart';
-const oldVar = 1;
+const newVar = 2;
+const addedVar = 3;
 
 void main() {}
''';

      final diff = GitDiffParser.parse(
        diffText,
        filePath: 'lib/test.dart',
        isStaged: false,
      );

      expect(diff.filePath, 'lib/test.dart');
      expect(diff.additions, 2);
      expect(diff.deletions, 1);
      expect(diff.hunks.length, 1);

      final hunk = diff.hunks.first;
      expect(hunk.oldStart, 1);
      expect(hunk.oldCount, 5);
      expect(hunk.newStart, 1);
      expect(hunk.newCount, 6);

      expect(hunk.lines.length, 6);
      expect(hunk.lines[0].type, GitDiffLineType.context);
      expect(hunk.lines[1].type, GitDiffLineType.deletion);
      expect(hunk.lines[1].content, 'const oldVar = 1;');
      expect(hunk.lines[2].type, GitDiffLineType.addition);
      expect(hunk.lines[2].content, 'const newVar = 2;');
      expect(hunk.lines[3].type, GitDiffLineType.addition);
      expect(hunk.lines[3].content, 'const addedVar = 3;');
    });
  });
}
