/// Primary classification of an AgentDeck domain event.
enum EventType {
  agentWaitingUser,
  agentFinished,
  agentFailed,
  gitConflictDetected,
  gitConflictResolved,
  connectionLost,
  connectionRestored,
  tmuxSessionMissing,
  workingDirectoryMissing,
  serverResourceWarning,
  serverResourceCritical,
  serverResourceRecovered,
}

/// Severity level determining attention hierarchy and alert styling.
enum EventSeverity {
  info,
  warning,
  actionRequired,
  critical,
}

/// Subsystem source originating the event.
enum EventSource {
  agent,
  git,
  connection,
  tmux,
  files,
  server,
  workspace,
}

/// User read/acknowledged status.
enum EventReadState {
  unread,
  read,
  acknowledged,
}

/// Privacy preview mode for notifications on lock screen and UI.
enum NotificationPrivacyMode {
  full,
  projectOnly,
  generic,
}

/// Typed destination for 1-tap navigation from notifications.
class NotificationDestination {
  const NotificationDestination({
    required this.route,
    this.projectId,
    this.serverId,
    this.agentInstanceId,
    this.tmuxSessionName,
  });

  final String route;
  final String? projectId;
  final String? serverId;
  final String? agentInstanceId;
  final String? tmuxSessionName;

  Map<String, dynamic> toJson() => {
        'route': route,
        if (projectId != null) 'projectId': projectId,
        if (serverId != null) 'serverId': serverId,
        if (agentInstanceId != null) 'agentInstanceId': agentInstanceId,
        if (tmuxSessionName != null) 'tmuxSessionName': tmuxSessionName,
      };

  factory NotificationDestination.fromJson(Map<String, dynamic> json) =>
      NotificationDestination(
        route: json['route'] as String? ?? 'workspace',
        projectId: json['projectId'] as String?,
        serverId: json['serverId'] as String?,
        agentInstanceId: json['agentInstanceId'] as String?,
        tmuxSessionName: json['tmuxSessionName'] as String?,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is NotificationDestination &&
          other.route == route &&
          other.projectId == projectId &&
          other.serverId == serverId &&
          other.agentInstanceId == agentInstanceId &&
          other.tmuxSessionName == tmuxSessionName;

  @override
  int get hashCode => Object.hash(
        route,
        projectId,
        serverId,
        agentInstanceId,
        tmuxSessionName,
      );
}

/// Structured, deduplicated, privacy-safe domain event.
class AgentDeckEvent {
  const AgentDeckEvent({
    required this.id,
    required this.type,
    required this.detectedAt,
    required this.severity,
    required this.source,
    required this.fingerprint,
    required this.title,
    required this.message,
    this.occurredAt,
    this.projectId,
    this.projectName,
    this.serverId,
    this.serverName,
    this.agentInstanceId,
    this.agentProviderId,
    this.agentProviderName,
    this.actionLabel,
    this.metadata = const {},
    this.isProduction = false,
    this.destination,
    this.readState = EventReadState.unread,
  });

  final String id;
  final EventType type;
  final DateTime detectedAt;
  final DateTime? occurredAt;
  final EventSeverity severity;
  final EventSource source;
  final String fingerprint;
  final String title;
  final String message;
  final String? projectId;
  final String? projectName;
  final String? serverId;
  final String? serverName;
  final String? agentInstanceId;
  final String? agentProviderId;
  final String? agentProviderName;
  final String? actionLabel;
  final Map<String, dynamic> metadata;
  final bool isProduction;
  final NotificationDestination? destination;
  final EventReadState readState;

  bool get isUnread => readState == EventReadState.unread;
  bool get isActionable =>
      severity == EventSeverity.actionRequired ||
      severity == EventSeverity.critical;

