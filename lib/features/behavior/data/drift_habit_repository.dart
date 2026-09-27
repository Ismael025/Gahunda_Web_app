import 'dart:math';

import 'package:drift/drift.dart';

import '../../planner/data/planning_database.dart';
import '../domain/habit_entities.dart';
import '../domain/habit_repository.dart';

typedef HabitUtcClock = DateTime Function();
typedef HabitIdFactory = String Function(String prefix);

final class DriftHabitRepository implements HabitRepository {
  DriftHabitRepository(
    this._database, {
    HabitUtcClock? clock,
    HabitIdFactory? idFactory,
  })  : _clock = clock ?? DateTime.now,
        _idFactory = idFactory;

  final PlanningDatabase _database;
  final HabitUtcClock _clock;
  final HabitIdFactory? _idFactory;
  final Random _random = Random.secure();
  int _idCounter = 0;

  @override
  Stream<HabitDashboard> watchDashboard(DateTime localDay) {
    return _database.watchQuery(() => getDashboard(localDay));
  }

  @override
  Future<HabitDashboard> getDashboard(DateTime localDay) async {
    final DateTime selectedDay = dateOnly(localDay);
    final DateTime today = dateOnly(_clock().toLocal());
    final DateTime weekStart = startOfHabitWeek(selectedDay);
    final List<Habit> habits = (await _database.readRows('''
      SELECT * FROM habits
      WHERE is_archived = 0
      ORDER BY preferred_time_minute IS NULL,
               preferred_time_minute ASC,
               created_at_utc ASC
    ''')).map(_habitFromRow).toList(growable: false);
    final List<HabitCheckIn> checkIns = (await _database.readRows('''
      SELECT ci.*
      FROM habit_check_ins ci
      JOIN habits h ON h.id = ci.habit_id
      WHERE h.is_archived = 0
      ORDER BY ci.local_day ASC
    ''')).map(_checkInFromRow).toList(growable: false);
    final Map<String, Map<String, HabitCheckIn>> byHabit =
        <String, Map<String, HabitCheckIn>>{};
    for (final HabitCheckIn checkIn in checkIns) {
      byHabit.putIfAbsent(checkIn.habitId,
          () => <String, HabitCheckIn>{})[_dayKey(checkIn.localDay)] = checkIn;
    }

    final List<HabitDayProgress> dayProgress = <HabitDayProgress>[];
    for (final Habit habit in habits) {
      if (!habit.isScheduledOn(selectedDay)) continue;
      final Map<String, HabitCheckIn> habitCheckIns =
          byHabit[habit.id] ?? const <String, HabitCheckIn>{};
      final ({int current, int best}) streaks = _calculateStreaks(
        habit,
        habitCheckIns,
        selectedDay.isAfter(today) ? today : selectedDay,
        today,
      );
      dayProgress.add(
        HabitDayProgress(
          habit: habit,
          localDay: selectedDay,
          checkIn: habitCheckIns[_dayKey(selectedDay)],
          currentStreak: streaks.current,
          bestStreak: streaks.best,
        ),
      );
    }

    final List<HabitDaySummary> week = <HabitDaySummary>[];
    for (int offset = 0; offset < 7; offset += 1) {
      final DateTime day = weekStart.add(Duration(days: offset));
      final bool future = day.isAfter(today);
      int scheduled = 0;
      int completed = 0;
      int recorded = 0;
      if (!future) {
        for (final Habit habit in habits) {
          if (!habit.isScheduledOn(day)) continue;
          scheduled += 1;
          final HabitCheckIn? checkIn = byHabit[habit.id]?[_dayKey(day)];
          if (checkIn != null) {
            recorded += 1;
            if (_isSuccessful(habit, checkIn)) completed += 1;
          }
        }
      }
      week.add(
        HabitDaySummary(
          localDay: day,
          scheduledCount: scheduled,
          completedCount: completed,
          recordedCount: recorded,
          isFuture: future,
        ),
      );
    }

    final DateTime yesterday = today.subtract(const Duration(days: 1));
    final List<Habit> recovery = <Habit>[];
    for (final Habit habit in habits) {
      if (!habit.isScheduledOn(yesterday)) continue;
      final HabitCheckIn? checkIn = byHabit[habit.id]?[_dayKey(yesterday)];
      if (checkIn == null || !_isSuccessful(habit, checkIn)) {
        recovery.add(habit);
      }
    }

    return HabitDashboard(
      localDay: selectedDay,
      weekStartsOnLocal: weekStart,
      activeHabits: habits,
      dayProgress: dayProgress,
      week: week,
      recoveryCandidates: recovery,
    );
  }

