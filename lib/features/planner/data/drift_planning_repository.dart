import 'dart:async';
import 'dart:math';

import 'package:drift/drift.dart';

import '../domain/planning_entities.dart';
import '../domain/planning_repository.dart';
import 'planning_database.dart';

typedef UtcClock = DateTime Function();
typedef LocalIdFactory = String Function(String prefix);

final class DriftPlanningRepository implements PlanningRepository {
  DriftPlanningRepository(
    this._database, {
    UtcClock? clock,
    LocalIdFactory? idFactory,
  })  : _clock = clock ?? DateTime.now,
        _idFactory = idFactory;

  final PlanningDatabase _database;
  final UtcClock _clock;
  final LocalIdFactory? _idFactory;
  final Random _random = Random.secure();
  int _idCounter = 0;

  void dispose() {}

  @override
  Stream<List<PlanningPath>> watchPlanningPaths() {
    return _database.watchQuery(getPlanningPaths);
  }

  @override
  Stream<List<ScheduledPlanningTask>> watchTasksForLocalDay(
    DateTime localDay,
  ) {
    return _database.watchQuery(
      () => _getTasksForLocalDay(localDay),
    );
  }

  @override
  Stream<List<PlanningTask>> watchUnscheduledTasks() {
    return _database.watchQuery(_getUnscheduledTasks);
  }

  @override
  Future<List<PlanningPath>> getPlanningPaths({
    bool includeArchived = false,
  }) async {
    final String goalFilter = includeArchived
        ? ''
        : "WHERE status != 'archived' AND archived_at_utc IS NULL";
    final List<Goal> goals = (await _database.readRows('''
      SELECT * FROM goals
      $goalFilter
      ORDER BY created_at_utc ASC
    ''')).map(_goalFromRow).toList(growable: false);

    if (goals.isEmpty) return const <PlanningPath>[];

    final List<PlanPeriod> periods = (await _database.readRows(
      'SELECT * FROM plan_periods ORDER BY starts_at_utc ASC',
    ))
        .map(_periodFromRow)
        .toList(growable: false);
    final List<Milestone> milestones = (await _database.readRows(
      'SELECT * FROM milestones ORDER BY created_at_utc ASC',
    ))
        .map(_milestoneFromRow)
        .toList(growable: false);
    final List<PlanningTask> tasks = (await _database.readRows('''
      SELECT * FROM planning_tasks
      WHERE deleted_at_utc IS NULL
      ORDER BY created_at_utc ASC
    ''')).map(_taskFromRow).toList(growable: false);
    final List<TimeBlock> timeBlocks = (await _database.readRows(
      'SELECT * FROM time_blocks ORDER BY starts_at_utc ASC',
    ))
        .map(_timeBlockFromRow)
        .toList(growable: false);

    return goals.map((Goal goal) {
      final List<Milestone> goalMilestones = milestones
          .where((Milestone milestone) => milestone.goalId == goal.id)
          .toList(growable: false);
      final Set<String> milestoneIds =
          goalMilestones.map((Milestone milestone) => milestone.id).toSet();
      final List<PlanningTask> goalTasks = tasks
          .where(
            (PlanningTask task) =>
                task.goalId == goal.id ||
                milestoneIds.contains(task.milestoneId),
          )
          .toList(growable: false);
      final Set<String> taskIds =
          goalTasks.map((PlanningTask task) => task.id).toSet();

      return PlanningPath(
        goal: goal,
        periods: periods
            .where((PlanPeriod period) => period.goalId == goal.id)
            .toList(growable: false),
        milestones: goalMilestones,
        tasks: goalTasks,
        timeBlocks: timeBlocks
            .where((TimeBlock block) => taskIds.contains(block.taskId))
            .toList(growable: false),
      );
    }).toList(growable: false);
  }

