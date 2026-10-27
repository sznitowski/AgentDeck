import 'dart:async';

import 'package:agentdeck/core/domain/remote_contracts.dart';
import 'package:agentdeck/features/agents/domain/agent_models.dart';
import 'package:agentdeck/features/agents/providers/antigravity_provider.dart';
import 'package:agentdeck/features/agents/providers/claude_code_provider.dart';
import 'package:agentdeck/features/agents/providers/codex_provider.dart';
import 'package:agentdeck/features/agents/providers/fake_agent_provider.dart';
import 'package:agentdeck/features/agents/providers/generic_cli_provider.dart';
import 'package:agentdeck/features/agents/providers/opencode_provider.dart';
import 'package:agentdeck/features/connections/domain/ssh_models.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeSshTransportHandle implements SshTmuxTransportHandle {
  _FakeSshTransportHandle(this.responses);
  final Map<String, RemoteCommandResult> responses;
  final doneSignal = Completer<void>();

  @override
  Future<void> get done => doneSignal.future;

  @override
  Future<void> close() async {
    if (!doneSignal.isCompleted) doneSignal.complete();
  }

  @override
  Future<TerminalSession> openTerminal(int columns, int rows) =>
      throw UnsupportedError('Not implemented for test');

  @override
  Future<RemoteCommandResult> run(List<String> command,
      {Duration timeout = const Duration(seconds: 10)}) async {
    final key = command.join(' ');
    if (responses.containsKey(key)) {
      return responses[key]!;
    }
    return const RemoteCommandResult(1, '', 'command not found');
  }

  @override
  Future<TerminalSession> attachTmux(
          String sessionName, int columns, int rows) =>
      throw UnsupportedError('Not implemented for test');
}

