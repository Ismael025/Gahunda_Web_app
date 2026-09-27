enum HabitDirection { build, reduce }

enum HabitMeasurement { binary, count, minutes }

const int everyDayWeekdaysMask = 0x7F;

int weekdayMaskFor(Iterable<int> weekdays) {
  int mask = 0;
  for (final int weekday in weekdays) {
    if (weekday < DateTime.monday || weekday > DateTime.sunday) {
      throw ArgumentError.value(weekday, 'weekdays', 'Invalid weekday.');
    }
    mask |= 1 << (weekday - DateTime.monday);
  }
  return mask;
}

class Habit {
  const Habit({
    required this.id,
    required this.name,
    required this.direction,
    required this.measurement,
    required this.targetValue,
    required this.unit,
    required this.weekdaysMask,
    required this.startsOnLocal,
    required this.colorValue,
    required this.isArchived,
    required this.createdAtUtc,
    required this.updatedAtUtc,
    this.description,
    this.preferredTimeMinute,
    this.endsOnLocal,
    this.archivedAtUtc,
  });

  final String id;
  final String name;
  final String? description;
  final HabitDirection direction;
  final HabitMeasurement measurement;
  final int targetValue;
  final String unit;
  final int weekdaysMask;
  final int? preferredTimeMinute;
  final DateTime startsOnLocal;
  final DateTime? endsOnLocal;
  final int colorValue;
  final bool isArchived;
  final DateTime createdAtUtc;
  final DateTime updatedAtUtc;
  final DateTime? archivedAtUtc;

  bool get isEveryDay => weekdaysMask == everyDayWeekdaysMask;

  bool isScheduledOn(DateTime localDay) {
    final DateTime day = dateOnly(localDay);
    if (day.isBefore(startsOnLocal)) return false;
    final DateTime? end = endsOnLocal;
    if (end != null && day.isAfter(end)) return false;
    final int bit = 1 << (day.weekday - DateTime.monday);
    return weekdaysMask & bit != 0;
  }

  List<int> get scheduledWeekdays {
    return <int>[
      for (int weekday = DateTime.monday;
          weekday <= DateTime.sunday;
          weekday += 1)
        if (weekdaysMask & (1 << (weekday - DateTime.monday)) != 0) weekday,
    ];
  }
}

class HabitCheckIn {
  const HabitCheckIn({
    required this.id,
    required this.habitId,
    required this.localDay,
    required this.value,
    required this.recordedAtUtc,
    required this.createdAtUtc,
    required this.updatedAtUtc,
    this.note,
  });

  final String id;
  final String habitId;
  final DateTime localDay;
  final int value;
  final String? note;
  final DateTime recordedAtUtc;
  final DateTime createdAtUtc;
  final DateTime updatedAtUtc;
}

class HabitDayProgress {
  const HabitDayProgress({
    required this.habit,
    required this.localDay,
    required this.currentStreak,
    required this.bestStreak,
    this.checkIn,
  });

  final Habit habit;
  final DateTime localDay;
  final HabitCheckIn? checkIn;
  final int currentStreak;
  final int bestStreak;

  bool get isRecorded => checkIn != null;

  bool get isSuccessful {
    final HabitCheckIn? value = checkIn;
    if (value == null) return false;
    return habit.direction == HabitDirection.build
        ? value.value >= habit.targetValue
        : value.value <= habit.targetValue;
  }

  double get progress {
    final HabitCheckIn? value = checkIn;
    if (value == null) return 0;
    if (habit.direction == HabitDirection.build) {
      if (habit.targetValue <= 0) return 0;
      return (value.value / habit.targetValue).clamp(0.0, 1.0).toDouble();
    }
    if (value.value <= habit.targetValue) return 1;
    if (habit.targetValue == 0) return 0;
    return (habit.targetValue / value.value).clamp(0.0, 1.0).toDouble();
  }
}

class HabitDaySummary {
  const HabitDaySummary({
    required this.localDay,
    required this.scheduledCount,
    required this.completedCount,
    required this.recordedCount,
    required this.isFuture,
  });

  final DateTime localDay;
  final int scheduledCount;
  final int completedCount;
  final int recordedCount;
  final bool isFuture;

  double get completion => scheduledCount == 0
      ? 0
      : (completedCount / scheduledCount).clamp(0.0, 1.0).toDouble();
}

class HabitDashboard {
  const HabitDashboard({
    required this.localDay,
    required this.weekStartsOnLocal,
    required this.activeHabits,
    required this.dayProgress,
    required this.week,
    required this.recoveryCandidates,
  });

  final DateTime localDay;
  final DateTime weekStartsOnLocal;
  final List<Habit> activeHabits;
  final List<HabitDayProgress> dayProgress;
  final List<HabitDaySummary> week;
  final List<Habit> recoveryCandidates;

  int get completedToday => dayProgress
      .where((HabitDayProgress progress) => progress.isSuccessful)
      .length;

  int get scheduledToday => dayProgress.length;

  int get weeklyCompleted => week.fold<int>(
        0,
        (int total, HabitDaySummary day) => total + day.completedCount,
      );

  int get weeklyScheduled => week.fold<int>(
        0,
        (int total, HabitDaySummary day) => total + day.scheduledCount,
      );

  double get weeklyConsistency => weeklyScheduled == 0
      ? 0
      : (weeklyCompleted / weeklyScheduled).clamp(0.0, 1.0).toDouble();

  int get strongestCurrentStreak => dayProgress.fold<int>(
        0,
        (int best, HabitDayProgress progress) =>
            progress.currentStreak > best ? progress.currentStreak : best,
      );

  HabitDaySummary? get strongestDay {
    HabitDaySummary? best;
    for (final HabitDaySummary day in week) {
      if (day.isFuture || day.scheduledCount == 0) continue;
      if (best == null || day.completion > best.completion) best = day;
    }
    return best;
  }
}

class HabitDraft {
  const HabitDraft({
    required this.name,
    required this.direction,
    required this.measurement,
    required this.targetValue,
    required this.unit,
    required this.weekdaysMask,
    required this.startsOnLocal,
    required this.colorValue,
    this.description,
    this.preferredTimeMinute,
    this.endsOnLocal,
  });

  final String name;
  final String? description;
  final HabitDirection direction;
  final HabitMeasurement measurement;
  final int targetValue;
  final String unit;
  final int weekdaysMask;
  final int? preferredTimeMinute;
  final DateTime startsOnLocal;
  final DateTime? endsOnLocal;
  final int colorValue;
}

class HabitCheckInDraft {
  const HabitCheckInDraft({
    required this.habitId,
    required this.localDay,
    required this.value,
    this.note,
  });

  final String habitId;
  final DateTime localDay;
  final int value;
  final String? note;
}

DateTime startOfHabitWeek(DateTime date) {
  final DateTime day = dateOnly(date);
  return day.subtract(Duration(days: day.weekday - DateTime.monday));
}

DateTime dateOnly(DateTime value) => DateTime(
      value.year,
      value.month,
      value.day,
    );
