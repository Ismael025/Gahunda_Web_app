import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gahunda/features/planner/data/drift_planning_repository.dart';
import 'package:gahunda/features/planner/data/planning_database.dart';
import 'package:gahunda/features/planner/domain/planning_entities.dart';

void main() {
  final DateTime fixedNow = DateTime.utc(2026, 9, 5, 8);
  int id = 0;

  DriftPlanningRepository createRepository(PlanningDatabase database) {
    return DriftPlanningRepository(
      database,
      clock: () => fixedNow,
      idFactory: (String prefix) => '$prefix-${id++}',
    );
  }

  PlanningPathDraft acceptanceDraft() {
    return PlanningPathDraft(
      annualGoalTitle: 'Complete the school year successfully',
      monthlyMilestoneTitle: 'Build a stable study routine',
      weeklyOutcomeTitle: 'Complete three focused sessions',
      taskTitle: 'Review chapter 3 for 60 minutes',
      taskStartsAtUtc: DateTime.utc(2026, 9, 5, 14),
    );
  }

  setUp(() => id = 0);

  test('creates the annual-to-daily hierarchy in one transaction', () async {
    final PlanningDatabase database = PlanningDatabase(NativeDatabase.memory());
    final DriftPlanningRepository repository = createRepository(database);
    addTearDown(() async {
      repository.dispose();
      await database.close();
    });

    final PlanningPath path = await repository.createPlanningPath(
      acceptanceDraft(),
    );

    expect(path.goal.scope, GoalScope.annual);
    expect(path.periods, hasLength(3));
    expect(path.milestones, hasLength(2));
    final Milestone monthly = path.milestoneForScope(GoalScope.monthly)!;
    final Milestone weekly = path.milestoneForScope(GoalScope.weekly)!;
    expect(monthly.goalId, path.goal.id);
    expect(weekly.goalId, path.goal.id);
    expect(weekly.parentMilestoneId, monthly.id);
    expect(path.tasks, hasLength(1));
    expect(path.firstTask!.goalId, path.goal.id);
    expect(path.firstTask!.milestoneId, weekly.id);
    expect(path.timeBlockForTask(path.firstTask!.id), isNotNull);
  });

  test('relationships persist after closing and reopening SQLite', () async {
    final Directory directory = await Directory.systemTemp.createTemp(
      'gahunda-planning-',
    );
    final File file = File('${directory.path}/planning.sqlite');
    addTearDown(() => directory.delete(recursive: true));

    final PlanningDatabase firstDatabase = PlanningDatabase(
      NativeDatabase(file),
    );
    final DriftPlanningRepository firstRepository = createRepository(
      firstDatabase,
    );
    final PlanningPath created = await firstRepository.createPlanningPath(
      acceptanceDraft(),
    );
    final String goalId = created.goal.id;
    final String monthlyId = created.milestoneForScope(GoalScope.monthly)!.id;
    final String weeklyId = created.milestoneForScope(GoalScope.weekly)!.id;
    final String taskId = created.firstTask!.id;
    firstRepository.dispose();
    await firstDatabase.close();

    final PlanningDatabase reopenedDatabase = PlanningDatabase(
      NativeDatabase(file),
    );
    final DriftPlanningRepository reopenedRepository = createRepository(
      reopenedDatabase,
    );
    addTearDown(() async {
      reopenedRepository.dispose();
      await reopenedDatabase.close();
    });

    final PlanningPath reopened =
        (await reopenedRepository.getPlanningPaths()).single;
    expect(reopened.goal.id, goalId);
    expect(
      reopened.milestoneForScope(GoalScope.monthly)!.id,
      monthlyId,
    );
    expect(
      reopened.milestoneForScope(GoalScope.weekly)!.parentMilestoneId,
      monthlyId,
    );
    expect(reopened.milestoneForScope(GoalScope.weekly)!.id, weeklyId);
    expect(reopened.firstTask!.id, taskId);
    expect(reopened.firstTask!.milestoneId, weeklyId);
    expect(reopened.timeBlockForTask(taskId), isNotNull);
  });

  test('supports unscheduled tasks and rescheduling unfinished tasks',
      () async {
    final PlanningDatabase database = PlanningDatabase(NativeDatabase.memory());
    final DriftPlanningRepository repository = createRepository(database);
    addTearDown(() async {
      repository.dispose();
      await database.close();
    });

    final PlanningTask task = await repository.createTask(
      const PlanningTaskDraft(title: 'Read database notes'),
    );
    expect(task.isScheduled, isFalse);
    expect(await repository.watchUnscheduledTasks().first, hasLength(1));

    final DateTime newStart = DateTime.utc(2026, 9, 6, 16);
    await repository.rescheduleTask(
      taskId: task.id,
      startsAtUtc: newStart,
      endsAtUtc: newStart.add(const Duration(minutes: 90)),
    );

    final List<ScheduledPlanningTask> scheduled =
        await repository.watchTasksForLocalDay(newStart.toLocal()).first;
    expect(scheduled, hasLength(1));
    expect(scheduled.single.task.id, task.id);
    expect(scheduled.single.timeBlock!.duration, const Duration(minutes: 90));
  });

  test('edits every title in an existing planning path', () async {
    final PlanningDatabase database = PlanningDatabase(NativeDatabase.memory());
    final DriftPlanningRepository repository = createRepository(database);
    addTearDown(() async {
      repository.dispose();
      await database.close();
    });
    final PlanningPath original = await repository.createPlanningPath(
      acceptanceDraft(),
    );
    final Milestone monthly = original.milestoneForScope(GoalScope.monthly)!;
    final Milestone weekly = original.milestoneForScope(GoalScope.weekly)!;

    await repository.updatePlanningPath(
      PlanningPathEdits(
        goalId: original.goal.id,
        annualGoalTitle: 'Pass the school year with strong results',
        monthlyMilestoneId: monthly.id,
        monthlyMilestoneTitle: 'Complete the database module',
        weeklyMilestoneId: weekly.id,
        weeklyOutcomeTitle: 'Finish chapter 4 exercises',
        taskId: original.firstTask!.id,
        taskTitle: 'Solve normalization exercises',
      ),
    );

    final PlanningPath updated = (await repository.getPlanningPaths()).single;
    expect(updated.goal.title, 'Pass the school year with strong results');
    expect(
      updated.milestoneForScope(GoalScope.monthly)!.title,
      'Complete the database module',
    );
    expect(
      updated.milestoneForScope(GoalScope.weekly)!.title,
      'Finish chapter 4 exercises',
    );
    expect(updated.firstTask!.title, 'Solve normalization exercises');
    expect(
      updated.timeBlockForTask(updated.firstTask!.id)!.title,
      'Solve normalization exercises',
    );
  });

  test('archives a goal without deleting completed history', () async {
    final PlanningDatabase database = PlanningDatabase(NativeDatabase.memory());
    final DriftPlanningRepository repository = createRepository(database);
    addTearDown(() async {
      repository.dispose();
      await database.close();
    });
    final PlanningPath path = await repository.createPlanningPath(
      acceptanceDraft(),
    );

    await repository.changeTaskStatus(
      path.firstTask!.id,
      PlanningTaskStatus.completed,
    );
    await repository.archiveGoalPreservingHistory(path.goal.id);

    expect(await repository.getPlanningPaths(), isEmpty);
    final List<PlanningPath> archived = await repository.getPlanningPaths(
      includeArchived: true,
    );
    expect(archived.single.goal.status, GoalStatus.archived);
    final List<PlanningTask> history = await repository.getCompletedTaskHistory(
      goalId: path.goal.id,
    );
    expect(history.single.id, path.firstTask!.id);
    expect(history.single.goalId, path.goal.id);
  });

  test('assignments require a subject link', () async {
    final PlanningDatabase database = PlanningDatabase(NativeDatabase.memory());
    final DriftPlanningRepository repository = createRepository(database);
    addTearDown(() async {
      repository.dispose();
      await database.close();
    });

    expect(
      () => repository.createTask(
        const PlanningTaskDraft(
          title: 'Submit database assignment',
          kind: PlanningTaskKind.assignment,
        ),
      ),
      throwsArgumentError,
    );

    final PlanningTask assignment = await repository.createTask(
      const PlanningTaskDraft(
        title: 'Submit database assignment',
        kind: PlanningTaskKind.assignment,
        subjectId: 'subject-database-systems',
      ),
    );
    expect(assignment.subjectId, 'subject-database-systems');
  });
}
