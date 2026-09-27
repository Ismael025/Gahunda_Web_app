// ignore_for_file: deprecated_member_use

import 'dart:async';
import 'dart:html' as html;

import '../domain/notification_entities.dart';
import 'notification_gateway.dart';

/// Browser notification delivery for the installable Gahunda web app.
///
/// Browsers do not expose a local scheduled-notification API. Timers therefore
/// deliver reminders while this page/PWA is running. Background delivery is a
/// separate Web Push concern and is deliberately reported as unsupported.
final class WebNotificationGateway implements NotificationGateway {
  static const Duration _maximumTimerDelay = Duration(hours: 12);

  final Map<int, Timer> _timers = <int, Timer>{};
  final Map<int, ReminderRequest> _pending = <int, ReminderRequest>{};

  @override
  bool get supportsBackgroundScheduling => false;

  @override
  Future<String> initialize() async {
    if (!html.Notification.supported) {
      throw UnsupportedError(
        'This browser does not support notifications. You can still use all '
        'planning and synchronization features.',
      );
    }
    final DateTime now = DateTime.now();
    final String zone = now.timeZoneName.trim();
    return zone.isEmpty ? 'Browser local time' : zone;
  }

  @override
  Future<ReminderPermissionResult> requestPermissions() async {
    await initialize();
    final String permission = html.Notification.permission == 'granted'
        ? 'granted'
        : await html.Notification.requestPermission();
    return ReminderPermissionResult(
      notificationsAllowed: permission == 'granted',
      exactTimingAllowed: false,
    );
  }

  @override
  Future<void> replaceAll(
    List<ReminderRequest> requests, {
    required bool exactTiming,
  }) async {
    await initialize();
    _cancelAll();
    final DateTime now = DateTime.now().toUtc();
    for (final ReminderRequest request in requests) {
      if (!request.scheduledAtUtc.isAfter(now)) continue;
      _pending[request.id] = request;
      _schedule(request.id);
    }
  }

  @override
  Future<int> pendingCount() async => _pending.length;

  @override
  Future<void> showTestNotification() async {
    await initialize();
    if (html.Notification.permission != 'granted') {
      throw StateError('Enable browser notification permission first.');
    }
    await _show(
      title: 'Gahunda reminders are ready',
      body: 'Web reminders will arrive while Gahunda is open.',
      tag: 'gahunda-test',
    );
  }

  void _schedule(int id) {
    final ReminderRequest? request = _pending[id];
    if (request == null) return;
    final Duration remaining =
        request.scheduledAtUtc.difference(DateTime.now().toUtc());
    if (remaining <= Duration.zero) {
      _timers.remove(id);
      _pending.remove(id);
      if (html.Notification.permission == 'granted') {
        unawaited(
          _show(
            title: request.title,
            body: request.body,
            tag: request.sourceKey,
          ),
        );
      }
      return;
    }
    final Duration delay =
        remaining > _maximumTimerDelay ? _maximumTimerDelay : remaining;
    _timers[id] = Timer(delay, () => _schedule(id));
  }

  Future<void> _show({
    required String title,
    required String body,
    required String tag,
  }) async {
    try {
      final dynamic serviceWorkers = html.window.navigator.serviceWorker;
      if (serviceWorkers != null) {
        final dynamic registration = await serviceWorkers.getRegistration();
        if (registration != null) {
          await registration.showNotification(
            title,
            <String, Object?>{
              'body': body,
              'tag': tag,
              'icon': 'icons/Icon-192.png',
              'badge': 'icons/Icon-192.png',
            },
          );
          return;
        }
      }
    } on Object {
      // The desktop Notification constructor below remains a safe fallback.
    }
    html.Notification(title, body: body, tag: tag);
  }

  void _cancelAll() {
    for (final Timer timer in _timers.values) {
      timer.cancel();
    }
    _timers.clear();
    _pending.clear();
  }
}
