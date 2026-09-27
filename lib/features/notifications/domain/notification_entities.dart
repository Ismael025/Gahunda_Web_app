enum ReminderKind {
  task,
  classSession,
  assignment,
  exam,
  habit,
  dailyClosure,
}

class NotificationPreferences {
  const NotificationPreferences({
    required this.enabled,
    required this.taskEnabled,
    required this.classEnabled,
    required this.assignmentEnabled,
    required this.examEnabled,
    required this.habitEnabled,
    required this.dailyClosureEnabled,
    required this.classLeadMinutes,
    required this.assignmentLeadMinutes,
    required this.examLeadMinutes,
    required this.dailyClosureMinute,
  });

  const NotificationPreferences.defaults()
      : enabled = false,
        taskEnabled = true,
        classEnabled = true,
        assignmentEnabled = true,
        examEnabled = true,
        habitEnabled = true,
        dailyClosureEnabled = false,
        classLeadMinutes = 10,
        assignmentLeadMinutes = 1440,
        examLeadMinutes = 60,
        dailyClosureMinute = 20 * 60 + 30;

  /// Task reminders intentionally stay fixed at five minutes.
  static const int taskLeadMinutes = 5;

  final bool enabled;
  final bool taskEnabled;
  final bool classEnabled;
  final bool assignmentEnabled;
  final bool examEnabled;
  final bool habitEnabled;
  final bool dailyClosureEnabled;
  final int classLeadMinutes;
  final int assignmentLeadMinutes;
  final int examLeadMinutes;
  final int dailyClosureMinute;

  NotificationPreferences copyWith({
    bool? enabled,
    bool? taskEnabled,
    bool? classEnabled,
    bool? assignmentEnabled,
    bool? examEnabled,
    bool? habitEnabled,
    bool? dailyClosureEnabled,
    int? classLeadMinutes,
    int? assignmentLeadMinutes,
    int? examLeadMinutes,
    int? dailyClosureMinute,
  }) {
    return NotificationPreferences(
      enabled: enabled ?? this.enabled,
      taskEnabled: taskEnabled ?? this.taskEnabled,
      classEnabled: classEnabled ?? this.classEnabled,
      assignmentEnabled: assignmentEnabled ?? this.assignmentEnabled,
      examEnabled: examEnabled ?? this.examEnabled,
      habitEnabled: habitEnabled ?? this.habitEnabled,
      dailyClosureEnabled: dailyClosureEnabled ?? this.dailyClosureEnabled,
      classLeadMinutes: classLeadMinutes ?? this.classLeadMinutes,
      assignmentLeadMinutes:
          assignmentLeadMinutes ?? this.assignmentLeadMinutes,
      examLeadMinutes: examLeadMinutes ?? this.examLeadMinutes,
      dailyClosureMinute: dailyClosureMinute ?? this.dailyClosureMinute,
    );
  }
}

class ReminderRequest {
  const ReminderRequest({
    required this.id,
    required this.kind,
    required this.sourceKey,
    required this.title,
    required this.body,
    required this.scheduledAtUtc,
    required this.payload,
  });

  final int id;
  final ReminderKind kind;
  final String sourceKey;
  final String title;
  final String body;
  final DateTime scheduledAtUtc;
  final String payload;
}

class ReminderPermissionResult {
  const ReminderPermissionResult({
    required this.notificationsAllowed,
    required this.exactTimingAllowed,
  });

  final bool notificationsAllowed;
  final bool exactTimingAllowed;
}

enum NotificationPhase { loading, disabled, ready, denied, error }

class NotificationState {
  const NotificationState({
    required this.phase,
    required this.preferences,
    this.pendingCount = 0,
    this.exactTimingAllowed = true,
    this.timeZoneName,
    this.message,
  });

  const NotificationState.loading()
      : phase = NotificationPhase.loading,
        preferences = const NotificationPreferences.defaults(),
        pendingCount = 0,
        exactTimingAllowed = true,
        timeZoneName = null,
        message = null;

  final NotificationPhase phase;
  final NotificationPreferences preferences;
  final int pendingCount;
  final bool exactTimingAllowed;
  final String? timeZoneName;
  final String? message;
}

int stableNotificationId(String sourceKey) {
  int hash = 0x811C9DC5;
  for (final int codeUnit in sourceKey.codeUnits) {
    hash = ((hash ^ codeUnit) * 0x01000193) & 0xFFFFFFFF;
  }
  final int positive = hash & 0x7FFFFFFF;
  return positive == 0 ? 1 : positive;
}
