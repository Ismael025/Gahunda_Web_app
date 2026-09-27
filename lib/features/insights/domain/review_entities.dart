enum ReviewCadence { weekly, monthly, annual }

DateTime reviewDateOnly(DateTime value) =>
    DateTime(value.year, value.month, value.day);

class ReviewPeriod {
  const ReviewPeriod._({
    required this.cadence,
    required this.startsOnLocal,
    required this.endsOnLocalExclusive,
  });

  factory ReviewPeriod.containing(
    ReviewCadence cadence,
    DateTime localDay,
  ) {
    final DateTime day = reviewDateOnly(localDay);
    final DateTime start = switch (cadence) {
      ReviewCadence.weekly =>
        day.subtract(Duration(days: day.weekday - DateTime.monday)),
      ReviewCadence.monthly => DateTime(day.year, day.month),
      ReviewCadence.annual => DateTime(day.year),
    };
    final DateTime end = switch (cadence) {
      ReviewCadence.weekly => start.add(const Duration(days: 7)),
      ReviewCadence.monthly => DateTime(start.year, start.month + 1),
      ReviewCadence.annual => DateTime(start.year + 1),
    };
    return ReviewPeriod._(
      cadence: cadence,
      startsOnLocal: start,
      endsOnLocalExclusive: end,
    );
  }

  final ReviewCadence cadence;
  final DateTime startsOnLocal;
  final DateTime endsOnLocalExclusive;

  DateTime get lastDay =>
      endsOnLocalExclusive.subtract(const Duration(days: 1));

  ReviewPeriod get previous => ReviewPeriod.containing(
        cadence,
        startsOnLocal.subtract(const Duration(days: 1)),
      );

  ReviewPeriod get next => ReviewPeriod.containing(
        cadence,
        endsOnLocalExclusive,
      );

  bool contains(DateTime localDay) {
    final DateTime day = reviewDateOnly(localDay);
    return !day.isBefore(startsOnLocal) && day.isBefore(endsOnLocalExclusive);
  }

  bool isCurrentAt(DateTime localNow) => contains(localNow);

  @override
  bool operator ==(Object other) {
    return other is ReviewPeriod &&
        cadence == other.cadence &&
        startsOnLocal == other.startsOnLocal;
  }

  @override
  int get hashCode => Object.hash(cadence, startsOnLocal);
}

class PeriodReview {
  const PeriodReview({
    required this.id,
    required this.cadence,
    required this.periodStartsOnLocal,
    required this.overallRating,
    required this.wins,
    required this.nextFocus,
    required this.createdAtUtc,
    required this.updatedAtUtc,
    this.challenges,
    this.lessons,
  });

  final String id;
  final ReviewCadence cadence;
  final DateTime periodStartsOnLocal;
  final int overallRating;
  final String wins;
  final String? challenges;
  final String? lessons;
  final String nextFocus;
  final DateTime createdAtUtc;
  final DateTime updatedAtUtc;
}

class PeriodReviewDraft {
  const PeriodReviewDraft({
    required this.cadence,
    required this.periodStartsOnLocal,
    required this.overallRating,
    required this.wins,
    required this.nextFocus,
    this.challenges,
    this.lessons,
  });

  final ReviewCadence cadence;
  final DateTime periodStartsOnLocal;
  final int overallRating;
  final String wins;
  final String? challenges;
  final String? lessons;
  final String nextFocus;
}

class DailyReflectionSummary {
  const DailyReflectionSummary({
    required this.localDay,
    required this.mood,
    required this.scheduledTaskCount,
    required this.completedTaskCount,
    required this.plannedMinutes,
    required this.completedMinutes,
    required this.closedAtUtc,
    this.win,
    this.lesson,
    this.tomorrowFocus,
  });

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
}

class ReviewDayMetrics {
  const ReviewDayMetrics({
    required this.localDay,
    required this.isFuture,
    required this.plannedTaskCount,
    required this.completedTaskCount,
    required this.resolvedTaskCount,
    required this.plannedMinutes,
    required this.completedMinutes,
    required this.habitScheduledCount,
    required this.habitSuccessfulCount,
    required this.spentRwf,
    required this.incomeRwf,
    required this.classCount,
    required this.assignmentDueCount,
    required this.assignmentCompletedCount,
    required this.examCount,
    this.mood,
  });

  final DateTime localDay;
  final bool isFuture;
  final int plannedTaskCount;
  final int completedTaskCount;
  final int resolvedTaskCount;
  final int plannedMinutes;
  final int completedMinutes;
  final int habitScheduledCount;
  final int habitSuccessfulCount;
  final int spentRwf;
  final int incomeRwf;
  final int classCount;
  final int assignmentDueCount;
  final int assignmentCompletedCount;
  final int examCount;
  final int? mood;
}

class PlanRealityBucket {
  const PlanRealityBucket({
    required this.label,
    required this.plannedMinutes,
    required this.completedMinutes,
  });

  final String label;
  final int plannedMinutes;
  final int completedMinutes;
}

class ReviewSummary {
  const ReviewSummary({
    required this.period,
    required this.generatedThroughLocal,
    required this.days,
    required this.dailyReflections,
    this.savedReview,
  });

  final ReviewPeriod period;
  final DateTime generatedThroughLocal;
  final List<ReviewDayMetrics> days;
  final List<DailyReflectionSummary> dailyReflections;
  final PeriodReview? savedReview;

  Iterable<ReviewDayMetrics> get elapsedDays =>
      days.where((ReviewDayMetrics day) => !day.isFuture);

