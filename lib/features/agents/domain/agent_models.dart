import 'dart:math';

class AgentCommandSafety {
  static final _safeExecutableRegExp = RegExp(r'^[a-zA-Z0-9_\-\.\/]+$');
  static final _disallowedExecutableChars =
      RegExp(r'[;&|`$<>\\\s\x00-\x1F\x7F]');

  static bool isSafeExecutable(String executable) {
    if (executable.trim().isEmpty) return false;
    if (_disallowedExecutableChars.hasMatch(executable)) return false;
    return _safeExecutableRegExp.hasMatch(executable);
  }

  static String sanitizeExecutable(String executable) {
    final trimmed = executable.trim();
    if (!isSafeExecutable(trimmed)) {
      throw ArgumentError.value(
          executable, 'executable', 'Contains unsafe characters or whitespace');
    }
    return trimmed;
  }

  static String escapePosixArgument(String arg) {
    if (arg.isEmpty) return "''";
    if (RegExp(r'^[a-zA-Z0-9_\-\.\/=]+$').hasMatch(arg)) {
      return arg;
    }
    // Single-quote escape: replace ' with '\'' and wrap in single quotes
    final escaped = arg.replaceAll("'", r"'\''");
    return "'$escaped'";
  }

  static String sanitizeSessionComponent(String component) {
    final cleaned =
        component.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9_\-]'), '_');
    return cleaned.isEmpty ? 'item' : cleaned;
  }

  static String generateAgentSessionName({
    required String providerId,
    required String projectId,
  }) {
    final safeProvider = sanitizeSessionComponent(providerId);
    final safeProject = sanitizeSessionComponent(projectId);
    final rng = Random.secure();
    final nonce = List.generate(
        4, (_) => rng.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
    return 'ad_agent_${safeProvider}_${safeProject}_$nonce';
  }

  static String stripAnsi(String text) {
    // Strips ANSI CSI sequences, OSC sequences, and control codes
    final ansiPattern = RegExp(
      r'(\x1B\[[0-?]*[ -/]*[@-~])|(\x1B\][^\x07\x1B]*(\x07|\x1B\\))|(\x1B[@-Z\\-_])',
      caseSensitive: false,
    );
    return text.replaceAll(ansiPattern, '');
  }
}