  @override
  Future<PlanningPath> createPlanningPath(PlanningPathDraft draft) async {
    final String annualTitle = _requiredTitle(
      draft.annualGoalTitle,
      'Annual goal',
    );
    final String monthlyTitle = _requiredTitle(
      draft.monthlyMilestoneTitle,
      'Monthly milestone',
    );
    final String weeklyTitle = _requiredTitle(
      draft.weeklyOutcomeTitle,
      'Weekly outcome',
    );
    final String taskTitle = _requiredTitle(draft.taskTitle, 'Task');
    if (draft.taskDuration <= Duration.zero) {
      throw ArgumentError.value(
        draft.taskDuration,
        'taskDuration',
        'Task duration must be greater than zero.',
      );
    }

    final DateTime now = _clock().toUtc();
    final DateTime taskStart = draft.taskStartsAtUtc.toUtc();
    final DateTime taskEnd = taskStart.add(draft.taskDuration);
    final DateTime annualStart = DateTime.utc(taskStart.year);
    final DateTime annualEnd = DateTime.utc(taskStart.year + 1);
    final DateTime monthStart = DateTime.utc(taskStart.year, taskStart.month);
    final DateTime monthEnd = DateTime.utc(taskStart.year, taskStart.month + 1);
    final DateTime weekStart = _startOfUtcWeek(taskStart);
    final DateTime weekEnd = weekStart.add(const Duration(days: 7));

    final String goalId = _newId('goal');
    final String annualPeriodId = _newId('period');
    final String monthlyPeriodId = _newId('period');
    final String weeklyPeriodId = _newId('period');
    final String monthlyMilestoneId = _newId('milestone');
    final String weeklyMilestoneId = _newId('milestone');
    final String taskId = _newId('task');
    final String blockId = _newId('block');

    await _database.transaction(() async {
      await _insertGoal(
        id: goalId,
        title: annualTitle,
        scope: GoalScope.annual,
        startsAtUtc: annualStart,
        dueAtUtc: annualEnd,
        now: now,
      );
      await _insertPeriod(
        id: annualPeriodId,
        goalId: goalId,
        label: '${taskStart.year}',
        scope: GoalScope.annual,
        startsAtUtc: annualStart,
        endsAtUtc: annualEnd,
      );
      await _insertPeriod(
        id: monthlyPeriodId,
        goalId: goalId,
        parentPeriodId: annualPeriodId,
        label: _monthLabel(taskStart),
        scope: GoalScope.monthly,
        startsAtUtc: monthStart,
        endsAtUtc: monthEnd,
      );
      await _insertPeriod(
        id: weeklyPeriodId,
        goalId: goalId,
        parentPeriodId: monthlyPeriodId,
        label: 'Week of ${_shortDate(weekStart)}',
        scope: GoalScope.weekly,
        startsAtUtc: weekStart,
        endsAtUtc: weekEnd,
      );
      await _insertMilestone(
        id: monthlyMilestoneId,
        goalId: goalId,
        planPeriodId: monthlyPeriodId,
        title: monthlyTitle,
        scope: GoalScope.monthly,
        dueAtUtc: monthEnd,
        now: now,
      );
      await _insertMilestone(
        id: weeklyMilestoneId,
        goalId: goalId,
        parentMilestoneId: monthlyMilestoneId,
        planPeriodId: weeklyPeriodId,
        title: weeklyTitle,
        scope: GoalScope.weekly,
        dueAtUtc: weekEnd,
        now: now,
      );
      await _insertTask(
        id: taskId,
        goalId: goalId,
        milestoneId: weeklyMilestoneId,
        title: taskTitle,
        kind: PlanningTaskKind.general,
        startsAtUtc: taskStart,
        dueAtUtc: taskEnd,
        now: now,
      );
      await _insertTimeBlock(
        id: blockId,
        taskId: taskId,
        title: taskTitle,
        startsAtUtc: taskStart,
        endsAtUtc: taskEnd,
        now: now,
      );
    });

    _notifyChanged();
    final List<PlanningPath> paths = await getPlanningPaths();
    return paths.singleWhere((PlanningPath path) => path.goal.id == goalId);
  }

