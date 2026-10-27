import 'dart:convert';

import '../../../core/domain/git.dart';
import '../../../core/domain/posix_path.dart';

/// Helper methods for safety validation and command construction.
class GitCommandSafety {
  static final RegExp _safeExecutableRegex =
      RegExp(r'^[a-zA-Z0-9_\-\.\/]{1,128}$');

  /// Validates executable binary name against malicious characters.
  static bool isValidExecutable(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return false;
    return _safeExecutableRegex.hasMatch(trimmed) &&
        !trimmed.contains(';') &&
        !trimmed.contains('&') &&
        !trimmed.contains('|') &&
        !trimmed.contains('`') &&
        !trimmed.contains(r'$(');
  }

  /// Safely escapes an arbitrary POSIX command argument.
  static String escapeArgument(String argument) {
    if (argument.contains('\u0000')) {
      throw const FormatException('Null byte not allowed in argument');
    }
    return "'" + argument.replaceAll("'", "'\"'\"'") + "'";
  }

  /// Identifies potentially sensitive files containing secrets/credentials.
  static bool isSensitiveFile(String path) {
    final normalized = PosixPath.normalize(path).toLowerCase();
    final name = PosixPath.basename(normalized);

    if (name.startsWith('.env')) return true;
    if (name.endsWith('.pem') ||
        name.endsWith('.key') ||
        name.endsWith('.p12') ||
        name.endsWith('.pfx') ||
        name.endsWith('.pkcs12') ||
        name.endsWith('.kdbx')) {
      return true;
    }
    if (name == 'id_rsa' ||
        name == 'id_ecdsa' ||
        name == 'id_ed25519' ||
        name == 'id_dsa') {
      return true;
    }
    if (name.startsWith('credentials') ||
        name.startsWith('secrets') ||
        name.contains('token') ||
        name.contains('password')) {
      return true;
    }
    return false;
  }

  /// Validates working directory path.
  static String sanitizeWorkingDirectory(String workingDirectory) {
    final normalized = PosixPath.normalize(workingDirectory);
    if (normalized.contains('\u0000') ||
        normalized.contains('\n') ||
        normalized.contains('\r')) {
      throw const FormatException('Invalid characters in working directory');
    }
    return normalized;
  }
}

/// Parser for `git status --porcelain=v2 --branch` output.
class GitPorcelainV2Parser {
  static GitStatus parse(String output) {
    String? branch;
    String? headCommit;
    bool isDetachedHead = false;
    String? upstream;
    int ahead = 0;
    int behind = 0;
    final changes = <GitFileChange>[];

    final lines = output.split('\n');
    for (var rawLine in lines) {
      final line = rawLine.trimRight();
      if (line.isEmpty) continue;

      if (line.startsWith('# ')) {
        // Branch header records
        final header = line.substring(2);
        if (header.startsWith('branch.oid ')) {
          final oid = header.substring('branch.oid '.length).trim();
          if (oid != '(initial)') {
            headCommit = oid;
          }
        } else if (header.startsWith('branch.head ')) {
          final head = header.substring('branch.head '.length).trim();
          if (head == '(detached)') {
            isDetachedHead = true;
            branch = null;
          } else {
            branch = head;
          }
        } else if (header.startsWith('branch.upstream ')) {
          upstream = header.substring('branch.upstream '.length).trim();
        } else if (header.startsWith('branch.ab ')) {
          final ab = header.substring('branch.ab '.length).trim();
          final parts = ab.split(' ');
          for (final part in parts) {
            if (part.startsWith('+')) {
              ahead = int.tryParse(part.substring(1)) ?? 0;
            } else if (part.startsWith('-')) {
              behind = int.tryParse(part.substring(1)) ?? 0;
            }
          }
        }
      } else if (line.startsWith('1 ')) {
        // Ordinary changed entry: 1 <XY> <sub> <mH> <mI> <mW> <hH> <hI> <path>
        final parts = line.split(' ');
        if (parts.length >= 9) {
          final xy = parts[1];
          final path = parts.sublist(8).join(' ');
          changes.add(GitFileChange(
            path: _unescapePath(path),
            indexStatus: _mapStatusCode(xy.isNotEmpty ? xy[0] : '.'),
            workTreeStatus: _mapStatusCode(xy.length > 1 ? xy[1] : '.'),
          ));
        }
      } else if (line.startsWith('2 ')) {
        // Renamed/copied entry: 2 <XY> <sub> <mH> <mI> <mW> <hH> <hI> <X><score> <path>\t<origPath>
        final tabIndex = line.indexOf('\t');
        if (tabIndex != -1) {
          final beforeTab = line.substring(0, tabIndex);
          final origPath = line.substring(tabIndex + 1);
          final parts = beforeTab.split(' ');
          if (parts.length >= 10) {
            final xy = parts[1];
            final path = parts.sublist(9).join(' ');
            changes.add(GitFileChange(
              path: _unescapePath(path),
              oldPath: _unescapePath(origPath),
              indexStatus: _mapStatusCode(xy.isNotEmpty ? xy[0] : '.'),
              workTreeStatus: _mapStatusCode(xy.length > 1 ? xy[1] : '.'),
            ));
          }
        }
      } else if (line.startsWith('u ')) {
        // Unmerged conflict entry: u <XY> <sub> <m1> <m2> <m3> <mW> <h1> <h2> <h3> <path>
        final parts = line.split(' ');
        if (parts.length >= 11) {
          final path = parts.sublist(10).join(' ');
          changes.add(GitFileChange(
            path: _unescapePath(path),
            indexStatus: GitFileStatus.conflict,
            workTreeStatus: GitFileStatus.conflict,
          ));
        }
      } else if (line.startsWith('? ')) {
        // Untracked entry: ? <path>
        final path = line.substring(2);
        changes.add(GitFileChange(
          path: _unescapePath(path),
          indexStatus: GitFileStatus.untracked,
          workTreeStatus: GitFileStatus.untracked,
        ));
      } else if (line.startsWith('! ')) {
        // Ignored entry: ! <path>
        final path = line.substring(2);
        changes.add(GitFileChange(
          path: _unescapePath(path),
          indexStatus: GitFileStatus.ignored,
          workTreeStatus: GitFileStatus.ignored,
        ));
      }
    }

    return GitStatus(
      branch: branch,
      headCommit: headCommit,
      isDetachedHead: isDetachedHead,
      upstream: upstream,
      ahead: ahead,
      behind: behind,
      changedFiles: changes,
    );
  }

