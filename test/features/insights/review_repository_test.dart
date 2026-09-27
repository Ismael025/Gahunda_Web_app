import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gahunda/features/behavior/data/drift_habit_repository.dart';
import 'package:gahunda/features/behavior/domain/habit_entities.dart';
import 'package:gahunda/features/insights/data/drift_review_repository.dart';
import 'package:gahunda/features/insights/domain/review_entities.dart';
import 'package:gahunda/features/money/data/drift_money_repository.dart';
import 'package:gahunda/features/money/domain/money_entities.dart';
import 'package:gahunda/features/planner/data/drift_planning_repository.dart';
import 'package:gahunda/features/planner/data/planning_database.dart';
import 'package:gahunda/features/planner/domain/planning_entities.dart';
import 'package:gahunda/features/school/data/drift_school_repository.dart';
import 'package:gahunda/features/school/domain/school_entities.dart';
import 'package:gahunda/features/today/data/drift_today_repository.dart';
import 'package:gahunda/features/today/domain/today_entities.dart';

void main() {
  final DateTime fixedNow = DateTime(2026, 9, 9, 12);
  int id = 0;

  String nextId(String prefix) => '$prefix-${id++}';

  DriftReviewRepository reviews(PlanningDatabase database) {
    return DriftReviewRepository(
      database,
      clock: () => fixedNow,
      idFactory: nextId,
    );
  }

  DriftPlanningRepository planning(PlanningDatabase database) {
    return DriftPlanningRepository(
      database,
      clock: () => fixedNow,
      idFactory: nextId,
    );
  }

  setUp(() => id = 0);

  test('weekly, monthly, and annual review periods use calendar boundaries',
      () {
    final ReviewPeriod week = ReviewPeriod.containing(
      ReviewCadence.weekly,
      fixedNow,
    );
    expect(week.startsOnLocal, DateTime(2026, 9, 7));
    expect(week.lastDay, DateTime(2026, 9, 13));
    expect(week.previous.startsOnLocal, DateTime(2026, 8, 31));
    expect(week.next.startsOnLocal, DateTime(2026, 9, 14));

    final ReviewPeriod leapMonth = ReviewPeriod.containing(
      ReviewCadence.monthly,
      DateTime(2028, 2, 29),
    );
    expect(leapMonth.startsOnLocal, DateTime(2028, 2));
    expect(leapMonth.lastDay, DateTime(2028, 2, 29));

    final ReviewPeriod year = ReviewPeriod.containing(
      ReviewCadence.annual,
      fixedNow,
    );
    expect(year.startsOnLocal, DateTime(2026));
    expect(year.lastDay, DateTime(2026, 12, 31));
  });

  test('scheduled task metrics reproduce plan versus reality', () async {
    final PlanningDatabase database = PlanningDatabase(NativeDatabase.memory());
    final DriftPlanningRepository planner = planning(database);
    final DriftReviewRepository repository = reviews(database);
    addTearDown(database.close);

    final PlanningTask completed = await planner.createTask(
      PlanningTaskDraft(
        title: 'Deep work',
        startsAtUtc: DateTime(2026, 9, 7, 9).toUtc(),
        duration: const Duration(minutes: 60),
      ),
    );
    await planner.createTask(
      PlanningTaskDraft(
        title: 'Study',
        startsAtUtc: DateTime(2026, 9, 8, 14).toUtc(),
        duration: const Duration(minutes: 90),
      ),
    );
    await planner.changeTaskStatus(
      completed.id,
      PlanningTaskStatus.completed,
    );

    final ReviewSummary summary = await repository.getSummary(
      ReviewPeriod.containing(ReviewCadence.weekly, fixedNow),
    );
    expect(summary.plannedTaskCount, 2);
    expect(summary.completedTaskCount, 1);
    expect(summary.plannedMinutes, 150);
    expect(summary.completedMinutes, 60);
    expect(summary.taskCompletion, 0.5);
    expect(summary.planRealityBuckets, hasLength(7));
    expect(summary.planRealityBuckets.first.plannedMinutes, 60);
    expect(summary.planRealityBuckets.first.completedMinutes, 60);
  });

  test('closed-day snapshots survive moving unfinished work forward', () async {
    final PlanningDatabase database = PlanningDatabase(NativeDatabase.memory());
    final DriftPlanningRepository planner = planning(database);
    final DriftTodayRepository today = DriftTodayRepository(
      database,
      clock: () => fixedNow,
      idFactory: nextId,
    );
    final DriftReviewRepository repository = reviews(database);
    addTearDown(database.close);

    final PlanningTask task = await planner.createTask(
      PlanningTaskDraft(
        title: 'Finish report',
        startsAtUtc: DateTime(2026, 9, 7, 10).toUtc(),
      ),
    );
    await today.closeDay(
      DailyClosureDraft(
        localDay: DateTime(2026, 9, 7),
        mood: 4,
        win: 'I protected the focus block',
        lesson: 'Start earlier',
        tomorrowFocus: 'Finish the report',
        taskResolutions: <String, DayTaskResolution>{
          task.id: DayTaskResolution.moveToTomorrow,
        },
      ),
    );

    final ReviewSummary summary = await repository.getSummary(
      ReviewPeriod.containing(ReviewCadence.weekly, fixedNow),
    );
    final ReviewDayMetrics monday = summary.days.first;
    final ReviewDayMetrics tuesday = summary.days[1];
    expect(monday.plannedTaskCount, 1);
    expect(monday.plannedMinutes, 60);
    expect(monday.mood, 4);
    expect(tuesday.plannedTaskCount, 1);
    expect(summary.dailyReflections.single.win, contains('focus block'));
  });

  test('habit consistency excludes future opportunities', () async {
    final PlanningDatabase database = PlanningDatabase(NativeDatabase.memory());
    final DriftHabitRepository habits = DriftHabitRepository(
      database,
      clock: () => fixedNow,
      idFactory: nextId,
    );
    final DriftReviewRepository repository = reviews(database);
    addTearDown(database.close);

    final Habit habit = await habits.createHabit(
      HabitDraft(
        name: 'Read',
        direction: HabitDirection.build,
        measurement: HabitMeasurement.count,
        targetValue: 10,
        unit: 'pages',
        weekdaysMask: everyDayWeekdaysMask,
        startsOnLocal: DateTime(2026, 9, 7),
        colorValue: 0xFF0F9D8A,
      ),
    );
    for (final DateTime day in <DateTime>[
      DateTime(2026, 9, 7),
      DateTime(2026, 9, 9),
    ]) {
      await habits.recordCheckIn(
        HabitCheckInDraft(habitId: habit.id, localDay: day, value: 10),
      );
    }

    final ReviewSummary summary = await repository.getSummary(
      ReviewPeriod.containing(ReviewCadence.weekly, fixedNow),
    );
    expect(summary.habitScheduledCount, 3);
    expect(summary.habitSuccessfulCount, 2);
    expect(summary.habitConsistency, closeTo(2 / 3, 0.0001));
    expect(
      summary.days.where((ReviewDayMetrics day) => day.isFuture),
      hasLength(4),
    );
  });

  test('period cash flow counts income and expenses but ignores transfers',
      () async {
    final PlanningDatabase database = PlanningDatabase(NativeDatabase.memory());
    final DriftMoneyRepository money = DriftMoneyRepository(
      database,
      clock: () => fixedNow,
      idFactory: nextId,
    );
    final DriftReviewRepository repository = reviews(database);
    addTearDown(database.close);

    final MoneyAccount wallet = await money.createAccount(
      const MoneyAccountDraft(
        name: 'Wallet',
        type: MoneyAccountType.cash,
        openingBalanceRwf: 100000,
        colorValue: 0xFF4F46E5,
      ),
    );
    final MoneyAccount bank = await money.createAccount(
      const MoneyAccountDraft(
        name: 'Bank',
        type: MoneyAccountType.bank,
        openingBalanceRwf: 0,
        colorValue: 0xFF0F9D8A,
      ),
    );
    final MoneyDashboard dashboard = await money.getDashboard(fixedNow);
    final MoneyCategory salary = dashboard.categories.singleWhere(
      (MoneyCategory item) => item.name == 'Salary',
    );
    final MoneyCategory food = dashboard.categories.singleWhere(
      (MoneyCategory item) => item.name == 'Food',
    );
    await money.recordTransaction(
      MoneyTransactionDraft(
        kind: MoneyTransactionKind.income,
        accountId: wallet.id,
        categoryId: salary.id,
        title: 'Allowance',
        amountRwf: 20000,
        occurredAtUtc: DateTime(2026, 9, 8, 8).toUtc(),
      ),
    );
    await money.recordTransaction(
      MoneyTransactionDraft(
        kind: MoneyTransactionKind.expense,
        accountId: wallet.id,
        categoryId: food.id,
        title: 'Lunch',
        amountRwf: 5000,
        occurredAtUtc: DateTime(2026, 9, 8, 13).toUtc(),
      ),
    );
    await money.recordTransaction(
      MoneyTransactionDraft(
        kind: MoneyTransactionKind.transfer,
        accountId: wallet.id,
        destinationAccountId: bank.id,
        title: 'Move to bank',
        amountRwf: 10000,
        occurredAtUtc: DateTime(2026, 9, 9, 9).toUtc(),
      ),
    );

    final ReviewSummary summary = await repository.getSummary(
      ReviewPeriod.containing(ReviewCadence.weekly, fixedNow),
    );
    expect(summary.incomeRwf, 20000);
    expect(summary.spentRwf, 5000);
    expect(summary.netCashFlowRwf, 15000);
  });

  test('school metrics count valid class occurrences and dated events',
      () async {
    final PlanningDatabase database = PlanningDatabase(NativeDatabase.memory());
    final DriftSchoolRepository school = DriftSchoolRepository(
      database,
      clock: () => fixedNow,
      idFactory: nextId,
    );
    final DriftPlanningRepository planner = planning(database);
    final DriftReviewRepository repository = reviews(database);
    addTearDown(database.close);

    final AcademicTerm term = await school.createAcademicTerm(
      AcademicTermDraft(
        name: 'Semester I',
        startsOnLocal: DateTime(2026, 9, 1),
        endsOnLocal: DateTime(2026, 9, 30),
      ),
    );
    final Subject subject = await school.createSubject(
      SubjectDraft(
        termId: term.id,
        name: 'Databases',
        colorValue: 0xFF4F46E5,
      ),
    );
    await school.createClassSession(
      ClassSessionDraft(
        subjectId: subject.id,
        weekday: DateTime.monday,
        startsAtMinute: 8 * 60,
        endsAtMinute: 10 * 60,
      ),
    );
    final SchoolAssignment assignment = await school.createAssignment(
      SchoolAssignmentDraft(
        subjectId: subject.id,
        title: 'Schema exercise',
        dueAtUtc: DateTime(2026, 9, 9, 17).toUtc(),
      ),
    );
    await planner.changeTaskStatus(
      assignment.taskId,
      PlanningTaskStatus.completed,
    );
    await school.createExam(
      ExamDraft(
        subjectId: subject.id,
        title: 'Database quiz',
        startsAtUtc: DateTime(2026, 9, 8, 11).toUtc(),
        endsAtUtc: DateTime(2026, 9, 8, 12).toUtc(),
      ),
    );

    final ReviewSummary summary = await repository.getSummary(
      ReviewPeriod.containing(ReviewCadence.weekly, fixedNow),
    );
    expect(summary.classCount, 1);
    expect(summary.assignmentDueCount, 1);
    expect(summary.assignmentCompletedCount, 1);
    expect(summary.examCount, 1);
  });

  test('a period review saves, updates, validates, and notifies watchers',
      () async {
    final PlanningDatabase database = PlanningDatabase(NativeDatabase.memory());
    final DriftReviewRepository repository = reviews(database);
    addTearDown(database.close);
    final ReviewPeriod period = ReviewPeriod.containing(
      ReviewCadence.weekly,
      fixedNow,
    );
    final Future<ReviewSummary> observed = repository
        .watchSummary(period)
        .firstWhere((ReviewSummary value) => value.savedReview != null);

    final PeriodReview first = await repository.saveReview(
      PeriodReviewDraft(
        cadence: ReviewCadence.weekly,
        periodStartsOnLocal: fixedNow,
        overallRating: 4,
        wins: 'Finished the important work',
        lessons: 'Protect mornings',
        nextFocus: 'Prepare the exam',
      ),
    );
    final ReviewSummary emitted = await observed;
    expect(emitted.savedReview?.id, first.id);

    final PeriodReview updated = await repository.saveReview(
      PeriodReviewDraft(
        cadence: ReviewCadence.weekly,
        periodStartsOnLocal: fixedNow,
        overallRating: 5,
        wins: 'Finished and reviewed the work',
        nextFocus: 'Rest and plan Monday',
      ),
    );
    expect(updated.id, first.id);
    expect(updated.overallRating, 5);
    expect(
      await database.readRows('SELECT * FROM period_reviews'),
      hasLength(1),
    );
    await expectLater(
      repository.saveReview(
        PeriodReviewDraft(
          cadence: ReviewCadence.weekly,
          periodStartsOnLocal: fixedNow,
          overallRating: 6,
          wins: 'Invalid',
          nextFocus: 'Invalid',
        ),
      ),
      throwsArgumentError,
    );
  });

  test('saved reviews persist after reopening a file database', () async {
    final Directory directory = await Directory.systemTemp.createTemp(
      'gahunda-review-persistence-',
    );
    final File file = File('${directory.path}/reviews.sqlite');
    addTearDown(() => directory.delete(recursive: true));

    PlanningDatabase database = PlanningDatabase(NativeDatabase(file));
    await reviews(database).saveReview(
      PeriodReviewDraft(
        cadence: ReviewCadence.monthly,
        periodStartsOnLocal: fixedNow,
        overallRating: 4,
        wins: 'Built a steady rhythm',
        nextFocus: 'Keep the rhythm simple',
      ),
    );
    await database.close();

    database = PlanningDatabase(NativeDatabase(file));
    addTearDown(database.close);
    final ReviewSummary summary = await reviews(database).getSummary(
      ReviewPeriod.containing(ReviewCadence.monthly, fixedNow),
    );
    expect(summary.savedReview?.wins, 'Built a steady rhythm');
    expect(summary.savedReview?.overallRating, 4);
  });

  test('schema version 5 upgrades without losing money data', () async {
    final Directory directory = await Directory.systemTemp.createTemp(
      'gahunda-review-migration-',
    );
    final File file = File('${directory.path}/migration.sqlite');
    addTearDown(() => directory.delete(recursive: true));

    final PlanningDatabase setup = PlanningDatabase(NativeDatabase(file));
    await setup.customStatement('''
      INSERT INTO money_accounts (
        id, name, type, opening_balance_rwf, color_value, is_archived,
        created_at_utc, updated_at_utc, archived_at_utc
      ) VALUES (
        'existing-wallet', 'Existing wallet', 'cash', 42000, 4283389905, 0,
        '2026-09-01T00:00:00Z', '2026-09-01T00:00:00Z', NULL
      )
    ''');
    await setup.customStatement('DROP TABLE notification_preferences');
    await setup.customStatement('DROP TABLE sync_metadata');
    await setup.customStatement('DROP TABLE period_reviews');
    await setup.customStatement('PRAGMA user_version = 5');
    await setup.close();

    final PlanningDatabase upgraded = PlanningDatabase(NativeDatabase(file));
    addTearDown(upgraded.close);
    expect(
      (await upgraded.readRows(
        "SELECT opening_balance_rwf FROM money_accounts "
        "WHERE id = 'existing-wallet'",
      ))
          .single
          .read<int>('opening_balance_rwf'),
      42000,
    );
    expect(
      await upgraded.readRows(
        "SELECT name FROM sqlite_master WHERE type = 'table' "
        "AND name = 'period_reviews'",
      ),
      hasLength(1),
    );
  });
}