  @override
  Future<void> updatePlanningPath(PlanningPathEdits edits) async {
    final String goalTitle =
        _requiredTitle(edits.annualGoalTitle, 'Annual goal');
    final String monthlyTitle = _requiredTitle(
      edits.monthlyMilestoneTitle,
      'Monthly milestone',
    );
    final String weeklyTitle = _requiredTitle(
      edits.weeklyOutcomeTitle,
      'Weekly outcome',
    );
    final String taskTitle = _requiredTitle(edits.taskTitle, 'Task');
    final DateTime now = _clock().toUtc();

    await _database.transaction(() async {
      await _requireUpdated(
        _database.updateRows(
          'UPDATE goals SET title = ?, updated_at_utc = ? WHERE id = ?',
          variables: _strings(<String>[goalTitle, _utc(now), edits.goalId]),
        ),
        'Goal',
      );
      await _requireUpdated(
        _database.updateRows(
          'UPDATE milestones SET title = ?, updated_at_utc = ? WHERE id = ?',
          variables: _strings(
            <String>[monthlyTitle, _utc(now), edits.monthlyMilestoneId],
          ),
        ),
        'Monthly milestone',
      );
      await _requireUpdated(
        _database.updateRows(
          'UPDATE milestones SET title = ?, updated_at_utc = ? WHERE id = ?',
          variables: _strings(
            <String>[weeklyTitle, _utc(now), edits.weeklyMilestoneId],
          ),
        ),
        'Weekly milestone',
      );
      await _requireUpdated(
        _database.updateRows(
          'UPDATE planning_tasks SET title = ?, updated_at_utc = ? WHERE id = ?',
          variables: _strings(<String>[taskTitle, _utc(now), edits.taskId]),
        ),
        'Task',
      );
      await _database.updateRows(
        'UPDATE time_blocks SET title = ?, updated_at_utc = ? WHERE task_id = ?',
        variables: _strings(<String>[taskTitle, _utc(now), edits.taskId]),
      );
    });
    _notifyChanged();
  }

  @override
  Future<PlanningTask> createTask(PlanningTaskDraft draft) async {
    final String title = _requiredTitle(draft.title, 'Task');
    if (draft.kind == PlanningTaskKind.assignment &&
        (draft.subjectId == null || draft.subjectId!.trim().isEmpty)) {
      throw ArgumentError(
        'A school assignment must link to a subject.',
        'subjectId',
      );
    }
    if (draft.startsAtUtc != null && draft.duration <= Duration.zero) {
      throw ArgumentError.value(
        draft.duration,
        'duration',
        'Scheduled task duration must be greater than zero.',
      );
    }

    final DateTime now = _clock().toUtc();
    final DateTime? startsAtUtc = draft.startsAtUtc?.toUtc();
    final DateTime? endsAtUtc = startsAtUtc?.add(draft.duration);
    final String taskId = _newId('task');

    await _database.transaction(() async {
      await _insertTask(
        id: taskId,
        goalId: draft.goalId,
        milestoneId: draft.milestoneId,
        subjectId: draft.subjectId,
        title: title,
        notes: draft.notes,
        kind: draft.kind,
        startsAtUtc: startsAtUtc,
        dueAtUtc: endsAtUtc,
        now: now,
      );
      if (startsAtUtc != null && endsAtUtc != null) {
        await _insertTimeBlock(
          id: _newId('block'),
          taskId: taskId,
          title: title,
          notes: draft.notes,
          startsAtUtc: startsAtUtc,
          endsAtUtc: endsAtUtc,
          now: now,
        );
      }
    });
    _notifyChanged();
    return _readTask(taskId);
  }

