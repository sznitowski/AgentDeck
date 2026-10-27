import '../../../core/domain/agents.dart';
import '../../connections/domain/ssh_models.dart';
import '../domain/agent_models.dart';
import 'output_classifiers.dart';

class AntigravityProvider implements AgentProvider {
  const AntigravityProvider();

  @override
  String get id => 'antigravity';

  @override
  String get displayName => 'Antigravity';

  @override
  List<String> get binaryCandidates => const ['agy', 'antigravity'];

  @override
  AgentCapabilities get capabilities => const AgentCapabilities(
        interactive: true,
        supportsResume: true,
        supportsNonInteractive: true,
        supportsStructuredOutput: true,
        supportsApprovalPrompts: true,
        supportsWorkingDirectory: true,
      );

  @override
  String get installGuidance =>
      'Install on server using the official Antigravity CLI installer (agy).';

  @override
  AgentOutputClassifier get outputClassifier =>
      const AntigravityOutputClassifier();

  @override
  Future<bool> isAvailable(SshTmuxTransportHandle transport) async {
    for (final bin in binaryCandidates) {
      final res = await transport.run(['command', '-v', bin]);
      if (res.exitCode == 0 && res.stdout.trim().isNotEmpty) {
        return true;
      }
    }
    return false;
  }

  @override
  Future<String?> detectVersion(SshTmuxTransportHandle transport,
      {String? executable}) async {
    final candidates = executable != null ? [executable] : binaryCandidates;
    for (final bin in candidates) {
      try {
        final res = await transport.run([bin, '--version']);
        if (res.exitCode == 0) {
          final out = res.stdout.trim();
          final match = RegExp(r'(\d+\.\d+[\.\w\-]*)').firstMatch(out);
          return match?.group(1) ?? out;
        }
      } catch (_) {}
    }
    return null;
  }

  @override
  List<String> buildLaunchCommand({
    required String executable,
    required String workingDirectory,
    List<String>? extraArgs,
  }) {
    final safeBin = AgentCommandSafety.sanitizeExecutable(executable);
    final cmd = <String>[safeBin];
    if (extraArgs != null) {
      for (final arg in extraArgs) {
        cmd.add(AgentCommandSafety.escapePosixArgument(arg));
      }
    }
    return cmd;
  }
}
