import 'dart:async';

import '../../../core/domain/events.dart';
import '../domain/notification_policy.dart';

/// Abstract contract for delivering notifications to the user across channels.
abstract class NotificationDeliveryService {
  /// Delivers a sanitized notification payload.
  Future<void> deliver(
      AgentDeckEvent event, SanitizedNotificationPayload payload);

  /// Stream of foreground events for in-app banners/snackbars.
  Stream<AgentDeckEvent> get inAppEvents;

  /// Requests OS notification permissions (deferred until user contextual action).
  Future<bool> requestPermissions();

  /// Releases resources.
  Future<void> dispose();
}

/// In-App notification delivery engine for foreground banners and live activity.
class InAppNotificationDelivery implements NotificationDeliveryService {
  InAppNotificationDelivery();

  final StreamController<AgentDeckEvent> _controller =
      StreamController<AgentDeckEvent>.broadcast();

  @override
  Stream<AgentDeckEvent> get inAppEvents => _controller.stream;

  @override
  Future<void> deliver(
    AgentDeckEvent event,
    SanitizedNotificationPayload payload,
  ) async {
    if (!_controller.isClosed) {
      _controller.add(event);
    }
  }

  @override
  Future<bool> requestPermissions() async {
    // In-app notifications do not require OS-level permissions
    return true;
  }

  @override
  Future<void> dispose() async {
    await _controller.close();
  }
}

/// Decoupled OS Local Notification adapter interface.
/// Actual native implementation is tagged [PENDING_MACOS_VALIDATION].
class LocalNotificationDelivery implements NotificationDeliveryService {
  LocalNotificationDelivery({NotificationDeliveryService? inAppFallback})
      : _inApp = inAppFallback ?? InAppNotificationDelivery();

  final NotificationDeliveryService _inApp;

  @override
  Stream<AgentDeckEvent> get inAppEvents => _inApp.inAppEvents;

  @override
  Future<void> deliver(
    AgentDeckEvent event,
    SanitizedNotificationPayload payload,
  ) async {
    // Forward to in-app stream
    await _inApp.deliver(event, payload);
    // Native OS local notification dispatch is reserved for macOS/iOS runner validation
  }

  @override
  Future<bool> requestPermissions() async {
    // Native UNUserNotificationCenter permission request requires iOS runner
    return true;
  }

  @override
  Future<void> dispose() async {
    await _inApp.dispose();
  }
}

/// Remote observer interface reserved for M8.5 Server Companion integration.
abstract class RemoteEventSource {
  Stream<AgentDeckEvent> get remoteEvents;
  Future<void> startObserving({required String serverId});
  Future<void> stopObserving({required String serverId});
}
