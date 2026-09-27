import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import '../domain/notification_entities.dart';
import 'notification_gateway.dart';

final class LocalNotificationGateway implements NotificationGateway {
  LocalNotificationGateway({FlutterLocalNotificationsPlugin? plugin})
      : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  static const NotificationDetails _details = NotificationDetails(
    android: AndroidNotificationDetails(
      'gahunda_reminders',
      'Gahunda reminders',
      channelDescription: 'Tasks, school, habits, and daily review reminders.',
      importance: Importance.high,
      priority: Priority.high,
    ),
    iOS: DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
      threadIdentifier: 'gahunda_reminders',
    ),
    macOS: DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
      threadIdentifier: 'gahunda_reminders',
    ),
    windows: WindowsNotificationDetails(),
  );

  final FlutterLocalNotificationsPlugin _plugin;
  bool _initialized = false;
  String _timeZoneName = 'UTC';

  @override
  bool get supportsBackgroundScheduling => true;

  @override
  Future<String> initialize() async {
    if (_initialized) return _timeZoneName;
    tz_data.initializeTimeZones();
    try {
      final dynamic zone = await FlutterTimezone.getLocalTimezone();
      final String identifier = zone.identifier as String;
      tz.setLocalLocation(tz.getLocation(identifier));
      _timeZoneName = identifier;
    } on Object {
      tz.setLocalLocation(tz.getLocation('UTC'));
      _timeZoneName = 'UTC (device timezone unavailable)';
    }

    const AndroidInitializationSettings android =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const DarwinInitializationSettings apple = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    const WindowsInitializationSettings windows = WindowsInitializationSettings(
      appName: 'Gahunda',
      appUserModelId: 'Gahunda.PersonalCompanion',
      guid: 'd7bb4a67-a537-4a70-97d7-2433cfc64211',
    );
    const InitializationSettings settings = InitializationSettings(
      android: android,
      iOS: apple,
      macOS: apple,
      windows: windows,
    );
    await _plugin.initialize(
      settings,
      onDidReceiveNotificationResponse: (NotificationResponse _) {},
    );
    _initialized = true;
    return _timeZoneName;
  }

  @override
  Future<ReminderPermissionResult> requestPermissions() async {
    await initialize();
    bool notificationsAllowed = true;
    bool exactTimingAllowed = true;

    final AndroidFlutterLocalNotificationsPlugin? android =
        _plugin.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    if (android != null) {
      notificationsAllowed =
          await android.requestNotificationsPermission() ?? true;
      exactTimingAllowed = await android.requestExactAlarmsPermission() ?? true;
    }

    final IOSFlutterLocalNotificationsPlugin? ios =
        _plugin.resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin>();
    if (ios != null) {
      notificationsAllowed = await ios.requestPermissions(
            alert: true,
            badge: true,
            sound: true,
          ) ??
          false;
    }

    final MacOSFlutterLocalNotificationsPlugin? macos =
        _plugin.resolvePlatformSpecificImplementation<
            MacOSFlutterLocalNotificationsPlugin>();
    if (macos != null) {
      notificationsAllowed = await macos.requestPermissions(
            alert: true,
            badge: true,
            sound: true,
          ) ??
          false;
    }

    return ReminderPermissionResult(
      notificationsAllowed: notificationsAllowed,
      exactTimingAllowed: exactTimingAllowed,
    );
  }

  @override
  Future<void> replaceAll(
    List<ReminderRequest> requests, {
    required bool exactTiming,
  }) async {
    await initialize();
    await _plugin.cancelAll();
    final AndroidScheduleMode scheduleMode = exactTiming
        ? AndroidScheduleMode.exactAllowWhileIdle
        : AndroidScheduleMode.inexactAllowWhileIdle;
    for (final ReminderRequest request in requests) {
      await _plugin.zonedSchedule(
        request.id,
        request.title,
        request.body,
        tz.TZDateTime.from(request.scheduledAtUtc, tz.local),
        _details,
        androidScheduleMode: scheduleMode,
        payload: request.payload,
      );
    }
  }

  @override
  Future<int> pendingCount() async {
    await initialize();
    return (await _plugin.pendingNotificationRequests()).length;
  }

  @override
  Future<void> showTestNotification() async {
    await initialize();
    await _plugin.show(
      2147483646,
      'Gahunda reminders are ready',
      'Your scheduled task reminders will arrive five minutes early.',
      _details,
      payload: 'test',
    );
  }
}
