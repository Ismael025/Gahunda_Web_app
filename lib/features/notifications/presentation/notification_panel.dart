import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/notification_providers.dart';
import '../domain/notification_entities.dart';

Future<void> showNotificationPanel(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (BuildContext context) => const _NotificationPanel(),
  );
}

class NotificationBellButton extends ConsumerWidget {
  const NotificationBellButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final NotificationState state = ref.watch(notificationControllerProvider);
    final bool needsAttention = state.phase == NotificationPhase.disabled ||
        state.phase == NotificationPhase.denied ||
        state.phase == NotificationPhase.error;
    return IconButton(
      tooltip: 'Reminders and notifications',
      onPressed: () => showNotificationPanel(context),
      icon: Badge(
        isLabelVisible: needsAttention,
        smallSize: 7,
        child: Icon(
          state.preferences.enabled
              ? Icons.notifications_active_outlined
              : Icons.notifications_none_rounded,
        ),
      ),
    );
  }
}

class _NotificationPanel extends ConsumerWidget {
  const _NotificationPanel();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final NotificationState state = ref.watch(notificationControllerProvider);
    final NotificationController controller =
        ref.read(notificationControllerProvider.notifier);
    final NotificationPreferences preferences = state.preferences;

    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          20,
          4,
          20,
          24 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 680),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Text(
                  'Reminders and notifications',
                  style: Theme.of(context)
                      .textTheme
                      .headlineSmall
                      ?.copyWith(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 6),
                const Text(
                  kIsWeb
                      ? 'Browser reminders work while Gahunda is open. Your data and core features remain available offline.'
                      : 'Reminders are scheduled on this device and continue to work without an internet connection.',
                ),
                if (kIsWeb) ...<Widget>[
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.secondaryContainer,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Text(
                      'Important: iPhone background reminders require the '
                      'separate Web Push server stage. Closing the web app stops '
                      'timed reminders in this build.',
                    ),
                  ),
                ],
                const SizedBox(height: 18),
                _StatusCard(state: state),
                const SizedBox(height: 14),
                if (state.phase == NotificationPhase.loading)
                  const Center(child: CircularProgressIndicator())
                else if (!preferences.enabled)
                  FilledButton.icon(
                    onPressed: controller.enable,
                    icon: const Icon(Icons.notifications_active_outlined),
                    label: const Text('Enable reminders'),
                  )
                else ...<Widget>[
                  _ReminderSwitch(
                    title: 'Scheduled tasks',
                    subtitle: kIsWeb
                        ? 'Calculated for 5 minutes before start and delivered while Gahunda is open.'
                        : 'Always exactly 5 minutes before the start time.',
                    value: preferences.taskEnabled,
                    onChanged: (bool value) => unawaited(
                      controller.updatePreferences(
                        preferences.copyWith(taskEnabled: value),
                      ),
                    ),
                  ),
                  _ReminderSwitch(
                    title: 'Classes',
                    subtitle: 'Each weekly class inside the active term.',
                    value: preferences.classEnabled,
                    onChanged: (bool value) => unawaited(
                      controller.updatePreferences(
                        preferences.copyWith(classEnabled: value),
                      ),
                    ),
                    trailing: _LeadDropdown(
                      enabled: preferences.classEnabled,
                      value: preferences.classLeadMinutes,
                      values: const <int>[5, 10, 15, 30, 60],
                      onChanged: (int value) => unawaited(
                        controller.updatePreferences(
                          preferences.copyWith(classLeadMinutes: value),
                        ),
                      ),
                    ),
                  ),
                  _ReminderSwitch(
                    title: 'Assignments',
                    subtitle: 'Before the assignment deadline.',
                    value: preferences.assignmentEnabled,
                    onChanged: (bool value) => unawaited(
                      controller.updatePreferences(
                        preferences.copyWith(assignmentEnabled: value),
                      ),
                    ),
                    trailing: _LeadDropdown(
                      enabled: preferences.assignmentEnabled,
                      value: preferences.assignmentLeadMinutes,
                      values: const <int>[60, 360, 720, 1440, 2880],
                      onChanged: (int value) => unawaited(
                        controller.updatePreferences(
                          preferences.copyWith(assignmentLeadMinutes: value),
                        ),
                      ),
                    ),
                  ),
                  _ReminderSwitch(
                    title: 'Exams',
                    subtitle: 'Before the exam begins.',
                    value: preferences.examEnabled,
                    onChanged: (bool value) => unawaited(
                      controller.updatePreferences(
                        preferences.copyWith(examEnabled: value),
                      ),
                    ),
                    trailing: _LeadDropdown(
                      enabled: preferences.examEnabled,
                      value: preferences.examLeadMinutes,
                      values: const <int>[15, 30, 60, 120, 1440],
                      onChanged: (int value) => unawaited(
                        controller.updatePreferences(
                          preferences.copyWith(examLeadMinutes: value),
                        ),
                      ),
                    ),
                  ),
                  _ReminderSwitch(
                    title: 'Habits',
                    subtitle: 'At each habit’s preferred time.',
                    value: preferences.habitEnabled,
                    onChanged: (bool value) => unawaited(
                      controller.updatePreferences(
                        preferences.copyWith(habitEnabled: value),
                      ),
                    ),
                  ),
                  _ReminderSwitch(
                    title: 'Daily closure',
                    subtitle: preferences.dailyClosureEnabled
                        ? 'Every day at ${_minuteLabel(preferences.dailyClosureMinute)}.'
                        : 'Optional evening reminder to reflect and close the day.',
                    value: preferences.dailyClosureEnabled,
                    onChanged: (bool value) => unawaited(
                      controller.updatePreferences(
                        preferences.copyWith(dailyClosureEnabled: value),
                      ),
                    ),
                    trailing: OutlinedButton(
                      onPressed: preferences.dailyClosureEnabled
                          ? () => _chooseClosureTime(
                                context,
                                controller,
                                preferences,
                              )
                          : null,
                      child: Text(
                        _minuteLabel(preferences.dailyClosureMinute),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: <Widget>[
                      OutlinedButton.icon(
                        onPressed: controller.sendTestNotification,
                        icon: const Icon(Icons.send_outlined),
                        label: const Text('Send test'),
                      ),
                      OutlinedButton.icon(
                        onPressed: controller.rebuild,
                        icon: const Icon(Icons.refresh_rounded),
                        label: const Text('Rebuild reminders'),
                      ),
                      TextButton.icon(
                        onPressed: controller.disable,
                        icon: const Icon(Icons.notifications_off_outlined),
                        label: const Text('Disable all'),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _chooseClosureTime(
    BuildContext context,
    NotificationController controller,
    NotificationPreferences preferences,
  ) async {
    final TimeOfDay initial = TimeOfDay(
      hour: preferences.dailyClosureMinute ~/ 60,
      minute: preferences.dailyClosureMinute % 60,
    );
    final TimeOfDay? selected = await showTimePicker(
      context: context,
      initialTime: initial,
    );
    if (selected == null) return;
    await controller.updatePreferences(
      preferences.copyWith(
        dailyClosureMinute: selected.hour * 60 + selected.minute,
      ),
    );
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.state});

  final NotificationState state;

  @override
  Widget build(BuildContext context) {
    final Color color = switch (state.phase) {
      NotificationPhase.ready => Colors.teal,
      NotificationPhase.denied || NotificationPhase.error => Colors.orange,
      NotificationPhase.loading ||
      NotificationPhase.disabled =>
        Theme.of(context).colorScheme.primary,
    };
    final IconData icon = switch (state.phase) {
      NotificationPhase.ready => Icons.notifications_active_outlined,
      NotificationPhase.denied => Icons.notifications_off_outlined,
      NotificationPhase.error => Icons.warning_amber_rounded,
      NotificationPhase.loading => Icons.hourglass_top_rounded,
      NotificationPhase.disabled => Icons.notifications_none_rounded,
    };
    final String title = switch (state.phase) {
      NotificationPhase.ready => 'Reminders ready',
      NotificationPhase.denied => 'Permission needed',
      NotificationPhase.error => 'Reminder setup needs attention',
      NotificationPhase.loading => 'Checking reminders',
      NotificationPhase.disabled => 'Reminders are off',
    };
    return Card(
      color: color.withValues(alpha: 0.10),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Icon(icon, color: color),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(title,
                      style: const TextStyle(fontWeight: FontWeight.w800)),
                  if (state.message != null) ...<Widget>[
                    const SizedBox(height: 4),
                    Text(state.message!),
                  ],
                  if (state.timeZoneName != null) ...<Widget>[
                    const SizedBox(height: 4),
                    Text(
                      'Device timezone: ${state.timeZoneName}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReminderSwitch extends StatelessWidget {
  const _ReminderSwitch({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
    this.trailing,
  });

  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 10, 10),
        child: Row(
          children: <Widget>[
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(title,
                      style: const TextStyle(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 2),
                  Text(subtitle),
                ],
              ),
            ),
            if (trailing != null) ...<Widget>[
              const SizedBox(width: 8),
              trailing!,
            ],
            Switch(value: value, onChanged: onChanged),
          ],
        ),
      ),
    );
  }
}

class _LeadDropdown extends StatelessWidget {
  const _LeadDropdown({
    required this.enabled,
    required this.value,
    required this.values,
    required this.onChanged,
  });

  final bool enabled;
  final int value;
  final List<int> values;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return DropdownButton<int>(
      value: value,
      onChanged: enabled
          ? (int? next) {
              if (next != null) onChanged(next);
            }
          : null,
      items: values
          .map<DropdownMenuItem<int>>(
            (int minutes) => DropdownMenuItem<int>(
              value: minutes,
              child: Text(_leadLabel(minutes)),
            ),
          )
          .toList(growable: false),
    );
  }
}

String _minuteLabel(int minute) {
  final int hour = minute ~/ 60;
  final int displayHour = hour == 0 ? 12 : (hour > 12 ? hour - 12 : hour);
  final String suffix = hour >= 12 ? 'PM' : 'AM';
  return '$displayHour:${(minute % 60).toString().padLeft(2, '0')} $suffix';
}

String _leadLabel(int minutes) {
  if (minutes % 1440 == 0) {
    final int days = minutes ~/ 1440;
    return '${days}d';
  }
  if (minutes % 60 == 0) return '${minutes ~/ 60}h';
  return '${minutes}m';
}