  AgentDeckEvent copyWith({
    String? id,
    EventType? type,
    DateTime? detectedAt,
    DateTime? occurredAt,
    EventSeverity? severity,
    EventSource? source,
    String? fingerprint,
    String? title,
    String? message,
    String? projectId,
    String? projectName,
    String? serverId,
    String? serverName,
    String? agentInstanceId,
    String? agentProviderId,
    String? agentProviderName,
    String? actionLabel,
    Map<String, dynamic>? metadata,
    bool? isProduction,
    NotificationDestination? destination,
    EventReadState? readState,
  }) {
    return AgentDeckEvent(
      id: id ?? this.id,
      type: type ?? this.type,
      detectedAt: detectedAt ?? this.detectedAt,
      occurredAt: occurredAt ?? this.occurredAt,
      severity: severity ?? this.severity,
      source: source ?? this.source,
      fingerprint: fingerprint ?? this.fingerprint,
      title: title ?? this.title,
      message: message ?? this.message,
      projectId: projectId ?? this.projectId,
      projectName: projectName ?? this.projectName,
      serverId: serverId ?? this.serverId,
      serverName: serverName ?? this.serverName,
      agentInstanceId: agentInstanceId ?? this.agentInstanceId,
      agentProviderId: agentProviderId ?? this.agentProviderId,
      agentProviderName: agentProviderName ?? this.agentProviderName,
      actionLabel: actionLabel ?? this.actionLabel,
      metadata: metadata ?? this.metadata,
      isProduction: isProduction ?? this.isProduction,
      destination: destination ?? this.destination,
      readState: readState ?? this.readState,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type.name,
        'detectedAt': detectedAt.toIso8601String(),
        if (occurredAt != null) 'occurredAt': occurredAt!.toIso8601String(),
        'severity': severity.name,
        'source': source.name,
        'fingerprint': fingerprint,
        'title': title,
        'message': message,
        if (projectId != null) 'projectId': projectId,
        if (projectName != null) 'projectName': projectName,
        if (serverId != null) 'serverId': serverId,
        if (serverName != null) 'serverName': serverName,
        if (agentInstanceId != null) 'agentInstanceId': agentInstanceId,
        if (agentProviderId != null) 'agentProviderId': agentProviderId,
        if (agentProviderName != null) 'agentProviderName': agentProviderName,
        if (actionLabel != null) 'actionLabel': actionLabel,
        'metadata': metadata,
        'isProduction': isProduction,
        if (destination != null) 'destination': destination!.toJson(),
        'readState': readState.name,
      };

  factory AgentDeckEvent.fromJson(Map<String, dynamic> json) => AgentDeckEvent(
        id: json['id'] as String? ?? '',
        type: EventType.values.firstWhere(
          (t) => t.name == json['type'],
          orElse: () => EventType.agentWaitingUser,
        ),
        detectedAt: json['detectedAt'] != null
            ? DateTime.tryParse(json['detectedAt'] as String) ?? DateTime.now()
            : DateTime.now(),
        occurredAt: json['occurredAt'] != null
            ? DateTime.tryParse(json['occurredAt'] as String)
            : null,
        severity: EventSeverity.values.firstWhere(
          (s) => s.name == json['severity'],
          orElse: () => EventSeverity.info,
        ),
        source: EventSource.values.firstWhere(
          (s) => s.name == json['source'],
          orElse: () => EventSource.workspace,
        ),
        fingerprint: json['fingerprint'] as String? ?? '',
        title: json['title'] as String? ?? '',
        message: json['message'] as String? ?? '',
        projectId: json['projectId'] as String?,
        projectName: json['projectName'] as String?,
        serverId: json['serverId'] as String?,
        serverName: json['serverName'] as String?,
        agentInstanceId: json['agentInstanceId'] as String?,
        agentProviderId: json['agentProviderId'] as String?,
        agentProviderName: json['agentProviderName'] as String?,
        actionLabel: json['actionLabel'] as String?,
        metadata: json['metadata'] is Map
            ? Map<String, dynamic>.from(json['metadata'] as Map)
            : const {},
        isProduction: json['isProduction'] as bool? ?? false,
        destination: json['destination'] is Map
            ? NotificationDestination.fromJson(
                Map<String, dynamic>.from(json['destination'] as Map))
            : null,
        readState: EventReadState.values.firstWhere(
          (r) => r.name == json['readState'],
          orElse: () => EventReadState.unread,
        ),
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AgentDeckEvent &&
          other.id == id &&
          other.type == type &&
          other.fingerprint == fingerprint &&
          other.readState == readState;

  @override
  int get hashCode => Object.hash(id, type, fingerprint, readState);
}
