import '../../../core/domain/agents.dart';
import '../../connections/domain/ssh_models.dart';
import '../domain/agent_models.dart';
import 'output_classifiers.dart';

class GenericCliProvider implements AgentProvider {
  const GenericCliProvider({
    this.id = 'generic',
    this.displayName = 'Generic CLI',
    this.binaryCandidates = const ['sh'],
    this.capabilities = const AgentCapabilities(
      interactive: true,
      supportsResume: true,
      supportsNonInteractive: false,
      supportsStructuredOutput: false,
      supportsApprovalPrompts: false,
      supportsWorkingDirectory: true,
    ),
    this.installGuidance =
        'Ensure the requested CLI binary is installed in PATH.',
    this.outputClassifier = const GenericOutputClassifier(),
  });

  @override
  final String id;

  @override
  final String displayName;

  @override
  final List<String> binaryCandidates;

  @override
  final AgentCapabilities capabilities;

  @override
  final String installGuidance;

  @override
  final AgentOutputClassifier outputClassifier;

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
    final bin = executable ?? binaryCandidates.first;
    try {
      final res = await transport.run([bin, '--version']);
      if (res.exitCode == 0) {
        final out = res.stdout.trim();
        final match = RegExp(r'(\d+\.\d+[\.\w\-]*)').firstMatch(out);
        return match?.group(1) ?? out;
      }
    } catch (_) {}
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
