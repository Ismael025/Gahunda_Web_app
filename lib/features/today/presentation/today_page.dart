import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/app_components.dart';
import '../../account/application/account_providers.dart';
import '../../account/domain/account_entities.dart';
import '../../behavior/application/habit_providers.dart';
import '../../behavior/domain/habit_entities.dart';
import '../../money/application/money_providers.dart';
import '../../money/domain/money_entities.dart';
import '../../planner/application/planning_providers.dart';
import '../../planner/domain/planning_entities.dart';
import '../../school/application/school_providers.dart';
import '../../school/domain/school_entities.dart';
import '../application/today_providers.dart';
import '../domain/today_entities.dart';

Future<void> openTodayReflectionFlow(
  BuildContext context,
  WidgetRef ref,
) async {
  final DateTime now = DateTime.now();
  final DateTime today = DateTime(now.year, now.month, now.day);
  final DailyClosureDraft? draft = await showDialog<DailyClosureDraft>(
    context: context,
    builder: (BuildContext context) => _DailyClosureLoader(localDay: today),
  );
  if (draft == null || !context.mounted) return;
  await _saveDayClosure(context, ref, draft);
}

Future<void> _openDayClosure(
  BuildContext context,
  WidgetRef ref,
  DateTime localDay,
  List<ScheduledPlanningTask> tasks,
  DailyClosure? existing,
) async {
  final DailyClosureDraft? draft = await showDialog<DailyClosureDraft>(
    context: context,
    builder: (BuildContext context) => _DailyClosureDialog(
      localDay: localDay,
      tasks: tasks,
      existing: existing,
    ),
  );
  if (draft == null || !context.mounted) return;

  await _saveDayClosure(context, ref, draft);
}

Future<void> _saveDayClosure(
  BuildContext context,
  WidgetRef ref,
  DailyClosureDraft draft,
) async {
  try {
    await ref.read(todayRepositoryProvider).closeDay(draft);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Your day was saved locally.')),
      );
    }
  } on Object catch (error) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not close the day: $error')),
      );
    }
  }
}

class _DailyClosureLoader extends ConsumerWidget {
  const _DailyClosureLoader({required this.localDay});

  final DateTime localDay;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<ScheduledPlanningTask>> tasks = ref.watch(
      tasksForLocalDayProvider(localDay),
    );
    final AsyncValue<DailyClosure?> closure = ref.watch(
      dailyClosureProvider(localDay),
    );
    return tasks.when(
      loading: _loadingDialog,
      error: (Object error, StackTrace _) => _errorDialog(context, error),
      data: (List<ScheduledPlanningTask> loadedTasks) => closure.when(
        loading: _loadingDialog,
        error: (Object error, StackTrace _) => _errorDialog(context, error),
        data: (DailyClosure? existing) => _DailyClosureDialog(
          localDay: localDay,
          tasks: loadedTasks,
          existing: existing,
        ),
      ),
    );
  }

  Widget _loadingDialog() {
    return const AlertDialog(
      title: Text('Close today'),
      content: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(strokeWidth: 2.5),
          ),
          SizedBox(width: 14),
          Text('Loading today’s reflection…'),
        ],
      ),
    );
  }

  Widget _errorDialog(BuildContext context, Object error) {
    return AlertDialog(
      title: const Text('Close today'),
      content: Text('Could not load today’s reflection: $error'),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }
}

class TodayPage extends ConsumerWidget {
  const TodayPage({super.key});