  @override
  Future<void> rescheduleTask({
    required String taskId,
    required DateTime startsAtUtc,
    required DateTime endsAtUtc,
  }) async {
    final DateTime start = startsAtUtc.toUtc();
    final DateTime end = endsAtUtc.toUtc();
    if (!end.isAfter(start)) {
      throw ArgumentError('A time block must end after it starts.');
    }
    final PlanningTask task = await _readTask(taskId);
    if (task.status == PlanningTaskStatus.completed ||
        task.status == PlanningTaskStatus.cancelled) {
      throw StateError('Completed or cancelled tasks cannot be rescheduled.');
    }
    final DateTime now = _clock().toUtc();

    await _database.transaction(() async {
      await _requireUpdated(
        _database.updateRows('''
          UPDATE planning_tasks
          SET scheduled_at_utc = ?, due_at_utc = ?, status = 'pending',
              updated_at_utc = ?
          WHERE id = ? AND deleted_at_utc IS NULL
        ''',
            variables: _strings(<String>[
              _utc(start),
              _utc(end),
              _utc(now),
              taskId,
            ])),
        'Task',
      );
      await _database.insertRow('''
        INSERT INTO time_blocks (
          id, task_id, title, notes, starts_at_utc, ends_at_utc,
          created_at_utc, updated_at_utc
        ) VALUES (?, ?, ?, NULLIF(?, ''), ?, ?, ?, ?)
        ON CONFLICT(task_id) DO UPDATE SET
          title = excluded.title,
          notes = excluded.notes,
          starts_at_utc = excluded.starts_at_utc,
          ends_at_utc = excluded.ends_at_utc,
          updated_at_utc = excluded.updated_at_utc
      ''',
          variables: _strings(<String>[
            _newId('block'),
            taskId,
            task.title,
            task.notes ?? '',
            _utc(start),
            _utc(end),
            _utc(now),
            _utc(now),
          ]));
    });
    _notifyChanged();
  }

  @override
  Future<void> unscheduleTask(String taskId) async {
    final DateTime now = _clock().toUtc();
    await _database.transaction(() async {
      await _requireUpdated(
        _database.updateRows('''
          UPDATE planning_tasks
          SET scheduled_at_utc = NULL, due_at_utc = NULL, updated_at_utc = ?
          WHERE id = ? AND deleted_at_utc IS NULL
        ''', variables: _strings(<String>[_utc(now), taskId])),
        'Task',
      );
      await _database.updateRows(
        'DELETE FROM time_blocks WHERE task_id = ?',
        variables: _strings(<String>[taskId]),
      );
    });
    _notifyChanged();
  }

  @override
  Future<void> changeTaskStatus(
    String taskId,
    PlanningTaskStatus status,
  ) async {
    final DateTime now = _clock().toUtc();
    final String completedAt =
        status == PlanningTaskStatus.completed ? _utc(now) : '';
    await _requireUpdated(
      _database.updateRows('''
        UPDATE planning_tasks
        SET status = ?, completed_at_utc = NULLIF(?, ''), updated_at_utc = ?
        WHERE id = ? AND deleted_at_utc IS NULL
      ''',
          variables: _strings(<String>[
            status.name,
            completedAt,
            _utc(now),
            taskId,
          ])),
      'Task',
    );
    _notifyChanged();
  }

  @override
  Future<void> archiveGoalPreservingHistory(String goalId) async {
    final DateTime now = _clock().toUtc();
    await _requireUpdated(
      _database.updateRows('''
        UPDATE goals
        SET status = 'archived', archived_at_utc = ?, updated_at_utc = ?
        WHERE id = ?
      ''', variables: _strings(<String>[_utc(now), _utc(now), goalId])),
      'Goal',
    );
    _notifyChanged();
  }

  @override
  Future<List<PlanningTask>> getCompletedTaskHistory({String? goalId}) async {
    final String goalClause = goalId == null ? '' : 'AND goal_id = ?';
    final List<QueryRow> rows = await _database.readRows('''
      SELECT * FROM planning_tasks
      WHERE status = 'completed' $goalClause
      ORDER BY completed_at_utc DESC
    ''',
        variables: goalId == null
            ? const <Variable<Object>>[]
            : _strings(<String>[goalId]));
    return rows.map(_taskFromRow).toList(growable: false);
  }

