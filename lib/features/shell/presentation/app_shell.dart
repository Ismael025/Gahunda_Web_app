import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../account/presentation/account_access.dart';
import '../../behavior/application/habit_providers.dart';
import '../../insights/presentation/insights_page.dart';
import '../../install/presentation/web_install_help.dart';
import '../../money/application/money_providers.dart';
import '../../money/presentation/money_page.dart';
import '../../notifications/presentation/notification_panel.dart';
import '../../planner/application/planning_providers.dart';
import '../../planner/domain/planning_entities.dart';
import '../../planner/presentation/planner_page.dart';
import '../../school/presentation/school_page.dart';
import '../../today/presentation/today_page.dart';
import '../../track/presentation/track_page.dart';

class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key});

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  int _selectedIndex = 0;

  static const List<Widget> _pages = <Widget>[
    TodayPage(),
    PlannerPage(),
    SchoolPage(),
    TrackPage(),
    MoneyPage(),
    InsightsPage(),
  ];

  static const List<NavigationDestination> _destinations =
      <NavigationDestination>[
    NavigationDestination(
      icon: Icon(Icons.home_outlined),
      selectedIcon: Icon(Icons.home_rounded),
      label: 'Today',
    ),
    NavigationDestination(
      icon: Icon(Icons.calendar_month_outlined),
      selectedIcon: Icon(Icons.calendar_month_rounded),
      label: 'Plan',
    ),
    NavigationDestination(
      icon: Icon(Icons.school_outlined),
      selectedIcon: Icon(Icons.school_rounded),
      label: 'School',
    ),
    NavigationDestination(
      icon: Icon(Icons.track_changes_outlined),
      selectedIcon: Icon(Icons.track_changes_rounded),
      label: 'Track',
    ),
    NavigationDestination(
      icon: Icon(Icons.account_balance_wallet_outlined),
      selectedIcon: Icon(Icons.account_balance_wallet_rounded),
      label: 'Money',
    ),
    NavigationDestination(
      icon: Icon(Icons.insights_outlined),
      selectedIcon: Icon(Icons.insights_rounded),
      label: 'Insights',
    ),
  ];

  void _selectPage(int index) {
    setState(() => _selectedIndex = index);
  }

  Future<void> _openQuickAdd() async {
    final _QuickAddAction? action = await showModalBottomSheet<_QuickAddAction>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (BuildContext context) => const _QuickAddSheet(),
    );
    if (action == null || !mounted) return;
    if (action == _QuickAddAction.habit) {
      _selectPage(3);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          ref.read(habitCreateRequestProvider.notifier).request();
        }
      });
      return;
    }
    if (action == _QuickAddAction.expense) {
      _selectPage(4);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          ref.read(expenseCreateRequestProvider.notifier).request();
        }
      });
      return;
    }
    if (action == _QuickAddAction.reflection) {
      _selectPage(0);
      await openTodayReflectionFlow(context, ref);
      return;
    }
    if (action != _QuickAddAction.task && action != _QuickAddAction.schedule) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content:
              Text('This quick action will be connected in its feature task.'),
        ),
      );
      return;
    }

    final _QuickTaskInput? input = await showDialog<_QuickTaskInput>(
      context: context,
      builder: (BuildContext context) => _QuickTaskDialog(
        scheduleInitially: action == _QuickAddAction.schedule,
      ),
    );
    if (input == null || !mounted) return;
    try {
      await ref.read(planningRepositoryProvider).createTask(
            PlanningTaskDraft(
              title: input.title,
              notes: input.notes,
              startsAtUtc: input.scheduled ? input.startsAtLocal.toUtc() : null,
              duration: Duration(minutes: input.durationMinutes),
            ),
          );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              input.scheduled
                  ? 'Task added to your local schedule.'
                  : 'Unscheduled task saved locally.',
            ),
          ),
        );
      }
    } on Object catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not save task: $error')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final bool wide = constraints.maxWidth >= 900;

        return Scaffold(
          appBar: AppBar(
            titleSpacing: wide ? 28 : 16,
            title: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Container(
                  width: 34,
                  height: 34,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primary,
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: const Text(
                    'G',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                const Text(
                  'Gahunda',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
              ],
            ),
            actions: <Widget>[
              if (kIsWeb) const WebInstallButton(),
              const NotificationBellButton(),
              const AccountAvatarButton(),
            ],
          ),
          body: Row(
            children: <Widget>[
              if (wide)
                NavigationRail(
                  selectedIndex: _selectedIndex,
                  onDestinationSelected: _selectPage,
                  labelType: NavigationRailLabelType.all,
                  groupAlignment: -0.75,
                  destinations: _destinations
                      .map(
                        (NavigationDestination item) =>
                            NavigationRailDestination(
                          icon: item.icon,
                          selectedIcon: item.selectedIcon,
                          label: Text(item.label),
                        ),
                      )
                      .toList(),
                ),
              Expanded(
                child: IndexedStack(
                  index: _selectedIndex,
                  children: _pages,
                ),
              ),
            ],
          ),
          bottomNavigationBar: wide
              ? null
              : NavigationBar(
                  selectedIndex: _selectedIndex,
                  onDestinationSelected: _selectPage,
                  labelBehavior:
                      NavigationDestinationLabelBehavior.onlyShowSelected,
                  destinations: _destinations,
                ),
          floatingActionButton: FloatingActionButton.extended(
            onPressed: _openQuickAdd,
            icon: const Icon(Icons.add_rounded),
            label: const Text('Quick add'),
          ),
        );
      },
    );
  }
}

