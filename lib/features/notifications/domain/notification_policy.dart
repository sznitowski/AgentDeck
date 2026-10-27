import '../../../core/domain/events.dart';

/// User configurable notification preferences.
class NotificationPreferences {
  const NotificationPreferences({
    this.notifyAgentWaiting = true,
    this.notifyAgentFailed = true,
    this.notifyAgentFinished = false,
    this.notifyGitConflict = true,
    this.notifyConnectionLost = true,
    this.notifyConnectionRestored = true,
    this.notifyServerCritical = true,
    this.notifyServerWarning = false,
    this.privacyMode = NotificationPrivacyMode.full,
  });

  final bool notifyAgentWaiting;
  final bool notifyAgentFailed;
  final bool notifyAgentFinished;
  final bool notifyGitConflict;
  final bool notifyConnectionLost;
  final bool notifyConnectionRestored;
  final bool notifyServerCritical;
  final bool notifyServerWarning;
  final NotificationPrivacyMode privacyMode;

  NotificationPreferences copyWith({
    bool? notifyAgentWaiting,
    bool? notifyAgentFailed,
    bool? notifyAgentFinished,
    bool? notifyGitConflict,
    bool? notifyConnectionLost,
    bool? notifyConnectionRestored,
    bool? notifyServerCritical,
    bool? notifyServerWarning,
    NotificationPrivacyMode? privacyMode,
  }) {
    return NotificationPreferences(
      notifyAgentWaiting: notifyAgentWaiting ?? this.notifyAgentWaiting,
      notifyAgentFailed: notifyAgentFailed ?? this.notifyAgentFailed,
      notifyAgentFinished: notifyAgentFinished ?? this.notifyAgentFinished,
      notifyGitConflict: notifyGitConflict ?? this.notifyGitConflict,
      notifyConnectionLost: notifyConnectionLost ?? this.notifyConnectionLost,
      notifyConnectionRestored:
          notifyConnectionRestored ?? this.notifyConnectionRestored,
      notifyServerCritical: notifyServerCritical ?? this.notifyServerCritical,
      notifyServerWarning: notifyServerWarning ?? this.notifyServerWarning,
      privacyMode: privacyMode ?? this.privacyMode,
    );
  }

  Map<String, dynamic> toJson() => {
        'notifyAgentWaiting': notifyAgentWaiting,
        'notifyAgentFailed': notifyAgentFailed,
        'notifyAgentFinished': notifyAgentFinished,
        'notifyGitConflict': notifyGitConflict,
        'notifyConnectionLost': notifyConnectionLost,
        'notifyConnectionRestored': notifyConnectionRestored,
        'notifyServerCritical': notifyServerCritical,
        'notifyServerWarning': notifyServerWarning,
        'privacyMode': privacyMode.name,
      };

  factory NotificationPreferences.fromJson(Map<String, dynamic> json) =>
      NotificationPreferences(
        notifyAgentWaiting: json['notifyAgentWaiting'] as bool? ?? true,
        notifyAgentFailed: json['notifyAgentFailed'] as bool? ?? true,
        notifyAgentFinished: json['notifyAgentFinished'] as bool? ?? false,
        notifyGitConflict: json['notifyGitConflict'] as bool? ?? true,
        notifyConnectionLost: json['notifyConnectionLost'] as bool? ?? true,
        notifyConnectionRestored:
            json['notifyConnectionRestored'] as bool? ?? true,
        notifyServerCritical: json['notifyServerCritical'] as bool? ?? true,
        notifyServerWarning: json['notifyServerWarning'] as bool? ?? false,
        privacyMode: NotificationPrivacyMode.values.firstWhere(
          (m) => m.name == json['privacyMode'],
          orElse: () => NotificationPrivacyMode.full,
        ),
      );
}

/// Output of title and message formatting after privacy rules are applied.
class SanitizedNotificationPayload {
  const SanitizedNotificationPayload({
    required this.title,
    required this.message,
    required this.isProduction,
  });

  final String title;
  final String message;
  final bool isProduction;
}

/// Decides if an event warrants alerting the user, and sanitizes notification payloads.
class NotificationPolicy {
  NotificationPolicy({
    this.globalPreferences = const NotificationPreferences(),
    Map<String, NotificationPreferences>? projectOverrides,
  }) : projectOverrides = projectOverrides ?? {};

