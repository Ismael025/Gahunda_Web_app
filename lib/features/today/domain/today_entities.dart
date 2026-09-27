import '../../planner/domain/planning_entities.dart';

enum DayTaskResolution { keepOpen, moveToTomorrow, skip, cancel }

class TodayMetrics {
  const TodayMetrics({
    required this.scheduledTaskCount,
    required this.completedTaskCount,
    required this.resolvedTaskCount,
    required this.plannedDuration,
    required this.completedDuration,
  });

  factory TodayMetrics.fromTasks(List<ScheduledPlanningTask> tasks) {
    Duration planned = Duration.zero;
    Duration completed = Duration.zero;
    int completedCount = 0;
    int resolvedCount = 0;

    for (final ScheduledPlanningTask item in tasks) {
      final Duration duration = _durationOf(item);
      planned += duration;
      if (item.task.status == PlanningTaskStatus.completed) {
        completedCount += 1;
        completed += duration;
      }
      if (item.task.isFinished) resolvedCount += 1;
    }

    return TodayMetrics(
      scheduledTaskCount: tasks.length,
      completedTaskCount: completedCount,
      resolvedTaskCount: resolvedCount,
      plannedDuration: planned,
      completedDuration: completed,
    );
  }

  final int scheduledTaskCount;
  final int completedTaskCount;
  final int resolvedTaskCount;
  final Duration plannedDuration;
  final Duration completedDuration;

  int get openTaskCount => scheduledTaskCount - resolvedTaskCount;

  double get completionProgress =>
      scheduledTaskCount == 0 ? 0 : completedTaskCount / scheduledTaskCount;

  double get resolutionProgress =>
      scheduledTaskCount == 0 ? 0 : resolvedTaskCount / scheduledTaskCount;

  double get completedTimeProgress => plannedDuration.inMinutes == 0
      ? 0
      : completedDuration.inMinutes / plannedDuration.inMinutes;
}

class DailyClosure {
  const DailyClosure({
    required this.id,
    required this.localDay,
    required this.mood,
    required this.scheduledTaskCount,
    required this.completedTaskCount,
    required this.plannedMinutes,
    required this.completedMinutes,
    required this.closedAtUtc,
    required this.createdAtUtc,
    required this.updatedAtUtc,
    this.win,
    this.lesson,
    this.tomorrowFocus,
  });

  final String id;
  final DateTime localDay;
  final int mood;
  final String? win;
  final String? lesson;
  final String? tomorrowFocus;
  final int scheduledTaskCount;
  final int completedTaskCount;
  final int plannedMinutes;
  final int completedMinutes;
  final DateTime closedAtUtc;
  final DateTime createdAtUtc;
  final DateTime updatedAtUtc;
}

class DailyClosureDraft {
  const DailyClosureDraft({
    required this.localDay,
    required this.mood,
    required this.taskResolutions,
    this.win,
    this.lesson,
    this.tomorrowFocus,
  });

  final DateTime localDay;
  final int mood;
  final String? win;
  final String? lesson;
  final String? tomorrowFocus;
  final Map<String, DayTaskResolution> taskResolutions;
}

Duration _durationOf(ScheduledPlanningTask item) {
  final DateTime? start = item.startsAtUtc;
  final DateTime? end = item.endsAtUtc;
  if (start == null || end == null || !end.isAfter(start)) {
    return Duration.zero;
  }
  return end.difference(start);
}
