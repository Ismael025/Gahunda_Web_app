import '../domain/notification_entities.dart';

abstract interface class NotificationGateway {
  /// Whether reminders continue after the application has been closed.
  bool get supportsBackgroundScheduling;

  Future<String> initialize();

  Future<ReminderPermissionResult> requestPermissions();

  Future<void> replaceAll(
    List<ReminderRequest> requests, {
    required bool exactTiming,
  });

  Future<int> pendingCount();

  Future<void> showTestNotification();
}