  static GitFileStatus _mapStatusCode(String code) {
    switch (code) {
      case '.':
        return GitFileStatus.unmodified;
      case 'M':
        return GitFileStatus.modified;
      case 'A':
        return GitFileStatus.added;
      case 'D':
        return GitFileStatus.deleted;
      case 'R':
        return GitFileStatus.renamed;
      case 'C':
        return GitFileStatus.copied;
      case '?':
        return GitFileStatus.untracked;
      case 'u':
      case 'U':
        return GitFileStatus.conflict;
      case '!':
        return GitFileStatus.ignored;
      default:
        return GitFileStatus.modified;
    }
  }

  static String _unescapePath(String rawPath) {
    var p = rawPath.trim();
    if (p.startsWith('"') && p.endsWith('"') && p.length >= 2) {
      final inner = p.substring(1, p.length - 1);
      final bytes = <int>[];
      var i = 0;
      while (i < inner.length) {
        if (inner[i] == r'\' && i + 1 < inner.length) {
          final next = inner[i + 1];
          if (next.codeUnitAt(0) >= 48 && next.codeUnitAt(0) <= 55) {
            // Octal sequence \ooo (up to 3 digits)
            var octalStr = next;
            var j = i + 2;
            while (j < inner.length &&
                j < i + 4 &&
                inner[j].codeUnitAt(0) >= 48 &&
                inner[j].codeUnitAt(0) <= 55) {
              octalStr += inner[j];
              j++;
            }
            bytes.add(int.parse(octalStr, radix: 8));
            i = j;
            continue;
          } else if (next == 'n') {
            bytes.add(10);
            i += 2;
            continue;
          } else if (next == 't') {
            bytes.add(9);
            i += 2;
            continue;
          } else if (next == 'r') {
            bytes.add(13);
            i += 2;
            continue;
          } else if (next == r'\' || next == '"') {
            bytes.add(next.codeUnitAt(0));
            i += 2;
            continue;
          }
        }
        bytes.addAll(utf8.encode(inner[i]));
        i++;
      }
      return utf8.decode(bytes, allowMalformed: true);
    }
    return p;
  }
}

