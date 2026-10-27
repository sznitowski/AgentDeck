import 'dart:async';
import '../../../core/domain/events.dart';
import '../domain/push_notification_service.dart';

/// Test and mock implementation of [PushNotificationService] for headless testing and lab verification.
class FakePushNotificationService implements PushNotificationService {
  FakePushNotificationService({
    PushAuthorizationStatus initialStatus =
        PushAuthorizationStatus.notDetermined,
    this.initialToken =
        'mock_device_token_740f4707bebcf74f9b7c25d48e3358945f6aa01da5ddb387462c7eaf61bb78ad',
  }) : _status = initialStatus;

  PushAuthorizationStatus _status;
  String? initialToken;
  NotificationDestination? _pendingTap;

  final _tokenController = StreamController<String>.broadcast();
  final _foregroundController =
      StreamController<PushNotificationPayload>.broadcast();
  final _tapController = StreamController<NotificationDestination>.broadcast();

  @override
  Future<PushAuthorizationStatus> getAuthorizationStatus() async => _status;

  @override
  Future<PushAuthorizationStatus> requestAuthorization() async {
    if (_status == PushAuthorizationStatus.notDetermined) {
      _status = PushAuthorizationStatus.authorized;
    }
    return _status;
  }

  void setAuthorizationStatus(PushAuthorizationStatus status) {
    _status = status;
  }

  @override
  Future<String?> getDeviceToken() async {
    if (_status == PushAuthorizationStatus.authorized) {
      return initialToken;
    }
    return null;
  }

  @override
  Stream<String> get onTokenRefresh => _tokenController.stream;

  @override
  Stream<PushNotificationPayload> get onForegroundNotification =>
      _foregroundController.stream;

  @override
  Stream<NotificationDestination> get onNotificationTap =>
      _tapController.stream;

  @override
  NotificationDestination? getPendingNotificationTap() => _pendingTap;

  @override
  void clearPendingNotificationTap() {
    _pendingTap = null;
  }

  // Helper test methods
  void emitTokenRefresh(String newToken) {
    initialToken = newToken;
    _tokenController.add(newToken);
  }

  void emitForegroundNotification(PushNotificationPayload payload) {
    _foregroundController.add(payload);
  }

  void emitNotificationTap(NotificationDestination destination) {
    _tapController.add(destination);
  }

  void setPendingNotificationTap(NotificationDestination destination) {
    _pendingTap = destination;
  }

  Future<void> dispose() async {
    await _tokenController.close();
    await _foregroundController.close();
    await _tapController.close();
  }
}
