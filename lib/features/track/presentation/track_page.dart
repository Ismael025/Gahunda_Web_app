import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/app_components.dart';
import '../../behavior/application/habit_providers.dart';
import '../../behavior/domain/habit_entities.dart';

class TrackPage extends ConsumerStatefulWidget {
  const TrackPage({super.key});

  @override
  ConsumerState<TrackPage> createState() => _TrackPageState();
}

class _TrackPageState extends ConsumerState<TrackPage> {
  late DateTime _selectedDay;

  @override
  void initState() {
    super.initState();
    _selectedDay = dateOnly(DateTime.now());
  }

  Future<void> _createHabit() async {
    final HabitDraft? draft = await showDialog<HabitDraft>(
      context: context,
      builder: (BuildContext context) => const _HabitDialog(),
    );
    if (draft == null || !mounted) return;
    await _runMutation(
      () async {
        await ref.read(habitRepositoryProvider).createHabit(draft);
      },
      'Habit created and saved locally.',
    );
  }

  Future<void> _editHabit(Habit habit) async {
    final HabitDraft? draft = await showDialog<HabitDraft>(
      context: context,
      builder: (BuildContext context) => _HabitDialog(initial: habit),
    );
    if (draft == null || !mounted) return;
    await _runMutation(
      () async {
        await ref.read(habitRepositoryProvider).updateHabit(habit.id, draft);
      },
      'Habit updated.',
    );
  }

