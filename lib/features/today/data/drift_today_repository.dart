import 'dart:math';

import 'package:drift/drift.dart';

import '../../planner/data/planning_database.dart';
import '../../planner/domain/planning_entities.dart';
import '../domain/today_entities.dart';
import '../domain/today_repository.dart';

typedef TodayUtcClock = DateTime Function();
typedef TodayIdFactory = String Function(String prefix);

final class DriftTodayRepository implements TodayRepository {
  DriftTodayRepository(
    this._database, {
    TodayUtcClock? clock,
    TodayIdFactory? idFactory,
  })  : _clock = clock ?? DateTime.now,
        _idFactory = idFactory;

  final PlanningDatabase _database;
  final TodayUtcClock _clock;
  final TodayIdFactory? _idFactory;
  final Random _random = Random.secure();
  int _idCounter = 0;

  @override
  Stream<DailyClosure?> watchClosureForLocalDay(DateTime localDay) {
    return _database.watchQuery(
      () => getClosureForLocalDay(localDay),
    );
  }

  @override
  Future<DailyClosure?> getClosureForLocalDay(DateTime localDay) async {
    final List<QueryRow> rows = await _database.readRows(
      'SELECT * FROM daily_closures WHERE local_day = ?',
      variables: _strings(<String>[_dayKey(localDay)]),
    );
    return rows.isEmpty ? null : _closureFromRow(rows.single);
  }

  @override
  Future<DailyClosure> closeDay(DailyClosureDraft draft) async {
    if (draft.mood < 1 || draft.mood > 5) {
      throw ArgumentError.value(
        draft.mood,
        'mood',
        'Mood must be from 1 to 5.',
      );
    }

    final DateTime now = _clock().toUtc();
    final String dayKey = _dayKey(draft.localDay);
    final List<_ScheduledSnapshot> snapshots = await _scheduledSnapshots(
      draft.localDay,
    );
    final Map<String, _ScheduledSnapshot> unfinished =
        <String, _ScheduledSnapshot>{
      for (final _ScheduledSnapshot snapshot in snapshots)
        if (!snapshot.isFinished) snapshot.id: snapshot,
    };

    if (!unfinished.keys.every(draft.taskResolutions.containsKey)) {
      throw ArgumentError(
        'Every unfinished task needs an explicit end-of-day decision.',
        'taskResolutions',
      );
    }
    for (final String taskId in draft.taskResolutions.keys) {
      if (!unfinished.containsKey(taskId)) {
        throw ArgumentError.value(
          taskId,
          'taskResolutions',
          'The task is not an unfinished task scheduled for this day.',
        );
      }
    }

    int completedCount = 0;
    int plannedMinutes = 0;
    int completedMinutes = 0;
    for (final _ScheduledSnapshot snapshot in snapshots) {
      plannedMinutes += snapshot.duration.inMinutes;
      if (snapshot.status == PlanningTaskStatus.completed) {
        completedCount += 1;
        completedMinutes += snapshot.duration.inMinutes;
      }
    }

    await _database.transaction(() async {
      for (final MapEntry<String, DayTaskResolution> entry
          in draft.taskResolutions.entries) {
        final _ScheduledSnapshot snapshot = unfinished[entry.key]!;
        switch (entry.value) {
          case DayTaskResolution.keepOpen:
            break;
          case DayTaskResolution.moveToTomorrow:
            await _moveToTomorrow(snapshot, draft.localDay, now);
            break;
          case DayTaskResolution.skip:
            await _setStatus(snapshot.id, PlanningTaskStatus.skipped, now);
            break;
          case DayTaskResolution.cancel:
            await _setStatus(snapshot.id, PlanningTaskStatus.cancelled, now);
            break;
        }
      }

      await _database.insertRow('''
        INSERT INTO daily_closures (
          id, local_day, mood, win, lesson, tomorrow_focus,
          scheduled_task_count, completed_task_count, planned_minutes,
          completed_minutes, closed_at_utc, created_at_utc, updated_at_utc
        ) VALUES (
          ?, ?, ?, NULLIF(?, ''), NULLIF(?, ''), NULLIF(?, ''),
          ?, ?, ?, ?, ?, ?, ?
        )
        ON CONFLICT(local_day) DO UPDATE SET
          mood = excluded.mood,
          win = excluded.win,
          lesson = excluded.lesson,
          tomorrow_focus = excluded.tomorrow_focus,
          scheduled_task_count = excluded.scheduled_task_count,
          completed_task_count = excluded.completed_task_count,
          planned_minutes = excluded.planned_minutes,
          completed_minutes = excluded.completed_minutes,
          closed_at_utc = excluded.closed_at_utc,
          updated_at_utc = excluded.updated_at_utc
      ''', variables: <Variable<Object>>[
        Variable<String>(_newId('closure')),
        Variable<String>(dayKey),
        Variable<int>(draft.mood),
        Variable<String>(_optionalText(draft.win)),
        Variable<String>(_optionalText(draft.lesson)),
        Variable<String>(_optionalText(draft.tomorrowFocus)),
        Variable<int>(snapshots.length),
        Variable<int>(completedCount),
        Variable<int>(plannedMinutes),
        Variable<int>(completedMinutes),
        Variable<String>(_utc(now)),
        Variable<String>(_utc(now)),
        Variable<String>(_utc(now)),
      ]);
    });

    _database.notifyChanged();
    return (await getClosureForLocalDay(draft.localDay))!;
  }

