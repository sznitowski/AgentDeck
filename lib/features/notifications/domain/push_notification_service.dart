import 'dart:async';
import '../../../core/domain/events.dart';

/// Represents system notification permission authorization states.
enum PushAuthorizationStatus {
  notDetermined,
  authorized,
  denied,
  provisional,
  unknown,
}

/// Payload extracted from an incoming APNs push alert.
class PushNotificationPayload {
  const PushNotificationPayload({
    required this.eventId,
    required this.type,
    required this.severity,
    required this.title,
    required this.body,
    this.serverId,
    this.projectId,
    this.destination,
    this.isProduction = false,
    required this.receivedAt,
  });

  final String eventId;
  final EventType type;
  final EventSeverity severity;
  final String title;
  final String body;
  final String? serverId;
  final String? projectId;
  final NotificationDestination? destination;
  final bool isProduction;
  final DateTime receivedAt;
}

/// Abstract contract for native iOS Push Notifications and APNs token lifecycle.
abstract class PushNotificationService {
  /// Queries current iOS notification authorization status.
  Future<PushAuthorizationStatus> getAuthorizationStatus();

  /// Requests user permission via native dialog (`UNUserNotificationCenter`).
  Future<PushAuthorizationStatus> requestAuthorization();

  /// Returns current 64-char hex device token if authorized and registered.
  Future<String?> getDeviceToken();

  /// Stream of rotated/refreshed device tokens.
  Stream<String> get onTokenRefresh;

  /// Stream of notifications received while app is in foreground.
  Stream<PushNotificationPayload> get onForegroundNotification;

  /// Stream of user taps on lock screen / banner notifications.
  Stream<NotificationDestination> get onNotificationTap;

  /// Retrieves cold-start pending destination if app was launched via push tap.
  NotificationDestination? getPendingNotificationTap();

  /// Clears pending cold-start destination after handling.
  void clearPendingNotificationTap();
}
