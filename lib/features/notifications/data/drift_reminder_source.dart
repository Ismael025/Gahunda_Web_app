import 'package:drift/drift.dart';

import '../../planner/data/planning_database.dart';
import '../domain/notification_entities.dart';

final class DriftReminderSource {
  const DriftReminderSource(this._database);

  static const int maximumPendingReminders = 60;
  static const Duration planningHorizon = Duration(days: 30);

  final PlanningDatabase _database;

  Future<List<ReminderRequest>> buildRequests({
    required NotificationPreferences preferences,
    DateTime? now,
  }) async {
    final DateTime current = (now ?? DateTime.now()).toLocal();
    final DateTime horizon = current.add(planningHorizon);
    final List<ReminderRequest> requests = <ReminderRequest>[];

    if (preferences.taskEnabled) {
      await _addTaskReminders(requests, current, horizon);
    }
    if (preferences.classEnabled) {
      await _addClassReminders(
        requests,
        current,
        horizon,
        preferences.classLeadMinutes,
      );
    }
    if (preferences.assignmentEnabled) {
      await _addAssignmentReminders(
        requests,
        current,
        horizon,
        preferences.assignmentLeadMinutes,
      );
    }
    if (preferences.examEnabled) {
      await _addExamReminders(
        requests,
        current,
        horizon,
        preferences.examLeadMinutes,
      );
    }
    if (preferences.habitEnabled) {
      await _addHabitReminders(requests, current, horizon);
    }
    if (preferences.dailyClosureEnabled) {
      await _addClosureReminders(
        requests,
        current,
        preferences.dailyClosureMinute,
      );
    }

    requests.sort(
      (ReminderRequest left, ReminderRequest right) =>
          left.scheduledAtUtc.compareTo(right.scheduledAtUtc),
    );
    return requests.take(maximumPendingReminders).toList(growable: false);
  }

  Future<void> _addTaskReminders(
    List<ReminderRequest> target,
    DateTime now,
    DateTime horizon,
  ) async {
    final List<QueryRow> rows = await _database.readRows('''
      SELECT t.id, t.title,
             COALESCE(b.starts_at_utc, t.scheduled_at_utc) AS starts_at_utc
      FROM planning_tasks t
      LEFT JOIN time_blocks b ON b.task_id = t.id
      WHERE t.deleted_at_utc IS NULL
        AND t.status IN ('pending', 'inProgress')
        AND COALESCE(b.starts_at_utc, t.scheduled_at_utc) IS NOT NULL
    ''');
    for (final QueryRow row in rows) {
      final DateTime startsAt =
          DateTime.parse(row.read<String>('starts_at_utc')).toLocal();
      final DateTime reminderAt = startsAt.subtract(
        const Duration(minutes: NotificationPreferences.taskLeadMinutes),
      );
      if (!_isFutureReminder(reminderAt, startsAt, now, horizon)) continue;
      final String id = row.read<String>('id');
      final String key = 'task:$id';
      target.add(
        ReminderRequest(
          id: stableNotificationId(key),
          kind: ReminderKind.task,
          sourceKey: key,
          title: 'Task in 5 minutes',
          body: '${row.read<String>('title')} • ${_clock(startsAt)}',
          scheduledAtUtc: reminderAt.toUtc(),
          payload: key,
        ),
      );
    }
  }

  Future<void> _addClassReminders(
    List<ReminderRequest> target,
    DateTime now,
    DateTime horizon,
    int leadMinutes,
  ) async {
    final List<QueryRow> rows = await _database.readRows('''
      SELECT c.id, c.weekday, c.starts_at_minute, c.room,
             s.name AS subject_name,
             t.starts_on_local, t.ends_on_local
      FROM class_sessions c
      JOIN subjects s ON s.id = c.subject_id
      JOIN academic_terms t ON t.id = s.term_id
      WHERE t.is_active = 1
    ''');
    for (final QueryRow row in rows) {
      final DateTime termStart =
          _date(DateTime.parse(row.read<String>('starts_on_local')));
      final DateTime termEnd =
          _date(DateTime.parse(row.read<String>('ends_on_local')));
      final int weekday = row.read<int>('weekday');
      final int minute = row.read<int>('starts_at_minute');
      for (DateTime day = _date(now);
          !day.isAfter(_date(horizon));
          day = day.add(const Duration(days: 1))) {
        if (day.weekday != weekday ||
            day.isBefore(termStart) ||
            day.isAfter(termEnd)) {
          continue;
        }
        final DateTime startsAt = _atMinute(day, minute);
        final DateTime reminderAt =
            startsAt.subtract(Duration(minutes: leadMinutes));
        if (!_isFutureReminder(reminderAt, startsAt, now, horizon)) continue;
        final String occurrence = _dayKey(day);
        final String id = row.read<String>('id');
        final String key = 'class:$id:$occurrence';
        final String? room = row.readNullable<String>('room');
        target.add(
          ReminderRequest(
            id: stableNotificationId(key),
            kind: ReminderKind.classSession,
            sourceKey: key,
            title: 'Class in ${_leadLabel(leadMinutes)}',
            body: '${row.read<String>('subject_name')} • ${_clock(startsAt)}'
                '${room == null || room.trim().isEmpty ? '' : ' • $room'}',
            scheduledAtUtc: reminderAt.toUtc(),
            payload: key,
          ),
        );
      }
    }
  }

