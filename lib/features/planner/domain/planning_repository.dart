import 'planning_entities.dart';

abstract interface class PlanningRepository {
  Stream<List<PlanningPath>> watchPlanningPaths();

  Stream<List<ScheduledPlanningTask>> watchTasksForLocalDay(DateTime localDay);

  Stream<List<PlanningTask>> watchUnscheduledTasks();

  Future<List<PlanningPath>> getPlanningPaths({bool includeArchived = false});

  Future<PlanningPath> createPlanningPath(PlanningPathDraft draft);

  Future<void> updatePlanningPath(PlanningPathEdits edits);

  Future<PlanningTask> createTask(PlanningTaskDraft draft);

  Future<void> rescheduleTask({
    required String taskId,
    required DateTime startsAtUtc,
    required DateTime endsAtUtc,
  });

  Future<void> unscheduleTask(String taskId);

  Future<void> changeTaskStatus(
    String taskId,
    PlanningTaskStatus status,
  );

  Future<void> archiveGoalPreservingHistory(String goalId);

  Future<List<PlanningTask>> getCompletedTaskHistory({String? goalId});
}
