import '../../features/connections/domain/ssh_models.dart';

enum AgentExecutionState {
  idle,
  starting,
  running,
  waitingUser,
  finished,
  failed,
  unknown,
}

enum ConnectionState {
  disconnected,
  connecting,
  connected,
  reconnecting,
  failed,
}

enum ObservationConfidence {
  confirmed,
  inferred,
  unknown,
}

enum ObservationSource {
  processExit,
  paneCommand,
  terminalPattern,
  tmuxSession,
  manual,
}

class AgentObservation {
  const AgentObservation({
    required this.state,
    required this.confidence,
    required this.source,
    required this.observedAt,
    this.detail,
  });

  final AgentExecutionState state;
  final ObservationConfidence confidence;
  final ObservationSource source;
  final DateTime observedAt;
  final String? detail;

  Map<String, dynamic> toJson() => {
        'state': state.name,
        'confidence': confidence.name,
        'source': source.name,
        'observedAt': observedAt.toUtc().toIso8601String(),
        if (detail != null) 'detail': detail,
      };

  factory AgentObservation.fromJson(Map<String, dynamic> json) {
    return AgentObservation(
      state: AgentExecutionState.values.firstWhere(
        (e) => e.name == json['state'],
        orElse: () => AgentExecutionState.unknown,
      ),
      confidence: ObservationConfidence.values.firstWhere(
        (e) => e.name == json['confidence'],
        orElse: () => ObservationConfidence.unknown,
      ),
      source: ObservationSource.values.firstWhere(
        (e) => e.name == json['source'],
        orElse: () => ObservationSource.manual,
      ),
      observedAt: DateTime.tryParse(json['observedAt'] as String? ?? '') ??
          DateTime.now().toUtc(),
      detail: json['detail'] as String?,
    );
  }

  @override
  String toString() =>
      'AgentObservation($state, confidence: $confidence, source: $source, detail: $detail)';
}

class AgentCapabilities {
  const AgentCapabilities({
    this.interactive = true,
    this.supportsResume = true,
    this.supportsNonInteractive = false,
    this.supportsStructuredOutput = false,
    this.supportsApprovalPrompts = false,
    this.supportsWorkingDirectory = true,
  });

  final bool interactive;
  final bool supportsResume;
  final bool supportsNonInteractive;
  final bool supportsStructuredOutput;
  final bool supportsApprovalPrompts;
  final bool supportsWorkingDirectory;
}

class AgentDefinition {
  const AgentDefinition({
    required this.id,
    required this.providerId,
    required this.displayName,
    this.executable,
    this.version,
    this.isAvailable = false,
    this.capabilities = const AgentCapabilities(),
    this.installGuidance,
  });

  final String id;
  final String providerId;
  final String displayName;
  final String? executable;
  final String? version;
  final bool isAvailable;
  final AgentCapabilities capabilities;
  final String? installGuidance;
}

class AgentInstance {
  const AgentInstance({
    required this.id,
    required this.providerId,
    required this.serverId,
    required this.projectId,
    required this.tmuxSessionName,
    required this.workingDirectory,
    this.executionState = AgentExecutionState.starting,
    this.observation,
    required this.startedAt,
    required this.lastObservedAt,
    this.exitCode,
    this.isStale = false,
    this.displayName,
  });

  final String id;
  final String providerId;
  final String serverId;
  final String projectId;
  final String tmuxSessionName;
  final String workingDirectory;
  final AgentExecutionState executionState;
  final AgentObservation? observation;
  final DateTime startedAt;
  final DateTime lastObservedAt;
  final int? exitCode;
  final bool isStale;
  final String? displayName;