  Future<List<ScheduledPlanningTask>> _getTasksForLocalDay(
    DateTime localDay,
  ) async {
    final DateTime localStart = DateTime(
      localDay.year,
      localDay.month,
      localDay.day,
    );
    final DateTime startUtc = localStart.toUtc();
    final DateTime endUtc = DateTime(
      localDay.year,
      localDay.month,
      localDay.day + 1,
    ).toUtc();
    final List<QueryRow> rows = await _database.readRows('''
      SELECT
        t.*,
        b.id AS block_id,
        b.task_id AS block_task_id,
        b.title AS block_title,
        b.notes AS block_notes,
        b.starts_at_utc AS block_starts_at_utc,
        b.ends_at_utc AS block_ends_at_utc,
        b.created_at_utc AS block_created_at_utc,
        b.updated_at_utc AS block_updated_at_utc
      FROM planning_tasks t
      LEFT JOIN time_blocks b ON b.task_id = t.id
      LEFT JOIN goals g ON g.id = t.goal_id
      WHERE t.deleted_at_utc IS NULL
        AND (t.goal_id IS NULL OR g.status != 'archived')
        AND (
          (b.starts_at_utc >= ? AND b.starts_at_utc < ?)
          OR
          (b.id IS NULL AND t.scheduled_at_utc >= ? AND t.scheduled_at_utc < ?)
        )
      ORDER BY COALESCE(b.starts_at_utc, t.scheduled_at_utc) ASC
    ''',
        variables: _strings(<String>[
          _utc(startUtc),
          _utc(endUtc),
          _utc(startUtc),
          _utc(endUtc),
        ]));

    return rows.map((QueryRow row) {
      final String? blockId = row.readNullable<String>('block_id');
      return ScheduledPlanningTask(
        task: _taskFromRow(row),
        timeBlock: blockId == null ? null : _timeBlockFromJoinedRow(row),
      );
    }).toList(growable: false);
  }

  Future<List<PlanningTask>> _getUnscheduledTasks() async {
    final List<QueryRow> rows = await _database.readRows('''
      SELECT t.*
      FROM planning_tasks t
      LEFT JOIN time_blocks b ON b.task_id = t.id
      LEFT JOIN goals g ON g.id = t.goal_id
      WHERE t.deleted_at_utc IS NULL
        AND (t.goal_id IS NULL OR g.status != 'archived')
        AND t.scheduled_at_utc IS NULL
        AND b.id IS NULL
        AND t.status IN ('pending', 'inProgress')
      ORDER BY t.created_at_utc ASC
    ''');
    return rows.map(_taskFromRow).toList(growable: false);
  }

  Future<PlanningTask> _readTask(String taskId) async {
    final List<QueryRow> rows = await _database.readRows('''
      SELECT * FROM planning_tasks
      WHERE id = ? AND deleted_at_utc IS NULL
    ''', variables: _strings(<String>[taskId]));
    if (rows.isEmpty) throw StateError('Task not found: $taskId');
    return _taskFromRow(rows.single);
  }

  Future<void> _insertGoal({
    required String id,
    required String title,
    required GoalScope scope,
    required DateTime startsAtUtc,
    required DateTime dueAtUtc,
    required DateTime now,
  }) async {
    await _database.insertRow('''
      INSERT INTO goals (
        id, title, description, scope, parent_goal_id, starts_at_utc,
        due_at_utc, status, created_at_utc, updated_at_utc, archived_at_utc
      ) VALUES (?, ?, NULL, ?, NULL, ?, ?, 'active', ?, ?, NULL)
    ''',
        variables: _strings(<String>[
          id,
          title,
          scope.name,
          _utc(startsAtUtc),
          _utc(dueAtUtc),
          _utc(now),
          _utc(now),
        ]));
  }

  Future<void> _insertPeriod({
    required String id,
    required String goalId,
    required String label,
    required GoalScope scope,
    required DateTime startsAtUtc,
    required DateTime endsAtUtc,
    String? parentPeriodId,
  }) async {
    await _database.insertRow('''
      INSERT INTO plan_periods (
        id, goal_id, parent_period_id, label, scope, starts_at_utc, ends_at_utc
      ) VALUES (?, ?, NULLIF(?, ''), ?, ?, ?, ?)
    ''',
        variables: _strings(<String>[
          id,
          goalId,
          parentPeriodId ?? '',
          label,
          scope.name,
          _utc(startsAtUtc),
          _utc(endsAtUtc),
        ]));
  }