  Future<void> _archiveHabit(Habit habit) async {
    final bool confirmed = await showDialog<bool>(
          context: context,
          builder: (BuildContext context) => AlertDialog(
            title: const Text('Archive habit?'),
            content: Text(
              '${habit.name} will leave the active list, but its check-in '
              'history will be preserved.',
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Keep habit'),
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
      () => ref.read(habitRepositoryProvider).archiveHabit(habit.id),
      'Habit archived; its history was preserved.',
    );
  }

  Future<void> _toggleBinary(HabitDayProgress progress) async {
    if (progress.checkIn != null) {
      await _runMutation(
        () => ref
            .read(habitRepositoryProvider)
            .clearCheckIn(progress.habit.id, progress.localDay),
        'Check-in cleared.',
      );
      return;
    }
    await _runMutation(
      () async {
        await ref.read(habitRepositoryProvider).recordCheckIn(
              HabitCheckInDraft(
                habitId: progress.habit.id,
                localDay: progress.localDay,
                value: 1,
              ),
            );
      },
      'Habit completed.',
    );
  }

  Future<void> _logProgress(HabitDayProgress progress) async {
    final _CheckInResult? result = await showDialog<_CheckInResult>(
      context: context,
      builder: (BuildContext context) => _CheckInDialog(progress: progress),
    );
    if (result == null || !mounted) return;
    if (result.clear) {
      await _runMutation(
        () => ref
            .read(habitRepositoryProvider)
            .clearCheckIn(progress.habit.id, progress.localDay),
        'Check-in cleared.',
      );
      return;
    }
    await _runMutation(
      () async {
        await ref.read(habitRepositoryProvider).recordCheckIn(
              HabitCheckInDraft(
                habitId: progress.habit.id,
                localDay: progress.localDay,
                value: result.value,
                note: result.note,
              ),
            );
      },
      'Progress recorded.',
    );
  }

  Future<void> _runMutation(
    Future<void> Function() operation,
    String successMessage,
  ) async {
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

  void _selectDay(DateTime day) {
    final DateTime value = dateOnly(day);
    if (value.isAfter(dateOnly(DateTime.now()))) return;
    setState(() => _selectedDay = value);
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<int>(habitCreateRequestProvider, (int? previous, int next) {
      if (previous == null || previous == next) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _createHabit();
      });
    });
    final AsyncValue<HabitDashboard> dashboard = ref.watch(
      habitDashboardProvider(_selectedDay),
    );
    final bool selectedToday = _sameDay(_selectedDay, DateTime.now());

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 110),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1180),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const PageIntro(
                eyebrow: 'Behavior, not perfection',
                title: 'Build a rhythm that works',
                subtitle:
                    'Track what you build, what you reduce, and how quickly '
                    'you recover.',
              ),
              const SizedBox(height: 20),
              _DayNavigator(
                selectedDay: _selectedDay,
                onPrevious: () => _selectDay(
                  _selectedDay.subtract(const Duration(days: 1)),
                ),
                onToday: () => _selectDay(DateTime.now()),
                onNext: selectedToday
                    ? null
                    : () => _selectDay(
                          _selectedDay.add(const Duration(days: 1)),
                        ),
                onAdd: _createHabit,
              ),
              const SizedBox(height: 22),
              dashboard.when(
                loading: () => const SurfaceCard(
                  child: Center(child: CircularProgressIndicator()),
                ),
                error: (Object error, StackTrace _) => SurfaceCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      const Text(
                        'Behavior data could not be loaded.',
                        style: TextStyle(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 6),
                      Text('$error'),
                      const SizedBox(height: 12),
                      OutlinedButton.icon(
                        onPressed: () => ref.invalidate(
                          habitDashboardProvider(_selectedDay),
                        ),
                        icon: const Icon(Icons.refresh_rounded),
                        label: const Text('Try again'),
                      ),
                    ],
                  ),
                ),
                data: _buildDashboard,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDashboard(HabitDashboard dashboard) {
    final HabitDaySummary? strongestDay = dashboard.strongestDay;
    final int percentage = (dashboard.weeklyConsistency * 100).round();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        ResponsiveCardGrid(
          children: <Widget>[
            MetricCard(
              label: 'Completed on this day',
              value: '${dashboard.completedToday} of '
                  '${dashboard.scheduledToday}',
              caption: dashboard.scheduledToday == 0
                  ? 'Nothing scheduled'
                  : 'Recorded against real targets',
              icon: Icons.check_circle_outline_rounded,
              color: AppColors.secondary,
            ),
            MetricCard(
              label: 'Weekly consistency',
              value: '$percentage%',
              caption: '${dashboard.weeklyCompleted} of '
                  '${dashboard.weeklyScheduled} opportunities',
              icon: Icons.show_chart_rounded,
              color: AppColors.primary,
            ),
            MetricCard(
              label: 'Strongest streak',
              value: '${dashboard.strongestCurrentStreak}',
              caption: 'Consecutive scheduled successes',
              icon: Icons.local_fire_department_outlined,
              color: AppColors.warning,
            ),
            MetricCard(
              label: 'Best day this week',
              value: strongestDay == null
                  ? 'Not yet'
                  : _weekdayName(strongestDay.localDay.weekday),
              caption: strongestDay == null
                  ? 'Start with one check-in'
                  : '${strongestDay.completedCount} of '
                      '${strongestDay.scheduledCount} completed',
              icon: Icons.light_mode_outlined,
              color: const Color(0xFF8B5CF6),
            ),
          ],
        ),
        const SizedBox(height: 28),
        SectionHeading(
          title: _sameDay(dashboard.localDay, DateTime.now())
              ? "Today's behaviors"
              : 'Behaviors for ${_shortDate(dashboard.localDay)}',
          actionLabel: 'Add habit',
          onAction: _createHabit,
        ),
        const SizedBox(height: 10),
        if (dashboard.activeHabits.isEmpty)
          _EmptyHabits(onCreate: _createHabit)
        else if (dashboard.dayProgress.isEmpty)
          const SurfaceCard(
            child: Row(
              children: <Widget>[
                Icon(Icons.event_available_outlined),
                SizedBox(width: 12),
                Expanded(
                  child: Text('No active habit is scheduled for this day.'),
                ),
              ],
            ),
          )
        else
          SurfaceCard(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Column(
              children: dashboard.dayProgress
                  .map(
                    (HabitDayProgress progress) => _HabitTile(
                      progress: progress,
                      onCheckIn:
                          progress.habit.measurement == HabitMeasurement.binary
                              ? () => _toggleBinary(progress)
                              : () => _logProgress(progress),
                      onEdit: () => _editHabit(progress.habit),
                      onArchive: () => _archiveHabit(progress.habit),
                    ),
                  )
                  .toList(growable: false),
            ),
          ),
        const SizedBox(height: 28),
        const SectionHeading(title: 'This week at a glance'),
        const SizedBox(height: 10),
        _WeekCard(
          dashboard: dashboard,
          selectedDay: _selectedDay,
          onSelectDay: _selectDay,
        ),
        const SizedBox(height: 28),
        _RecoveryCard(
          candidates: dashboard.recoveryCandidates,
          onReviewYesterday: () => _selectDay(
            dateOnly(DateTime.now()).subtract(const Duration(days: 1)),
          ),
        ),
      ],
    );
  }
}