class _QuickAddSheet extends StatelessWidget {
  const _QuickAddSheet();

  @override
  Widget build(BuildContext context) {
    const List<(_QuickAddAction, IconData, String, String)> actions =
        <(_QuickAddAction, IconData, String, String)>[
      (
        _QuickAddAction.task,
        Icons.task_alt_rounded,
        'Task',
        'Something you need to complete',
      ),
      (
        _QuickAddAction.schedule,
        Icons.calendar_today_rounded,
        'Schedule',
        'Reserve time on your day',
      ),
      (
        _QuickAddAction.expense,
        Icons.payments_outlined,
        'Expense',
        'Record money you spent',
      ),
      (
        _QuickAddAction.habit,
        Icons.auto_awesome_outlined,
        'Habit',
        'Add a behavior to track',
      ),
      (
        _QuickAddAction.reflection,
        Icons.edit_note_rounded,
        'Reflection',
        'Write a quick note about today',
      ),
    ];

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              'Quick add',
              style: Theme.of(context)
                  .textTheme
                  .headlineSmall
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            ...actions.map(
              ((_QuickAddAction, IconData, String, String) action) => ListTile(
                contentPadding: EdgeInsets.zero,
                leading: CircleAvatar(child: Icon(action.$2)),
                title: Text(action.$3),
                subtitle: Text(action.$4),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => Navigator.of(context).pop(action.$1),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _QuickTaskDialog extends StatefulWidget {
  const _QuickTaskDialog({required this.scheduleInitially});

  final bool scheduleInitially;

  @override
  State<_QuickTaskDialog> createState() => _QuickTaskDialogState();
}

class _QuickTaskDialogState extends State<_QuickTaskDialog> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _notesController = TextEditingController();
  late bool _scheduled;
  late DateTime _startsAtLocal;
  int _durationMinutes = 60;

  @override
  void initState() {
    super.initState();
    _scheduled = widget.scheduleInitially;
    final DateTime now = DateTime.now();
    final DateTime candidate = now.add(const Duration(hours: 1));
    final bool candidateIsToday = candidate.year == now.year &&
        candidate.month == now.month &&
        candidate.day == now.day;
    final DateTime nextHour = candidateIsToday
        ? candidate
        : DateTime(now.year, now.month, now.day, 23, 59);
    _startsAtLocal = DateTime(
      nextHour.year,
      nextHour.month,
      nextHour.day,
      nextHour.hour,
    );
  }

  @override
  void dispose() {
    _titleController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _chooseTime() async {
    final DateTime? date = await showDatePicker(
      context: context,
      initialDate: _startsAtLocal,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (date == null || !mounted) return;
    final TimeOfDay? time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_startsAtLocal),
    );
    if (time == null) return;
    setState(() {
      _startsAtLocal = DateTime(
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
      _QuickTaskInput(
        title: _titleController.text.trim(),
        notes: _notesController.text.trim(),
        scheduled: _scheduled,
        startsAtLocal: _startsAtLocal,
        durationMinutes: _durationMinutes,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add task'),
      content: SizedBox(
        width: 440,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              TextFormField(
                controller: _titleController,
                autofocus: true,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Task title',
                  hintText: 'What needs to be done?',
                ),
                validator: (String? value) =>
                    value == null || value.trim().isEmpty
                        ? 'Task title is required'
                        : null,
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _notesController,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Notes (optional)',
                  hintText: 'Useful details or a next action',
                ),
                maxLines: 2,
              ),
              const SizedBox(height: 10),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Schedule this task'),
                value: _scheduled,
                onChanged: (bool value) => setState(() => _scheduled = value),
              ),
              if (_scheduled)
                Column(
                  children: <Widget>[
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.schedule_rounded),
                      title: Text(_formatLocalDateTime(_startsAtLocal)),
                      trailing: TextButton(
                        onPressed: _chooseTime,
                        child: const Text('Change'),
                      ),
                    ),
                    DropdownButtonFormField<int>(
                      initialValue: _durationMinutes,
                      decoration: const InputDecoration(
                        labelText: 'Duration',
                        prefixIcon: Icon(Icons.timer_outlined),
                      ),
                      items: const <DropdownMenuItem<int>>[
                        DropdownMenuItem<int>(
                          value: 30,
                          child: Text('30 minutes'),
                        ),
                        DropdownMenuItem<int>(
                          value: 60,
                          child: Text('1 hour'),
                        ),
                        DropdownMenuItem<int>(
                          value: 90,
                          child: Text('1 hour 30 minutes'),
                        ),
                        DropdownMenuItem<int>(
                          value: 120,
                          child: Text('2 hours'),
                        ),
                      ],
                      onChanged: (int? value) {
                        if (value != null) {
                          setState(() => _durationMinutes = value);
                        }
                      },
                    ),
                  ],
                ),
            ],
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

class _QuickTaskInput {
  const _QuickTaskInput({
    required this.title,
    required this.notes,
    required this.scheduled,
    required this.startsAtLocal,
    required this.durationMinutes,
  });

  final String title;
  final String notes;
  final bool scheduled;
  final DateTime startsAtLocal;
  final int durationMinutes;
}

enum _QuickAddAction { task, schedule, expense, habit, reflection }

String _formatLocalDateTime(DateTime value) {
  final String day = value.day.toString().padLeft(2, '0');
  final String month = value.month.toString().padLeft(2, '0');
  final String hour = value.hour.toString().padLeft(2, '0');
  final String minute = value.minute.toString().padLeft(2, '0');
  return '${value.year}-$month-$day at $hour:$minute';
}