  Future<void> _insertMilestone({
    required String id,
    required String goalId,
    required String planPeriodId,
    required String title,
    required GoalScope scope,
    required DateTime dueAtUtc,
    required DateTime now,
    String? parentMilestoneId,
  }) async {
    await _database.insertRow('''
      INSERT INTO milestones (
        id, goal_id, parent_milestone_id, plan_period_id, title,
        description, scope, due_at_utc, status, created_at_utc, updated_at_utc
      ) VALUES (?, ?, NULLIF(?, ''), ?, ?, NULL, ?, ?, 'pending', ?, ?)
    ''',
        variables: _strings(<String>[
          id,
          goalId,
          parentMilestoneId ?? '',
          planPeriodId,
          title,
          scope.name,
          _utc(dueAtUtc),
          _utc(now),
          _utc(now),
        ]));
  }

  Future<void> _insertTask({
    required String id,
    required String title,
    required PlanningTaskKind kind,
    required DateTime now,
    String? goalId,
    String? milestoneId,
    String? subjectId,
    String? notes,
    DateTime? startsAtUtc,
    DateTime? dueAtUtc,
  }) async {
    await _database.insertRow('''
      INSERT INTO planning_tasks (
        id, goal_id, milestone_id, subject_id, title, notes, kind, status,
        scheduled_at_utc, due_at_utc, completed_at_utc, created_at_utc,
        updated_at_utc, deleted_at_utc
      ) VALUES (
        ?, NULLIF(?, ''), NULLIF(?, ''), NULLIF(?, ''), ?, NULLIF(?, ''),
        ?, 'pending', NULLIF(?, ''), NULLIF(?, ''), NULL, ?, ?, NULL
      )
    ''',
        variables: _strings(<String>[
          id,
          goalId ?? '',
          milestoneId ?? '',
          subjectId ?? '',
          title,
          notes ?? '',
          kind.name,
          startsAtUtc == null ? '' : _utc(startsAtUtc),
          dueAtUtc == null ? '' : _utc(dueAtUtc),
          _utc(now),
          _utc(now),
        ]));
  }

  Future<void> _insertTimeBlock({
    required String id,
    required String taskId,
    required String title,
    required DateTime startsAtUtc,
    required DateTime endsAtUtc,
    required DateTime now,
    String? notes,
  }) async {
    await _database.insertRow('''
      INSERT INTO time_blocks (
        id, task_id, title, notes, starts_at_utc, ends_at_utc,
        created_at_utc, updated_at_utc
      ) VALUES (?, ?, ?, NULLIF(?, ''), ?, ?, ?, ?)
    ''',
        variables: _strings(<String>[
          id,
          taskId,
          title,
          notes ?? '',
          _utc(startsAtUtc),
          _utc(endsAtUtc),
          _utc(now),
          _utc(now),
        ]));
  }

  Goal _goalFromRow(QueryRow row) {
    return Goal(
      id: row.read<String>('id'),
      title: row.read<String>('title'),
      description: row.readNullable<String>('description'),
      scope: GoalScope.values.byName(row.read<String>('scope')),
      parentGoalId: row.readNullable<String>('parent_goal_id'),
      startsAtUtc: _nullableDate(row, 'starts_at_utc'),
      dueAtUtc: _nullableDate(row, 'due_at_utc'),
      status: GoalStatus.values.byName(row.read<String>('status')),
      createdAtUtc: _date(row, 'created_at_utc'),
      updatedAtUtc: _date(row, 'updated_at_utc'),
      archivedAtUtc: _nullableDate(row, 'archived_at_utc'),
    );
  }

  PlanPeriod _periodFromRow(QueryRow row) {
    return PlanPeriod(
      id: row.read<String>('id'),
      goalId: row.readNullable<String>('goal_id'),
      parentPeriodId: row.readNullable<String>('parent_period_id'),
      label: row.read<String>('label'),
      scope: GoalScope.values.byName(row.read<String>('scope')),
      startsAtUtc: _date(row, 'starts_at_utc'),
      endsAtUtc: _date(row, 'ends_at_utc'),
    );
  }