  final NotificationPreferences globalPreferences;
  final Map<String, NotificationPreferences> projectOverrides;

  NotificationPolicy copyWith({
    NotificationPreferences? globalPreferences,
    Map<String, NotificationPreferences>? projectOverrides,
  }) {
    return NotificationPolicy(
      globalPreferences: globalPreferences ?? this.globalPreferences,
      projectOverrides: projectOverrides ?? this.projectOverrides,
    );
  }

  /// Determines whether an event should trigger an active notification.
  bool shouldNotify(AgentDeckEvent event) {
    final prefs =
        event.projectId != null && projectOverrides.containsKey(event.projectId)
            ? projectOverrides[event.projectId]!
            : globalPreferences;

    switch (event.type) {
      case EventType.agentWaitingUser:
        return prefs.notifyAgentWaiting;
      case EventType.agentFailed:
        return prefs.notifyAgentFailed;
      case EventType.agentFinished:
        return prefs.notifyAgentFinished;
      case EventType.gitConflictDetected:
        return prefs.notifyGitConflict;
      case EventType.gitConflictResolved:
        return false; // Resolved is informational in event log, not alert popup
      case EventType.connectionLost:
        return prefs.notifyConnectionLost;
      case EventType.connectionRestored:
        return prefs.notifyConnectionRestored;
      case EventType.serverResourceCritical:
        return prefs.notifyServerCritical;
      case EventType.serverResourceWarning:
        return prefs.notifyServerWarning;
      case EventType.serverResourceRecovered:
        return false;
      case EventType.tmuxSessionMissing:
        return prefs.notifyAgentFailed;
      case EventType.workingDirectoryMissing:
        return true;
    }
  }

  /// Transforms an event into a privacy-safe preview according to privacy mode.
  SanitizedNotificationPayload sanitizeForPreview(
    AgentDeckEvent event, {
    NotificationPrivacyMode? overrideMode,
  }) {
    final prefs =
        event.projectId != null && projectOverrides.containsKey(event.projectId)
            ? projectOverrides[event.projectId]!
            : globalPreferences;

    final mode = overrideMode ?? prefs.privacyMode;
    final prodPrefix = event.isProduction ? 'PRODUCTION • ' : '';

    switch (mode) {
      case NotificationPrivacyMode.full:
        final prefix = event.projectName != null
            ? '$prodPrefix${event.projectName}: '
            : (event.serverName != null
                ? '$prodPrefix${event.serverName}: '
                : prodPrefix);
        return SanitizedNotificationPayload(
          title: '$prefix${event.title}',
          message: event.message,
          isProduction: event.isProduction,
        );

      case NotificationPrivacyMode.projectOnly:
        final targetName = event.projectName ?? event.serverName ?? 'AgentDeck';
        return SanitizedNotificationPayload(
          title: '$prodPrefix$targetName',
          message: _genericMessageForType(event.type),
          isProduction: event.isProduction,
        );

      case NotificationPrivacyMode.generic:
        return SanitizedNotificationPayload(
          title: event.isProduction ? 'PRODUCTION Alert' : 'AgentDeck Alert',
          message: 'An item requires your attention.',
          isProduction: event.isProduction,
        );
    }
  }

  String _genericMessageForType(EventType type) {
    switch (type) {
      case EventType.agentWaitingUser:
        return 'Remote agent is waiting for input.';
      case EventType.agentFailed:
        return 'Remote agent execution failed.';
      case EventType.agentFinished:
        return 'Remote agent execution finished.';
      case EventType.gitConflictDetected:
        return 'Git repository has merge conflicts.';
      case EventType.gitConflictResolved:
        return 'Git merge conflicts resolved.';
      case EventType.connectionLost:
        return 'Server connection lost.';
      case EventType.connectionRestored:
        return 'Server connection restored.';
      case EventType.serverResourceCritical:
        return 'Server resources in critical state.';
      case EventType.serverResourceWarning:
        return 'Server resources warning.';
      case EventType.serverResourceRecovered:
        return 'Server resources recovered.';
      case EventType.tmuxSessionMissing:
        return 'Session not found on host.';
      case EventType.workingDirectoryMissing:
        return 'Working directory inaccessible.';
    }
  }
}