  @override
  Future<Habit> createHabit(HabitDraft draft) async {
    _validateDraft(draft);
    final DateTime now = _clock().toUtc();
    final String id = _newId('habit');
    await _database.insertRow('''
      INSERT INTO habits (
        id, name, description, direction, measurement, target_value, unit,
        weekdays_mask, preferred_time_minute, starts_on_local, ends_on_local,
        color_value, is_archived, created_at_utc, updated_at_utc,
        archived_at_utc
      ) VALUES (
        ?, ?, NULLIF(?, ''), ?, ?, ?, ?, ?, CAST(NULLIF(?, '') AS INTEGER),
        ?, NULLIF(?, ''), ?, 0,
        ?, ?, NULL
      )
    ''', variables: <Variable<Object>>[
      Variable<String>(id),
      Variable<String>(_requiredText(draft.name, 'Habit name')),
      Variable<String>(_optionalText(draft.description)),
      Variable<String>(draft.direction.name),
      Variable<String>(draft.measurement.name),
      Variable<int>(draft.targetValue),
      Variable<String>(_requiredText(draft.unit, 'Unit')),
      Variable<int>(draft.weekdaysMask),
      Variable<String>(draft.preferredTimeMinute?.toString() ?? ''),
      Variable<String>(_dayKey(draft.startsOnLocal)),
      Variable<String>(_optionalDayKey(draft.endsOnLocal)),
      Variable<int>(draft.colorValue),
      Variable<String>(_utc(now)),
      Variable<String>(_utc(now)),
    ]);
    _database.notifyChanged();
    return _readHabit(id);
  }

  @override
  Future<Habit> updateHabit(String habitId, HabitDraft draft) async {
    final Habit existing = await _readHabit(habitId);
    if (existing.isArchived)
      throw StateError('Archived habits cannot be edited.');
    _validateDraft(draft);
    final DateTime now = _clock().toUtc();
    await _requireUpdated(
      _database.updateRows('''
        UPDATE habits
        SET name = ?, description = NULLIF(?, ''), direction = ?,
            measurement = ?, target_value = ?, unit = ?, weekdays_mask = ?,
            preferred_time_minute = CAST(NULLIF(?, '') AS INTEGER),
            starts_on_local = ?,
            ends_on_local = NULLIF(?, ''), color_value = ?, updated_at_utc = ?
        WHERE id = ? AND is_archived = 0
      ''', variables: <Variable<Object>>[
        Variable<String>(_requiredText(draft.name, 'Habit name')),
        Variable<String>(_optionalText(draft.description)),
        Variable<String>(draft.direction.name),
        Variable<String>(draft.measurement.name),
        Variable<int>(draft.targetValue),
        Variable<String>(_requiredText(draft.unit, 'Unit')),
        Variable<int>(draft.weekdaysMask),
        Variable<String>(draft.preferredTimeMinute?.toString() ?? ''),
        Variable<String>(_dayKey(draft.startsOnLocal)),
        Variable<String>(_optionalDayKey(draft.endsOnLocal)),
        Variable<int>(draft.colorValue),
        Variable<String>(_utc(now)),
        Variable<String>(habitId),
      ]),
      'Habit',
    );
    _database.notifyChanged();
    return _readHabit(habitId);
  }

  @override
  Future<HabitCheckIn> recordCheckIn(HabitCheckInDraft draft) async {
    final Habit habit = await _readHabit(draft.habitId);
    if (habit.isArchived) {
      throw StateError('Archived habits cannot receive check-ins.');
    }
    final DateTime localDay = dateOnly(draft.localDay);
    final DateTime today = dateOnly(_clock().toLocal());
    if (localDay.isAfter(today)) {
      throw ArgumentError('A future habit check-in cannot be recorded.');
    }
    if (!habit.isScheduledOn(localDay)) {
      throw ArgumentError('This habit is not scheduled on that day.');
    }
    if (draft.value < 0) {
      throw ArgumentError.value(
          draft.value, 'value', 'Value cannot be negative.');
    }
    if (habit.measurement == HabitMeasurement.binary && draft.value != 1) {
      throw ArgumentError('A yes/no habit check-in must have value 1.');
    }
    final DateTime now = _clock().toUtc();
    final String dayKey = _dayKey(localDay);
    await _database.insertRow('''
      INSERT INTO habit_check_ins (
        id, habit_id, local_day, value, note, recorded_at_utc,
        created_at_utc, updated_at_utc
      ) VALUES (?, ?, ?, ?, NULLIF(?, ''), ?, ?, ?)
      ON CONFLICT(habit_id, local_day) DO UPDATE SET
        value = excluded.value,
        note = excluded.note,
        recorded_at_utc = excluded.recorded_at_utc,
        updated_at_utc = excluded.updated_at_utc
    ''', variables: <Variable<Object>>[
      Variable<String>(_newId('checkin')),
      Variable<String>(habit.id),
      Variable<String>(dayKey),
      Variable<int>(draft.value),
      Variable<String>(_optionalText(draft.note)),
      Variable<String>(_utc(now)),
      Variable<String>(_utc(now)),
      Variable<String>(_utc(now)),
    ]);
    _database.notifyChanged();
    return _readCheckIn(habit.id, dayKey);
  }