  Future<void> _addAssignmentReminders(
    List<ReminderRequest> target,
    DateTime now,
    DateTime horizon,
    int leadMinutes,
  ) async {
    final List<QueryRow> rows = await _database.readRows('''
      SELECT a.id, a.due_at_utc, p.title, s.name AS subject_name
      FROM school_assignments a
      JOIN planning_tasks p ON p.id = a.task_id
      JOIN subjects s ON s.id = a.subject_id
      WHERE p.deleted_at_utc IS NULL
        AND p.status IN ('pending', 'inProgress')
    ''');
    for (final QueryRow row in rows) {
      final DateTime dueAt =
          DateTime.parse(row.read<String>('due_at_utc')).toLocal();
      final DateTime reminderAt =
          dueAt.subtract(Duration(minutes: leadMinutes));
      if (!_isFutureReminder(reminderAt, dueAt, now, horizon)) continue;
      final String id = row.read<String>('id');
      final String key = 'assignment:$id';
      target.add(
        ReminderRequest(
          id: stableNotificationId(key),
          kind: ReminderKind.assignment,
          sourceKey: key,
          title: 'Assignment due ${_leadLabel(leadMinutes)}',
          body: '${row.read<String>('title')} • '
              '${row.read<String>('subject_name')}',
          scheduledAtUtc: reminderAt.toUtc(),
          payload: key,
        ),
      );
    }
  }

  Future<void> _addExamReminders(
    List<ReminderRequest> target,
    DateTime now,
    DateTime horizon,
    int leadMinutes,
  ) async {
    final List<QueryRow> rows = await _database.readRows('''
      SELECT e.id, e.title, e.starts_at_utc, e.room,
             s.name AS subject_name
      FROM exams e
      JOIN subjects s ON s.id = e.subject_id
      JOIN academic_terms t ON t.id = s.term_id
      WHERE t.is_active = 1
    ''');
    for (final QueryRow row in rows) {
      final DateTime startsAt =
          DateTime.parse(row.read<String>('starts_at_utc')).toLocal();
      final DateTime reminderAt =
          startsAt.subtract(Duration(minutes: leadMinutes));
      if (!_isFutureReminder(reminderAt, startsAt, now, horizon)) continue;
      final String id = row.read<String>('id');
      final String key = 'exam:$id';
      final String? room = row.readNullable<String>('room');
      target.add(
        ReminderRequest(
          id: stableNotificationId(key),
          kind: ReminderKind.exam,
          sourceKey: key,
          title: 'Exam in ${_leadLabel(leadMinutes)}',
          body: '${row.read<String>('title')} • '
              '${row.read<String>('subject_name')}'
              '${room == null || room.trim().isEmpty ? '' : ' • $room'}',
          scheduledAtUtc: reminderAt.toUtc(),
          payload: key,
        ),
      );
    }
  }

