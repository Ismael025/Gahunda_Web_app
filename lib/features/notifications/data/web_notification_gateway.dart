// ignore_for_file: deprecated_member_use

import 'dart:async';
import 'dart:convert';
import 'dart:html' as html;
import 'dart:js_interop';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/notification_entities.dart';
import 'notification_gateway.dart';

@JS('gahundaSubscribeForPush')
external JSPromise<JSString> _subscribeForPush(JSString vapidPublicKey);

@JS('gahundaUnsubscribeFromPush')
external JSPromise<JSBoolean> _unsubscribeFromPush();

/// Web notification delivery with an in-page fallback and Supabase Web Push.
///
/// JavaScript timers cover an open browser tab. The remote queue and service
/// worker cover an installed PWA after the page has been suspended or closed.
final class WebNotificationGateway implements NotificationGateway {
  WebNotificationGateway({required SupabaseClient? client}) : _client = client;

  static const Duration _maximumTimerDelay = Duration(hours: 12);
  static const String _vapidPublicKey =
      String.fromEnvironment('WEB_PUSH_VAPID_PUBLIC_KEY');

  final SupabaseClient? _client;
  final Map<int, Timer> _timers = <int, Timer>{};
  final Map<int, ReminderRequest> _pending = <int, ReminderRequest>{};
  StreamSubscription<AuthState>? _authSubscription;

  @override
  bool get supportsBackgroundScheduling =>
      _client?.auth.currentUser != null && _vapidPublicKey.trim().isNotEmpty;

  @override
  Future<String> initialize() async {
    if (!html.Notification.supported) {
      throw UnsupportedError(
        'This browser does not support notifications. You can still use all '
        'planning and synchronization features.',
      );
    }
    _authSubscription ??= _client?.auth.onAuthStateChange.listen(
      (AuthState state) => unawaited(_handleAuthState(state)),
    );
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
    if (permission == 'granted' && _client?.auth.currentUser != null) {
      await _registerPushSubscription();
    }
    return ReminderPermissionResult(
      notificationsAllowed: permission == 'granted',
      // Supabase Cron checks the queue once per minute.
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
    await _replaceRemoteQueue(_pending.values.toList(growable: false));
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
      body: supportsBackgroundScheduling
          ? 'Background Web Push is connected to this device.'
          : 'Sign in and rebuild with the Web Push key to enable background delivery.',
      tag: 'gahunda-test',
    );
  }

  Future<void> _registerPushSubscription() async {
    final SupabaseClient? client = _client;
    if (client == null || client.auth.currentUser == null) return;
    if (_vapidPublicKey.trim().isEmpty) {
      throw StateError(
        'WEB_PUSH_VAPID_PUBLIC_KEY is missing from this web build.',
      );
    }
    final JSString response =
        await _subscribeForPush(_vapidPublicKey.toJS).toDart;
    final String raw = response.toDart;
    final Object? decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic>) {
      throw StateError('The browser returned an invalid push subscription.');
    }
    await client.rpc<void>(
      'upsert_gahunda_push_subscription',
      params: <String, Object?>{
        'p_device_id': decoded['device_id'],
        'p_endpoint': decoded['endpoint'],
        'p_p256dh': decoded['p256dh'],
        'p_auth_key': decoded['auth'],
        'p_user_agent': html.window.navigator.userAgent,
      },
    );
  }

  Future<void> _handleAuthState(AuthState state) async {
    try {
      if (state.event == AuthChangeEvent.signedOut) {
        await _unsubscribeFromPush().toDart;
        return;
      }
      if (state.event == AuthChangeEvent.signedIn &&
          html.Notification.permission == 'granted') {
        await _registerPushSubscription();
        if (_pending.isNotEmpty) {
          await _replaceRemoteQueue(_pending.values.toList(growable: false));
        }
      }
    } on Object {
      // A later manual rebuild retries registration and queue synchronization.
    }
  }

  Future<void> _replaceRemoteQueue(List<ReminderRequest> requests) async {
    final SupabaseClient? client = _client;
    if (client == null || client.auth.currentUser == null) return;
    if (html.Notification.permission == 'granted') {
      await _registerPushSubscription();
    }
    if (!supportsBackgroundScheduling) return;
    await client.rpc<void>(
      'replace_gahunda_push_reminders',
      params: <String, Object?>{
        'p_reminders': requests
            .map<Map<String, Object?>>(
              (ReminderRequest request) => <String, Object?>{
                'source_key': request.sourceKey,
                'title': request.title,
                'body': request.body,
                'scheduled_at_utc':
                    request.scheduledAtUtc.toUtc().toIso8601String(),
                'target_url': './',
              },
            )
            .toList(growable: false),
      },
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
