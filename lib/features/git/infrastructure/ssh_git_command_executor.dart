import '../../../core/domain/agents.dart';
import '../../../core/domain/git.dart';
import '../../connections/application/ssh_connection_service.dart';
import '../../connections/domain/ssh_models.dart';

/// Adapter that executes remote Git commands over verified SSH transport.
class SshGitCommandExecutor implements GitCommandExecutor {
  const SshGitCommandExecutor({
    required this.connection,
    required this.serverId,
  });

  final SshConnectionService connection;
  final String serverId;

  @override
  Future<RemoteCommandOutput> execute(
    List<String> arguments, {
    Duration timeout = const Duration(seconds: 15),
  }) async {
    if (connection.state != ConnectionState.connected ||
        connection.connectedProfileId != serverId) {
      throw const GitFailure(
        GitFailureKind.disconnected,
        message: 'SSH is not connected to the target server.',
      );
    }

    try {
      final res = await connection.runRemoteCommand(
        arguments,
        timeout: timeout,
      );
      return RemoteCommandOutput(res.exitCode, res.stdout, res.stderr);
    } on SshFailure catch (failure) {
      if (failure.kind == SshFailureKind.timeout) {
        throw const GitFailure(
          GitFailureKind.timeout,
          message: 'Remote Git command timed out.',
        );
      }
      if (failure.kind == SshFailureKind.closed ||
          failure.kind == SshFailureKind.network) {
        throw const GitFailure(
          GitFailureKind.disconnected,
          message: 'SSH transport closed during command execution.',
        );
      }
      throw GitFailure(
        GitFailureKind.operationFailed,
        message: 'SSH command execution failure: ${failure.kind.name}',
      );
    } catch (e) {
      throw GitFailure(
        GitFailureKind.operationFailed,
        message: 'Unexpected command execution error: $e',
      );
    }
  }
}