  Future<void> _addHabitReminders(
    List<ReminderRequest> target,
    DateTime now,
    DateTime horizon,
  ) async {
    final List<QueryRow> rows = await _database.readRows('''
      SELECT id, name, direction, target_value, weekdays_mask,
             preferred_time_minute, starts_on_local, ends_on_local
      FROM habits
      WHERE is_archived = 0 AND preferred_time_minute IS NOT NULL
    ''');
    final List<QueryRow> checkInRows = await _database.readRows('''
      SELECT habit_id, local_day, value FROM habit_check_ins
    ''');
    final Map<String, int> checkIns = <String, int>{
      for (final QueryRow row in checkInRows)
        '${row.read<String>('habit_id')}:${row.read<String>('local_day')}':
            row.read<int>('value'),
    };
    for (final QueryRow row in rows) {
      final DateTime startsOn =
          _date(DateTime.parse(row.read<String>('starts_on_local')));
      final String? rawEnd = row.readNullable<String>('ends_on_local');
      final DateTime? endsOn =
          rawEnd == null ? null : _date(DateTime.parse(rawEnd));
      final int mask = row.read<int>('weekdays_mask');
      final int minute = row.read<int>('preferred_time_minute');
      for (DateTime day = _date(now);
          !day.isAfter(_date(horizon));
          day = day.add(const Duration(days: 1))) {
        final int weekdayBit = 1 << (day.weekday - DateTime.monday);
        if ((mask & weekdayBit) == 0 ||
            day.isBefore(startsOn) ||
            (endsOn != null && day.isAfter(endsOn))) {
          continue;
        }
        final DateTime reminderAt = _atMinute(day, minute);
        if (!reminderAt.isAfter(now) || reminderAt.isAfter(horizon)) continue;
        final String id = row.read<String>('id');
        final String dayKey = _dayKey(day);
        final int? recordedValue = checkIns['$id:$dayKey'];
        if (recordedValue != null) {
          final int targetValue = row.read<int>('target_value');
          final bool successful = row.read<String>('direction') == 'build'
              ? recordedValue >= targetValue
              : recordedValue <= targetValue;
          if (successful) continue;
        }
        final String key = 'habit:$id:$dayKey';
        target.add(
          ReminderRequest(
            id: stableNotificationId(key),
            kind: ReminderKind.habit,
            sourceKey: key,
            title: 'Habit reminder',
            body: row.read<String>('name'),
            scheduledAtUtc: reminderAt.toUtc(),
            payload: key,
          ),
        );
      }
    }
  }

  Future<void> _addClosureReminders(
    List<ReminderRequest> target,
    DateTime now,
    int minute,
  ) async {
    final List<QueryRow> rows = await _database.readRows(
      'SELECT local_day FROM daily_closures',
    );
    final Set<String> closedDays = rows
        .map<String>((QueryRow row) => row.read<String>('local_day'))
        .toSet();
    for (int offset = 0; offset < 7; offset += 1) {
      final DateTime day = _date(now).add(Duration(days: offset));
      final String dayKey = _dayKey(day);
      if (closedDays.contains(dayKey)) continue;
      final DateTime reminderAt = _atMinute(day, minute);
      if (!reminderAt.isAfter(now)) continue;
      final String key = 'closure:$dayKey';
      target.add(
        ReminderRequest(
          id: stableNotificationId(key),
          kind: ReminderKind.dailyClosure,
          sourceKey: key,
          title: 'Close your day',
          body: 'Capture your win, lesson, and tomorrow focus.',
          scheduledAtUtc: reminderAt.toUtc(),
          payload: key,
        ),
      );
    }
  }
}

bool _isFutureReminder(
  DateTime reminderAt,
  DateTime eventAt,
  DateTime now,
  DateTime horizon,
) {
  return reminderAt.isAfter(now) &&
      eventAt.isAfter(now) &&
      eventAt.isBefore(horizon);
}

DateTime _date(DateTime value) => DateTime(value.year, value.month, value.day);

DateTime _atMinute(DateTime day, int minute) => DateTime(
      day.year,
      day.month,
      day.day,
      minute ~/ 60,
      minute % 60,
    );

String _clock(DateTime value) => '${value.hour.toString().padLeft(2, '0')}:'
    '${value.minute.toString().padLeft(2, '0')}';

String _dayKey(DateTime value) => '${value.year.toString().padLeft(4, '0')}-'
    '${value.month.toString().padLeft(2, '0')}-'
    '${value.day.toString().padLeft(2, '0')}';

String _leadLabel(int minutes) {
  if (minutes == 0) return 'now';
  if (minutes % 1440 == 0) {
    final int days = minutes ~/ 1440;
    return '$days ${days == 1 ? 'day' : 'days'}';
  }
  if (minutes % 60 == 0) {
    final int hours = minutes ~/ 60;
    return '$hours ${hours == 1 ? 'hour' : 'hours'}';
  }
  return '$minutes ${minutes == 1 ? 'minute' : 'minutes'}';
}
