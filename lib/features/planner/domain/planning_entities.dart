enum GoalScope { annual, monthly, weekly, daily }

enum GoalStatus { active, completed, archived }

enum MilestoneStatus { pending, inProgress, completed, skipped, cancelled }

enum PlanningTaskStatus {
  pending,
  inProgress,
  completed,
  skipped,
  cancelled,
}

enum PlanningTaskKind { general, assignment }

class Goal {
  const Goal({
    required this.id,
    required this.title,
    required this.scope,
    required this.status,
    required this.createdAtUtc,
    required this.updatedAtUtc,
    this.description,
    this.parentGoalId,
    this.startsAtUtc,
    this.dueAtUtc,
    this.archivedAtUtc,
  });

  final String id;
  final String title;
  final String? description;
  final GoalScope scope;
  final String? parentGoalId;
  final DateTime? startsAtUtc;
  final DateTime? dueAtUtc;
  final GoalStatus status;
  final DateTime createdAtUtc;
  final DateTime updatedAtUtc;
  final DateTime? archivedAtUtc;

  bool get isArchived => status == GoalStatus.archived;
}

class PlanPeriod {
  const PlanPeriod({
    required this.id,
    required this.label,
    required this.scope,
    required this.startsAtUtc,
    required this.endsAtUtc,
    this.goalId,
    this.parentPeriodId,
  });

  final String id;
  final String? goalId;
  final String? parentPeriodId;
  final String label;
  final GoalScope scope;
  final DateTime startsAtUtc;
  final DateTime endsAtUtc;
}

class Milestone {
  const Milestone({
    required this.id,
    required this.title,
    required this.scope,
    required this.status,
    required this.createdAtUtc,
    required this.updatedAtUtc,
    this.goalId,
    this.parentMilestoneId,
    this.planPeriodId,
    this.description,
    this.dueAtUtc,
  });

  final String id;
  final String? goalId;
  final String? parentMilestoneId;
  final String? planPeriodId;
  final String title;
  final String? description;
  final GoalScope scope;
  final DateTime? dueAtUtc;
  final MilestoneStatus status;
  final DateTime createdAtUtc;
  final DateTime updatedAtUtc;
}

class PlanningTask {
  const PlanningTask({
    required this.id,
    required this.title,
    required this.kind,
    required this.status,
    required this.createdAtUtc,
    required this.updatedAtUtc,
    this.goalId,
    this.milestoneId,
    this.subjectId,
    this.notes,
    this.scheduledAtUtc,
    this.dueAtUtc,
    this.completedAtUtc,
  });

  final String id;
  final String? goalId;
  final String? milestoneId;
  final String? subjectId;
  final String title;
  final String? notes;
  final PlanningTaskKind kind;
  final PlanningTaskStatus status;
  final DateTime? scheduledAtUtc;
  final DateTime? dueAtUtc;
  final DateTime? completedAtUtc;
  final DateTime createdAtUtc;
  final DateTime updatedAtUtc;

  bool get isScheduled => scheduledAtUtc != null;

  bool get isFinished =>
      status == PlanningTaskStatus.completed ||
      status == PlanningTaskStatus.skipped ||
      status == PlanningTaskStatus.cancelled;
}

class TimeBlock {
  const TimeBlock({
    required this.id,
    required this.title,
    required this.startsAtUtc,
    required this.endsAtUtc,
    required this.createdAtUtc,
    required this.updatedAtUtc,
    this.taskId,
    this.notes,
  });

  final String id;
  final String? taskId;
  final String title;
  final String? notes;
  final DateTime startsAtUtc;
  final DateTime endsAtUtc;
  final DateTime createdAtUtc;
  final DateTime updatedAtUtc;

  Duration get duration => endsAtUtc.difference(startsAtUtc);
}

class ScheduledPlanningTask {
  const ScheduledPlanningTask({required this.task, this.timeBlock});

  final PlanningTask task;
  final TimeBlock? timeBlock;

  DateTime? get startsAtUtc => timeBlock?.startsAtUtc ?? task.scheduledAtUtc;

  DateTime? get endsAtUtc => timeBlock?.endsAtUtc ?? task.dueAtUtc;
}

class PlanningPath {
  const PlanningPath({
    required this.goal,
    required this.periods,
    required this.milestones,
    required this.tasks,
    required this.timeBlocks,
  });

  final Goal goal;
  final List<PlanPeriod> periods;
  final List<Milestone> milestones;
  final List<PlanningTask> tasks;
  final List<TimeBlock> timeBlocks;

  Milestone? milestoneForScope(GoalScope scope) {
    for (final Milestone milestone in milestones) {
      if (milestone.scope == scope) return milestone;
    }
    return null;
  }

  PlanningTask? get firstTask => tasks.isEmpty ? null : tasks.first;

  TimeBlock? timeBlockForTask(String taskId) {
    for (final TimeBlock block in timeBlocks) {
      if (block.taskId == taskId) return block;
    }
    return null;
  }
}

class PlanningPathDraft {
  const PlanningPathDraft({
    required this.annualGoalTitle,
    required this.monthlyMilestoneTitle,
    required this.weeklyOutcomeTitle,
    required this.taskTitle,
    required this.taskStartsAtUtc,
    this.taskDuration = const Duration(hours: 1),
  });

  final String annualGoalTitle;
  final String monthlyMilestoneTitle;
  final String weeklyOutcomeTitle;
  final String taskTitle;
  final DateTime taskStartsAtUtc;
  final Duration taskDuration;
}

class PlanningPathEdits {
  const PlanningPathEdits({
    required this.goalId,
    required this.annualGoalTitle,
    required this.monthlyMilestoneId,
    required this.monthlyMilestoneTitle,
    required this.weeklyMilestoneId,
    required this.weeklyOutcomeTitle,
    required this.taskId,
    required this.taskTitle,
  });

  final String goalId;
  final String annualGoalTitle;
  final String monthlyMilestoneId;
  final String monthlyMilestoneTitle;
  final String weeklyMilestoneId;
  final String weeklyOutcomeTitle;
  final String taskId;
  final String taskTitle;
}

class PlanningTaskDraft {
  const PlanningTaskDraft({
    required this.title,
    this.goalId,
    this.milestoneId,
    this.subjectId,
    this.notes,
    this.kind = PlanningTaskKind.general,
    this.startsAtUtc,
    this.duration = const Duration(hours: 1),
  });

  final String title;
  final String? goalId;
  final String? milestoneId;
  final String? subjectId;
  final String? notes;
  final PlanningTaskKind kind;
  final DateTime? startsAtUtc;
  final Duration duration;
}