  Future<void> _checkInHabit(
    BuildContext context,
    WidgetRef ref,
    HabitDayProgress progress,
  ) async {
    _TodayHabitCheckIn? input;
    if (progress.habit.measurement == HabitMeasurement.binary) {
      input = progress.checkIn == null
          ? const _TodayHabitCheckIn(value: 1)
          : const _TodayHabitCheckIn(clear: true);
    } else {
      input = await showDialog<_TodayHabitCheckIn>(
        context: context,
        builder: (BuildContext context) =>
            _TodayHabitCheckInDialog(progress: progress),
      );
    }
    if (input == null || !context.mounted) return;

    try {
      if (input.clear) {
        await ref
            .read(habitRepositoryProvider)
            .clearCheckIn(progress.habit.id, progress.localDay);
      } else {
        await ref.read(habitRepositoryProvider).recordCheckIn(
              HabitCheckInDraft(
                habitId: progress.habit.id,
                localDay: progress.localDay,
                value: input.value,
                note: input.note,
              ),
            );
      }
    } on Object catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not update habit: $error')),
        );
      }
    }
  }

  Future<void> _toggleAssignment(
    BuildContext context,
    WidgetRef ref,
    SchoolAssignment assignment,
  ) async {
    final PlanningTaskStatus next = assignment.isFinished
        ? PlanningTaskStatus.pending
        : PlanningTaskStatus.completed;
    try {
      await ref
          .read(planningRepositoryProvider)
          .changeTaskStatus(assignment.taskId, next);
    } on Object catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not update assignment: $error')),
        );
      }
    }
  }

  Future<void> _runTaskAction(
    BuildContext context,
    WidgetRef ref,
    ScheduledPlanningTask item,
    _TodayTaskAction action,
  ) async {
    final PlanningTask task = item.task;
    try {
      switch (action) {
        case _TodayTaskAction.complete:
          await ref
              .read(planningRepositoryProvider)
              .changeTaskStatus(task.id, PlanningTaskStatus.completed);
          break;
        case _TodayTaskAction.reopen:
          await ref
              .read(planningRepositoryProvider)
              .changeTaskStatus(task.id, PlanningTaskStatus.pending);
          break;
        case _TodayTaskAction.moveToTomorrow:
          final DateTime start = item.startsAtUtc!.toLocal();
          final DateTime nextLocal = DateTime(
            start.year,
            start.month,
            start.day + 1,
            start.hour,
            start.minute,
          );
          final Duration duration = _durationOf(item);
          await ref.read(planningRepositoryProvider).rescheduleTask(
                taskId: task.id,
                startsAtUtc: nextLocal.toUtc(),
                endsAtUtc: nextLocal.toUtc().add(duration),
              );
          break;
        case _TodayTaskAction.skip:
          await ref
              .read(planningRepositoryProvider)
              .changeTaskStatus(task.id, PlanningTaskStatus.skipped);
          break;
        case _TodayTaskAction.cancel:
          await ref
              .read(planningRepositoryProvider)
              .changeTaskStatus(task.id, PlanningTaskStatus.cancelled);
          break;
      }
    } on Object catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not update task: $error')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final DateTime now = DateTime.now();
    final DateTime today = DateTime(now.year, now.month, now.day);
    final AccountUser? account = ref.watch(
      syncControllerProvider.select((SyncState value) => value.user),
    );
    final AsyncValue<List<ScheduledPlanningTask>> schedule = ref.watch(
      tasksForLocalDayProvider(today),
    );
    final AsyncValue<DailyClosure?> closure = ref.watch(
      dailyClosureProvider(today),
    );
    final AsyncValue<SchoolWeekData> school = ref.watch(
      schoolWeekProvider(today),
    );
    final AsyncValue<HabitDashboard> habits = ref.watch(
      habitDashboardProvider(today),
    );
    final AsyncValue<MoneyDashboard> money = ref.watch(
      moneyDashboardProvider(startOfMoneyMonth(today)),
    );
    final List<ScheduledPlanningTask>? loadedTasks = schedule.asData?.value;
    final DailyClosure? savedClosure = closure.asData?.value;
    final HabitDashboard? loadedHabits = habits.asData?.value;
    final TodayMetrics metrics = TodayMetrics.fromTasks(
      loadedTasks ?? const <ScheduledPlanningTask>[],
    );

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 110),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1180),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              PageIntro(
                eyebrow: _longDate(now),
                title: 'Good morning, ${_greetingName(account)}',
                subtitle:
                    'Your live plan for today, available offline and updated instantly.',
              ),
              const SizedBox(height: 24),
              ResponsiveCardGrid(
                children: <Widget>[
                  MetricCard(
                    label: 'Completed tasks',
                    value: loadedTasks == null
                        ? 'Loading…'
                        : '${metrics.completedTaskCount} of '
                            '${metrics.scheduledTaskCount}',
                    caption: '${metrics.openTaskCount} still open',
                    icon: Icons.task_alt_rounded,
                    color: AppColors.primary,
                  ),
                  MetricCard(
                    label: 'Planned time',
                    value: loadedTasks == null
                        ? 'Loading…'
                        : _durationLabel(metrics.plannedDuration),
                    caption: 'From today’s time blocks',
                    icon: Icons.calendar_today_rounded,
                    color: const Color(0xFF8B5CF6),
                  ),
                  MetricCard(
                    label: 'Completed focus',
                    value: loadedTasks == null
                        ? 'Loading…'
                        : _durationLabel(metrics.completedDuration),
                    caption: 'Time attached to completed tasks',
                    icon: Icons.timer_outlined,
                    color: AppColors.secondary,
                  ),
                  MetricCard(
                    label: 'Day closure',
                    value: closure.isLoading
                        ? 'Loading…'
                        : savedClosure == null
                            ? 'Open'
                            : 'Closed',
                    caption: savedClosure == null
                        ? 'Reflect when your day is done'
                        : 'Mood ${savedClosure.mood}/5 • saved '
                            '${_clockTime(savedClosure.closedAtUtc.toLocal())}',
                    icon: Icons.nights_stay_outlined,
                    color: AppColors.warning,
                  ),
                ],
              ),
              const SizedBox(height: 28),
              const SectionHeading(title: "Today's schedule"),
              const SizedBox(height: 10),
              schedule.when(
                loading: () => const SurfaceCard(
                  child: Center(child: CircularProgressIndicator()),
                ),
                error: (Object error, StackTrace _) => SurfaceCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      const Text(
                        'The local schedule could not be loaded.',
                        style: TextStyle(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 6),
                      Text('$error'),
                    ],
                  ),
                ),
                data: (List<ScheduledPlanningTask> tasks) {
                  if (tasks.isEmpty) {
                    return const SurfaceCard(
                      child: Row(
                        children: <Widget>[
                          Icon(Icons.event_available_outlined),
                          SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'No task is scheduled today. Use Quick add or '
                              'create a connected path in Plan.',
                            ),
                          ),
                        ],
                      ),
                    );
                  }
                  return SurfaceCard(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 6,
                    ),
                    child: Column(
                      children: tasks
                          .map(
                            (ScheduledPlanningTask item) => _ScheduleTile(
                              item: item,
                              onAction: (_TodayTaskAction action) =>
                                  _runTaskAction(context, ref, item, action),
                            ),
                          )
                          .toList(growable: false),
                    ),
                  );
                },
              ),
              const SizedBox(height: 28),
              const SectionHeading(title: "Today's school"),
              const SizedBox(height: 10),
              _TodaySchoolCard(
                localDay: today,
                school: school,
                onToggleAssignment: (SchoolAssignment assignment) =>
                    _toggleAssignment(context, ref, assignment),
              ),
              const SizedBox(height: 28),
              const SectionHeading(title: "Today's habits"),
              const SizedBox(height: 10),
              _TodayHabitsCard(
                dashboard: habits,
                onCheckIn: (HabitDayProgress progress) =>
                    _checkInHabit(context, ref, progress),
              ),
              const SizedBox(height: 28),
              const SectionHeading(title: "Today's money"),
              const SizedBox(height: 10),
              _TodayMoneyCard(localDay: today, dashboard: money),
              const SizedBox(height: 28),
              const SectionHeading(title: 'Daily progress'),
              const SizedBox(height: 10),
              SurfaceCard(
                child: Column(
                  children: <Widget>[
                    ProgressLine(
                      label: 'Task completion',
                      valueLabel: '${metrics.completedTaskCount} / '
                          '${metrics.scheduledTaskCount}',
                      progress: metrics.completionProgress,
                      color: AppColors.primary,
                    ),
                    const SizedBox(height: 20),
                    ProgressLine(
                      label: 'Completed planned time',
                      valueLabel:
                          '${_durationLabel(metrics.completedDuration)} '
                          '/ ${_durationLabel(metrics.plannedDuration)}',
                      progress: metrics.completedTimeProgress,
                      color: AppColors.secondary,
                    ),
                    const SizedBox(height: 20),
                    ProgressLine(
                      label: 'Tasks resolved',
                      valueLabel: '${metrics.resolvedTaskCount} / '
                          '${metrics.scheduledTaskCount}',
                      progress: metrics.resolutionProgress,
                      color: AppColors.warning,
                    ),
                    if (loadedHabits != null) ...<Widget>[
                      const SizedBox(height: 20),
                      ProgressLine(
                        label: 'Habit targets',
                        valueLabel: '${loadedHabits.completedToday} / '
                            '${loadedHabits.scheduledToday}',
                        progress: loadedHabits.scheduledToday == 0
                            ? 0
                            : loadedHabits.completedToday /
                                loadedHabits.scheduledToday,
                        color: AppColors.secondary,
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 28),
              _DayClosureCard(
                closure: closure,
                onPressed: loadedTasks == null
                    ? null
                    : () => _openDayClosure(
                          context,
                          ref,
                          today,
                          loadedTasks,
                          savedClosure,
                        ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TodayHabitsCard extends StatelessWidget {
  const _TodayHabitsCard({
    required this.dashboard,
    required this.onCheckIn,
  });

  final AsyncValue<HabitDashboard> dashboard;
  final ValueChanged<HabitDayProgress> onCheckIn;

  @override
  Widget build(BuildContext context) {
    return dashboard.when(
      loading: () => const SurfaceCard(
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (Object error, StackTrace _) => SurfaceCard(
        child: Text('Habit data could not be loaded: $error'),
      ),
      data: (HabitDashboard data) {
        if (data.activeHabits.isEmpty) {
          return const SurfaceCard(
            child: Row(
              children: <Widget>[
                Icon(Icons.track_changes_outlined),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'No habits yet. Create one in Track or use Quick add.',
                  ),
                ),
              ],
            ),
          );
        }
        if (data.dayProgress.isEmpty) {
          return const SurfaceCard(
            child: Row(
              children: <Widget>[
                Icon(Icons.event_available_outlined),
                SizedBox(width: 12),
                Expanded(child: Text('No habit is scheduled for today.')),
              ],
            ),
          );
        }

        final List<Widget> rows = <Widget>[];
        for (final HabitDayProgress progress in data.dayProgress) {
          if (rows.isNotEmpty) rows.add(const Divider(height: 1));
          rows.add(
            _TodayHabitRow(
              progress: progress,
              onCheckIn: () => onCheckIn(progress),
            ),
          );
        }
        if (data.recoveryCandidates.isNotEmpty) {
          rows
            ..add(const Divider(height: 1))
            ..add(
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Row(
                  children: <Widget>[
                    const Icon(Icons.restart_alt_rounded),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        '${data.recoveryCandidates.length} '
                        'habit${data.recoveryCandidates.length == 1 ? '' : 's'} '
                        'can be recovered from yesterday in Track.',
                      ),
                    ),
                  ],
                ),
              ),
            );
        }
        return SurfaceCard(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Column(children: rows),
        );
      },
    );
  }
}

class _TodayHabitRow extends StatelessWidget {
  const _TodayHabitRow({
    required this.progress,
    required this.onCheckIn,
  });

  final HabitDayProgress progress;
  final VoidCallback onCheckIn;

  @override
  Widget build(BuildContext context) {
    final Habit habit = progress.habit;
    final Color color = Color(habit.colorValue);
    final bool successful = progress.isSuccessful;
    final bool binary = habit.measurement == HabitMeasurement.binary;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: <Widget>[
          CircleAvatar(
            backgroundColor: color.withValues(alpha: 0.14),
            foregroundColor: color,
            child: Icon(
              binary ? Icons.task_alt_rounded : Icons.show_chart_rounded,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  habit.name,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 2),
                Text(
                  _todayHabitDetail(progress),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (binary)
            IconButton(
              tooltip: successful ? 'Clear check-in' : 'Mark complete',
              onPressed: onCheckIn,
              icon: Icon(
                successful ? Icons.check_circle_rounded : Icons.circle_outlined,
                color: successful ? AppColors.secondary : color,
              ),
            )
          else
            OutlinedButton(
              onPressed: onCheckIn,
              child: Text(progress.checkIn == null ? 'Log' : 'Update'),
            ),
        ],
      ),
    );
  }
}

class _TodayMoneyCard extends StatelessWidget {
  const _TodayMoneyCard({required this.localDay, required this.dashboard});

  final DateTime localDay;
  final AsyncValue<MoneyDashboard> dashboard;

  @override
  Widget build(BuildContext context) {
    return dashboard.when(
      loading: () => const SurfaceCard(
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (Object error, StackTrace _) => SurfaceCard(
        child: Text('Money data could not be loaded: $error'),
      ),
      data: (MoneyDashboard data) {
        if (data.activeAccounts.isEmpty) {
          return const SurfaceCard(
            child: Row(
              children: <Widget>[
                Icon(Icons.account_balance_wallet_outlined),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Create your first account in Money to see today’s spending here.',
                  ),
                ),
              ],
            ),
          );
        }
        final List<MoneyTransaction> todayTransactions = data.transactions
            .where(
              (MoneyTransaction item) =>
                  _sameTodayDay(item.occurredAtUtc.toLocal(), localDay),
            )
            .toList(growable: false);
        return SurfaceCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              LayoutBuilder(
                builder: (BuildContext context, BoxConstraints constraints) {
                  final int columns = constraints.maxWidth >= 680 ? 3 : 1;
                  const double spacing = 12;
                  final double width =
                      (constraints.maxWidth - spacing * (columns - 1)) /
                          columns;
                  return Wrap(
                    spacing: spacing,
                    runSpacing: spacing,
                    children: <Widget>[
                      SizedBox(
                        width: width,
                        child: _TodayMoneyMetric(
                          label: 'Spent today',
                          value: _todayRwf(data.spentOnLocalDay(localDay)),
                          color: AppColors.danger,
                        ),
                      ),
                      SizedBox(
                        width: width,
                        child: _TodayMoneyMetric(
                          label: 'Income today',
                          value: _todayRwf(data.incomeOnLocalDay(localDay)),
                          color: AppColors.secondary,
                        ),
                      ),
                      SizedBox(
                        width: width,
                        child: _TodayMoneyMetric(
                          label: 'Spendable now',
                          value: _todayRwf(data.totalSpendableRwf),
                          color: AppColors.primary,
                        ),
                      ),
                    ],
                  );
                },
              ),
              if (todayTransactions.isNotEmpty) ...<Widget>[
                const Divider(height: 28),
                ...todayTransactions.take(3).map(
                      (MoneyTransaction item) => _TodayMoneyTransactionRow(
                        transaction: item,
                        dashboard: data,
                      ),
                    ),
                if (todayTransactions.length > 3)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      '${todayTransactions.length - 3} more today • open Money for the full ledger',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
              ] else ...<Widget>[
                const SizedBox(height: 14),
                Text(
                  'No money entries today. Use Quick add → Expense when you spend.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _TodayMoneyMetric extends StatelessWidget {
  const _TodayMoneyMetric({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(label, style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 3),
            Text(
              value,
              style: TextStyle(color: color, fontWeight: FontWeight.w800),
            ),
          ],
        ),
      ),
    );
  }
}

class _TodayMoneyTransactionRow extends StatelessWidget {
  const _TodayMoneyTransactionRow({
    required this.transaction,
    required this.dashboard,
  });

  final MoneyTransaction transaction;
  final MoneyDashboard dashboard;

  @override
  Widget build(BuildContext context) {
    final MoneyCategory? category =
        dashboard.categoryById(transaction.categoryId);
    final MoneyAccountSummary? account =
        dashboard.accountById(transaction.accountId);
    final Color color = switch (transaction.kind) {
      MoneyTransactionKind.expense => AppColors.danger,
      MoneyTransactionKind.income => AppColors.secondary,
      MoneyTransactionKind.transfer => AppColors.primary,
    };
    final String amountPrefix = switch (transaction.kind) {
      MoneyTransactionKind.expense => '−',
      MoneyTransactionKind.income => '+',
      MoneyTransactionKind.transfer => '',
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: <Widget>[
          Icon(
            transaction.kind == MoneyTransactionKind.transfer
                ? Icons.swap_horiz_rounded
                : transaction.kind == MoneyTransactionKind.income
                    ? Icons.north_east_rounded
                    : Icons.south_east_rounded,
            color: color,
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  transaction.title,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                Text(
                  '${category?.name ?? (transaction.kind == MoneyTransactionKind.transfer ? 'Transfer' : 'Archived category')} • ${account?.account.name ?? 'Archived account'}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          Text(
            '$amountPrefix${_todayRwf(transaction.amountRwf)}',
            style: TextStyle(color: color, fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }
}

class _TodayHabitCheckInDialog extends StatefulWidget {
  const _TodayHabitCheckInDialog({required this.progress});

  final HabitDayProgress progress;

  @override
  State<_TodayHabitCheckInDialog> createState() =>
      _TodayHabitCheckInDialogState();
}

class _TodayHabitCheckInDialogState extends State<_TodayHabitCheckInDialog> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  late final TextEditingController _value;
  late final TextEditingController _note;

  @override
  void initState() {
    super.initState();
    final HabitDayProgress progress = widget.progress;
    _value = TextEditingController(
      text: '${progress.checkIn?.value ?? progress.habit.targetValue}',
    );
    _note = TextEditingController(text: progress.checkIn?.note);
  }

  @override
  void dispose() {
    _value.dispose();
    _note.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.of(context).pop(
      _TodayHabitCheckIn(
        value: int.parse(_value.text.trim()),
        note: _note.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final Habit habit = widget.progress.habit;
    return AlertDialog(
      title: Text('Log ${habit.name}'),
      content: SizedBox(
        width: 420,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              TextFormField(
                controller: _value,
                autofocus: true,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: 'Actual ${habit.unit}',
                  helperText: habit.direction == HabitDirection.build
                      ? 'Target: at least ${habit.targetValue} ${habit.unit}'
                      : 'Limit: at most ${habit.targetValue} ${habit.unit}',
                ),
                validator: _wholeNumberValidator,
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _note,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(labelText: 'Note (optional)'),
              ),
            ],
          ),
        ),
      ),
      actions: <Widget>[
        if (widget.progress.checkIn != null)
          TextButton(
            onPressed: () => Navigator.of(context).pop(
              const _TodayHabitCheckIn(clear: true),
            ),
            child: const Text('Clear'),
          ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Save check-in')),
      ],
    );
  }
}

class _TodayHabitCheckIn {
  const _TodayHabitCheckIn({
    this.value = 0,
    this.note = '',
    this.clear = false,
  });

  final int value;
  final String note;
  final bool clear;
}

class _TodaySchoolCard extends StatelessWidget {
  const _TodaySchoolCard({
    required this.localDay,
    required this.school,
    required this.onToggleAssignment,
  });

  final DateTime localDay;
  final AsyncValue<SchoolWeekData> school;
  final ValueChanged<SchoolAssignment> onToggleAssignment;

  @override
  Widget build(BuildContext context) {
    return school.when(
      loading: () => const SurfaceCard(
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (Object error, StackTrace _) => SurfaceCard(
        child: Text('School data could not be loaded: $error'),
      ),
      data: (SchoolWeekData data) {
        final AcademicTerm? term = data.activeTerm;
        if (term == null) {
          return const SurfaceCard(
            child: Row(
              children: <Widget>[
                Icon(Icons.school_outlined),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Set up an academic term in School to see today’s '
                    'classes and deadlines here.',
                  ),
                ),
              ],
            ),
          );
        }
        if (!term.contains(localDay)) {
          return SurfaceCard(
            child: Text('${term.name} does not include today’s date.'),
          );
        }

        final List<ClassSession> sessions = data.sessionsForLocalDay(localDay);
        final List<Exam> exams = data.examsForLocalDay(localDay);
        final List<SchoolAssignment> assignments =
            data.assignmentsDueOnLocalDay(localDay);
        if (sessions.isEmpty && exams.isEmpty && assignments.isEmpty) {
          return SurfaceCard(
            child: Row(
              children: <Widget>[
                const Icon(Icons.event_available_outlined),
                const SizedBox(width: 12),
                Expanded(
                  child: Text('No classes, exams, or deadlines today in '
                      '${term.name}.'),
                ),
              ],
            ),
          );
        }

        final List<Widget> rows = <Widget>[];
        void addRow(Widget row) {
          if (rows.isNotEmpty) rows.add(const Divider(height: 1));
          rows.add(row);
        }

        for (final ClassSession session in sessions) {
          final Subject? subject = data.subjectById(session.subjectId);
          addRow(
            _TodaySchoolRow(
              color: Color(subject?.colorValue ?? 0xFF4F46E5),
              icon: Icons.class_outlined,
              title: subject?.name ?? 'Unknown subject',
              detail:
                  '${_schoolMinuteRange(session.startsAtMinute, session.endsAtMinute)}'
                  '${_optionalSchoolDetail(session.room)}',
            ),
          );
        }
        for (final Exam exam in exams) {
          final Subject? subject = data.subjectById(exam.subjectId);
          addRow(
            _TodaySchoolRow(
              color: AppColors.danger,
              icon: Icons.quiz_outlined,
              title: exam.title,
              detail: '${subject?.name ?? 'Unknown subject'} • '
                  '${_clockTime(exam.startsAtUtc.toLocal())}–'
                  '${_clockTime(exam.endsAtUtc.toLocal())}'
                  '${_optionalSchoolDetail(exam.room)}',
            ),
          );
        }
        for (final SchoolAssignment assignment in assignments) {
          final Subject? subject = data.subjectById(assignment.subjectId);
          final bool completed =
              assignment.status == PlanningTaskStatus.completed;
          addRow(
            _TodaySchoolRow(
              color: Color(subject?.colorValue ?? 0xFF4F46E5),
              icon: Icons.assignment_outlined,
              title: assignment.title,
              detail: '${subject?.name ?? 'Unknown subject'} • due '
                  '${_clockTime(assignment.dueAtUtc.toLocal())}',
              completed: completed,
              trailing: IconButton(
                tooltip: assignment.isFinished
                    ? 'Reopen assignment'
                    : 'Complete assignment',
                onPressed: () => onToggleAssignment(assignment),
                icon: Icon(
                  assignment.isFinished
                      ? Icons.check_circle_rounded
                      : Icons.circle_outlined,
                  color: completed ? AppColors.secondary : AppColors.primary,
                ),
              ),
            ),
          );
        }

        return SurfaceCard(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Column(children: rows),
        );
      },
    );
  }
}

class _TodaySchoolRow extends StatelessWidget {
  const _TodaySchoolRow({
    required this.color,
    required this.icon,
    required this.title,
    required this.detail,
    this.completed = false,
    this.trailing,
  });

  final Color color;
  final IconData icon;
  final String title;
  final String detail;
  final bool completed;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final Widget? trailingWidget = trailing;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: <Widget>[
          CircleAvatar(
            backgroundColor: color.withValues(alpha: 0.14),
            foregroundColor: color,
            child: Icon(icon, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  title,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    decoration: completed ? TextDecoration.lineThrough : null,
                  ),
                ),
                const SizedBox(height: 2),
                Text(detail, style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
          if (trailingWidget != null) trailingWidget,
        ],
      ),
    );
  }
}

class _ScheduleTile extends StatelessWidget {
  const _ScheduleTile({required this.item, required this.onAction});

  final ScheduledPlanningTask item;
  final ValueChanged<_TodayTaskAction> onAction;

  @override
  Widget build(BuildContext context) {
    final PlanningTask task = item.task;
    final bool completed = task.status == PlanningTaskStatus.completed;
    final bool finished = task.isFinished;
    final Color color = task.kind == PlanningTaskKind.assignment
        ? AppColors.secondary
        : AppColors.primary;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: <Widget>[
          Container(
            width: 4,
            height: 58,
            decoration: BoxDecoration(
              color: finished ? color.withValues(alpha: 0.55) : color,
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  task.title,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    decoration: completed ? TextDecoration.lineThrough : null,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${_timeRange(item)}  •  ${_taskCategory(task)}  •  '
                  '${_statusLabel(task.status)}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: finished ? 'Reopen task' : 'Mark completed',
            onPressed: () => onAction(
              finished ? _TodayTaskAction.reopen : _TodayTaskAction.complete,
            ),
            icon: Icon(
              _statusIcon(task.status),
              color: completed ? AppColors.secondary : color,
            ),
          ),
          PopupMenuButton<_TodayTaskAction>(
            tooltip: 'Task actions',
            onSelected: onAction,
            itemBuilder: (BuildContext context) =>
                <PopupMenuEntry<_TodayTaskAction>>[
              if (finished)
                const PopupMenuItem<_TodayTaskAction>(
                  value: _TodayTaskAction.reopen,
                  child: Text('Reopen'),
                ),
              if (!finished)
                const PopupMenuItem<_TodayTaskAction>(
                  value: _TodayTaskAction.complete,
                  child: Text('Complete'),
                ),
              if (!finished)
                const PopupMenuItem<_TodayTaskAction>(
                  value: _TodayTaskAction.moveToTomorrow,
                  child: Text('Move to tomorrow'),
                ),
              if (!finished)
                const PopupMenuItem<_TodayTaskAction>(
                  value: _TodayTaskAction.skip,
                  child: Text('Skip'),
                ),
              if (!finished)
                const PopupMenuItem<_TodayTaskAction>(
                  value: _TodayTaskAction.cancel,
                  child: Text('Cancel'),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DayClosureCard extends StatelessWidget {
  const _DayClosureCard({required this.closure, required this.onPressed});

  final AsyncValue<DailyClosure?> closure;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final DailyClosure? value = closure.asData?.value;
    final bool isClosed = value != null;
    return SurfaceCard(
      color: Theme.of(context).colorScheme.primaryContainer,
      child: Row(
        children: <Widget>[
          Icon(
            isClosed
                ? Icons.check_circle_outline_rounded
                : Icons.nights_stay_outlined,
            color: Theme.of(context).colorScheme.onPrimaryContainer,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  isClosed ? 'Today is closed' : 'Close your day intentionally',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 3),
                Text(
                  isClosed
                      ? _closureSummary(value)
                      : 'Record a win, a lesson, tomorrow’s focus, and decide '
                          'what happens to unfinished tasks.',
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          FilledButton.tonal(
            onPressed: onPressed,
            child: Text(isClosed ? 'Edit closure' : 'Close day'),
          ),
        ],
      ),
    );
  }
}

class _DailyClosureDialog extends StatefulWidget {
  const _DailyClosureDialog({
    required this.localDay,
    required this.tasks,
    required this.existing,
  });

  final DateTime localDay;
  final List<ScheduledPlanningTask> tasks;
  final DailyClosure? existing;

  @override
  State<_DailyClosureDialog> createState() => _DailyClosureDialogState();
}

class _DailyClosureDialogState extends State<_DailyClosureDialog> {
  late final TextEditingController _winController;
  late final TextEditingController _lessonController;
  late final TextEditingController _tomorrowController;
  late final List<ScheduledPlanningTask> _unfinished;
  late final Map<String, DayTaskResolution> _resolutions;
  late int _mood;

  @override
  void initState() {
    super.initState();
    final DailyClosure? existing = widget.existing;
    _winController = TextEditingController(text: existing?.win);
    _lessonController = TextEditingController(text: existing?.lesson);
    _tomorrowController = TextEditingController(text: existing?.tomorrowFocus);
    _mood = existing?.mood ?? 3;
    _unfinished = widget.tasks
        .where((ScheduledPlanningTask item) => !item.task.isFinished)
        .toList(growable: false);
    _resolutions = <String, DayTaskResolution>{
      for (final ScheduledPlanningTask item in _unfinished)
        item.task.id: DayTaskResolution.keepOpen,
    };
  }

  @override
  void dispose() {
    _winController.dispose();
    _lessonController.dispose();
    _tomorrowController.dispose();
    super.dispose();
  }

  void _submit() {
    Navigator.of(context).pop(
      DailyClosureDraft(
        localDay: widget.localDay,
        mood: _mood,
        win: _winController.text,
        lesson: _lessonController.text,
        tomorrowFocus: _tomorrowController.text,
        taskResolutions: Map<String, DayTaskResolution>.unmodifiable(
          _resolutions,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        widget.existing == null ? 'Close today' : 'Edit today’s closure',
      ),
      content: SizedBox(
        width: 620,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                'How did today feel?',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 8),
              SegmentedButton<int>(
                segments: const <ButtonSegment<int>>[
                  ButtonSegment<int>(value: 1, label: Text('1')),
                  ButtonSegment<int>(value: 2, label: Text('2')),
                  ButtonSegment<int>(value: 3, label: Text('3')),
                  ButtonSegment<int>(value: 4, label: Text('4')),
                  ButtonSegment<int>(value: 5, label: Text('5')),
                ],
                selected: <int>{_mood},
                onSelectionChanged: (Set<int> values) {
                  setState(() => _mood = values.single);
                },
              ),
              const SizedBox(height: 18),
              TextField(
                controller: _winController,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Today’s win',
                  hintText: 'What went well?',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _lessonController,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Lesson or obstacle',
                  hintText: 'What should you remember?',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _tomorrowController,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Tomorrow’s main focus',
                  hintText: 'What matters most tomorrow?',
                ),
              ),
              if (_unfinished.isNotEmpty) ...<Widget>[
                const SizedBox(height: 22),
                Text(
                  'Unfinished tasks',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 4),
                Text(
                  'Choose what happens to each task before saving.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 10),
                ..._unfinished.map(
                  (ScheduledPlanningTask item) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: DropdownButtonFormField<DayTaskResolution>(
                      initialValue: _resolutions[item.task.id],
                      decoration: InputDecoration(labelText: item.task.title),
                      items: DayTaskResolution.values
                          .map(
                            (DayTaskResolution resolution) =>
                                DropdownMenuItem<DayTaskResolution>(
                              value: resolution,
                              child: Text(_resolutionLabel(resolution)),
                            ),
                          )
                          .toList(growable: false),
                      onChanged: (DayTaskResolution? value) {
                        if (value != null) _resolutions[item.task.id] = value;
                      },
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Save closure')),
      ],
    );
  }
}

enum _TodayTaskAction { complete, reopen, moveToTomorrow, skip, cancel }

IconData _statusIcon(PlanningTaskStatus status) {
  switch (status) {
    case PlanningTaskStatus.pending:
    case PlanningTaskStatus.inProgress:
      return Icons.circle_outlined;
    case PlanningTaskStatus.completed:
      return Icons.check_circle_rounded;
    case PlanningTaskStatus.skipped:
      return Icons.skip_next_rounded;
    case PlanningTaskStatus.cancelled:
      return Icons.cancel_outlined;
  }
}

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

String _resolutionLabel(DayTaskResolution resolution) {
  switch (resolution) {
    case DayTaskResolution.keepOpen:
      return 'Keep open today';
    case DayTaskResolution.moveToTomorrow:
      return 'Move to tomorrow';
    case DayTaskResolution.skip:
      return 'Mark skipped';
    case DayTaskResolution.cancel:
      return 'Cancel task';
  }
}

String _closureSummary(DailyClosure closure) {
  final String focus = closure.tomorrowFocus?.trim() ?? '';
  if (focus.isNotEmpty) return 'Tomorrow: $focus';
  return '${closure.completedTaskCount} of '
      '${closure.scheduledTaskCount} scheduled tasks completed.';
}

String _taskCategory(PlanningTask task) {
  if (task.kind == PlanningTaskKind.assignment) return 'Assignment';
  return task.goalId == null ? 'Task' : 'Goal task';
}

String _timeRange(ScheduledPlanningTask item) {
  final DateTime? start = item.startsAtUtc?.toLocal();
  final DateTime? end = item.endsAtUtc?.toLocal();
  if (start == null) return 'Unscheduled';
  if (end == null) return _clockTime(start);
  return '${_clockTime(start)} – ${_clockTime(end)}';
}

Duration _durationOf(ScheduledPlanningTask item) {
  final DateTime? start = item.startsAtUtc;
  final DateTime? end = item.endsAtUtc;
  if (start == null || end == null || !end.isAfter(start)) {
    return const Duration(hours: 1);
  }
  return end.difference(start);
}

String _durationLabel(Duration duration) {
  final int hours = duration.inHours;
  final int minutes = duration.inMinutes.remainder(60);
  if (hours == 0) return '${minutes}m';
  if (minutes == 0) return '${hours}h';
  return '${hours}h ${minutes}m';
}

String _clockTime(DateTime value) {
  final String hour = value.hour.toString().padLeft(2, '0');
  final String minute = value.minute.toString().padLeft(2, '0');
  return '$hour:$minute';
}

String _todayHabitDetail(HabitDayProgress progress) {
  final Habit habit = progress.habit;
  final HabitCheckIn? checkIn = progress.checkIn;
  final String target = habit.direction == HabitDirection.build
      ? 'target ${habit.targetValue} ${habit.unit}'
      : 'limit ${habit.targetValue} ${habit.unit}';
  final String value =
      checkIn == null ? target : '${checkIn.value} ${habit.unit} • $target';
  final int? minute = habit.preferredTimeMinute;
  final String timing = minute == null
      ? ''
      : ' • ${_twoDigits(minute ~/ 60)}:${_twoDigits(minute % 60)}';
  return '$value$timing • ${progress.currentStreak} day streak';
}

String? _wholeNumberValidator(String? value) {
  final int? parsed = int.tryParse(value?.trim() ?? '');
  return parsed == null || parsed < 0 ? 'Enter zero or a whole number' : null;
}

String _twoDigits(int value) => value.toString().padLeft(2, '0');

String _schoolMinuteRange(int startsAtMinute, int endsAtMinute) {
  String label(int minute) {
    final String hour = (minute ~/ 60).toString().padLeft(2, '0');
    final String minutes = (minute % 60).toString().padLeft(2, '0');
    return '$hour:$minutes';
  }

  return '${label(startsAtMinute)}–${label(endsAtMinute)}';
}

String _optionalSchoolDetail(String? value) {
  final String detail = value?.trim() ?? '';
  return detail.isEmpty ? '' : ' • $detail';
}

bool _sameTodayDay(DateTime first, DateTime second) {
  return first.year == second.year &&
      first.month == second.month &&
      first.day == second.day;
}

String _todayRwf(int value) {
  final bool negative = value < 0;
  final String digits = value.abs().toString();
  final StringBuffer grouped = StringBuffer();
  for (int index = 0; index < digits.length; index += 1) {
    if (index > 0 && (digits.length - index) % 3 == 0) grouped.write(',');
    grouped.write(digits[index]);
  }
  return '${negative ? '−' : ''}RWF $grouped';
}

String _greetingName(AccountUser? user) {
  final String? displayName = user?.displayName?.trim();
  if (displayName != null && displayName.isNotEmpty) {
    return displayName.split(RegExp(r'\s+')).first;
  }
  final String? email = user?.email.trim();
  if (email != null && email.contains('@')) {
    return email.substring(0, email.indexOf('@'));
  }
  return 'Ismael';
}

String _longDate(DateTime value) {
  const List<String> weekdays = <String>[
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday',
  ];
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
  return '${weekdays[value.weekday - 1]}, ${value.day} '
      '${months[value.month - 1]}';
}