  AgentInstance copyWith({
    String? id,
    String? providerId,
    String? serverId,
    String? projectId,
    String? tmuxSessionName,
    String? workingDirectory,
    AgentExecutionState? executionState,
    AgentObservation? observation,
    DateTime? startedAt,
    DateTime? lastObservedAt,
    int? exitCode,
    bool? isStale,
    String? displayName,
  }) {
    return AgentInstance(
      id: id ?? this.id,
      providerId: providerId ?? this.providerId,
      serverId: serverId ?? this.serverId,
      projectId: projectId ?? this.projectId,
      tmuxSessionName: tmuxSessionName ?? this.tmuxSessionName,
      workingDirectory: workingDirectory ?? this.workingDirectory,
      executionState: executionState ?? this.executionState,
      observation: observation ?? this.observation,
      startedAt: startedAt ?? this.startedAt,
      lastObservedAt: lastObservedAt ?? this.lastObservedAt,
      exitCode: exitCode ?? this.exitCode,
      isStale: isStale ?? this.isStale,
      displayName: displayName ?? this.displayName,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'providerId': providerId,
        'serverId': serverId,
        'projectId': projectId,
        'tmuxSessionName': tmuxSessionName,
        'workingDirectory': workingDirectory,
        'executionState': executionState.name,
        if (observation != null) 'observation': observation!.toJson(),
        'startedAt': startedAt.toUtc().toIso8601String(),
        'lastObservedAt': lastObservedAt.toUtc().toIso8601String(),
        if (exitCode != null) 'exitCode': exitCode,
        'isStale': isStale,
        if (displayName != null) 'displayName': displayName,
      };

  factory AgentInstance.fromJson(Map<String, dynamic> json) {
    return AgentInstance(
      id: json['id'] as String,
      providerId: json['providerId'] as String,
      serverId: json['serverId'] as String,
      projectId: json['projectId'] as String,
      tmuxSessionName: json['tmuxSessionName'] as String,
      workingDirectory: json['workingDirectory'] as String,
      executionState: AgentExecutionState.values.firstWhere(
        (e) => e.name == json['executionState'],
        orElse: () => AgentExecutionState.unknown,
      ),
      observation: json['observation'] != null
          ? AgentObservation.fromJson(
              json['observation'] as Map<String, dynamic>)
          : null,
      startedAt: DateTime.tryParse(json['startedAt'] as String? ?? '') ??
          DateTime.now().toUtc(),
      lastObservedAt:
          DateTime.tryParse(json['lastObservedAt'] as String? ?? '') ??
              DateTime.now().toUtc(),
      exitCode: json['exitCode'] as int?,
      isStale: json['isStale'] as bool? ?? false,
      displayName: json['displayName'] as String?,
    );
  }
}

abstract interface class AgentOutputClassifier {
  AgentObservation classify(String terminalOutput);
}

abstract interface class AgentProvider {
  String get id;
  String get displayName;
  List<String> get binaryCandidates;
  AgentCapabilities get capabilities;
  String get installGuidance;
  AgentOutputClassifier get outputClassifier;

  Future<bool> isAvailable(SshTmuxTransportHandle transport);
  Future<String?> detectVersion(SshTmuxTransportHandle transport,
      {String? executable});
  List<String> buildLaunchCommand({
    required String executable,
    required String workingDirectory,
    List<String>? extraArgs,
  });
}

abstract interface class AgentInstanceRepository {
  Future<List<AgentInstance>> all();
  Future<List<AgentInstance>> forServer(String serverId);
  Future<List<AgentInstance>> forProject(String serverId, String projectId);
  Future<AgentInstance?> find(String id);
  Future<void> put(AgentInstance instance);
  Future<void> delete(String id);
  Future<void> readCheck();
}

// Backward-compatibility M0 shells:
class AgentCapability {
  const AgentCapability(this.id, this.description);
  final String id;
  final String description;
}

class AgentExecution {
  const AgentExecution({
    required this.providerId,
    required this.projectId,
    required this.state,
    required this.connectionState,
  });

  final String providerId;
  final String projectId;
  final AgentExecutionState state;
  final ConnectionState connectionState;
}
