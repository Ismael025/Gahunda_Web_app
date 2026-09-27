import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gahunda/features/behavior/data/drift_habit_repository.dart';
import 'package:gahunda/features/behavior/domain/habit_entities.dart';
import 'package:gahunda/features/planner/data/planning_database.dart';

void main() {
  final DateTime fixedNow = DateTime(2026, 9, 9, 12);
  int id = 0;

  DriftHabitRepository repository(PlanningDatabase database) {
    return DriftHabitRepository(
      database,
      clock: () => fixedNow,
      idFactory: (String prefix) => '$prefix-${id++}',
    );
  }

  HabitDraft buildHabit({
    String name = 'Read',
    HabitMeasurement measurement = HabitMeasurement.binary,
    int target = 1,
    String unit = 'done',
    int weekdaysMask = everyDayWeekdaysMask,
    DateTime? startsOn,
    DateTime? endsOn,
  }) {
    return HabitDraft(
      name: name,
      direction: HabitDirection.build,
      measurement: measurement,
      targetValue: target,
      unit: unit,
      weekdaysMask: weekdaysMask,
      startsOnLocal: startsOn ?? DateTime(2026, 9, 7),
      endsOnLocal: endsOn,
      colorValue: 0xFF0F9D8A,
    );
  }

  HabitDraft reductionHabit({
    String name = 'Social media',
    int target = 30,
    String unit = 'minutes',
  }) {
    return HabitDraft(
      name: name,
      direction: HabitDirection.reduce,
      measurement: HabitMeasurement.minutes,
      targetValue: target,
      unit: unit,
      weekdaysMask: everyDayWeekdaysMask,
      startsOnLocal: DateTime(2026, 9, 7),
      colorValue: 0xFFF59E0B,
    );
  }

  setUp(() => id = 0);

  test('creates, completes, and clears a yes/no habit check-in', () async {
    final PlanningDatabase database = PlanningDatabase(NativeDatabase.memory());
    final DriftHabitRepository habits = repository(database);
    addTearDown(database.close);

    final Habit habit = await habits.createHabit(buildHabit());
    HabitDashboard dashboard = await habits.getDashboard(fixedNow);
    expect(dashboard.scheduledToday, 1);
    expect(dashboard.completedToday, 0);

    await habits.recordCheckIn(
      HabitCheckInDraft(
        habitId: habit.id,
        localDay: fixedNow,
        value: 1,
      ),
    );
    dashboard = await habits.getDashboard(fixedNow);
    expect(dashboard.completedToday, 1);
    expect(dashboard.dayProgress.single.isSuccessful, isTrue);

    await habits.clearCheckIn(habit.id, fixedNow);
    dashboard = await habits.getDashboard(fixedNow);
    expect(dashboard.dayProgress.single.checkIn, isNull);
  });

  test('reduction habits succeed at the limit and fail above it', () async {
    final PlanningDatabase database = PlanningDatabase(NativeDatabase.memory());
    final DriftHabitRepository habits = repository(database);
    addTearDown(database.close);
    final Habit habit = await habits.createHabit(reductionHabit());

    await habits.recordCheckIn(
      HabitCheckInDraft(
        habitId: habit.id,
        localDay: fixedNow,
        value: 30,
      ),
    );
    expect(
      (await habits.getDashboard(fixedNow)).dayProgress.single.isSuccessful,
      isTrue,
    );

    await habits.recordCheckIn(
      HabitCheckInDraft(
        habitId: habit.id,
        localDay: fixedNow,
        value: 31,
      ),
    );
    final HabitDayProgress progress =
        (await habits.getDashboard(fixedNow)).dayProgress.single;
    expect(progress.isRecorded, isTrue);
    expect(progress.isSuccessful, isFalse);
    expect(
      await database.readRows('SELECT * FROM habit_check_ins'),
      hasLength(1),
    );
  });

  test('selected weekdays and optional end dates control occurrences',
      () async {
    final PlanningDatabase database = PlanningDatabase(NativeDatabase.memory());
    final DriftHabitRepository habits = repository(database);
    addTearDown(database.close);
    final Habit habit = await habits.createHabit(
      buildHabit(
        measurement: HabitMeasurement.count,
        target: 5,
        unit: 'pages',
        weekdaysMask: weekdayMaskFor(<int>[
          DateTime.monday,
          DateTime.wednesday,
        ]),
        endsOn: DateTime(2026, 9, 16),
      ),
    );

    expect(
      (await habits.getDashboard(DateTime(2026, 9, 8))).dayProgress,
      isEmpty,
    );
    expect(
      (await habits.getDashboard(DateTime(2026, 9, 9))).dayProgress,
      hasLength(1),
    );
    expect(
      (await habits.getDashboard(DateTime(2026, 9, 21))).dayProgress,
      isEmpty,
    );
    await expectLater(
      habits.recordCheckIn(
        HabitCheckInDraft(
          habitId: habit.id,
          localDay: DateTime(2026, 9, 8),
          value: 5,
        ),
      ),
      throwsArgumentError,
    );
  });

  test('weekly consistency excludes days that have not happened yet', () async {
    final PlanningDatabase database = PlanningDatabase(NativeDatabase.memory());
    final DriftHabitRepository habits = repository(database);
    addTearDown(database.close);
    final Habit habit = await habits.createHabit(buildHabit());

    for (final DateTime day in <DateTime>[
      DateTime(2026, 9, 7),
      DateTime(2026, 9, 9),
    ]) {
      await habits.recordCheckIn(
        HabitCheckInDraft(habitId: habit.id, localDay: day, value: 1),
      );
    }

    final HabitDashboard dashboard = await habits.getDashboard(fixedNow);
    expect(dashboard.weeklyScheduled, 3);
    expect(dashboard.weeklyCompleted, 2);
    expect(dashboard.weeklyConsistency, closeTo(2 / 3, 0.0001));
    expect(
      dashboard.week.where((HabitDaySummary day) => day.isFuture),
      hasLength(4),
    );
    expect(
      dashboard.week
          .where((HabitDaySummary day) => day.isFuture)
          .every((HabitDaySummary day) => day.scheduledCount == 0),
      isTrue,
    );
  });

  test('current and best streaks use consecutive scheduled successes',
      () async {
    final PlanningDatabase database = PlanningDatabase(NativeDatabase.memory());
    final DriftHabitRepository habits = repository(database);
    addTearDown(database.close);
    final Habit habit = await habits.createHabit(
      buildHabit(
        weekdaysMask: weekdayMaskFor(<int>[
          DateTime.monday,
          DateTime.tuesday,
          DateTime.wednesday,
          DateTime.thursday,
          DateTime.friday,
        ]),
        startsOn: DateTime(2026, 9, 1),
      ),
    );
    for (final DateTime day in <DateTime>[
      DateTime(2026, 9, 7),
      DateTime(2026, 9, 8),
    ]) {
      await habits.recordCheckIn(
        HabitCheckInDraft(habitId: habit.id, localDay: day, value: 1),
      );
    }

    HabitDayProgress progress =
        (await habits.getDashboard(fixedNow)).dayProgress.single;
    expect(progress.currentStreak, 2);
    expect(progress.bestStreak, 2);

    await habits.recordCheckIn(
      HabitCheckInDraft(habitId: habit.id, localDay: fixedNow, value: 1),
    );
    progress = (await habits.getDashboard(fixedNow)).dayProgress.single;
    expect(progress.currentStreak, 3);
    expect(progress.bestStreak, 3);
  });

  test('yesterday stays in recovery until its target is met', () async {
    final PlanningDatabase database = PlanningDatabase(NativeDatabase.memory());
    final DriftHabitRepository habits = repository(database);
    addTearDown(database.close);
    final Habit habit = await habits.createHabit(reductionHabit(target: 20));
    final DateTime yesterday = DateTime(2026, 9, 8);

    expect(
      (await habits.getDashboard(fixedNow)).recoveryCandidates.single.id,
      habit.id,
    );
    await habits.recordCheckIn(
      HabitCheckInDraft(habitId: habit.id, localDay: yesterday, value: 25),
    );
    expect(
      (await habits.getDashboard(fixedNow)).recoveryCandidates,
      hasLength(1),
    );
    await habits.recordCheckIn(
      HabitCheckInDraft(habitId: habit.id, localDay: yesterday, value: 18),
    );
    expect(
      (await habits.getDashboard(fixedNow)).recoveryCandidates,
      isEmpty,
    );
  });

  test('rejects future check-ins and invalid build targets', () async {
    final PlanningDatabase database = PlanningDatabase(NativeDatabase.memory());
    final DriftHabitRepository habits = repository(database);
    addTearDown(database.close);

    await expectLater(
      habits.createHabit(
        buildHabit(
          measurement: HabitMeasurement.count,
          target: 0,
          unit: 'glasses',
        ),
      ),
      throwsArgumentError,
    );
    final Habit habit = await habits.createHabit(buildHabit());
    await expectLater(
      habits.recordCheckIn(
        HabitCheckInDraft(
          habitId: habit.id,
          localDay: DateTime(2026, 9, 10),
          value: 1,
        ),
      ),
      throwsArgumentError,
    );
  });

  test('habits persist after reopening and archive keeps check-in history',
      () async {
    final Directory directory = await Directory.systemTemp.createTemp(
      'gahunda-habits-',
    );
    final File file = File('${directory.path}/gahunda.sqlite');
    addTearDown(() => directory.delete(recursive: true));

    PlanningDatabase database = PlanningDatabase(NativeDatabase(file));
    DriftHabitRepository habits = repository(database);
    final Habit habit = await habits.createHabit(buildHabit(name: 'Journal'));
    await habits.recordCheckIn(
      HabitCheckInDraft(habitId: habit.id, localDay: fixedNow, value: 1),
    );
    await database.close();

    database = PlanningDatabase(NativeDatabase(file));
    habits = repository(database);
    HabitDashboard dashboard = await habits.getDashboard(fixedNow);
    expect(dashboard.activeHabits.single.name, 'Journal');
    expect(dashboard.dayProgress.single.isSuccessful, isTrue);

    await habits.archiveHabit(habit.id);
    dashboard = await habits.getDashboard(fixedNow);
    expect(dashboard.activeHabits, isEmpty);
    expect(
      await database.readRows('SELECT * FROM habit_check_ins'),
      hasLength(1),
    );
    await database.close();
  });

  test('schema version 3 upgrades to habits without losing planning data',
      () async {
    final Directory directory = await Directory.systemTemp.createTemp(
      'gahunda-habit-migration-',
    );
    final File file = File('${directory.path}/migration.sqlite');
    addTearDown(() => directory.delete(recursive: true));

    final PlanningDatabase setup = PlanningDatabase(NativeDatabase(file));
    await setup.customStatement('''
      INSERT INTO goals (
        id, title, description, scope, parent_goal_id, starts_at_utc,
        due_at_utc, status, created_at_utc, updated_at_utc, archived_at_utc
      ) VALUES (
        'existing-goal', 'Keep my plan', NULL, 'annual', NULL, NULL, NULL,
        'active', '2026-09-01T00:00:00Z', '2026-09-01T00:00:00Z', NULL
      )
    ''');
    // Reconstruct a genuine version 3 database. This test runs against the
    // current schema first, so every table introduced after version 3 must be
    // removed before lowering user_version. Leaving later money or review
    // tables in place would make the 3 -> 7 migration create them twice.
    for (final String table in <String>[
      'notification_preferences',
      'sync_metadata',
      'period_reviews',
      'money_budgets',
      'money_transactions',
      'savings_movements',
      'savings_goals',
      'money_categories',
      'money_accounts',
      'habit_check_ins',
      'habits',
    ]) {
      await setup.customStatement('DROP TABLE $table');
    }
    await setup.customStatement('PRAGMA user_version = 3');
    await setup.close();

    final PlanningDatabase upgraded = PlanningDatabase(NativeDatabase(file));
    addTearDown(upgraded.close);
    expect(
      (await upgraded.readRows(
        "SELECT title FROM goals WHERE id = 'existing-goal'",
      ))
          .single
          .read<String>('title'),
      'Keep my plan',
    );
    expect(
      await upgraded.readRows(
        "SELECT name FROM sqlite_master WHERE type = 'table' "
        "AND name IN ('habits', 'habit_check_ins')",
      ),
      hasLength(2),
    );
    expect(
      await upgraded.readRows('SELECT * FROM money_categories'),
      hasLength(14),
    );
  });
}