  Future<List<_ScheduledSnapshot>> _scheduledSnapshots(
    DateTime localDay,
  ) async {
    final DateTime localStart = DateTime(
      localDay.year,
      localDay.month,
      localDay.day,
    );
    final DateTime localEnd = DateTime(
      localDay.year,
      localDay.month,
      localDay.day + 1,
    );
    final List<QueryRow> rows = await _database.readRows('''
      SELECT
        t.id,
        t.status,
        COALESCE(b.starts_at_utc, t.scheduled_at_utc) AS effective_start,
        COALESCE(b.ends_at_utc, t.due_at_utc) AS effective_end
      FROM planning_tasks t
      LEFT JOIN time_blocks b ON b.task_id = t.id
      LEFT JOIN goals g ON g.id = t.goal_id
      WHERE t.deleted_at_utc IS NULL
        AND (t.goal_id IS NULL OR g.status != 'archived')
        AND COALESCE(b.starts_at_utc, t.scheduled_at_utc) >= ?
        AND COALESCE(b.starts_at_utc, t.scheduled_at_utc) < ?
      ORDER BY effective_start ASC
    ''',
        variables: _strings(<String>[
          _utc(localStart.toUtc()),
          _utc(localEnd.toUtc()),
        ]));

    return rows.map((QueryRow row) {
      final DateTime start = DateTime.parse(
        row.read<String>('effective_start'),
      );
      final String? endValue = row.readNullable<String>('effective_end');
      final DateTime? end = endValue == null ? null : DateTime.parse(endValue);
      return _ScheduledSnapshot(
        id: row.read<String>('id'),
        status: PlanningTaskStatus.values.byName(row.read<String>('status')),
        startsAtUtc: start,
        endsAtUtc: end,
      );
    }).toList(growable: false);
  }

