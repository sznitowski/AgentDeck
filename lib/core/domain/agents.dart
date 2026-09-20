enum AgentExecutionState {
  idle,
  starting,
  running,
  waitingUser,
  finished,
  failed
}

enum ConnectionState {
  disconnected,
  connecting,
  connected,
  reconnecting,
  failed
}

class AgentCapability {
  const AgentCapability(this.id, this.description);

  final String id;
  final String description;
}

abstract interface class AgentProvider {
  String get id;
  String get displayName;
  Set<AgentCapability> get capabilities;
}

class AgentExecution {
  const AgentExecution(
      {required this.providerId,
      required this.projectId,
      required this.state,
      required this.connectionState});

  final String providerId;
  final String projectId;
  final AgentExecutionState state;
  final ConnectionState connectionState;
}