  Milestone _milestoneFromRow(QueryRow row) {
    return Milestone(
      id: row.read<String>('id'),
      goalId: row.readNullable<String>('goal_id'),
      parentMilestoneId: row.readNullable<String>('parent_milestone_id'),
      planPeriodId: row.readNullable<String>('plan_period_id'),
      title: row.read<String>('title'),
      description: row.readNullable<String>('description'),
      scope: GoalScope.values.byName(row.read<String>('scope')),
      dueAtUtc: _nullableDate(row, 'due_at_utc'),
      status: MilestoneStatus.values.byName(row.read<String>('status')),
      createdAtUtc: _date(row, 'created_at_utc'),
      updatedAtUtc: _date(row, 'updated_at_utc'),
    );
  }

  PlanningTask _taskFromRow(QueryRow row) {
    return PlanningTask(
      id: row.read<String>('id'),
      goalId: row.readNullable<String>('goal_id'),
      milestoneId: row.readNullable<String>('milestone_id'),
      subjectId: row.readNullable<String>('subject_id'),
      title: row.read<String>('title'),
      notes: row.readNullable<String>('notes'),
      kind: PlanningTaskKind.values.byName(row.read<String>('kind')),
      status: PlanningTaskStatus.values.byName(row.read<String>('status')),
      scheduledAtUtc: _nullableDate(row, 'scheduled_at_utc'),
      dueAtUtc: _nullableDate(row, 'due_at_utc'),
      completedAtUtc: _nullableDate(row, 'completed_at_utc'),
      createdAtUtc: _date(row, 'created_at_utc'),
      updatedAtUtc: _date(row, 'updated_at_utc'),
    );
  }

  TimeBlock _timeBlockFromRow(QueryRow row) {
    return TimeBlock(
      id: row.read<String>('id'),
      taskId: row.readNullable<String>('task_id'),
      title: row.read<String>('title'),
      notes: row.readNullable<String>('notes'),
      startsAtUtc: _date(row, 'starts_at_utc'),
      endsAtUtc: _date(row, 'ends_at_utc'),
      createdAtUtc: _date(row, 'created_at_utc'),
      updatedAtUtc: _date(row, 'updated_at_utc'),
    );
  }

  TimeBlock _timeBlockFromJoinedRow(QueryRow row) {
    return TimeBlock(
      id: row.read<String>('block_id'),
      taskId: row.readNullable<String>('block_task_id'),
      title: row.read<String>('block_title'),
      notes: row.readNullable<String>('block_notes'),
      startsAtUtc: _date(row, 'block_starts_at_utc'),
      endsAtUtc: _date(row, 'block_ends_at_utc'),
      createdAtUtc: _date(row, 'block_created_at_utc'),
      updatedAtUtc: _date(row, 'block_updated_at_utc'),
    );
  }

  String _newId(String prefix) {
    final LocalIdFactory? factory = _idFactory;
    if (factory != null) return factory(prefix);
    _idCounter += 1;
    final String time =
        _clock().toUtc().microsecondsSinceEpoch.toRadixString(36);
    final String random = _random.nextInt(0x7fffffff).toRadixString(36);
    return '$prefix-$time-$random-$_idCounter';
  }

  void _notifyChanged() {
    _database.notifyChanged();
  }
}

String _requiredTitle(String value, String field) {
  final String trimmed = value.trim();
  if (trimmed.isEmpty) {
    throw ArgumentError.value(value, field, '$field cannot be empty.');
  }
  return trimmed;
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

String _utc(DateTime value) => value.toUtc().toIso8601String();

DateTime _date(QueryRow row, String column) {
  return DateTime.parse(row.read<String>(column)).toUtc();
}

DateTime? _nullableDate(QueryRow row, String column) {
  final String? value = row.readNullable<String>(column);
  return value == null ? null : DateTime.parse(value).toUtc();
}

DateTime _startOfUtcWeek(DateTime value) {
  final DateTime day = DateTime.utc(value.year, value.month, value.day);
  return day.subtract(Duration(days: day.weekday - DateTime.monday));
}

String _shortDate(DateTime value) {
  final String month = value.month.toString().padLeft(2, '0');
  final String day = value.day.toString().padLeft(2, '0');
  return '${value.year}-$month-$day';
}

String _monthLabel(DateTime value) {
  const List<String> months = <String>[
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];
  return '${months[value.month - 1]} ${value.year}';
}
