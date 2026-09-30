import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../account/application/account_providers.dart';
import '../../planner/application/planning_providers.dart';
import '../../planner/data/planning_database.dart';
import '../data/drift_reminder_source.dart';
import '../data/notification_gateway.dart';
import '../data/notification_gateway_factory.dart';
import '../data/notification_preferences_repository.dart';
import '../domain/notification_entities.dart';

final Provider<NotificationPreferencesRepository>
    notificationPreferencesRepositoryProvider =
    Provider<NotificationPreferencesRepository>((Ref ref) {
  return NotificationPreferencesRepository(
    ref.watch(planningDatabaseProvider),
  );
});

final Provider<DriftReminderSource> reminderSourceProvider =
    Provider<DriftReminderSource>((Ref ref) {
  return DriftReminderSource(ref.watch(planningDatabaseProvider));
});

final Provider<NotificationGateway> notificationGatewayProvider =
    Provider<NotificationGateway>((Ref ref) {
  return createNotificationGateway(
    client: ref.watch(supabaseClientProvider),
  );
});

final StateNotifierProvider<NotificationController, NotificationState>
    notificationControllerProvider =
    StateNotifierProvider<NotificationController, NotificationState>(
  (Ref ref) {
    final NotificationController controller = NotificationController(
      database: ref.watch(planningDatabaseProvider),
      preferencesRepository:
          ref.watch(notificationPreferencesRepositoryProvider),
      reminderSource: ref.watch(reminderSourceProvider),
      gateway: ref.watch(notificationGatewayProvider),
    );
    unawaited(controller.initialize());
    return controller;
  },
);

final class NotificationController extends StateNotifier<NotificationState> {
  NotificationController({
    required PlanningDatabase database,
    required NotificationPreferencesRepository preferencesRepository,
    required DriftReminderSource reminderSource,
    required NotificationGateway gateway,
    Duration rebuildDelay = const Duration(milliseconds: 600),
  })  : _database = database,
        _preferencesRepository = preferencesRepository,
        _reminderSource = reminderSource,
        _gateway = gateway,
        _rebuildDelay = rebuildDelay,
        super(const NotificationState.loading());

  final PlanningDatabase _database;
  final NotificationPreferencesRepository _preferencesRepository;
  final DriftReminderSource _reminderSource;
  final NotificationGateway _gateway;
  final Duration _rebuildDelay;

  StreamSubscription<void>? _databaseSubscription;
  Timer? _rebuildTimer;
  bool _rebuilding = false;
  bool _rebuildRequested = false;
  bool _disposed = false;
  bool _exactTimingAllowed = true;
  String? _timeZoneName;

  String _readyMessage(int pending) {
    if (!_gateway.supportsBackgroundScheduling) {
      return '$pending reminders are ready while Gahunda is open. '
          'Background Web Push is not enabled in this build.';
    }
    return _exactTimingAllowed
        ? '$pending upcoming reminders are scheduled.'
        : kIsWeb
            ? '$pending reminders are queued for background Web Push. '
                'The server checks due reminders each minute.'
            : '$pending reminders are scheduled with approximate Android timing.';
  }

  Future<void> initialize() async {
    try {
      final NotificationPreferences preferences =
          await _preferencesRepository.load();
      _databaseSubscription = _database.changes.listen((_) {
        if (!state.preferences.enabled) return;
        _rebuildTimer?.cancel();
        _rebuildTimer = Timer(
          _rebuildDelay,
          () => unawaited(rebuild()),
        );
      });
      if (!preferences.enabled) {
        _set(
          NotificationState(
            phase: NotificationPhase.disabled,
            preferences: preferences,
            message: 'Enable reminders when you are ready.',
          ),
        );
        return;
      }
      _timeZoneName = await _gateway.initialize();
      _set(
        NotificationState(
          phase: NotificationPhase.ready,
          preferences: preferences,
          timeZoneName: _timeZoneName,
          message: 'Preparing your reminders…',
        ),
      );
      await rebuild();
    } on Object catch (error) {
      _setError(error);
    }
  }

