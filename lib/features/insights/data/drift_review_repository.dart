import 'dart:math';

import 'package:drift/drift.dart';

import '../../planner/data/planning_database.dart';
import '../domain/review_entities.dart';
import '../domain/review_repository.dart';

typedef ReviewClock = DateTime Function();
typedef ReviewIdFactory = String Function(String prefix);

final class DriftReviewRepository implements ReviewRepository {
  DriftReviewRepository(
    this._database, {
    ReviewClock? clock,
    ReviewIdFactory? idFactory,
  })  : _clock = clock ?? DateTime.now,
        _idFactory = idFactory;

  final PlanningDatabase _database;
  final ReviewClock _clock;
  final ReviewIdFactory? _idFactory;
  final Random _random = Random.secure();
  int _idCounter = 0;

  @override
  Stream<ReviewSummary> watchSummary(ReviewPeriod period) {
    return _database.watchQuery(() => getSummary(period));
  }

  @override
  Future<ReviewSummary> getSummary(ReviewPeriod requestedPeriod) async {
    final ReviewPeriod period = ReviewPeriod.containing(
      requestedPeriod.cadence,
      requestedPeriod.startsOnLocal,
    );
    final DateTime today = reviewDateOnly(_clock().toLocal());
    final Map<String, _DayAccumulator> byDay = <String, _DayAccumulator>{};
    for (DateTime day = period.startsOnLocal;
        day.isBefore(period.endsOnLocalExclusive);
        day = day.add(const Duration(days: 1))) {
      byDay[_dayKey(day)] = _DayAccumulator(
        localDay: day,
        isFuture: day.isAfter(today),
      );
    }

    final List<DailyReflectionSummary> reflections =
        await _loadDailyClosures(period, today);
    await _loadTasks(period, byDay);
    for (final DailyReflectionSummary closure in reflections) {
      final _DayAccumulator? day = byDay[_dayKey(closure.localDay)];
      if (day == null || day.isFuture) continue;
      // A closure is the historical snapshot taken before unfinished tasks
      // were moved or resolved. It therefore replaces the live task view for
      // that day instead of being added to it.
      day
        ..plannedTaskCount = closure.scheduledTaskCount
        ..completedTaskCount = closure.completedTaskCount
        ..resolvedTaskCount = closure.completedTaskCount
        ..plannedMinutes = closure.plannedMinutes
        ..completedMinutes = closure.completedMinutes
        ..mood = closure.mood;
    }

    await _loadHabits(period, byDay);
    await _loadMoney(period, byDay);
    await _loadSchool(period, byDay);

    final PeriodReview? savedReview = await _readReviewForPeriod(period);
    final DateTime generatedThrough = today.isBefore(period.startsOnLocal)
        ? period.startsOnLocal
        : today.isAfter(period.lastDay)
            ? period.lastDay
            : today;
    return ReviewSummary(
      period: period,
      generatedThroughLocal: generatedThrough,
      days: byDay.values
          .map((_DayAccumulator day) => day.build())
          .toList(growable: false),
      dailyReflections: reflections,
      savedReview: savedReview,
    );
  }

  Future<List<DailyReflectionSummary>> _loadDailyClosures(
    ReviewPeriod period,
    DateTime today,
  ) async {
    final List<QueryRow> rows = await _database.readRows('''
      SELECT * FROM daily_closures
      WHERE local_day >= ? AND local_day < ?
      ORDER BY local_day DESC
    ''',
        variables: _strings(<String>[
          _dayKey(period.startsOnLocal),
          _dayKey(period.endsOnLocalExclusive),
        ]));
    return rows
        .map(
          (QueryRow row) => DailyReflectionSummary(
            localDay: _localDay(row.read<String>('local_day')),
            mood: row.read<int>('mood'),
            win: row.readNullable<String>('win'),
            lesson: row.readNullable<String>('lesson'),
            tomorrowFocus: row.readNullable<String>('tomorrow_focus'),
            scheduledTaskCount: row.read<int>('scheduled_task_count'),
            completedTaskCount: row.read<int>('completed_task_count'),
            plannedMinutes: row.read<int>('planned_minutes'),
            completedMinutes: row.read<int>('completed_minutes'),
            closedAtUtc: _utcDate(row, 'closed_at_utc'),
          ),
        )
        .where(
          (DailyReflectionSummary item) => !item.localDay.isAfter(today),
        )
        .toList(growable: false);
  }

