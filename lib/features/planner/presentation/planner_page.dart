import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/app_components.dart';
import '../application/planning_providers.dart';
import '../domain/planning_entities.dart';
import '../domain/planning_repository.dart';

class PlannerPage extends ConsumerStatefulWidget {
  const PlannerPage({super.key});

  @override
  ConsumerState<PlannerPage> createState() => _PlannerPageState();
}

class _PlannerPageState extends ConsumerState<PlannerPage> {
  String _period = 'Week';

  Future<void> _createPath() async {
    final _PathFormResult? result = await showDialog<_PathFormResult>(
      context: context,
      builder: (BuildContext context) => const _PlanningPathDialog(),
    );
    if (result == null || !mounted) return;

    await _runMutation(
      () async {
        await ref.read(planningRepositoryProvider).createPlanningPath(
              PlanningPathDraft(
                annualGoalTitle: result.annualGoal,
                monthlyMilestoneTitle: result.monthlyMilestone,
                weeklyOutcomeTitle: result.weeklyOutcome,
                taskTitle: result.task,
                taskStartsAtUtc: result.taskStartsAtLocal.toUtc(),
              ),
            );
      },
      successMessage: 'Planning path saved on this device.',
    );
  }

  Future<void> _editPath(PlanningPath path) async {
    final Milestone? monthly = path.milestoneForScope(GoalScope.monthly);
    final Milestone? weekly = path.milestoneForScope(GoalScope.weekly);
    final PlanningTask? task = path.firstTask;
    if (monthly == null || weekly == null || task == null) {
      _showMessage('This path is incomplete and cannot be edited as one unit.');
      return;
    }
    final DateTime initialStart =
        path.timeBlockForTask(task.id)?.startsAtUtc.toLocal() ??
            task.scheduledAtUtc?.toLocal() ??
            DateTime.now();
    final _PathFormResult? result = await showDialog<_PathFormResult>(
      context: context,
      builder: (BuildContext context) => _PlanningPathDialog(
        title: 'Edit planning path',
        initialAnnualGoal: path.goal.title,
        initialMonthlyMilestone: monthly.title,
        initialWeeklyOutcome: weekly.title,
        initialTask: task.title,
        initialStartLocal: initialStart,
      ),
    );
    if (result == null || !mounted) return;

    await _runMutation(() async {
      final PlanningRepository repository =
          ref.read(planningRepositoryProvider);
      await repository.updatePlanningPath(
        PlanningPathEdits(
          goalId: path.goal.id,
          annualGoalTitle: result.annualGoal,
          monthlyMilestoneId: monthly.id,
          monthlyMilestoneTitle: result.monthlyMilestone,
          weeklyMilestoneId: weekly.id,
          weeklyOutcomeTitle: result.weeklyOutcome,
          taskId: task.id,
          taskTitle: result.task,
        ),
      );
      final DateTime startUtc = result.taskStartsAtLocal.toUtc();
      final DateTime? existingStartUtc =
          path.timeBlockForTask(task.id)?.startsAtUtc ?? task.scheduledAtUtc;
      if (!task.isFinished && startUtc != existingStartUtc) {
        await repository.rescheduleTask(
          taskId: task.id,
          startsAtUtc: startUtc,
          endsAtUtc: startUtc.add(const Duration(hours: 1)),
        );
      }
    }, successMessage: 'Planning path updated.');
  }

  Future<void> _rescheduleTask(PlanningTask task) async {
    final DateTime? localStart = await _pickDateTime(
      task.scheduledAtUtc?.toLocal() ?? DateTime.now(),
    );
    if (localStart == null || !mounted) return;
    await _runMutation(
      () => ref.read(planningRepositoryProvider).rescheduleTask(
            taskId: task.id,
            startsAtUtc: localStart.toUtc(),
            endsAtUtc: localStart.toUtc().add(const Duration(hours: 1)),
          ),
      successMessage: 'Task rescheduled.',
    );
  }

