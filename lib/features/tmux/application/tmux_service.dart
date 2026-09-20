import '../../../core/domain/profiles.dart';
import '../../../core/domain/remote_contracts.dart';
import '../../connections/application/ssh_connection_service.dart';
import '../domain/tmux_models.dart';

class TmuxService {
  TmuxService(
      {required this.connection,
      required this.references,
      required this.serverId,
      DateTime Function()? clock})
      : _clock = clock ?? DateTime.now;
  final SshConnectionService connection;
  final TmuxSessionRepository references;
  final String serverId;
  final DateTime Function() _clock;

  void _checkConnection() {
    if (connection.connectedProfileId != serverId) {
      throw const TmuxFailure('connection');
    }
  }

  Future<TmuxCapability> detect() async {
    _checkConnection();
    try {
      final path = await connection.runRemoteCommand(['command', '-v', 'tmux']);
      if (path.exitCode == 1 || path.exitCode == 127) {
        return const TmuxCapability(TmuxAvailability.notInstalled);
      }
      if (path.exitCode != 0)
        return const TmuxCapability(TmuxAvailability.error);
      final version = await connection.runRemoteCommand(['tmux', '-V']);
      if (version.exitCode != 0)
        return const TmuxCapability(TmuxAvailability.error);
      final match = RegExp(r'\btmux\s+([0-9]+(?:\.[0-9]+)?[a-z]?)\b')
          .firstMatch(version.stdout.trim());
      if (match == null)
        return const TmuxCapability(TmuxAvailability.unsupported);
      return TmuxCapability(TmuxAvailability.available,
          version: match.group(1));
    } catch (_) {
      return const TmuxCapability(TmuxAvailability.error);
    }
  }

  Future<List<TmuxSessionInfo>> list() async {
    _checkConnection();
    final response = await connection.runRemoteCommand([
      'tmux',
      'list-sessions',
      '-F',
      '#{session_name}:#{session_attached}:#{session_created}'
    ]);
    if (response.exitCode != 0 && response.exitCode != 1) {
      throw const TmuxFailure('list');
    }
    final refs = {
      for (final row in await references.forServer(serverId))
        row.remoteName: row
    };
    final found = <String>{};
    final sessions = <TmuxSessionInfo>[];
    if (response.exitCode == 0) {
      for (final line in response.stdout.split('\n')) {
        final trimmed = line.trim();
        if (trimmed.isEmpty) continue;
        final parts = trimmed.split(':');
        if (parts.length < 3) continue;
        final created = int.tryParse(parts.last);
        final clients = int.tryParse(parts[parts.length - 2]);
        if (clients == null || clients < 0 || created == null) continue;
        final name = parts.sublist(0, parts.length - 2).join(':');
        if (name.isEmpty || found.contains(name)) continue;
        found.add(name);
        final ref = refs[name];
        sessions.add(TmuxSessionInfo(
            remoteName: name,
            displayName: ref?.displayName ?? name,
            managed: ref != null,
            projectId: ref?.projectId,
            attachedClients: clients,
            state: clients > 0
                ? TmuxSessionState.attached
                : TmuxSessionState.detached,
            createdAt: DateTime.fromMillisecondsSinceEpoch(created * 1000,
                isUtc: true),
            lastAttachedAt: ref?.lastAttachedAt));
      }
    }
    for (final ref in refs.values) {
      if (!found.contains(ref.remoteName)) {
        sessions.add(TmuxSessionInfo(
            remoteName: ref.remoteName,
            displayName: ref.displayName,
            managed: true,
            projectId: ref.projectId,
            state: TmuxSessionState.stale,
            lastAttachedAt: ref.lastAttachedAt));
      }
    }
    return sessions;
  }

  Future<TmuxSessionInfo> create(
      {required String displayName,
      String? projectId,
      String? workingDirectory}) async {
    _checkConnection();
    final display = displayName.trim();
    if (display.isEmpty ||
        display.length > 80 ||
        display.contains(RegExp(r'[\x00-\x1f\x7f]')) ||
        (workingDirectory != null &&
            !validWorkingDirectory(workingDirectory))) {
      throw const TmuxFailure('invalidInput');
    }
    final name = newTmuxName();
    final args = [
      'tmux',
      '-u',
      'new-session',
      '-d',
      '-s',
      name,
      '-x',
      '80',
      '-y',
      '24'
    ];
    if (workingDirectory != null) args.addAll(['-c', workingDirectory]);
    final result = await connection.runRemoteCommand(args);
    if (result.exitCode != 0) {
      throw TmuxFailure(
          'create: exit=${result.exitCode}, stdout=${result.stdout.trim()}, stderr=${result.stderr.trim()}');
    }
    final remote = await list();
    final created = remote.where((item) => item.remoteName == name).firstOrNull;
    if (created == null) throw const TmuxFailure('createUnconfirmed');
    final ref = TmuxSessionReference(
        serverId: serverId,
        remoteName: name,
        displayName: display,
        projectId: projectId);
    await references.save(ref);
    return TmuxSessionInfo(
        remoteName: name,
        displayName: display,
        managed: true,
        projectId: projectId,
        state: TmuxSessionState.detached,
        createdAt: created.createdAt);
  }

  Future<TmuxSessionInfo> createForProject(ProjectProfile project,
      {required String displayName}) {
    if (project.serverId != serverId) throw const TmuxFailure('serverMismatch');
    return create(
        displayName: displayName,
        projectId: project.id,
        workingDirectory: project.workingDirectory);
  }

  Future<TerminalSession> attach(String name, int columns, int rows) async {
    _checkConnection();
    if (!validTmuxName(name)) throw const TmuxFailure('invalidName');
    final current =
        (await list()).where((item) => item.remoteName == name).firstOrNull;
    if (current == null ||
        !current.managed ||
        current.state == TmuxSessionState.stale) {
      throw const TmuxFailure('missing');
    }
    final session = await connection.attachTmux(name, columns, rows);
    final ref = (await references.forServer(serverId))
        .where((item) => item.remoteName == name)
        .firstOrNull;
    try {
      if (ref != null) await references.save(ref.attachedAt(_clock()));
    } catch (_) {
      await session.close();
      rethrow;
    }
    return session;
  }

  // Closing only this PTY channel detaches this client. Other clients remain.
  Future<void> detach(TerminalSession session) => session.close();

  Future<void> terminate(String name) async {
    _checkConnection();
    if (!validTmuxName(name)) throw const TmuxFailure('invalidName');
    final ref = (await references.forServer(serverId))
        .where((item) => item.remoteName == name)
        .firstOrNull;
    if (ref == null) throw const TmuxFailure('external');
    final result = await connection
        .runRemoteCommand(['tmux', 'kill-session', '-t', '=' + name]);
    if (result.exitCode != 0) throw const TmuxFailure('terminate');
    await references.delete(serverId, name);
  }
}