  @override
  Future<void> clearCheckIn(String habitId, DateTime localDay) async {
    await _database.updateRows(
      'DELETE FROM habit_check_ins WHERE habit_id = ? AND local_day = ?',
      variables: _strings(<String>[habitId, _dayKey(localDay)]),
    );
    _database.notifyChanged();
  }

  @override
  Future<void> archiveHabit(String habitId) async {
    final DateTime now = _clock().toUtc();
    await _requireUpdated(
      _database.updateRows('''
        UPDATE habits
        SET is_archived = 1, archived_at_utc = ?, updated_at_utc = ?
        WHERE id = ? AND is_archived = 0
      ''',
          variables: _strings(<String>[
            _utc(now),
            _utc(now),
            habitId,
          ])),
      'Habit',
    );
    _database.notifyChanged();
  }

  Future<Habit> _readHabit(String habitId) async {
    final List<QueryRow> rows = await _database.readRows(
      'SELECT * FROM habits WHERE id = ?',
      variables: _strings(<String>[habitId]),
    );
    if (rows.isEmpty) throw StateError('Habit was not found.');
    return _habitFromRow(rows.single);
  }

  Future<HabitCheckIn> _readCheckIn(String habitId, String dayKey) async {
    final List<QueryRow> rows = await _database.readRows('''
      SELECT * FROM habit_check_ins
      WHERE habit_id = ? AND local_day = ?
    ''', variables: _strings(<String>[habitId, dayKey]));
    if (rows.isEmpty) throw StateError('Habit check-in was not found.');
    return _checkInFromRow(rows.single);
  }

  void _validateDraft(HabitDraft draft) {
    _requiredText(draft.name, 'Habit name');
    _requiredText(draft.unit, 'Unit');
    if (draft.weekdaysMask < 1 || draft.weekdaysMask > everyDayWeekdaysMask) {
      throw ArgumentError('Select at least one valid weekday.');
    }
    if (draft.targetValue < 0 ||
        (draft.direction == HabitDirection.build && draft.targetValue == 0)) {
      throw ArgumentError('The habit target is invalid.');
    }
    if (draft.measurement == HabitMeasurement.binary &&
        (draft.direction != HabitDirection.build || draft.targetValue != 1)) {
      throw ArgumentError('A yes/no habit must be a build target of 1.');
    }
    final int? preferredTime = draft.preferredTimeMinute;
    if (preferredTime != null &&
        (preferredTime < 0 || preferredTime >= 24 * 60)) {
      throw ArgumentError('Preferred time must fall inside one day.');
    }
    final DateTime start = dateOnly(draft.startsOnLocal);
    final DateTime? draftEnd = draft.endsOnLocal;
    final DateTime? end = draftEnd == null ? null : dateOnly(draftEnd);
    if (end != null && end.isBefore(start)) {
      throw ArgumentError('The end date cannot be before the start date.');
    }
    if (draft.colorValue < 0 || draft.colorValue > 0xFFFFFFFF) {
      throw ArgumentError('Habit color must be a 32-bit ARGB value.');
    }
  }

  Habit _habitFromRow(QueryRow row) {
    final String? end = row.readNullable<String>('ends_on_local');
    return Habit(
      id: row.read<String>('id'),
      name: row.read<String>('name'),
      description: row.readNullable<String>('description'),
      direction: HabitDirection.values.byName(row.read<String>('direction')),
      measurement: HabitMeasurement.values.byName(
        row.read<String>('measurement'),
      ),
      targetValue: row.read<int>('target_value'),
      unit: row.read<String>('unit'),
      weekdaysMask: row.read<int>('weekdays_mask'),
      preferredTimeMinute: row.readNullable<int>('preferred_time_minute'),
      startsOnLocal: _localDay(row.read<String>('starts_on_local')),
      endsOnLocal: end == null ? null : _localDay(end),
      colorValue: row.read<int>('color_value'),
      isArchived: row.read<int>('is_archived') == 1,
      createdAtUtc: _date(row, 'created_at_utc'),
      updatedAtUtc: _date(row, 'updated_at_utc'),
      archivedAtUtc: _nullableDate(row, 'archived_at_utc'),
    );
  }

