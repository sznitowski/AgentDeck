import 'dart:math';

enum TmuxAvailability { available, notInstalled, unsupported, error }

enum TmuxSessionState { attached, detached, stale }

class TmuxCapability {
  const TmuxCapability(this.availability, {this.version});
  final TmuxAvailability availability;
  final String? version;
}

class TmuxSessionReference {
  const TmuxSessionReference(
      {required this.serverId,
      required this.remoteName,
      required this.displayName,
      this.projectId,
      this.lastAttachedAt});
  final String serverId;
  final String remoteName;
  final String displayName;
  final String? projectId;
  final DateTime? lastAttachedAt;

  TmuxSessionReference attachedAt(DateTime at) => TmuxSessionReference(
      serverId: serverId,
      remoteName: remoteName,
      displayName: displayName,
      projectId: projectId,
      lastAttachedAt: at);
}

class TmuxSessionInfo {
  const TmuxSessionInfo(
      {required this.remoteName,
      required this.displayName,
      required this.state,
      required this.managed,
      this.projectId,
      this.attachedClients = 0,
      this.createdAt,
      this.lastAttachedAt});
  final String remoteName;
  final String displayName;
  final TmuxSessionState state;
  final bool managed;
  final String? projectId;
  final int attachedClients;
  final DateTime? createdAt;
  final DateTime? lastAttachedAt;
}

class TmuxFailure implements Exception {
  const TmuxFailure(this.kind);
  final String kind;
  @override
  String toString() => 'TmuxFailure($kind)';
}

abstract interface class TmuxSessionRepository {
  Future<List<TmuxSessionReference>> forServer(String serverId);
  Future<void> save(TmuxSessionReference reference);
  Future<void> delete(String serverId, String remoteName);
  Future<void> deleteServer(String serverId);
  Future<void> readCheck();
}

bool validTmuxName(String name) => RegExp(r'^ad_[a-f0-9]{16}$').hasMatch(name);

String newTmuxName([Random? random]) {
  final source = random ?? Random.secure();
  return 'ad_' +
      List.generate(
              8, (_) => source.nextInt(256).toRadixString(16).padLeft(2, '0'))
          .join();
}

bool validWorkingDirectory(String path) =>
    path.startsWith('/') &&
    path.length <= 1024 &&
    RegExp(r'^/[A-Za-z0-9_./ -]*$').hasMatch(path) &&
    !path.split('/').contains('..') &&
    !path.split('/').contains('.');