  Future<void> _loadTasks(
    ReviewPeriod period,
    Map<String, _DayAccumulator> byDay,
  ) async {
    final List<QueryRow> rows = await _database.readRows('''
      SELECT
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
          _utc(period.startsOnLocal.toUtc()),
          _utc(period.endsOnLocalExclusive.toUtc()),
        ]));
    for (final QueryRow row in rows) {
      final DateTime start = _utcDate(row, 'effective_start');
      final _DayAccumulator? day = byDay[_dayKey(start.toLocal())];
      if (day == null || day.isFuture) continue;
      final String status = row.read<String>('status');
      final DateTime? end = _nullableUtcDate(row, 'effective_end');
      final int duration = end != null && end.isAfter(start)
          ? end.difference(start).inMinutes
          : 0;
      day
        ..plannedTaskCount += 1
        ..plannedMinutes += duration;
      if (status == 'completed') {
        day
          ..completedTaskCount += 1
          ..completedMinutes += duration;
      }
      if (_isFinishedStatus(status)) day.resolvedTaskCount += 1;
    }
  }

  Future<void> _loadHabits(
    ReviewPeriod period,
    Map<String, _DayAccumulator> byDay,
  ) async {
    final List<_ReviewHabit> habits = (await _database.readRows('''
      SELECT * FROM habits
      WHERE starts_on_local < ?
        AND (ends_on_local IS NULL OR ends_on_local >= ?)
      ORDER BY created_at_utc ASC
    ''',
            variables: _strings(<String>[
              _dayKey(period.endsOnLocalExclusive),
              _dayKey(period.startsOnLocal),
            ])))
        .map(_ReviewHabit.fromRow)
        .toList(growable: false);
    final Map<String, int> checkIns = <String, int>{};
    final List<QueryRow> rows = await _database.readRows('''
      SELECT habit_id, local_day, value
      FROM habit_check_ins
      WHERE local_day >= ? AND local_day < ?
    ''',
        variables: _strings(<String>[
          _dayKey(period.startsOnLocal),
          _dayKey(period.endsOnLocalExclusive),
        ]));
    for (final QueryRow row in rows) {
      checkIns[
              '${row.read<String>('habit_id')}|${row.read<String>('local_day')}'] =
          row.read<int>('value');
    }

    for (final _DayAccumulator day in byDay.values) {
      if (day.isFuture) continue;
      for (final _ReviewHabit habit in habits) {
        if (!habit.isScheduledOn(day.localDay)) continue;
        day.habitScheduledCount += 1;
        final int? value = checkIns['${habit.id}|${_dayKey(day.localDay)}'];
        if (value != null && habit.isSuccessful(value)) {
          day.habitSuccessfulCount += 1;
        }
      }
    }
  }

  Future<void> _loadMoney(
    ReviewPeriod period,
    Map<String, _DayAccumulator> byDay,
  ) async {
    final List<QueryRow> rows = await _database.readRows('''
      SELECT kind, amount_rwf, occurred_at_utc
      FROM money_transactions
      WHERE deleted_at_utc IS NULL
        AND occurred_at_utc >= ?
        AND occurred_at_utc < ?
      ORDER BY occurred_at_utc ASC
    ''',
        variables: _strings(<String>[
          _utc(period.startsOnLocal.toUtc()),
          _utc(period.endsOnLocalExclusive.toUtc()),
        ]));
    for (final QueryRow row in rows) {
      final DateTime local = _utcDate(row, 'occurred_at_utc').toLocal();
      final _DayAccumulator? day = byDay[_dayKey(local)];
      if (day == null || day.isFuture) continue;
      final int amount = row.read<int>('amount_rwf');
      switch (row.read<String>('kind')) {
        case 'expense':
          day.spentRwf += amount;
          break;
        case 'income':
          day.incomeRwf += amount;
          break;
        case 'transfer':
          break;
      }
    }
  }

  Future<void> _loadSchool(
    ReviewPeriod period,
    Map<String, _DayAccumulator> byDay,
  ) async {
    final List<QueryRow> sessionRows = await _database.readRows('''
      SELECT cs.weekday, t.starts_on_local, t.ends_on_local
      FROM class_sessions cs
      JOIN subjects s ON s.id = cs.subject_id
      JOIN academic_terms t ON t.id = s.term_id
      WHERE t.starts_on_local < ? AND t.ends_on_local >= ?
    ''',
        variables: _strings(<String>[
          _dayKey(period.endsOnLocalExclusive),
          _dayKey(period.startsOnLocal),
        ]));
    for (final _DayAccumulator day in byDay.values) {
      if (day.isFuture) continue;
      for (final QueryRow row in sessionRows) {
        if (row.read<int>('weekday') != day.localDay.weekday) continue;
        final DateTime starts = _localDay(row.read<String>('starts_on_local'));
        final DateTime ends = _localDay(row.read<String>('ends_on_local'));
        if (!day.localDay.isBefore(starts) && !day.localDay.isAfter(ends)) {
          day.classCount += 1;
        }
      }
    }

    final List<QueryRow> assignmentRows = await _database.readRows('''
      SELECT a.due_at_utc, t.status
      FROM school_assignments a
      JOIN planning_tasks t ON t.id = a.task_id
      WHERE t.deleted_at_utc IS NULL
        AND a.due_at_utc >= ?
        AND a.due_at_utc < ?
    ''',
        variables: _strings(<String>[
          _utc(period.startsOnLocal.toUtc()),
          _utc(period.endsOnLocalExclusive.toUtc()),
        ]));
    for (final QueryRow row in assignmentRows) {
      final DateTime local = _utcDate(row, 'due_at_utc').toLocal();
      final _DayAccumulator? day = byDay[_dayKey(local)];
      if (day == null || day.isFuture) continue;
      day.assignmentDueCount += 1;
      if (row.read<String>('status') == 'completed') {
        day.assignmentCompletedCount += 1;
      }
    }

    final List<QueryRow> examRows = await _database.readRows('''
      SELECT starts_at_utc
      FROM exams
      WHERE starts_at_utc >= ? AND starts_at_utc < ?
    ''',
        variables: _strings(<String>[
          _utc(period.startsOnLocal.toUtc()),
          _utc(period.endsOnLocalExclusive.toUtc()),
        ]));
    for (final QueryRow row in examRows) {
      final DateTime local = _utcDate(row, 'starts_at_utc').toLocal();
      final _DayAccumulator? day = byDay[_dayKey(local)];
      if (day != null && !day.isFuture) day.examCount += 1;
    }
  }

  @override
  Future<PeriodReview> saveReview(PeriodReviewDraft draft) async {
    if (draft.overallRating < 1 || draft.overallRating > 5) {
      throw ArgumentError.value(
        draft.overallRating,
        'overallRating',
        'Review rating must be from 1 to 5.',
      );
    }
    final String wins = _requiredText(draft.wins, 'Wins');
    final String nextFocus = _requiredText(draft.nextFocus, 'Next focus');
    final ReviewPeriod period = ReviewPeriod.containing(
      draft.cadence,
      draft.periodStartsOnLocal,
    );
    final DateTime now = _clock().toUtc();
    final String id = _newId('period-review');
    await _database.insertRow('''
      INSERT INTO period_reviews (
        id, cadence, period_starts_on_local, overall_rating, wins,
        challenges, lessons, next_focus, created_at_utc, updated_at_utc
      ) VALUES (?, ?, ?, ?, ?, NULLIF(?, ''), NULLIF(?, ''), ?, ?, ?)
      ON CONFLICT(cadence, period_starts_on_local) DO UPDATE SET
        overall_rating = excluded.overall_rating,
        wins = excluded.wins,
        challenges = excluded.challenges,
        lessons = excluded.lessons,
        next_focus = excluded.next_focus,
        updated_at_utc = excluded.updated_at_utc
    ''', variables: <Variable<Object>>[
      Variable<String>(id),
      Variable<String>(draft.cadence.name),
      Variable<String>(_dayKey(period.startsOnLocal)),
      Variable<int>(draft.overallRating),
      Variable<String>(wins),
      Variable<String>(_optionalText(draft.challenges)),
      Variable<String>(_optionalText(draft.lessons)),
      Variable<String>(nextFocus),
      Variable<String>(_utc(now)),
      Variable<String>(_utc(now)),
    ]);
    _database.notifyChanged();
    return (await _readReviewForPeriod(period))!;
  }

  Future<PeriodReview?> _readReviewForPeriod(ReviewPeriod period) async {
    final List<QueryRow> rows = await _database.readRows('''
      SELECT * FROM period_reviews
      WHERE cadence = ? AND period_starts_on_local = ?
    ''',
        variables: _strings(<String>[
          period.cadence.name,
          _dayKey(period.startsOnLocal),
        ]));
    if (rows.isEmpty) return null;
    final QueryRow row = rows.single;
    return PeriodReview(
      id: row.read<String>('id'),
      cadence: ReviewCadence.values.byName(row.read<String>('cadence')),
      periodStartsOnLocal:
          _localDay(row.read<String>('period_starts_on_local')),
      overallRating: row.read<int>('overall_rating'),
      wins: row.read<String>('wins'),
      challenges: row.readNullable<String>('challenges'),
      lessons: row.readNullable<String>('lessons'),
      nextFocus: row.read<String>('next_focus'),
      createdAtUtc: _utcDate(row, 'created_at_utc'),
      updatedAtUtc: _utcDate(row, 'updated_at_utc'),
    );
  }

  String _newId(String prefix) {
    final ReviewIdFactory? factory = _idFactory;
    if (factory != null) return factory(prefix);
    _idCounter += 1;
    return '$prefix-${_clock().toUtc().microsecondsSinceEpoch}-'
        '$_idCounter-${_random.nextInt(1 << 32)}';
  }
}

class _DayAccumulator {
  _DayAccumulator({required this.localDay, required this.isFuture});

  final DateTime localDay;
  final bool isFuture;
  int plannedTaskCount = 0;
  int completedTaskCount = 0;
  int resolvedTaskCount = 0;
  int plannedMinutes = 0;
  int completedMinutes = 0;
  int habitScheduledCount = 0;
  int habitSuccessfulCount = 0;
  int spentRwf = 0;
  int incomeRwf = 0;
  int classCount = 0;
  int assignmentDueCount = 0;
  int assignmentCompletedCount = 0;
  int examCount = 0;
  int? mood;

  ReviewDayMetrics build() => ReviewDayMetrics(
        localDay: localDay,
        isFuture: isFuture,
        plannedTaskCount: plannedTaskCount,
        completedTaskCount: completedTaskCount,
        resolvedTaskCount: resolvedTaskCount,
        plannedMinutes: plannedMinutes,
        completedMinutes: completedMinutes,
        habitScheduledCount: habitScheduledCount,
        habitSuccessfulCount: habitSuccessfulCount,
        spentRwf: spentRwf,
        incomeRwf: incomeRwf,
        classCount: classCount,
        assignmentDueCount: assignmentDueCount,
        assignmentCompletedCount: assignmentCompletedCount,
        examCount: examCount,
        mood: mood,
      );
}

class _ReviewHabit {
  const _ReviewHabit({
    required this.id,
    required this.direction,
    required this.targetValue,
    required this.weekdaysMask,
    required this.startsOnLocal,
    this.endsOnLocal,
    this.archivedOnLocal,
  });

  factory _ReviewHabit.fromRow(QueryRow row) {
    final String? archived = row.readNullable<String>('archived_at_utc');
    return _ReviewHabit(
      id: row.read<String>('id'),
      direction: row.read<String>('direction'),
      targetValue: row.read<int>('target_value'),
      weekdaysMask: row.read<int>('weekdays_mask'),
      startsOnLocal: _localDay(row.read<String>('starts_on_local')),
      endsOnLocal: _nullableLocalDay(row, 'ends_on_local'),
      archivedOnLocal: archived == null
          ? null
          : reviewDateOnly(DateTime.parse(archived).toLocal()),
    );
  }

  final String id;
  final String direction;
  final int targetValue;
  final int weekdaysMask;
  final DateTime startsOnLocal;
  final DateTime? endsOnLocal;
  final DateTime? archivedOnLocal;

  bool isScheduledOn(DateTime value) {
    final DateTime day = reviewDateOnly(value);
    if (day.isBefore(startsOnLocal)) return false;
    if (endsOnLocal != null && day.isAfter(endsOnLocal!)) return false;
    if (archivedOnLocal != null && day.isAfter(archivedOnLocal!)) return false;
    final int bit = 1 << (day.weekday - DateTime.monday);
    return weekdaysMask & bit != 0;
  }

  bool isSuccessful(int value) =>
      direction == 'build' ? value >= targetValue : value <= targetValue;
}

bool _isFinishedStatus(String status) =>
    status == 'completed' || status == 'skipped' || status == 'cancelled';

String _requiredText(String? value, String field) {
  final String text = value?.trim() ?? '';
  if (text.isEmpty) throw ArgumentError('$field cannot be empty.');
  return text;
}

String _optionalText(String? value) => value?.trim() ?? '';

String _dayKey(DateTime value) {
  final DateTime day = reviewDateOnly(value);
  final String month = day.month.toString().padLeft(2, '0');
  final String date = day.day.toString().padLeft(2, '0');
  return '${day.year}-$month-$date';
}

DateTime _localDay(String value) {
  final List<int> parts = value.split('-').map(int.parse).toList();
  return DateTime(parts[0], parts[1], parts[2]);
}

DateTime? _nullableLocalDay(QueryRow row, String column) {
  final String? value = row.readNullable<String>(column);
  return value == null ? null : _localDay(value);
}

DateTime _utcDate(QueryRow row, String column) =>
    DateTime.parse(row.read<String>(column)).toUtc();

DateTime? _nullableUtcDate(QueryRow row, String column) {
  final String? value = row.readNullable<String>(column);
  return value == null ? null : DateTime.parse(value).toUtc();
}

String _utc(DateTime value) => value.toUtc().toIso8601String();

List<Variable<Object>> _strings(List<String> values) => values
    .map<Variable<Object>>((String value) => Variable<String>(value))
    .toList(growable: false);