  HabitCheckIn _checkInFromRow(QueryRow row) {
    return HabitCheckIn(
      id: row.read<String>('id'),
      habitId: row.read<String>('habit_id'),
      localDay: _localDay(row.read<String>('local_day')),
      value: row.read<int>('value'),
      note: row.readNullable<String>('note'),
      recordedAtUtc: _date(row, 'recorded_at_utc'),
      createdAtUtc: _date(row, 'created_at_utc'),
      updatedAtUtc: _date(row, 'updated_at_utc'),
    );
  }

  String _newId(String prefix) {
    final HabitIdFactory? factory = _idFactory;
    if (factory != null) return factory(prefix);
    _idCounter += 1;
    final String time =
        _clock().toUtc().microsecondsSinceEpoch.toRadixString(36);
    final String random = _random.nextInt(0x7fffffff).toRadixString(36);
    return '$prefix-$time-$random-$_idCounter';
  }
}

({int current, int best}) _calculateStreaks(
  Habit habit,
  Map<String, HabitCheckIn> checkIns,
  DateTime throughDay,
  DateTime today,
) {
  final DateTime start = habit.startsOnLocal;
  final DateTime? habitEnd = habit.endsOnLocal;
  DateTime end = throughDay;
  if (habitEnd != null && habitEnd.isBefore(end)) end = habitEnd;
  if (end.isBefore(start)) return (current: 0, best: 0);

  int running = 0;
  int best = 0;
  for (DateTime day = start;
      !day.isAfter(end);
      day = day.add(const Duration(days: 1))) {
    if (!habit.isScheduledOn(day)) continue;
    final HabitCheckIn? checkIn = checkIns[_dayKey(day)];
    if (checkIn != null && _isSuccessful(habit, checkIn)) {
      running += 1;
      if (running > best) best = running;
    } else {
      running = 0;
    }
  }

  int current = 0;
  for (DateTime day = end;
      !day.isBefore(start);
      day = day.subtract(const Duration(days: 1))) {
    if (!habit.isScheduledOn(day)) continue;
    final HabitCheckIn? checkIn = checkIns[_dayKey(day)];
    if (_sameDay(day, today) && checkIn == null) continue;
    if (checkIn != null && _isSuccessful(habit, checkIn)) {
      current += 1;
    } else {
      break;
    }
  }
  return (current: current, best: best);
}

bool _isSuccessful(Habit habit, HabitCheckIn checkIn) {
  return habit.direction == HabitDirection.build
      ? checkIn.value >= habit.targetValue
      : checkIn.value <= habit.targetValue;
}

String _requiredText(String value, String field) {
  final String text = value.trim();
  if (text.isEmpty) {
    throw ArgumentError.value(value, field, '$field cannot be empty.');
  }
  return text;
}

String _optionalText(String? value) => value?.trim() ?? '';

String _optionalDayKey(DateTime? value) {
  return value == null ? '' : _dayKey(value);
}

String _dayKey(DateTime value) {
  final DateTime day = dateOnly(value);
  final String month = day.month.toString().padLeft(2, '0');
  final String date = day.day.toString().padLeft(2, '0');
  return '${day.year}-$month-$date';
}

DateTime _localDay(String value) {
  final List<int> parts = value.split('-').map(int.parse).toList();
  return DateTime(parts[0], parts[1], parts[2]);
}

String _utc(DateTime value) => value.toUtc().toIso8601String();

DateTime _date(QueryRow row, String column) {
  return DateTime.parse(row.read<String>(column)).toUtc();
}

DateTime? _nullableDate(QueryRow row, String column) {
  final String? value = row.readNullable<String>(column);
  return value == null ? null : DateTime.parse(value).toUtc();
}

bool _sameDay(DateTime first, DateTime second) {
  return first.year == second.year &&
      first.month == second.month &&
      first.day == second.day;
}

Future<void> _requireUpdated(Future<int> operation, String recordName) async {
  final int count = await operation;
  if (count == 0) throw StateError('$recordName was not found.');
}

List<Variable<Object>> _strings(List<String> values) {
  return values
      .map<Variable<Object>>((String value) => Variable<String>(value))
      .toList(growable: false);
}