class _DayNavigator extends StatelessWidget {
  const _DayNavigator({
    required this.selectedDay,
    required this.onPrevious,
    required this.onToday,
    required this.onNext,
    required this.onAdd,
  });

  final DateTime selectedDay;
  final VoidCallback onPrevious;
  final VoidCallback onToday;
  final VoidCallback? onNext;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: <Widget>[
        IconButton(
          tooltip: 'Previous day',
          onPressed: onPrevious,
          icon: const Icon(Icons.chevron_left_rounded),
        ),
        Text(
          _longDate(selectedDay),
          style: Theme.of(context)
              .textTheme
              .titleMedium
              ?.copyWith(fontWeight: FontWeight.w800),
        ),
        TextButton(onPressed: onToday, child: const Text('Today')),
        IconButton(
          tooltip: 'Next day',
          onPressed: onNext,
          icon: const Icon(Icons.chevron_right_rounded),
        ),
        FilledButton.icon(
          onPressed: onAdd,
          icon: const Icon(Icons.add_rounded),
          label: const Text('New habit'),
        ),
      ],
    );
  }
}

class _HabitTile extends StatelessWidget {
  const _HabitTile({
    required this.progress,
    required this.onCheckIn,
    required this.onEdit,
    required this.onArchive,
  });

  final HabitDayProgress progress;
  final VoidCallback onCheckIn;
  final VoidCallback onEdit;
  final VoidCallback onArchive;

