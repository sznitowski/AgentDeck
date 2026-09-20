/// Centralized POSIX path manipulation for remote Linux/Unix filesystems.
///
/// Ensures consistent POSIX semantics regardless of host platform (Windows or iOS).
class PosixPath {
  const PosixPath._();

  /// Normalizes a POSIX path by removing redundant slashes, resolving `.`
  /// and handling standard POSIX rules.
  ///
  /// Rejects paths with embedded null bytes (`\0`).
  static String normalize(String path) {
    if (path.contains('\u0000')) {
      throw const FormatException('Path contains null bytes');
    }
    final raw = path.trim();
    if (raw.isEmpty) return '.';

    final isAbs = raw.startsWith('/');
    final rawSegments = raw.split('/');
    final segments = <String>[];

    for (final seg in rawSegments) {
      if (seg.isEmpty || seg == '.') continue;
      if (seg == '..') {
        if (segments.isNotEmpty && segments.last != '..') {
          segments.removeLast();
        } else if (!isAbs) {
          segments.add('..');
        }
      } else {
        segments.add(seg);
      }
    }

    if (isAbs) {
      return '/' + segments.join('/');
    }
    if (segments.isEmpty) return '.';
    return segments.join('/');
  }

  /// Safely joins a [base] path with a [segment].
  ///
  /// If [segment] is absolute, returns normalized [segment].
  static String join(String base, String segment) {
    if (segment.contains('\u0000') || base.contains('\u0000')) {
      throw const FormatException('Path contains null bytes');
    }
    final trimmedSegment = segment.trim();
    if (trimmedSegment.startsWith('/')) {
      return normalize(trimmedSegment);
    }
    final trimmedBase = base.trim();
    if (trimmedBase.isEmpty || trimmedBase == '.') {
      return normalize(trimmedSegment);
    }
    if (trimmedBase.endsWith('/')) {
      return normalize('$trimmedBase$trimmedSegment');
    }
    return normalize('$trimmedBase/$trimmedSegment');
  }

  /// Returns the parent directory of [path].
  ///
  /// Returns `'/'` for root or parent of top-level paths.
  static String parent(String path) {
    final normalized = normalize(path);
    if (normalized == '/' || normalized == '.') return normalized;
    final lastSlash = normalized.lastIndexOf('/');
    if (lastSlash == -1) return '.';
    if (lastSlash == 0) return '/';
    return normalized.substring(0, lastSlash);
  }

  /// Returns the trailing filename or directory name of [path].
  static String basename(String path) {
    final normalized = normalize(path);
    if (normalized == '/') return '/';
    final lastSlash = normalized.lastIndexOf('/');
    if (lastSlash == -1) return normalized;
    return normalized.substring(lastSlash + 1);
  }

  /// Returns the file extension of [path], including the leading dot (e.g. `'.env'`, `'.txt'`).
  ///
  /// Returns empty string if no extension exists.
  static String extension(String path) {
    final base = basename(path);
    final dot = base.lastIndexOf('.');
    if (dot <= 0) return '';
    return base.substring(dot);
  }

  /// Returns whether [path] is an absolute POSIX path.
  static bool isAbsolute(String path) => path.trim().startsWith('/');

  /// Validates a single filename component for creation/renaming.
  ///
  /// Disallows empty strings, `/`, `.`, `..`, and null bytes.
  static bool isValidFilename(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty ||
        trimmed.length > 255 ||
        trimmed.contains('/') ||
        trimmed.contains('\u0000') ||
        trimmed == '.' ||
        trimmed == '..') {
      return false;
    }
    return true;
  }

  /// Checks if [path] contains path traversal components (`..`).
  static bool containsTraversal(String path) {
    if (path.contains('\u0000')) return true;
    final segments = path.split('/');
    return segments.contains('..');
  }

  /// Splits [path] into its constituent POSIX segments.
  static List<String> split(String path) {
    final normalized = normalize(path);
    if (normalized == '/') return const ['/'];
    final segments = normalized.split('/').where((s) => s.isNotEmpty).toList();
    if (normalized.startsWith('/')) {
      return ['/', ...segments];
    }
    return segments;
  }
}
