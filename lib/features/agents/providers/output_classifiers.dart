import '../../../core/domain/agents.dart';
import '../domain/agent_models.dart';

class CodexOutputClassifier implements AgentOutputClassifier {
  const CodexOutputClassifier();

  static final _waitingPatterns = [
    RegExp(r'\?\s+[^\n]+', caseSensitive: false),
    RegExp(r'\[y/n\]', caseSensitive: false),
    RegExp(r'\(y/n\)', caseSensitive: false),
    RegExp(r'approve\s+(command|edit|file|action)', caseSensitive: false),
    RegExp(r'allow\s+(command|execution|edit)', caseSensitive: false),
    RegExp(r'(›|>)\s*$', multiLine: true),
    RegExp(r'enter\s+to\s+continue', caseSensitive: false),
    RegExp(r'what\s+would\s+you\s+like\s+to\s+do', caseSensitive: false),
  ];

  @override
  AgentObservation classify(String terminalOutput) {
    final clean = AgentCommandSafety.stripAnsi(terminalOutput).trim();
    if (clean.isEmpty) {
      return AgentObservation(
        state: AgentExecutionState.unknown,
        confidence: ObservationConfidence.unknown,
        source: ObservationSource.terminalPattern,
        observedAt: DateTime.now().toUtc(),
      );
    }

    // Examine last 15 lines of output
    final lines = clean.split('\n');
    final recent =
        lines.length > 15 ? lines.sublist(lines.length - 15).join('\n') : clean;

    for (final pattern in _waitingPatterns) {
      if (pattern.hasMatch(recent)) {
        return AgentObservation(
          state: AgentExecutionState.waitingUser,
          confidence: ObservationConfidence.inferred,
          source: ObservationSource.terminalPattern,
          observedAt: DateTime.now().toUtc(),
          detail: 'Codex waiting on user prompt/approval',
        );
      }
    }

    return AgentObservation(
      state: AgentExecutionState.unknown,
      confidence: ObservationConfidence.unknown,
      source: ObservationSource.terminalPattern,
      observedAt: DateTime.now().toUtc(),
    );
  }
}

class ClaudeCodeOutputClassifier implements AgentOutputClassifier {
  const ClaudeCodeOutputClassifier();

  static final _waitingPatterns = [
    RegExp(r'(›|>)\s*$', multiLine: true),
    RegExp(r'\?\s+[^\n]+', caseSensitive: false),
    RegExp(r'\[y/n\]', caseSensitive: false),
    RegExp(r'\(y/n\)', caseSensitive: false),
    RegExp(r'allow\s+[^\n]+\?', caseSensitive: false),
    RegExp(r'press\s+enter\s+to\s+continue', caseSensitive: false),
    RegExp(r'would\s+you\s+like\s+to', caseSensitive: false),
  ];

  @override
  AgentObservation classify(String terminalOutput) {
    final clean = AgentCommandSafety.stripAnsi(terminalOutput).trim();
    if (clean.isEmpty) {
      return AgentObservation(
        state: AgentExecutionState.unknown,
        confidence: ObservationConfidence.unknown,
        source: ObservationSource.terminalPattern,
        observedAt: DateTime.now().toUtc(),
      );
    }

    final lines = clean.split('\n');
    final recent =
        lines.length > 15 ? lines.sublist(lines.length - 15).join('\n') : clean;

    for (final pattern in _waitingPatterns) {
      if (pattern.hasMatch(recent)) {
        return AgentObservation(
          state: AgentExecutionState.waitingUser,
          confidence: ObservationConfidence.inferred,
          source: ObservationSource.terminalPattern,
          observedAt: DateTime.now().toUtc(),
          detail: 'Claude Code prompt awaiting user interaction',
        );
      }
    }

    return AgentObservation(
      state: AgentExecutionState.unknown,
      confidence: ObservationConfidence.unknown,
      source: ObservationSource.terminalPattern,
      observedAt: DateTime.now().toUtc(),
    );
  }
}

class OpenCodeOutputClassifier implements AgentOutputClassifier {
  const OpenCodeOutputClassifier();

  static final _waitingPatterns = [
    RegExp(r'(›|>)\s*$', multiLine: true),
    RegExp(r'\?\s+[^\n]+', caseSensitive: false),
    RegExp(r'\[y/n\]', caseSensitive: false),
    RegExp(r'confirm\s+action', caseSensitive: false),
    RegExp(r'permission\s+request', caseSensitive: false),
  ];

  @override
  AgentObservation classify(String terminalOutput) {
    final clean = AgentCommandSafety.stripAnsi(terminalOutput).trim();
    if (clean.isEmpty) {
      return AgentObservation(
        state: AgentExecutionState.unknown,
        confidence: ObservationConfidence.unknown,
        source: ObservationSource.terminalPattern,
        observedAt: DateTime.now().toUtc(),
      );
    }

    final lines = clean.split('\n');
    final recent =
        lines.length > 15 ? lines.sublist(lines.length - 15).join('\n') : clean;

    for (final pattern in _waitingPatterns) {
      if (pattern.hasMatch(recent)) {
        return AgentObservation(
          state: AgentExecutionState.waitingUser,
          confidence: ObservationConfidence.inferred,
          source: ObservationSource.terminalPattern,
          observedAt: DateTime.now().toUtc(),
          detail: 'OpenCode awaiting user input',
        );
      }
    }

    return AgentObservation(
      state: AgentExecutionState.unknown,
      confidence: ObservationConfidence.unknown,
      source: ObservationSource.terminalPattern,
      observedAt: DateTime.now().toUtc(),
    );
  }
}