  Future<void> enable() async {
    try {
      _timeZoneName = await _gateway.initialize();
      final ReminderPermissionResult permission =
          await _gateway.requestPermissions();
      if (!permission.notificationsAllowed) {
        final NotificationPreferences preferences =
            state.preferences.copyWith(enabled: false);
        await _preferencesRepository.save(preferences);
        _set(
          NotificationState(
            phase: NotificationPhase.denied,
            preferences: preferences,
            exactTimingAllowed: permission.exactTimingAllowed,
            timeZoneName: _timeZoneName,
            message:
                'Notification permission was not granted. If the prompt does not appear again, allow Gahunda in system Settings.',
          ),
        );
        return;
      }
      _exactTimingAllowed = permission.exactTimingAllowed;
      final NotificationPreferences preferences =
          state.preferences.copyWith(enabled: true);
      await _preferencesRepository.save(preferences);
      _set(
        NotificationState(
          phase: NotificationPhase.ready,
          preferences: preferences,
          exactTimingAllowed: _exactTimingAllowed,
          timeZoneName: _timeZoneName,
          message: !_gateway.supportsBackgroundScheduling
              ? 'Browser notifications are enabled. Keep Gahunda open for timed reminders.'
              : _exactTimingAllowed
                  ? 'Notifications are enabled.'
                  : kIsWeb
                      ? 'Notifications are enabled. Web reminders can arrive after Gahunda is closed.'
                      : 'Notifications are enabled, but Android may deliver them late until exact alarms are allowed.',
        ),
      );
      await rebuild();
    } on Object catch (error) {
      _setError(error);
    }
  }

  Future<void> disable() async {
    try {
      final NotificationPreferences preferences =
          state.preferences.copyWith(enabled: false);
      await _preferencesRepository.save(preferences);
      _set(
        NotificationState(
          phase: NotificationPhase.disabled,
          preferences: preferences,
          exactTimingAllowed: _exactTimingAllowed,
          timeZoneName: _timeZoneName,
          message: 'Removing pending Gahunda reminders…',
        ),
      );
      await _gateway.initialize();
      await _gateway.replaceAll(
        const <ReminderRequest>[],
        exactTiming: false,
      );
      _set(
        NotificationState(
          phase: NotificationPhase.disabled,
          preferences: preferences,
          exactTimingAllowed: _exactTimingAllowed,
          timeZoneName: _timeZoneName,
          message: 'All pending Gahunda reminders were removed.',
        ),
      );
    } on Object catch (error) {
      _setError(error);
    }
  }

  Future<void> updatePreferences(NotificationPreferences preferences) async {
    try {
      await _preferencesRepository.save(preferences);
      _set(
        NotificationState(
          phase: preferences.enabled
              ? NotificationPhase.ready
              : NotificationPhase.disabled,
          preferences: preferences,
          pendingCount: state.pendingCount,
          exactTimingAllowed: _exactTimingAllowed,
          timeZoneName: _timeZoneName,
          message: state.message,
        ),
      );
      if (preferences.enabled) {
        if (_rebuilding) _rebuildRequested = true;
        await rebuild();
      }
    } on Object catch (error) {
      _setError(error);
    }
  }

  Future<void> rebuild() async {
    if (_disposed || !state.preferences.enabled) return;
    if (_rebuilding) {
      _rebuildRequested = true;
      return;
    }
    _rebuilding = true;
    try {
      do {
        _rebuildRequested = false;
        final NotificationPreferences preferences = state.preferences;
        _timeZoneName ??= await _gateway.initialize();
        final List<ReminderRequest> requests =
            await _reminderSource.buildRequests(
          preferences: preferences,
        );
        if (!state.preferences.enabled) break;
        if (!identical(preferences, state.preferences)) {
          _rebuildRequested = true;
          continue;
        }
        await _gateway.replaceAll(
          requests,
          exactTiming: _exactTimingAllowed,
        );
        final int pending = await _gateway.pendingCount();
        _set(
          NotificationState(
            phase: NotificationPhase.ready,
            preferences: state.preferences,
            pendingCount: pending,
            exactTimingAllowed: _exactTimingAllowed,
            timeZoneName: _timeZoneName,
            message: _readyMessage(pending),
          ),
        );
      } while (_rebuildRequested && !_disposed);
    } on Object catch (error) {
      _setError(error);
    } finally {
      _rebuilding = false;
    }
  }

  Future<void> sendTestNotification() async {
    try {
      await _gateway.showTestNotification();
    } on Object catch (error) {
      _setError(error);
    }
  }

  void _set(NotificationState next) {
    if (!_disposed) state = next;
  }

  void _setError(Object error) {
    _set(
      NotificationState(
        phase: NotificationPhase.error,
        preferences: state.preferences,
        pendingCount: state.pendingCount,
        exactTimingAllowed: _exactTimingAllowed,
        timeZoneName: _timeZoneName,
        message: _friendlyError(error),
      ),
    );
  }

  @override
  void dispose() {
    _disposed = true;
    _rebuildTimer?.cancel();
    unawaited(_databaseSubscription?.cancel());
    super.dispose();
  }
}

String _friendlyError(Object error) {
  final String value = error.toString();
  if (value.contains('MissingPluginException')) {
    return 'Notification support is not installed in this platform build. Repair the platform files, then rebuild the app.';
  }
  return value.replaceFirst('Exception: ', '');
}
