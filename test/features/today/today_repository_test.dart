import 'dart:async';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gahunda/features/planner/data/drift_planning_repository.dart';
import 'package:gahunda/features/planner/data/planning_database.dart';
import 'package:gahunda/features/planner/domain/planning_entities.dart';
import 'package:gahunda/features/today/data/drift_today_repository.dart';
import 'package:gahunda/features/today/domain/today_entities.dart';

void main() {
  final DateTime localDay = DateTime(2026, 9, 5);
  final DateTime fixedNow = DateTime.utc(2026, 9, 5, 18);
  int id = 0;

  DriftPlanningRepository planningRepository(PlanningDatabase database) {
    return DriftPlanningRepository(
      database,
      clock: () => fixedNow,
      idFactory: (String prefix) => '$prefix-${id++}',
    );
  }

  DriftTodayRepository todayRepository(PlanningDatabase database) {
    return DriftTodayRepository(
      database,
      clock: () => fixedNow,
      idFactory: (String prefix) => '$prefix-${id++}',
    );
  }

  Future<PlanningTask> createScheduledTask(
    DriftPlanningRepository repository,
    String title,
    int hour, {
    int minutes = 60,
  }) {
    return repository.createTask(
      PlanningTaskDraft(
        title: title,
        startsAtUtc: DateTime(
          localDay.year,
          localDay.month,
          localDay.day,
          hour,
        ).toUtc(),
        duration: Duration(minutes: minutes),
      ),
    );
  }

  setUp(() => id = 0);

  test('today stream reflects task changes immediately', () async {
    final PlanningDatabase database = PlanningDatabase(
      NativeDatabase.memory(),
    );
    final DriftPlanningRepository planning = planningRepository(database);
    addTearDown(() async {
      planning.dispose();
      await database.close();
    });

    final StreamIterator<List<ScheduledPlanningTask>> iterator =
        StreamIterator<List<ScheduledPlanningTask>>(
      planning.watchTasksForLocalDay(localDay),
    );
    addTearDown(iterator.cancel);

    expect(await iterator.moveNext(), isTrue);
    expect(iterator.current, isEmpty);

    final PlanningTask task = await createScheduledTask(
      planning,
      'Review today’s notes',
      10,
    );
    expect(await iterator.moveNext(), isTrue);
    expect(iterator.current.single.task.status, PlanningTaskStatus.pending);

    await planning.changeTaskStatus(task.id, PlanningTaskStatus.completed);
    expect(await iterator.moveNext(), isTrue);
    expect(iterator.current.single.task.status, PlanningTaskStatus.completed);
  });

  test('daily closure resolves unfinished tasks and saves real metrics',
      () async {
    final PlanningDatabase database = PlanningDatabase(
      NativeDatabase.memory(),
    );
    final DriftPlanningRepository planning = planningRepository(database);
    final DriftTodayRepository today = todayRepository(database);
    addTearDown(() async {
      planning.dispose();
      await database.close();
    });

    final PlanningTask completed = await createScheduledTask(
      planning,
      'Focused study',
      8,
    );
    final PlanningTask carried = await createScheduledTask(
      planning,
      'Finish exercises',
      10,
      minutes: 45,
    );
    final PlanningTask skipped = await createScheduledTask(
      planning,
      'Optional reading',
      12,
      minutes: 30,
    );
    await planning.changeTaskStatus(
      completed.id,
      PlanningTaskStatus.completed,
    );

    final DailyClosure closure = await today.closeDay(
      DailyClosureDraft(
        localDay: localDay,
        mood: 4,
        win: 'Completed the focused session',
        lesson: 'Start difficult work earlier',
        tomorrowFocus: 'Finish the exercises',
        taskResolutions: <String, DayTaskResolution>{
          carried.id: DayTaskResolution.moveToTomorrow,
          skipped.id: DayTaskResolution.skip,
        },
      ),
    );

    expect(closure.scheduledTaskCount, 3);
    expect(closure.completedTaskCount, 1);
    expect(closure.plannedMinutes, 135);
    expect(closure.completedMinutes, 60);
    expect(closure.mood, 4);

    final List<ScheduledPlanningTask> todayTasks =
        await planning.watchTasksForLocalDay(localDay).first;
    expect(
      todayTasks.map((ScheduledPlanningTask item) => item.task.id),
      containsAll(<String>[completed.id, skipped.id]),
    );
    expect(
      todayTasks
          .singleWhere(
              (ScheduledPlanningTask item) => item.task.id == skipped.id)
          .task
          .status,
      PlanningTaskStatus.skipped,
    );

    final DateTime tomorrow = DateTime(2026, 9, 6);
    final List<ScheduledPlanningTask> tomorrowTasks =
        await planning.watchTasksForLocalDay(tomorrow).first;
    expect(tomorrowTasks.single.task.id, carried.id);
    expect(tomorrowTasks.single.timeBlock!.duration.inMinutes, 45);
  });

  test('daily closure persists after the database is reopened', () async {
    final Directory directory = await Directory.systemTemp.createTemp(
      'gahunda-today-',
    );
    final File file = File('${directory.path}/today.sqlite');
    addTearDown(() => directory.delete(recursive: true));

    final PlanningDatabase firstDatabase = PlanningDatabase(
      NativeDatabase(file),
    );
    final DriftTodayRepository firstToday = todayRepository(firstDatabase);
    await firstToday.closeDay(
      DailyClosureDraft(
        localDay: localDay,
        mood: 5,
        win: 'Stayed consistent',
        tomorrowFocus: 'Prepare the weekly plan',
        taskResolutions: const <String, DayTaskResolution>{},
      ),
    );
    await firstDatabase.close();

    final PlanningDatabase reopenedDatabase = PlanningDatabase(
      NativeDatabase(file),
    );
    final DriftTodayRepository reopenedToday = todayRepository(
      reopenedDatabase,
    );
    addTearDown(reopenedDatabase.close);

    final DailyClosure? closure = await reopenedToday.getClosureForLocalDay(
      localDay,
    );
    expect(closure, isNotNull);
    expect(closure!.mood, 5);
    expect(closure.win, 'Stayed consistent');
    expect(closure.tomorrowFocus, 'Prepare the weekly plan');
  });

  test('today metrics are calculated from task status and time blocks', () {
    final DateTime start = DateTime.utc(2026, 9, 5, 8);
    ScheduledPlanningTask item(
      String id,
      PlanningTaskStatus status,
      int minutes,
    ) {
      return ScheduledPlanningTask(
        task: PlanningTask(
          id: id,
          title: id,
          kind: PlanningTaskKind.general,
          status: status,
          scheduledAtUtc: start,
          dueAtUtc: start.add(Duration(minutes: minutes)),
          createdAtUtc: start,
          updatedAtUtc: start,
        ),
      );
    }

    final TodayMetrics metrics = TodayMetrics.fromTasks(
      <ScheduledPlanningTask>[
        item('completed', PlanningTaskStatus.completed, 60),
        item('pending', PlanningTaskStatus.pending, 30),
        item('skipped', PlanningTaskStatus.skipped, 15),
      ],
    );

    expect(metrics.scheduledTaskCount, 3);
    expect(metrics.completedTaskCount, 1);
    expect(metrics.resolvedTaskCount, 2);
    expect(metrics.openTaskCount, 1);
    expect(metrics.plannedDuration.inMinutes, 105);
    expect(metrics.completedDuration.inMinutes, 60);
  });
}