  Future<DateTime?> _pickDateTime(DateTime initialLocal) async {
    final DateTime? date = await showDatePicker(
      context: context,
      initialDate: initialLocal,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (date == null || !mounted) return null;
    final TimeOfDay? time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initialLocal),
    );
    if (time == null) return null;
    return DateTime(date.year, date.month, date.day, time.hour, time.minute);
  }

  Future<void> _handleTaskAction(
    _TaskAction action,
    PlanningTask task,
  ) async {
    switch (action) {
      case _TaskAction.reschedule:
        await _rescheduleTask(task);
      case _TaskAction.unschedule:
        await _runMutation(
          () => ref.read(planningRepositoryProvider).unscheduleTask(task.id),
          successMessage: 'Task moved to the unscheduled list.',
        );
      case _TaskAction.complete:
        await _setTaskStatus(task.id, PlanningTaskStatus.completed);
      case _TaskAction.skip:
        await _setTaskStatus(task.id, PlanningTaskStatus.skipped);
      case _TaskAction.cancel:
        await _setTaskStatus(task.id, PlanningTaskStatus.cancelled);
    }
  }

  Future<void> _setTaskStatus(
    String taskId,
    PlanningTaskStatus status,
  ) {
    return _runMutation(
      () =>
          ref.read(planningRepositoryProvider).changeTaskStatus(taskId, status),
      successMessage: 'Task marked ${_statusLabel(status).toLowerCase()}.',
    );
  }

  Future<void> _archivePath(PlanningPath path) async {
    final bool confirmed = await showDialog<bool>(
          context: context,
          builder: (BuildContext context) => AlertDialog(
            title: const Text('Archive this goal?'),
            content: const Text(
              'The goal leaves your active plan, but completed task history '
              'and all relationships remain stored.',
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Keep goal'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Archive'),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed || !mounted) return;
    await _runMutation(
      () => ref
          .read(planningRepositoryProvider)
          .archiveGoalPreservingHistory(path.goal.id),
      successMessage: 'Goal archived; completed history was preserved.',
    );
  }

  Future<void> _runMutation(
    Future<void> Function() operation, {
    required String successMessage,
  }) async {
    try {
      await operation();
      if (mounted) _showMessage(successMessage);
    } on Object catch (error) {
      if (mounted) _showMessage('Could not save: $error');
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final AsyncValue<List<PlanningPath>> paths = ref.watch(
      planningPathsProvider,
    );
    final AsyncValue<List<PlanningTask>> unscheduledTasks = ref.watch(
      unscheduledTasksProvider,
    );

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 110),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1180),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const PageIntro(
                eyebrow: 'Connected planning',
                title: 'Turn direction into action',
                subtitle:
                    'Every daily action should contribute to a larger goal.',
              ),
              const SizedBox(height: 22),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: <Widget>[
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: SegmentedButton<String>(
                      segments: const <ButtonSegment<String>>[
                        ButtonSegment<String>(value: 'Day', label: Text('Day')),
                        ButtonSegment<String>(
                            value: 'Week', label: Text('Week')),
                        ButtonSegment<String>(
                          value: 'Month',
                          label: Text('Month'),
                        ),
                        ButtonSegment<String>(
                            value: 'Year', label: Text('Year')),
                      ],
                      selected: <String>{_period},
                      onSelectionChanged: (Set<String> selection) {
                        setState(() => _period = selection.first);
                      },
                    ),
                  ),
                  FilledButton.icon(
                    onPressed: _createPath,
                    icon: const Icon(Icons.add_rounded),
                    label: const Text('New planning path'),
                  ),
                ],
              ),
              const SizedBox(height: 26),
              SectionHeading(title: '$_period plan'),
              const SizedBox(height: 10),
              paths.when(
                loading: () => const SurfaceCard(
                  child: Center(child: CircularProgressIndicator()),
                ),
                error: (Object error, StackTrace _) => SurfaceCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      const Text(
                        'Your local plan could not be loaded.',
                        style: TextStyle(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 8),
                      Text('$error'),
                      const SizedBox(height: 12),
                      OutlinedButton.icon(
                        onPressed: () => ref.invalidate(planningPathsProvider),
                        icon: const Icon(Icons.refresh_rounded),
                        label: const Text('Try again'),
                      ),
                    ],
                  ),
                ),
                data: (List<PlanningPath> value) {
                  if (value.isEmpty) return _EmptyPlan(onCreate: _createPath);
                  return Column(
                    children: value
                        .map(
                          (PlanningPath path) => Padding(
                            padding: const EdgeInsets.only(bottom: 14),
                            child: _PlanningPathCard(
                              path: path,
                              onEdit: () => _editPath(path),
                              onArchive: () => _archivePath(path),
                              onTaskAction: (
                                PlanningTask task,
                                _TaskAction action,
                              ) {
                                _handleTaskAction(action, task);
                              },
                            ),
                          ),
                        )
                        .toList(growable: false),
                  );
                },
              ),
              const SizedBox(height: 14),
              const SectionHeading(title: 'Unscheduled tasks'),
              const SizedBox(height: 10),
              unscheduledTasks.when(
                loading: () => const SurfaceCard(
                  child: Center(child: CircularProgressIndicator()),
                ),
                error: (Object error, StackTrace _) => SurfaceCard(
                  child: Text('Unscheduled tasks could not be loaded: $error'),
                ),
                data: (List<PlanningTask> tasks) {
                  if (tasks.isEmpty) {
                    return const SurfaceCard(
                      child: Text(
                        'No open unscheduled tasks. Quick add can create one.',
                      ),
                    );
                  }
                  return SurfaceCard(
                    child: Column(
                      children: tasks
                          .map(
                            (PlanningTask task) => Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: _TaskStep(
                                task: task,
                                block: null,
                                onAction: (_TaskAction action) {
                                  _handleTaskAction(action, task);
                                },
                              ),
                            ),
                          )
                          .toList(growable: false),
                    ),
                  );
                },
              ),
              const SizedBox(height: 18),
              _PlanningRulesCard(),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyPlan extends StatelessWidget {
  const _EmptyPlan({required this.onCreate});

  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    return SurfaceCard(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Column(
            children: <Widget>[
              const Icon(Icons.route_outlined,
                  size: 44, color: AppColors.primary),
              const SizedBox(height: 14),
              Text(
                'Build your first connected plan',
                textAlign: TextAlign.center,
                style: Theme.of(context)
                    .textTheme
                    .titleLarge
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 6),
              const Text(
                'Connect an annual goal to a monthly milestone, a weekly '
                'outcome, and one scheduled task.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 18),
              FilledButton.icon(
                onPressed: onCreate,
                icon: const Icon(Icons.add_rounded),
                label: const Text('Create planning path'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PlanningPathCard extends StatelessWidget {
  const _PlanningPathCard({
    required this.path,
    required this.onEdit,
    required this.onArchive,
    required this.onTaskAction,
  });

  final PlanningPath path;
  final VoidCallback onEdit;
  final VoidCallback onArchive;
  final void Function(PlanningTask task, _TaskAction action) onTaskAction;

  @override
  Widget build(BuildContext context) {
    final Milestone? monthly = path.milestoneForScope(GoalScope.monthly);
    final Milestone? weekly = path.milestoneForScope(GoalScope.weekly);
    final PlanningTask? task = path.firstTask;
    final TimeBlock? block =
        task == null ? null : path.timeBlockForTask(task.id);

    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      'ANNUAL DIRECTION',
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                            color: Theme.of(context).colorScheme.primary,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.8,
                          ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      path.goal.title,
                      style: Theme.of(context)
                          .textTheme
                          .titleLarge
                          ?.copyWith(fontWeight: FontWeight.w800),
                    ),
                  ],
                ),
              ),
              PopupMenuButton<_PathAction>(
                tooltip: 'Planning path actions',
                onSelected: (_PathAction action) {
                  if (action == _PathAction.edit) {
                    onEdit();
                  } else {
                    onArchive();
                  }
                },
                itemBuilder: (BuildContext context) =>
                    const <PopupMenuEntry<_PathAction>>[
                  PopupMenuItem<_PathAction>(
                    value: _PathAction.edit,
                    child: Text('Edit path'),
                  ),
                  PopupMenuItem<_PathAction>(
                    value: _PathAction.archive,
                    child: Text('Archive goal'),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 18),
          if (monthly != null)
            _PathStep(
              label: 'Month',
              title: monthly.title,
              icon: Icons.calendar_month_outlined,
            ),
          if (weekly != null)
            _PathStep(
              label: 'Week',
              title: weekly.title,
              icon: Icons.view_week_outlined,
            ),
          if (task != null)
            _TaskStep(
              task: task,
              block: block,
              onAction: (_TaskAction action) => onTaskAction(task, action),
            ),
        ],
      ),
    );
  }
}

class _PathStep extends StatelessWidget {
  const _PathStep({
    required this.label,
    required this.title,
    required this.icon,
  });

  final String label;
  final String title;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        children: <Widget>[
          CircleAvatar(child: Icon(icon, size: 20)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(label, style: Theme.of(context).textTheme.labelMedium),
                Text(title,
                    style: const TextStyle(fontWeight: FontWeight.w700)),
              ],
            ),
          ),
          const Icon(Icons.arrow_downward_rounded, size: 18),
        ],
      ),
    );
  }
}