/// Parser for structured `git log` output using ASCII Unit Separators (`\x1f`).
class GitLogParser {
  static List<GitCommit> parse(String output) {
    final commits = <GitCommit>[];
    final lines = output.split('\n');

    for (final rawLine in lines) {
      final line = rawLine.trim();
      if (line.isEmpty) continue;

      final fields = line.split('\x1f');
      if (fields.length >= 6) {
        final hash = fields[0].trim();
        final shortHash = fields[1].trim();
        final authorName = fields[2].trim();
        final authorEmail =
            fields[3].trim().isNotEmpty ? fields[3].trim() : null;
        final timestampSec = int.tryParse(fields[4].trim()) ?? 0;
        final subject = fields[5].trim();
        final parents = fields.length > 6 && fields[6].trim().isNotEmpty
            ? fields[6].trim().split(' ')
            : <String>[];

        commits.add(GitCommit(
          hash: hash,
          shortHash: shortHash.isNotEmpty
              ? shortHash
              : (hash.length > 7 ? hash.substring(0, 7) : hash),
          authorName: authorName,
          authorEmail: authorEmail,
          timestamp: DateTime.fromMillisecondsSinceEpoch(timestampSec * 1000,
              isUtc: true),
          subject: subject,
          parents: parents,
        ));
      }
    }

    return commits;
  }
}

/// Parser for unified diff strings into hunks and line records.
class GitDiffParser {
  static GitDiff parse(
    String rawDiff, {
    required String filePath,
    bool isStaged = false,
    bool isSensitive = false,
    int maxLines = 1000,
  }) {
    if (rawDiff.trim().isEmpty) {
      return GitDiff(
        filePath: filePath,
        isStaged: isStaged,
        isSensitive: isSensitive,
        rawText: '',
        hunks: const [],
        additions: 0,
        deletions: 0,
        isTruncated: false,
      );
    }

    final rawLines = rawDiff.split('\n');
    final isTruncated = rawLines.length > maxLines;
    final linesToParse = isTruncated ? rawLines.sublist(0, maxLines) : rawLines;

    final hunks = <GitDiffHunk>[];
    var currentHunkLines = <GitDiffLine>[];
    String? currentHeader;
    int oldStart = 0;
    int oldCount = 0;
    int newStart = 0;
    int newCount = 0;
    int additions = 0;
    int deletions = 0;

    int oldLineNum = 0;
    int newLineNum = 0;

    final hunkRegex =
        RegExp(r'^@@ -(\d+)(?:,(\d+))? \+(\d+)(?:,(\d+))? @@(.*)$');

    void flushHunk() {
      if (currentHeader != null && currentHunkLines.isNotEmpty) {
        hunks.add(GitDiffHunk(
          header: currentHeader,
          lines: List.unmodifiable(currentHunkLines),
          oldStart: oldStart,
          oldCount: oldCount,
          newStart: newStart,
          newCount: newCount,
        ));
        currentHunkLines = [];
      }
    }

    for (final line in linesToParse) {
      final match = hunkRegex.firstMatch(line);
      if (match != null) {
        flushHunk();
        currentHeader = line;
        oldStart = int.tryParse(match.group(1) ?? '0') ?? 0;
        oldCount = int.tryParse(match.group(2) ?? '1') ?? 1;
        newStart = int.tryParse(match.group(3) ?? '0') ?? 0;
        newCount = int.tryParse(match.group(4) ?? '1') ?? 1;

        oldLineNum = oldStart;
        newLineNum = newStart;
        continue;
      }

      if (currentHeader != null) {
        if (line.startsWith('+')) {
          additions++;
          currentHunkLines.add(GitDiffLine(
            type: GitDiffLineType.addition,
            content: line.substring(1),
            newLineNumber: newLineNum++,
          ));
        } else if (line.startsWith('-')) {
          deletions++;
          currentHunkLines.add(GitDiffLine(
            type: GitDiffLineType.deletion,
            content: line.substring(1),
            oldLineNumber: oldLineNum++,
          ));
        } else if (line.startsWith(' ')) {
          currentHunkLines.add(GitDiffLine(
            type: GitDiffLineType.context,
            content: line.substring(1),
            oldLineNumber: oldLineNum++,
            newLineNumber: newLineNum++,
          ));
        } else if (line.startsWith(r'\ No newline at end of file')) {
          currentHunkLines.add(GitDiffLine(
            type: GitDiffLineType.header,
            content: line,
          ));
        }
      }
    }

    flushHunk();

    return GitDiff(
      filePath: filePath,
      isStaged: isStaged,
      isSensitive: isSensitive,
      rawText: rawDiff,
      hunks: hunks,
      additions: additions,
      deletions: deletions,
      isTruncated: isTruncated,
    );
  }
}