  Future<void> _moveToTomorrow(
    _ScheduledSnapshot snapshot,
    DateTime localDay,
    DateTime now,
  ) async {
    final DateTime originalLocal = snapshot.startsAtUtc.toLocal();
    final DateTime nextLocal = DateTime(
      localDay.year,
      localDay.month,
      localDay.day + 1,
      originalLocal.hour,
      originalLocal.minute,
    );
    final DateTime nextStart = nextLocal.toUtc();
    final Duration duration = snapshot.duration > Duration.zero
        ? snapshot.duration
        : const Duration(hours: 1);
    final DateTime nextEnd = nextStart.add(duration);

    await _database.updateRows('''
      UPDATE planning_tasks
      SET scheduled_at_utc = ?, due_at_utc = ?, status = 'pending',
          completed_at_utc = NULL, updated_at_utc = ?
      WHERE id = ? AND deleted_at_utc IS NULL
    ''',
        variables: _strings(<String>[
          _utc(nextStart),
          _utc(nextEnd),
          _utc(now),
          snapshot.id,
        ]));
    await _database.updateRows('''
      UPDATE time_blocks
      SET starts_at_utc = ?, ends_at_utc = ?, updated_at_utc = ?
      WHERE task_id = ?
    ''',
        variables: _strings(<String>[
          _utc(nextStart),
          _utc(nextEnd),
          _utc(now),
          snapshot.id,
        ]));
  }

  Future<void> _setStatus(
    String taskId,
    PlanningTaskStatus status,
    DateTime now,
  ) async {
    await _database.updateRows('''
      UPDATE planning_tasks
      SET status = ?, completed_at_utc = NULL, updated_at_utc = ?
      WHERE id = ? AND deleted_at_utc IS NULL
    ''', variables: _strings(<String>[status.name, _utc(now), taskId]));
  }

  DailyClosure _closureFromRow(QueryRow row) {
    return DailyClosure(
      id: row.read<String>('id'),
      localDay: _localDayFromKey(row.read<String>('local_day')),
      mood: row.read<int>('mood'),
      win: row.readNullable<String>('win'),
      lesson: row.readNullable<String>('lesson'),
      tomorrowFocus: row.readNullable<String>('tomorrow_focus'),
      scheduledTaskCount: row.read<int>('scheduled_task_count'),
      completedTaskCount: row.read<int>('completed_task_count'),
      plannedMinutes: row.read<int>('planned_minutes'),
      completedMinutes: row.read<int>('completed_minutes'),
      closedAtUtc: DateTime.parse(row.read<String>('closed_at_utc')).toUtc(),
      createdAtUtc: DateTime.parse(row.read<String>('created_at_utc')).toUtc(),
      updatedAtUtc: DateTime.parse(row.read<String>('updated_at_utc')).toUtc(),
    );
  }

  String _newId(String prefix) {
    final TodayIdFactory? factory = _idFactory;
    if (factory != null) return factory(prefix);
    _idCounter += 1;
    final String time =
        _clock().toUtc().microsecondsSinceEpoch.toRadixString(36);
    final String random = _random.nextInt(0x7fffffff).toRadixString(36);
    return '$prefix-$time-$random-$_idCounter';
  }
}

class _ScheduledSnapshot {
  const _ScheduledSnapshot({
    required this.id,
    required this.status,
    required this.startsAtUtc,
    required this.endsAtUtc,
  });

  final String id;
  final PlanningTaskStatus status;
  final DateTime startsAtUtc;
  final DateTime? endsAtUtc;

  bool get isFinished =>
      status == PlanningTaskStatus.completed ||
      status == PlanningTaskStatus.skipped ||
      status == PlanningTaskStatus.cancelled;

  Duration get duration {
    final DateTime? end = endsAtUtc;
    if (end == null || !end.isAfter(startsAtUtc)) return Duration.zero;
    return end.difference(startsAtUtc);
  }
}

String _dayKey(DateTime value) {
  final String month = value.month.toString().padLeft(2, '0');
  final String day = value.day.toString().padLeft(2, '0');
  return '${value.year}-$month-$day';
}

DateTime _localDayFromKey(String value) {
  final List<int> parts = value.split('-').map(int.parse).toList();
  return DateTime(parts[0], parts[1], parts[2]);
}

String _optionalText(String? value) => value?.trim() ?? '';

String _utc(DateTime value) => value.toUtc().toIso8601String();

List<Variable<Object>> _strings(List<String> values) {
  return values
      .map<Variable<Object>>((String value) => Variable<String>(value))
      .toList(growable: false);
}