  @override
  Widget build(BuildContext context) {
    final Habit habit = progress.habit;
    final HabitCheckIn? checkIn = progress.checkIn;
    final Color color = Color(habit.colorValue);
    final bool successful = progress.isSuccessful;
    final bool overLimit = habit.direction == HabitDirection.reduce &&
        checkIn != null &&
        !successful;
    final String status = checkIn == null
        ? 'Not recorded'
        : successful
            ? habit.direction == HabitDirection.reduce
                ? 'Within limit'
                : 'Target reached'
            : overLimit
                ? 'Over limit'
                : 'In progress';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          CircleAvatar(
            backgroundColor: color.withValues(alpha: 0.14),
            foregroundColor: color,
            child: Icon(_habitIcon(habit.measurement)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        habit.name,
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                    Text(
                      status,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: overLimit
                                ? AppColors.danger
                                : successful
                                    ? AppColors.secondary
                                    : null,
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  '${_valueDescription(progress)}  •  '
                  '${_scheduleDescription(habit)}  •  '
                  '${progress.currentStreak} day streak',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 7),
                LinearProgressIndicator(
                  value: progress.progress,
                  minHeight: 6,
                  borderRadius: BorderRadius.circular(10),
                  color: overLimit ? AppColors.danger : color,
                  backgroundColor: color.withValues(alpha: 0.12),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          if (habit.measurement == HabitMeasurement.binary)
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
              child: Text(checkIn == null ? 'Log' : 'Update'),
            ),
          PopupMenuButton<_HabitAction>(
            tooltip: 'Habit actions',
            onSelected: (_HabitAction action) {
              switch (action) {
                case _HabitAction.edit:
                  onEdit();
                  break;
                case _HabitAction.archive:
                  onArchive();
                  break;
              }
            },
            itemBuilder: (BuildContext context) =>
                const <PopupMenuEntry<_HabitAction>>[
              PopupMenuItem<_HabitAction>(
                value: _HabitAction.edit,
                child: Text('Edit habit'),
              ),
              PopupMenuItem<_HabitAction>(
                value: _HabitAction.archive,
                child: Text('Archive habit'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _WeekCard extends StatelessWidget {
  const _WeekCard({
    required this.dashboard,
    required this.selectedDay,
    required this.onSelectDay,
  });

  final HabitDashboard dashboard;
  final DateTime selectedDay;
  final ValueChanged<DateTime> onSelectDay;

  @override
  Widget build(BuildContext context) {
    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: dashboard.week
                .map(
                  (HabitDaySummary day) => Expanded(
                    child: _DayDot(
                      summary: day,
                      selected: _sameDay(day.localDay, selectedDay),
                      isToday: _sameDay(day.localDay, DateTime.now()),
                      onTap:
                          day.isFuture ? null : () => onSelectDay(day.localDay),
                    ),
                  ),
                )
                .toList(growable: false),
          ),
          const SizedBox(height: 22),
          ProgressLine(
            label: 'Weekly habit target',
            valueLabel: '${dashboard.weeklyCompleted} / '
                '${dashboard.weeklyScheduled} check-ins',
            progress: dashboard.weeklyConsistency,
            color: AppColors.secondary,
          ),
        ],
      ),
    );
  }
}

class _DayDot extends StatelessWidget {
  const _DayDot({
    required this.summary,
    required this.selected,
    required this.isToday,
    required this.onTap,
  });

  final HabitDaySummary summary;
  final bool selected;
  final bool isToday;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final Color color = summary.isFuture || summary.scheduledCount == 0
        ? Theme.of(context).colorScheme.surfaceContainerHighest
        : summary.completion >= 0.8
            ? AppColors.secondary
            : summary.completedCount > 0
                ? AppColors.warning
                : Theme.of(context).colorScheme.surfaceContainerHighest;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Column(
          children: <Widget>[
            Container(
              width: 36,
              height: 36,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
                border: selected || isToday
                    ? Border.all(
                        color: Theme.of(context).colorScheme.primary,
                        width: selected ? 3 : 2,
                      )
                    : null,
              ),
              child: summary.scheduledCount == 0 || summary.isFuture
                  ? Text('${summary.localDay.day}')
                  : Text(
                      '${summary.completedCount}/${summary.scheduledCount}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
            ),
            const SizedBox(height: 6),
            Text(
              _shortWeekday(summary.localDay.weekday),
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ),
    );
  }
}

class _RecoveryCard extends StatelessWidget {
  const _RecoveryCard({
    required this.candidates,
    required this.onReviewYesterday,
  });

  final List<Habit> candidates;
  final VoidCallback onReviewYesterday;

  @override
  Widget build(BuildContext context) {
    if (candidates.isEmpty) {
      return SurfaceCard(
        color: Theme.of(context).colorScheme.tertiaryContainer,
        child: const Row(
          children: <Widget>[
            Icon(Icons.auto_awesome_outlined),
            SizedBox(width: 12),
            Expanded(
              child: Text(
                'No recovery is waiting from yesterday. Keep the rhythm '
                'small and repeatable.',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      );
    }
    final String names =
        candidates.take(3).map((Habit habit) => habit.name).join(', ');
    return SurfaceCard(
      color: Theme.of(context).colorScheme.tertiaryContainer,
      child: Row(
        children: <Widget>[
          const Icon(Icons.restart_alt_rounded),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Text(
                  'Recovery, not punishment',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 3),
                Text(
                  '${candidates.length} habit${candidates.length == 1 ? '' : 's'} '
                  'need attention from yesterday: $names.',
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          FilledButton.tonal(
            onPressed: onReviewYesterday,
            child: const Text('Review yesterday'),
          ),
        ],
      ),
    );
  }
}

class _EmptyHabits extends StatelessWidget {
  const _EmptyHabits({required this.onCreate});

  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    return SurfaceCard(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Column(
            children: <Widget>[
              const Icon(
                Icons.track_changes_rounded,
                size: 46,
                color: AppColors.secondary,
              ),
              const SizedBox(height: 12),
              Text(
                'Create your first habit',
                style: Theme.of(context)
                    .textTheme
                    .titleLarge
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 6),
              const Text(
                'Track a yes/no behavior, a count, time spent, or a limit '
                'you want to stay under.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: onCreate,
                icon: const Icon(Icons.add_rounded),
                label: const Text('Add habit'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HabitDialog extends StatefulWidget {
  const _HabitDialog({this.initial});

  final Habit? initial;

  @override
  State<_HabitDialog> createState() => _HabitDialogState();
}

class _HabitDialogState extends State<_HabitDialog> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _description;
  late final TextEditingController _target;
  late String _unit;
  late HabitDirection _direction;
  late HabitMeasurement _measurement;
  late int _weekdaysMask;
  late DateTime _startsOn;
  DateTime? _endsOn;
  TimeOfDay? _preferredTime;
  late int _color;

  @override
  void initState() {
    super.initState();
    final Habit? initial = widget.initial;
    _name = TextEditingController(text: initial?.name);
    _description = TextEditingController(text: initial?.description);
    _direction = initial?.direction ?? HabitDirection.build;
    _measurement = initial?.measurement ?? HabitMeasurement.binary;
    _target = TextEditingController(
      text: '${initial?.targetValue ?? 1}',
    );
    _unit = initial?.unit ?? 'done';
    _weekdaysMask = initial?.weekdaysMask ?? everyDayWeekdaysMask;
    _startsOn = initial?.startsOnLocal ?? dateOnly(DateTime.now());
    _endsOn = initial?.endsOnLocal;
    final int? minute = initial?.preferredTimeMinute;
    _preferredTime = minute == null
        ? null
        : TimeOfDay(hour: minute ~/ 60, minute: minute % 60);
    _color = initial?.colorValue ?? _habitColors.first.$1;
  }

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    _target.dispose();
    super.dispose();
  }

  void _changeMeasurement(HabitMeasurement measurement) {
    setState(() {
      _measurement = measurement;
      if (measurement == HabitMeasurement.binary) {
        _direction = HabitDirection.build;
        _target.text = '1';
        _unit = 'done';
      } else {
        final List<String> options = _standardUnitsFor(measurement);
        if (!options.contains(_unit)) _unit = options.first;
      }
    });
  }

  Future<void> _pickStart() async {
    final DateTime? selected = await showDatePicker(
      context: context,
      initialDate: _startsOn,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (selected != null) setState(() => _startsOn = selected);
  }

  Future<void> _pickEnd() async {
    final DateTime? selected = await showDatePicker(
      context: context,
      initialDate: _endsOn ?? _startsOn.add(const Duration(days: 30)),
      firstDate: _startsOn,
      lastDate: DateTime(2100),
    );
    if (selected != null) setState(() => _endsOn = selected);
  }

  Future<void> _pickPreferredTime() async {
    final TimeOfDay? selected = await showTimePicker(
      context: context,
      initialTime: _preferredTime ?? const TimeOfDay(hour: 7, minute: 0),
    );
    if (selected != null) setState(() => _preferredTime = selected);
  }

  void _toggleWeekday(int weekday, bool selected) {
    final int bit = 1 << (weekday - DateTime.monday);
    setState(() {
      if (selected) {
        _weekdaysMask |= bit;
      } else {
        _weekdaysMask &= ~bit;
      }
    });
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    if (_weekdaysMask == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select at least one weekday.')),
      );
      return;
    }
    final int target = _measurement == HabitMeasurement.binary
        ? 1
        : int.parse(_target.text.trim());
    if (_direction == HabitDirection.build && target == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('A build target must be at least 1.')),
      );
      return;
    }
    final DateTime? endsOn = _endsOn;
    if (endsOn != null && dateOnly(endsOn).isBefore(dateOnly(_startsOn))) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('End date must be on or after start.')),
      );
      return;
    }
    final TimeOfDay? preferredTime = _preferredTime;
    Navigator.of(context).pop(
      HabitDraft(
        name: _name.text.trim(),
        description: _description.text.trim(),
        direction: _direction,
        measurement: _measurement,
        targetValue: target,
        unit: _measurement == HabitMeasurement.binary ? 'done' : _unit,
        weekdaysMask: _weekdaysMask,
        preferredTimeMinute: preferredTime == null
            ? null
            : preferredTime.hour * 60 + preferredTime.minute,
        startsOnLocal: _startsOn,
        endsOnLocal: endsOn,
        colorValue: _color,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool binary = _measurement == HabitMeasurement.binary;
    final DateTime? endsOn = _endsOn;
    final TimeOfDay? preferredTime = _preferredTime;
    final List<String> unitOptions = _unitOptionsFor(
      _measurement,
      currentUnit: _unit,
    );
    return AlertDialog(
      title: Text(widget.initial == null ? 'Create habit' : 'Edit habit'),
      content: SizedBox(
        width: 620,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                TextFormField(
                  controller: _name,
                  autofocus: widget.initial == null,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                    labelText: 'Habit name',
                    hintText: 'Read before bed',
                  ),
                  validator: _requiredValidator,
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _description,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                    labelText: 'Why it matters (optional)',
                    hintText: 'Wind down without scrolling',
                  ),
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<HabitDirection>(
                  initialValue: _direction,
                  decoration: const InputDecoration(labelText: 'Goal type'),
                  items: const <DropdownMenuItem<HabitDirection>>[
                    DropdownMenuItem<HabitDirection>(
                      value: HabitDirection.build,
                      child: Text('Build or reach a target'),
                    ),
                    DropdownMenuItem<HabitDirection>(
                      value: HabitDirection.reduce,
                      child: Text('Reduce or stay below a limit'),
                    ),
                  ],
                  onChanged: binary
                      ? null
                      : (HabitDirection? value) {
                          if (value != null) {
                            setState(() => _direction = value);
                          }
                        },
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<HabitMeasurement>(
                  initialValue: _measurement,
                  decoration: const InputDecoration(labelText: 'Track as'),
                  items: const <DropdownMenuItem<HabitMeasurement>>[
                    DropdownMenuItem<HabitMeasurement>(
                      value: HabitMeasurement.binary,
                      child: Text('Yes / no'),
                    ),
                    DropdownMenuItem<HabitMeasurement>(
                      value: HabitMeasurement.count,
                      child: Text('Count / quantity'),
                    ),
                    DropdownMenuItem<HabitMeasurement>(
                      value: HabitMeasurement.minutes,
                      child: Text('Time'),
                    ),
                  ],
                  onChanged: (HabitMeasurement? value) {
                    if (value != null) _changeMeasurement(value);
                  },
                ),
                if (!binary) ...<Widget>[
                  const SizedBox(height: 10),
                  _AdaptivePair(
                    first: TextFormField(
                      controller: _target,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: _direction == HabitDirection.build
                            ? 'Daily target'
                            : 'Daily maximum',
                      ),
                      validator: _nonNegativeNumberValidator,
                    ),
                    second: DropdownButtonFormField<String>(
                      key: ValueKey<String>(
                        'unit-${_measurement.name}-$_unit',
                      ),
                      initialValue: _unit,
                      decoration: const InputDecoration(labelText: 'Unit'),
                      items: unitOptions
                          .map(
                            (String unit) => DropdownMenuItem<String>(
                              value: unit,
                              child: Text(_unitLabel(unit)),
                            ),
                          )
                          .toList(growable: false),
                      onChanged: (String? value) {
                        if (value != null) setState(() => _unit = value);
                      },
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                Text(
                  'Scheduled weekdays',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 7,
                  children: List<Widget>.generate(7, (int index) {
                    final int weekday = index + DateTime.monday;
                    final int bit = 1 << index;
                    return FilterChip(
                      label: Text(_shortWeekday(weekday)),
                      selected: _weekdaysMask & bit != 0,
                      onSelected: (bool selected) =>
                          _toggleWeekday(weekday, selected),
                    );
                  }),
                ),
                const SizedBox(height: 12),
                _AdaptivePair(
                  first: _DateOption(
                    label: 'Starts',
                    value: _shortDate(_startsOn),
                    onPressed: _pickStart,
                  ),
                  second: _DateOption(
                    label: 'Ends',
                    value: endsOn == null ? 'No end date' : _shortDate(endsOn),
                    onPressed: _pickEnd,
                    onClear: endsOn == null
                        ? null
                        : () => setState(() => _endsOn = null),
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _pickPreferredTime,
                        icon: const Icon(Icons.schedule_outlined),
                        label: Text(
                          preferredTime == null
                              ? 'Add preferred time'
                              : 'Preferred ${preferredTime.format(context)}',
                        ),
                      ),
                    ),
                    if (preferredTime != null)
                      IconButton(
                        tooltip: 'Remove preferred time',
                        onPressed: () => setState(() => _preferredTime = null),
                        icon: const Icon(Icons.close_rounded),
                      ),
                  ],
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<int>(
                  initialValue: _color,
                  decoration: const InputDecoration(labelText: 'Color'),
                  items: _habitColors
                      .map(
                        ((int, String) option) => DropdownMenuItem<int>(
                          value: option.$1,
                          child: Row(
                            children: <Widget>[
                              CircleAvatar(
                                radius: 7,
                                backgroundColor: Color(option.$1),
                              ),
                              const SizedBox(width: 8),
                              Text(option.$2),
                            ],
                          ),
                        ),
                      )
                      .toList(growable: false),
                  onChanged: (int? value) {
                    if (value != null) setState(() => _color = value);
                  },
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

class _CheckInDialog extends StatefulWidget {
  const _CheckInDialog({required this.progress});

  final HabitDayProgress progress;

  @override
  State<_CheckInDialog> createState() => _CheckInDialogState();
}

class _CheckInDialogState extends State<_CheckInDialog> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  late final TextEditingController _value;
  late final TextEditingController _note;

  @override
  void initState() {
    super.initState();
    _value = TextEditingController(
      text:
          '${widget.progress.checkIn?.value ?? widget.progress.habit.targetValue}',
    );
    _note = TextEditingController(text: widget.progress.checkIn?.note);
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
      _CheckInResult(
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
        width: 440,
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
                validator: _nonNegativeNumberValidator,
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _note,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Note (optional)',
                ),
              ),
            ],
          ),
        ),
      ),
      actions: <Widget>[
        if (widget.progress.checkIn != null)
          TextButton(
            onPressed: () => Navigator.of(context).pop(
              const _CheckInResult(value: 0, clear: true),
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

class _AdaptivePair extends StatelessWidget {
  const _AdaptivePair({required this.first, required this.second});

  final Widget first;
  final Widget second;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        if (constraints.maxWidth < 480) {
          return Column(
            children: <Widget>[
              first,
              const SizedBox(height: 10),
              second,
            ],
          );
        }
        return Row(
          children: <Widget>[
            Expanded(child: first),
            const SizedBox(width: 10),
            Expanded(child: second),
          ],
        );
      },
    );
  }
}

class _DateOption extends StatelessWidget {
  const _DateOption({
    required this.label,
    required this.value,
    required this.onPressed,
    this.onClear,
  });

  final String label;
  final String value;
  final VoidCallback onPressed;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.event_outlined),
      title: Text(label),
      subtitle: Text(value),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (onClear != null)
            IconButton(
              tooltip: 'Clear',
              onPressed: onClear,
              icon: const Icon(Icons.close_rounded),
            ),
          TextButton(onPressed: onPressed, child: const Text('Change')),
        ],
      ),
    );
  }
}

class _CheckInResult {
  const _CheckInResult({
    required this.value,
    this.note = '',
    this.clear = false,
  });

  final int value;
  final String note;
  final bool clear;
}

enum _HabitAction { edit, archive }

String _valueDescription(HabitDayProgress progress) {
  final Habit habit = progress.habit;
  final HabitCheckIn? checkIn = progress.checkIn;
  if (checkIn == null) {
    return habit.direction == HabitDirection.build
        ? 'Target ${habit.targetValue} ${habit.unit}'
        : 'Limit ${habit.targetValue} ${habit.unit}';
  }
  return habit.direction == HabitDirection.build
      ? '${checkIn.value}/${habit.targetValue} ${habit.unit}'
      : '${checkIn.value} ${habit.unit} • limit ${habit.targetValue}';
}

String _scheduleDescription(Habit habit) {
  final String days = habit.isEveryDay
      ? 'Every day'
      : habit.scheduledWeekdays.map(_shortWeekday).join(', ');
  final int? minute = habit.preferredTimeMinute;
  if (minute == null) return days;
  final String hour = (minute ~/ 60).toString().padLeft(2, '0');
  final String minutes = (minute % 60).toString().padLeft(2, '0');
  return '$days at $hour:$minutes';
}

IconData _habitIcon(HabitMeasurement measurement) {
  return switch (measurement) {
    HabitMeasurement.binary => Icons.task_alt_rounded,
    HabitMeasurement.count => Icons.numbers_rounded,
    HabitMeasurement.minutes => Icons.timer_outlined,
  };
}

String? _requiredValidator(String? value) {
  return value == null || value.trim().isEmpty
      ? 'This field is required'
      : null;
}

String? _nonNegativeNumberValidator(String? value) {
  final int? parsed = int.tryParse(value?.trim() ?? '');
  return parsed == null || parsed < 0 ? 'Enter zero or a whole number' : null;
}

List<String> _standardUnitsFor(HabitMeasurement measurement) {
  return switch (measurement) {
    HabitMeasurement.binary => const <String>['done'],
    HabitMeasurement.count => _countUnits,
    HabitMeasurement.minutes => _timeUnits,
  };
}

List<String> _unitOptionsFor(
  HabitMeasurement measurement, {
  required String currentUnit,
}) {
  final List<String> standard = _standardUnitsFor(measurement);
  if (standard.contains(currentUnit)) return standard;
  return <String>[currentUnit, ...standard];
}

String _unitLabel(String unit) {
  if (unit.isEmpty) return unit;
  return '${unit[0].toUpperCase()}${unit.substring(1)}';
}

String _shortDate(DateTime value) {
  final String month = value.month.toString().padLeft(2, '0');
  final String day = value.day.toString().padLeft(2, '0');
  return '${value.year}-$month-$day';
}

String _longDate(DateTime value) {
  return '${_weekdayName(value.weekday)}, ${_shortDate(value)}';
}

String _weekdayName(int weekday) {
  const List<String> names = <String>[
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday',
  ];
  return names[weekday - DateTime.monday];
}

String _shortWeekday(int weekday) {
  const List<String> names = <String>[
    'Mon',
    'Tue',
    'Wed',
    'Thu',
    'Fri',
    'Sat',
    'Sun',
  ];
  return names[weekday - DateTime.monday];
}

bool _sameDay(DateTime first, DateTime second) {
  return first.year == second.year &&
      first.month == second.month &&
      first.day == second.day;
}

const List<(int, String)> _habitColors = <(int, String)>[
  (0xFF0F9D8A, 'Teal'),
  (0xFF4F46E5, 'Indigo'),
  (0xFFF59E0B, 'Amber'),
  (0xFF8B5CF6, 'Purple'),
  (0xFF2563EB, 'Blue'),
  (0xFFEF4444, 'Red'),
];

const List<String> _countUnits = <String>[
  'times',
  'repetitions',
  'sets',
  'steps',
  'pages',
  'glasses',
  'cups',
  'servings',
  'sessions',
  'items',
  'laps',
  'meters',
  'kilometers',
];

const List<String> _timeUnits = <String>[
  'minutes',
  'hours',
  'seconds',
];