class AntigravityOutputClassifier implements AgentOutputClassifier {
  const AntigravityOutputClassifier();

  static final _waitingPatterns = [
    RegExp(r'\?\s+[^\n]+', caseSensitive: false),
    RegExp(r'(›|>)\s*$', multiLine: true),
    RegExp(r'\[y/n\]', caseSensitive: false),
    RegExp(r'waiting\s+for\s+instructions', caseSensitive: false),
    RegExp(r'press\s+enter', caseSensitive: false),
  ];

  @override
  AgentObservation classify(String terminalOutput) {
    final clean = AgentCommandSafety.stripAnsi(terminalOutput).trim();
    if (clean.isEmpty) {
      return AgentObservation(
        state: AgentExecutionState.unknown,
        confidence: ObservationConfidence.unknown,
        source: ObservationSource.terminalPattern,
        observedAt: DateTime.now().toUtc(),
      );
    }

    final lines = clean.split('\n');
    final recent =
        lines.length > 15 ? lines.sublist(lines.length - 15).join('\n') : clean;

    for (final pattern in _waitingPatterns) {
      if (pattern.hasMatch(recent)) {
        return AgentObservation(
          state: AgentExecutionState.waitingUser,
          confidence: ObservationConfidence.inferred,
          source: ObservationSource.terminalPattern,
          observedAt: DateTime.now().toUtc(),
          detail: 'Antigravity CLI awaiting input',
        );
      }
    }

    return AgentObservation(
      state: AgentExecutionState.unknown,
      confidence: ObservationConfidence.unknown,
      source: ObservationSource.terminalPattern,
      observedAt: DateTime.now().toUtc(),
    );
  }
}

class GenericOutputClassifier implements AgentOutputClassifier {
  const GenericOutputClassifier();

  static final _waitingPatterns = [
    RegExp(r'\[y/n\]', caseSensitive: false),
    RegExp(r'\(yes/no\)', caseSensitive: false),
    RegExp(r'\?\s*$', multiLine: true),
    RegExp(r':\s*$', multiLine: true),
  ];

  @override
  AgentObservation classify(String terminalOutput) {
    final clean = AgentCommandSafety.stripAnsi(terminalOutput).trim();
    if (clean.isEmpty) {
      return AgentObservation(
        state: AgentExecutionState.unknown,
        confidence: ObservationConfidence.unknown,
        source: ObservationSource.terminalPattern,
        observedAt: DateTime.now().toUtc(),
      );
    }

    final lines = clean.split('\n');
    final recent =
        lines.length > 10 ? lines.sublist(lines.length - 10).join('\n') : clean;

    for (final pattern in _waitingPatterns) {
      if (pattern.hasMatch(recent)) {
        return AgentObservation(
          state: AgentExecutionState.waitingUser,
          confidence: ObservationConfidence.inferred,
          source: ObservationSource.terminalPattern,
          observedAt: DateTime.now().toUtc(),
          detail: 'Generic CLI waiting for user input',
        );
      }
    }

    return AgentObservation(
      state: AgentExecutionState.unknown,
      confidence: ObservationConfidence.unknown,
      source: ObservationSource.terminalPattern,
      observedAt: DateTime.now().toUtc(),
    );
  }
}

class FakeAgentOutputClassifier implements AgentOutputClassifier {
  const FakeAgentOutputClassifier();

  @override
  AgentObservation classify(String terminalOutput) {
    final clean = AgentCommandSafety.stripAnsi(terminalOutput);

    final lastRunning = clean.lastIndexOf('[RUNNING]');
    final lastWaiting = clean.lastIndexOf('[WAITING_USER]');
    final lastFinished = clean.lastIndexOf('[FINISHED]');
    final lastFailed = clean.lastIndexOf('[FAILED]');

    final maxIdx = [lastRunning, lastWaiting, lastFinished, lastFailed]
        .reduce((a, b) => a > b ? a : b);

    if (maxIdx == -1) {
      return AgentObservation(
        state: AgentExecutionState.unknown,
        confidence: ObservationConfidence.unknown,
        source: ObservationSource.terminalPattern,
        observedAt: DateTime.now().toUtc(),
      );
    }

    if (maxIdx == lastFinished) {
      return AgentObservation(
        state: AgentExecutionState.finished,
        confidence: ObservationConfidence.confirmed,
        source: ObservationSource.terminalPattern,
        observedAt: DateTime.now().toUtc(),
        detail: 'FakeAgent emitted finish signal',
      );
    }

    if (maxIdx == lastFailed) {
      return AgentObservation(
        state: AgentExecutionState.failed,
        confidence: ObservationConfidence.confirmed,
        source: ObservationSource.terminalPattern,
        observedAt: DateTime.now().toUtc(),
        detail: 'FakeAgent emitted failure signal',
      );
    }

    if (maxIdx == lastWaiting) {
      return AgentObservation(
        state: AgentExecutionState.waitingUser,
        confidence: ObservationConfidence.confirmed,
        source: ObservationSource.terminalPattern,
        observedAt: DateTime.now().toUtc(),
        detail: 'FakeAgent waiting on stdin input',
      );
    }

    return AgentObservation(
      state: AgentExecutionState.running,
      confidence: ObservationConfidence.confirmed,
      source: ObservationSource.terminalPattern,
      observedAt: DateTime.now().toUtc(),
      detail: 'FakeAgent running signal',
    );
  }
}
