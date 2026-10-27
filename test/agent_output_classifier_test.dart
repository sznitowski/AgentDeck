import 'package:agentdeck/core/domain/agents.dart';
import 'package:agentdeck/features/agents/providers/output_classifiers.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CodexOutputClassifier', () {
    const classifier = CodexOutputClassifier();

    test('classifies approval and question prompts as waitingUser', () {
      final samples = [
        'Do you want to apply these changes? [y/n]',
        'Approve edit to lib/main.dart [y/n]:',
        'Allow command "npm test"? [y/n]',
        'What would you like to do next?\n› ',
        'Please confirm execution of script?\n> ',
        '\x1B[32m✔ Changes analyzed\x1B[0m\n\x1B[1m? Apply patch to file? [y/n]\x1B[0m',
      ];

      for (final sample in samples) {
        final obs = classifier.classify(sample);
        expect(obs.state, AgentExecutionState.waitingUser,
            reason: 'Sample: "$sample" should be waitingUser');
        expect(obs.confidence, ObservationConfidence.inferred);
      }
    });

    test('classifies non-prompt output as unknown', () {
      final samples = [
        'Compiling package:flutter...\nDone in 3.4s\n',
        'Running tests: 12 passed, 0 failed',
        'Reading directory tree /var/docker...',
        '',
        '   ',
      ];

      for (final sample in samples) {
        final obs = classifier.classify(sample);
        expect(obs.state, AgentExecutionState.unknown);
        expect(obs.confidence, ObservationConfidence.unknown);
      }
    });
  });

  group('ClaudeCodeOutputClassifier', () {
    const classifier = ClaudeCodeOutputClassifier();

    test('classifies Claude Code prompts as waitingUser', () {
      final samples = [
        'Allow Claude to edit pubspec.yaml? (y/n)',
        'Press Enter to continue...',
        '\x1B[36mClaude Code v1.2\x1B[0m\n> ',
        '? Select an action from the list:\n  1. Review\n  2. Apply\n> ',
      ];

      for (final sample in samples) {
        final obs = classifier.classify(sample);
        expect(obs.state, AgentExecutionState.waitingUser);
        expect(obs.confidence, ObservationConfidence.inferred);
      }
    });
  });

  group('OpenCodeOutputClassifier', () {
    const classifier = OpenCodeOutputClassifier();

    test('classifies OpenCode prompts as waitingUser', () {
      final samples = [
        'Confirm action: delete temporary file? [y/n]',
        'Permission request for bash tool execution:\n> ',
      ];

      for (final sample in samples) {
        final obs = classifier.classify(sample);
        expect(obs.state, AgentExecutionState.waitingUser);
        expect(obs.confidence, ObservationConfidence.inferred);
      }
    });
  });

  group('AntigravityOutputClassifier', () {
    const classifier = AntigravityOutputClassifier();

    test('classifies Antigravity CLI prompts as waitingUser', () {
      final samples = [
        'Waiting for instructions from user...\n> ',
        '? Choose execution mode [plan/default]:',
        'Press enter to approve changes',
      ];

      for (final sample in samples) {
        final obs = classifier.classify(sample);
        expect(obs.state, AgentExecutionState.waitingUser);
        expect(obs.confidence, ObservationConfidence.inferred);
      }
    });
  });

  group('FakeAgentOutputClassifier', () {
    const classifier = FakeAgentOutputClassifier();

    test('classifies deterministic markers with confirmed confidence', () {
      final waitObs = classifier
          .classify('Starting fake agent...\n[WAITING_USER] Enter prompt: ');
      expect(waitObs.state, AgentExecutionState.waitingUser);
      expect(waitObs.confidence, ObservationConfidence.confirmed);

      final runObs = classifier
          .classify('Task dispatched\n[RUNNING] Processing background job...');
      expect(runObs.state, AgentExecutionState.running);
      expect(runObs.confidence, ObservationConfidence.confirmed);

      final finishObs = classifier
          .classify('\x1B[32mJob completed\x1B[0m\n[FINISHED] Exit status 0');
      expect(finishObs.state, AgentExecutionState.finished);
      expect(finishObs.confidence, ObservationConfidence.confirmed);

      final failObs = classifier.classify('Error caught\n[FAILED] Crash 1');
      expect(failObs.state, AgentExecutionState.failed);
      expect(failObs.confidence, ObservationConfidence.confirmed);
    });
  });

  group('GenericOutputClassifier', () {
    const classifier = GenericOutputClassifier();

    test('classifies common CLI prompts', () {
      expect(classifier.classify('Do you want to continue? [y/N]').state,
          AgentExecutionState.waitingUser);
      expect(classifier.classify('Proceed with installation? (yes/no)').state,
          AgentExecutionState.waitingUser);
      expect(classifier.classify('Enter value:').state,
          AgentExecutionState.waitingUser);
    });
  });
}
