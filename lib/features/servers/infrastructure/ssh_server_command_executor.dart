import '../../../core/domain/agents.dart';
import '../../../core/domain/git.dart' show RemoteCommandOutput;
import '../../../core/domain/server_operations.dart';
import '../../connections/application/ssh_connection_service.dart';
import '../../connections/domain/ssh_models.dart';

/// Adapter that executes remote server operations over verified SSH transport.
class SshServerCommandExecutor implements ServerCommandExecutor {
  const SshServerCommandExecutor({
    required this.connection,
    required this.serverId,
  });

  final SshConnectionService connection;
  final String serverId;

  @override
  Future<RemoteCommandOutput> execute(
    String executable,
    List<String> arguments, {
    Duration? timeout,
  }) async {
    if (connection.state != ConnectionState.connected ||
        connection.connectedProfileId != serverId) {
      throw const ServerOperationFailure(
        ServerOperationFailureKind.connectionLost,
        'SSH is not connected to target server.',
      );
    }

    try {
      final cmd = [executable, ...arguments];
      final res = await connection.runRemoteCommand(
        cmd,
        timeout: timeout ?? const Duration(seconds: 15),
      );
      return RemoteCommandOutput(res.exitCode, res.stdout, res.stderr);
    } on SshFailure catch (failure) {
      if (failure.kind == SshFailureKind.timeout) {
        throw const ServerOperationFailure(
          ServerOperationFailureKind.timeout,
          'Remote command timed out.',
        );
      }
      if (failure.kind == SshFailureKind.closed ||
          failure.kind == SshFailureKind.network) {
        throw const ServerOperationFailure(
          ServerOperationFailureKind.connectionLost,
          'SSH transport closed during command execution.',
        );
      }
      throw ServerOperationFailure(
        ServerOperationFailureKind.operationFailed,
        'SSH command execution failure: ${failure.kind.name}',
      );
    } catch (e) {
      if (e is ServerOperationFailure) rethrow;
      throw ServerOperationFailure(
        ServerOperationFailureKind.operationFailed,
        'Unexpected command execution error: $e',
        e,
      );
    }
  }
}