class _TaskStep extends StatelessWidget {
  const _TaskStep({
    required this.task,
    required this.block,
    required this.onAction,
  });

  final PlanningTask task;
  final TimeBlock? block;
  final ValueChanged<_TaskAction> onAction;

  @override
  Widget build(BuildContext context) {
    final DateTime? start = block?.startsAtUtc ?? task.scheduledAtUtc;
    return Row(
      children: <Widget>[
        const CircleAvatar(child: Icon(Icons.today_outlined, size: 20)),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                start == null ? 'Unscheduled task' : _formatDateTime(start),
                style: Theme.of(context).textTheme.labelMedium,
              ),
              Text(task.title,
                  style: const TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 3),
              Text(
                _statusLabel(task.status),
                style: TextStyle(
                  color: task.status == PlanningTaskStatus.completed
                      ? AppColors.secondary
                      : Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        PopupMenuButton<_TaskAction>(
          tooltip: 'Task actions',
          onSelected: onAction,
          itemBuilder: (BuildContext context) => <PopupMenuEntry<_TaskAction>>[
            if (!task.isFinished)
              const PopupMenuItem<_TaskAction>(
                value: _TaskAction.complete,
                child: Text('Complete'),
              ),
            if (!task.isFinished)
              const PopupMenuItem<_TaskAction>(
                value: _TaskAction.reschedule,
                child: Text('Reschedule'),
              ),
            if (task.isScheduled && !task.isFinished)
              const PopupMenuItem<_TaskAction>(
                value: _TaskAction.unschedule,
                child: Text('Remove schedule'),
              ),
            if (!task.isFinished)
              const PopupMenuItem<_TaskAction>(
                value: _TaskAction.skip,
                child: Text('Skip'),
              ),
            if (!task.isFinished)
              const PopupMenuItem<_TaskAction>(
                value: _TaskAction.cancel,
                child: Text('Cancel'),
              ),
          ],
        ),
      ],
    );
  }
}

class _PlanningRulesCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return SurfaceCard(
      color: Theme.of(context).colorScheme.secondaryContainer,
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(Icons.offline_bolt_outlined),
          SizedBox(width: 12),
          Expanded(
            child: Text(
              'Plans are stored locally and work offline. Archiving a goal '
              'never erases its completed task history.',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

class _PlanningPathDialog extends StatefulWidget {
  const _PlanningPathDialog({
    this.title = 'Create planning path',
    this.initialAnnualGoal = '',
    this.initialMonthlyMilestone = '',
    this.initialWeeklyOutcome = '',
    this.initialTask = '',
    this.initialStartLocal,
  });

  final String title;
  final String initialAnnualGoal;
  final String initialMonthlyMilestone;
  final String initialWeeklyOutcome;
  final String initialTask;
  final DateTime? initialStartLocal;

  @override
  State<_PlanningPathDialog> createState() => _PlanningPathDialogState();
}

class _PlanningPathDialogState extends State<_PlanningPathDialog> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  late final TextEditingController _annualController;
  late final TextEditingController _monthlyController;
  late final TextEditingController _weeklyController;
  late final TextEditingController _taskController;
  late DateTime _taskStartsAtLocal;

  @override
  void initState() {
    super.initState();
    _annualController = TextEditingController(text: widget.initialAnnualGoal);
    _monthlyController = TextEditingController(
      text: widget.initialMonthlyMilestone,
    );
    _weeklyController =
        TextEditingController(text: widget.initialWeeklyOutcome);
    _taskController = TextEditingController(text: widget.initialTask);
    final DateTime nextHour = DateTime.now().add(const Duration(hours: 1));
    _taskStartsAtLocal = widget.initialStartLocal ??
        DateTime(
          nextHour.year,
          nextHour.month,
          nextHour.day,
          nextHour.hour,
        );
  }

  @override
  void dispose() {
    _annualController.dispose();
    _monthlyController.dispose();
    _weeklyController.dispose();
    _taskController.dispose();
    super.dispose();
  }

  Future<void> _chooseSchedule() async {
    final DateTime? date = await showDatePicker(
      context: context,
      initialDate: _taskStartsAtLocal,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (date == null || !mounted) return;
    final TimeOfDay? time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_taskStartsAtLocal),
    );
    if (time == null) return;
    setState(() {
      _taskStartsAtLocal = DateTime(
        date.year,
        date.month,
        date.day,
        time.hour,
        time.minute,
      );
    });
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.of(context).pop(
      _PathFormResult(
        annualGoal: _annualController.text.trim(),
        monthlyMilestone: _monthlyController.text.trim(),
        weeklyOutcome: _weeklyController.text.trim(),
        task: _taskController.text.trim(),
        taskStartsAtLocal: _taskStartsAtLocal,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                _PathTextField(
                  controller: _annualController,
                  label: 'Annual goal',
                  hint: 'Complete the school year successfully',
                ),
                const SizedBox(height: 12),
                _PathTextField(
                  controller: _monthlyController,
                  label: 'Monthly milestone',
                  hint: 'Build a stable study routine',
                ),
                const SizedBox(height: 12),
                _PathTextField(
                  controller: _weeklyController,
                  label: 'Weekly outcome',
                  hint: 'Complete three focused sessions',
                ),
                const SizedBox(height: 12),
                _PathTextField(
                  controller: _taskController,
                  label: 'Task',
                  hint: 'Review chapter 3 for 60 minutes',
                ),
                const SizedBox(height: 12),
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                  leading: const Icon(Icons.schedule_rounded),
                  title: const Text('Task schedule'),
                  subtitle: Text(_formatLocalDateTime(_taskStartsAtLocal)),
                  trailing: TextButton(
                    onPressed: _chooseSchedule,
                    child: const Text('Change'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Save locally')),
      ],
    );
  }
}

class _PathTextField extends StatelessWidget {
  const _PathTextField({
    required this.controller,
    required this.label,
    required this.hint,
  });

  final TextEditingController controller;
  final String label;
  final String hint;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      decoration: InputDecoration(labelText: label, hintText: hint),
      textCapitalization: TextCapitalization.sentences,
      validator: (String? value) {
        return value == null || value.trim().isEmpty
            ? '$label is required'
            : null;
      },
    );
  }
}

class _PathFormResult {
  const _PathFormResult({
    required this.annualGoal,
    required this.monthlyMilestone,
    required this.weeklyOutcome,
    required this.task,
    required this.taskStartsAtLocal,
  });

  final String annualGoal;
  final String monthlyMilestone;
  final String weeklyOutcome;
  final String task;
  final DateTime taskStartsAtLocal;
}

enum _PathAction { edit, archive }

enum _TaskAction { complete, reschedule, unschedule, skip, cancel }

String _statusLabel(PlanningTaskStatus status) {
  switch (status) {
    case PlanningTaskStatus.pending:
      return 'Pending';
    case PlanningTaskStatus.inProgress:
      return 'In progress';
    case PlanningTaskStatus.completed:
      return 'Completed';
    case PlanningTaskStatus.skipped:
      return 'Skipped';
    case PlanningTaskStatus.cancelled:
      return 'Cancelled';
  }
}

String _formatDateTime(DateTime utcValue) {
  return _formatLocalDateTime(utcValue.toLocal());
}

String _formatLocalDateTime(DateTime value) {
  final String day = value.day.toString().padLeft(2, '0');
  final String month = value.month.toString().padLeft(2, '0');
  final String hour = value.hour.toString().padLeft(2, '0');
  final String minute = value.minute.toString().padLeft(2, '0');
  return '${value.year}-$month-$day at $hour:$minute';
}
