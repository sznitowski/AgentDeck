import '../../../core/domain/events.dart';

/// Companion discovery status classifications.
enum CompanionStatus {
  available,
  notInstalled,
  incompatibleVersion,
  unhealthy,
}

/// Information about companion availability and protocol negotiation.
class CompanionAvailability {
  const CompanionAvailability({
    required this.status,
    this.versionInfo,
    this.error,
  });

  final CompanionStatus status;
  final CompanionVersionInfo? versionInfo;
  final String? error;

  bool get isAvailable => status == CompanionStatus.available;
}

/// Companion binary and protocol version metadata.
class CompanionVersionInfo {
  const CompanionVersionInfo({
    required this.schemaVersion,
    required this.binaryVersion,
    required this.protocolVersion,
  });

  final int schemaVersion;
  final String binaryVersion;
  final int protocolVersion;

  factory CompanionVersionInfo.fromJson(Map<String, dynamic> json) =>
      CompanionVersionInfo(
        schemaVersion: json['schemaVersion'] as int? ?? 1,
        binaryVersion: json['binaryVersion'] as String? ?? '0.0.0',
        protocolVersion: json['protocolVersion'] as int? ?? 1,
      );

  Map<String, dynamic> toJson() => {
        'schemaVersion': schemaVersion,
        'binaryVersion': binaryVersion,
        'protocolVersion': protocolVersion,
      };
}

/// Batch of events retrieved from the server companion journal.
class CompanionEventBatch {
  const CompanionEventBatch({
    required this.schemaVersion,
    required this.events,
    required this.lastSequence,
    required this.hasMore,
  });

  final int schemaVersion;
  final List<AgentDeckEvent> events;
  final int lastSequence;
  final bool hasMore;

  factory CompanionEventBatch.fromJson(Map<String, dynamic> json) {
    final rawList = json['events'] as List<dynamic>? ?? [];
    final parsedEvents = <AgentDeckEvent>[];

    for (final item in rawList) {
      if (item is Map) {
        final m = Map<String, dynamic>.from(item);
        parsedEvents.add(
          AgentDeckEvent(
            id: m['eventId'] as String? ?? m['id'] as String? ?? '',
            type: EventType.values.firstWhere(
              (t) => t.name == m['type'],
              orElse: () => EventType.agentWaitingUser,
            ),
            detectedAt: m['detectedAt'] != null
                ? DateTime.tryParse(m['detectedAt'] as String) ?? DateTime.now()
                : DateTime.now(),
            occurredAt: m['occurredAt'] != null
                ? DateTime.tryParse(m['occurredAt'] as String)
                : null,
            severity: EventSeverity.values.firstWhere(
              (s) => s.name == m['severity'],
              orElse: () => EventSeverity.info,
            ),
            source: EventSource.values.firstWhere(
              (s) => s.name == m['source'],
              orElse: () => EventSource.agent,
            ),
            fingerprint: m['fingerprint'] as String? ?? '',
            title: m['title'] as String? ?? '',
            message: m['message'] as String? ?? '',
            projectId: m['projectId'] as String?,
            projectName: m['projectName'] as String?,
            serverId: m['serverId'] as String?,
            serverName: m['serverName'] as String?,
            agentInstanceId: m['agentInstanceId'] as String?,
            agentProviderId: m['agentProviderId'] as String?,
            agentProviderName: m['agentProviderName'] as String?,
            actionLabel: m['actionLabel'] as String?,
            metadata: m['metadata'] is Map
                ? Map<String, dynamic>.from(m['metadata'] as Map)
                : const {},
            isProduction: m['isProduction'] as bool? ?? false,
            destination: m['destination'] is Map
                ? NotificationDestination.fromJson(
                    Map<String, dynamic>.from(m['destination'] as Map),
                  )
                : null,
            readState: EventReadState.unread,
          ),
        );
      }
    }

    return CompanionEventBatch(
      schemaVersion: json['schemaVersion'] as int? ?? 1,
      events: parsedEvents,
      lastSequence: json['lastSequence'] as int? ?? 0,
      hasMore: json['hasMore'] as bool? ?? false,
    );
  }
}

/// Abstract contract for communicating with a remote server companion.
abstract class RemoteCompanionClient {
  /// Discovers if the companion is installed and negotiates protocol version.
  Future<CompanionAvailability> discover(String serverId);

  /// Queries events from the companion journal strictly after [afterSequence].
  Future<CompanionEventBatch> fetchEvents(
    String serverId, {
    required int afterSequence,
    int limit = 100,
  });

  /// Fetches companion health telemetry.
  Future<Map<String, dynamic>> fetchHealth(String serverId);

  /// Fetches full companion status and project observations.
  Future<Map<String, dynamic>> fetchStatus(String serverId);

  /// Fetches in-memory snapshot of observed projects.
  Future<Map<String, dynamic>> fetchSnapshot(String serverId);
}