  int get plannedTaskCount => elapsedDays.fold<int>(
        0,
        (int total, ReviewDayMetrics day) => total + day.plannedTaskCount,
      );

  int get completedTaskCount => elapsedDays.fold<int>(
        0,
        (int total, ReviewDayMetrics day) => total + day.completedTaskCount,
      );

  int get resolvedTaskCount => elapsedDays.fold<int>(
        0,
        (int total, ReviewDayMetrics day) => total + day.resolvedTaskCount,
      );

  int get plannedMinutes => elapsedDays.fold<int>(
        0,
        (int total, ReviewDayMetrics day) => total + day.plannedMinutes,
      );

  int get completedMinutes => elapsedDays.fold<int>(
        0,
        (int total, ReviewDayMetrics day) => total + day.completedMinutes,
      );

  int get habitScheduledCount => elapsedDays.fold<int>(
        0,
        (int total, ReviewDayMetrics day) => total + day.habitScheduledCount,
      );

  int get habitSuccessfulCount => elapsedDays.fold<int>(
        0,
        (int total, ReviewDayMetrics day) => total + day.habitSuccessfulCount,
      );

  int get spentRwf => elapsedDays.fold<int>(
        0,
        (int total, ReviewDayMetrics day) => total + day.spentRwf,
      );

  int get incomeRwf => elapsedDays.fold<int>(
        0,
        (int total, ReviewDayMetrics day) => total + day.incomeRwf,
      );

  int get classCount => elapsedDays.fold<int>(
        0,
        (int total, ReviewDayMetrics day) => total + day.classCount,
      );

  int get assignmentDueCount => elapsedDays.fold<int>(
        0,
        (int total, ReviewDayMetrics day) => total + day.assignmentDueCount,
      );

  int get assignmentCompletedCount => elapsedDays.fold<int>(
        0,
        (int total, ReviewDayMetrics day) =>
            total + day.assignmentCompletedCount,
      );

  int get examCount => elapsedDays.fold<int>(
        0,
        (int total, ReviewDayMetrics day) => total + day.examCount,
      );

  int get netCashFlowRwf => incomeRwf - spentRwf;

  double get taskCompletion => plannedTaskCount == 0
      ? 0
      : (completedTaskCount / plannedTaskCount).clamp(0.0, 1.0).toDouble();

  double get completedTimeRatio => plannedMinutes == 0
      ? 0
      : (completedMinutes / plannedMinutes).clamp(0.0, 1.0).toDouble();

  double get habitConsistency => habitScheduledCount == 0
      ? 0
      : (habitSuccessfulCount / habitScheduledCount).clamp(0.0, 1.0).toDouble();

  double get assignmentCompletion => assignmentDueCount == 0
      ? 0
      : (assignmentCompletedCount / assignmentDueCount)
          .clamp(0.0, 1.0)
          .toDouble();

  double get dayClosureRate => elapsedDays.isEmpty
      ? 0
      : (dailyReflections.length / elapsedDays.length)
          .clamp(0.0, 1.0)
          .toDouble();

  double? get averageMood {
    if (dailyReflections.isEmpty) return null;
    final int total = dailyReflections.fold<int>(
      0,
      (int value, DailyReflectionSummary item) => value + item.mood,
    );
    return total / dailyReflections.length;
  }

  bool get hasEvidence =>
      plannedTaskCount > 0 ||
      habitScheduledCount > 0 ||
      spentRwf > 0 ||
      incomeRwf > 0 ||
      classCount > 0 ||
      assignmentDueCount > 0 ||
      examCount > 0 ||
      dailyReflections.isNotEmpty;

  List<PlanRealityBucket> get planRealityBuckets {
    switch (period.cadence) {
      case ReviewCadence.weekly:
        const List<String> labels = <String>[
          'Mon',
          'Tue',
          'Wed',
          'Thu',
          'Fri',
          'Sat',
          'Sun',
        ];
        return <PlanRealityBucket>[
          for (int index = 0; index < days.length; index += 1)
            _bucket(labels[index], <ReviewDayMetrics>[days[index]]),
        ];
      case ReviewCadence.monthly:
        final int bucketCount = ((days.length - 1) ~/ 7) + 1;
        return <PlanRealityBucket>[
          for (int index = 0; index < bucketCount; index += 1)
            _bucket(
              'W${index + 1}',
              days.skip(index * 7).take(7).toList(growable: false),
            ),
        ];
      case ReviewCadence.annual:
        const List<String> labels = <String>[
          'Jan',
          'Feb',
          'Mar',
          'Apr',
          'May',
          'Jun',
          'Jul',
          'Aug',
          'Sep',
          'Oct',
          'Nov',
          'Dec',
        ];
        return <PlanRealityBucket>[
          for (int month = 1; month <= 12; month += 1)
            _bucket(
              labels[month - 1],
              days
                  .where((ReviewDayMetrics day) => day.localDay.month == month)
                  .toList(growable: false),
            ),
        ];
    }
  }

  static PlanRealityBucket _bucket(
    String label,
    List<ReviewDayMetrics> values,
  ) {
    return PlanRealityBucket(
      label: label,
      plannedMinutes: values.fold<int>(
        0,
        (int total, ReviewDayMetrics day) => total + day.plannedMinutes,
      ),
      completedMinutes: values.fold<int>(
        0,
        (int total, ReviewDayMetrics day) => total + day.completedMinutes,
      ),
    );
  }
}