void main() {
  group('AgentCommandSafety', () {
    test('isSafeExecutable accepts valid binary names and paths', () {
      expect(AgentCommandSafety.isSafeExecutable('codex'), isTrue);
      expect(AgentCommandSafety.isSafeExecutable('claude'), isTrue);
      expect(AgentCommandSafety.isSafeExecutable('opencode'), isTrue);
      expect(AgentCommandSafety.isSafeExecutable('agy'), isTrue);
      expect(
          AgentCommandSafety.isSafeExecutable('/usr/local/bin/codex'), isTrue);
      expect(
          AgentCommandSafety.isSafeExecutable('agentdeck-fake-agent'), isTrue);
    });

    test('isSafeExecutable blocks shell injection characters', () {
      final badExecutables = [
        'codex; rm -rf /',
        'codex && cat /etc/passwd',
        'codex | sh',
        'codex \$(whoami)',
        'codex `id`',
        'codex\nrm -rf /',
        'codex\t--flag',
        'codex > /tmp/out',
        'codex < /tmp/in',
        'codex &',
        '',
        '   ',
      ];

      for (final bad in badExecutables) {
        expect(AgentCommandSafety.isSafeExecutable(bad), isFalse,
            reason: 'Should block $bad');
        expect(() => AgentCommandSafety.sanitizeExecutable(bad),
            throwsArgumentError);
      }
    });

    test('escapePosixArgument safely wraps args with metacharacters', () {
      expect(AgentCommandSafety.escapePosixArgument('hello'), 'hello');
      expect(
          AgentCommandSafety.escapePosixArgument('foo-bar_1.2'), 'foo-bar_1.2');
      expect(AgentCommandSafety.escapePosixArgument('--flag=value'),
          '--flag=value');
      expect(AgentCommandSafety.escapePosixArgument('/var/data/project'),
          '/var/data/project');

      // Unsafe inputs
      expect(AgentCommandSafety.escapePosixArgument('foo; rm -rf /'),
          "'foo; rm -rf /'");
      expect(AgentCommandSafety.escapePosixArgument('hello world'),
          "'hello world'");
      expect(
          AgentCommandSafety.escapePosixArgument(r'$(whoami)'), r"'$(whoami)'");
      expect(AgentCommandSafety.escapePosixArgument('`id`'), r"'`id`'");
    });

    test(
        'generateAgentSessionName sanitizes components and creates unique ad_agent_ session',
        () {
      final s1 = AgentCommandSafety.generateAgentSessionName(
          providerId: 'codex', projectId: 'proj 1!');
      final s2 = AgentCommandSafety.generateAgentSessionName(
          providerId: 'codex', projectId: 'proj 1!');

      expect(s1, startsWith('ad_agent_codex_proj_1__'));
      expect(s1, isNot(equals(s2)));
      expect(RegExp(r'^ad_agent_[a-zA-Z0-9_]{4,64}$').hasMatch(s1), isTrue);
    });

    test('stripAnsi removes ANSI color codes and escapes', () {
      const colored = '\x1B[31mError:\x1B[0m \x1B[1mFatal crash\x1B[0m';
      expect(AgentCommandSafety.stripAnsi(colored), 'Error: Fatal crash');

      const complex = '\x1B[38;5;196mRed text\x1B[0m\x1B[2K\rPrompt > ';
      expect(AgentCommandSafety.stripAnsi(complex), 'Red text\rPrompt > ');
    });
  });

  group('Provider discovery and version detection', () {
    test('CodexProvider detects availability and parses version', () async {
      const provider = CodexProvider();
      final transport = _FakeSshTransportHandle({
        'command -v codex':
            const RemoteCommandResult(0, '/usr/local/bin/codex\n', ''),
        'codex --version':
            const RemoteCommandResult(0, 'codex 0.4.12-beta\n', ''),
      });

      expect(await provider.isAvailable(transport), isTrue);
      expect(await provider.detectVersion(transport), '0.4.12-beta');
    });

    test('ClaudeCodeProvider detects availability and parses version',
        () async {
      const provider = ClaudeCodeProvider();
      final transport = _FakeSshTransportHandle({
        'command -v claude':
            const RemoteCommandResult(0, '/usr/bin/claude\n', ''),
        'claude --version':
            const RemoteCommandResult(0, 'claude-code 1.2.0 (release)\n', ''),
      });

      expect(await provider.isAvailable(transport), isTrue);
      expect(await provider.detectVersion(transport), '1.2.0');
    });

    test('OpenCodeProvider detects availability and parses version', () async {
      const provider = OpenCodeProvider();
      final transport = _FakeSshTransportHandle({
        'command -v opencode':
            const RemoteCommandResult(0, '/usr/local/bin/opencode\n', ''),
        'opencode --version':
            const RemoteCommandResult(0, 'opencode v0.1.48\n', ''),
      });

      expect(await provider.isAvailable(transport), isTrue);
      expect(await provider.detectVersion(transport), '0.1.48');
    });

    test('AntigravityProvider detects agy or antigravity alias', () async {
      const provider = AntigravityProvider();
      final transport = _FakeSshTransportHandle({
        'command -v agy': const RemoteCommandResult(1, '', 'not found'),
        'command -v antigravity':
            const RemoteCommandResult(0, '/home/user/.bin/antigravity\n', ''),
        'antigravity --version':
            const RemoteCommandResult(0, 'antigravity 2.1.0\n', ''),
      });

      expect(await provider.isAvailable(transport), isTrue);
      expect(await provider.detectVersion(transport), '2.1.0');
    });

    test('FakeAgentProvider detects availability and version', () async {
      const provider = FakeAgentProvider();
      final transport = _FakeSshTransportHandle({
        'command -v agentdeck-fake-agent': const RemoteCommandResult(
            0, '/usr/local/bin/agentdeck-fake-agent\n', ''),
        'agentdeck-fake-agent --version': const RemoteCommandResult(
            0, 'agentdeck-fake-agent 1.0.0-lab\n', ''),
      });

      expect(await provider.isAvailable(transport), isTrue);
      expect(await provider.detectVersion(transport), '1.0.0-lab');
    });

    test('GenericCliProvider handles custom binary and arguments', () {
      const provider = GenericCliProvider(
        id: 'python-agent',
        displayName: 'Python Runner',
        binaryCandidates: ['python3'],
      );

      final cmd = provider.buildLaunchCommand(
        executable: 'python3',
        workingDirectory: '/var/www/app',
        extraArgs: ['-u', 'agent.py', '--mode=live; dangerous'],
      );

      expect(cmd, ['python3', '-u', 'agent.py', "'--mode=live; dangerous'"]);
    });
  });
}
