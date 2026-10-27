import 'dart:async';

/// Normalized platform lifecycle states independent of UI framework.
enum AppLifecycleStatus {
  resumed,
  inactive,
  paused,
  detached,
  hidden,
}

/// Coordinates app lifecycle changes, managing foreground polling and triggering catch-up evaluations upon resume.
class AppLifecycleCoordinator {
  AppLifecycleCoordinator({
    this.onAppResumed,
    this.onAppBackgrounded,
  });

  final FutureOr<void> Function()? onAppResumed;
  final FutureOr<void> Function()? onAppBackgrounded;

  bool _isForeground = true;
  bool get isForeground => _isForeground;

  /// Explicitly processes lifecycle state changes.
  Future<void> handleLifecycleChange(AppLifecycleStatus state) async {
    switch (state) {
      case AppLifecycleStatus.resumed:
        _isForeground = true;
        if (onAppResumed != null) {
          await onAppResumed!();
        }
        break;
      case AppLifecycleStatus.inactive:
      case AppLifecycleStatus.paused:
      case AppLifecycleStatus.detached:
      case AppLifecycleStatus.hidden:
        _isForeground = false;
        if (onAppBackgrounded != null) {
          await onAppBackgrounded!();
        }
        break;
    }
  }

  void dispose() {}
}
