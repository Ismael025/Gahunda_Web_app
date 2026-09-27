import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/app_components.dart';
import '../application/review_providers.dart';
import '../domain/review_entities.dart';

class InsightsPage extends ConsumerStatefulWidget {
  const InsightsPage({super.key});

  @override
  ConsumerState<InsightsPage> createState() => _InsightsPageState();
}

class _InsightsPageState extends ConsumerState<InsightsPage> {
  ReviewCadence _cadence = ReviewCadence.weekly;
  late DateTime _anchorDay;

  @override
  void initState() {
    super.initState();
    _anchorDay = reviewDateOnly(DateTime.now());
  }

  ReviewPeriod get _period => ReviewPeriod.containing(_cadence, _anchorDay);

  void _selectCadence(ReviewCadence cadence) {
    setState(() {
      _cadence = cadence;
      _anchorDay = reviewDateOnly(DateTime.now());
    });
  }

  void _showPrevious() {
    setState(() => _anchorDay = _period.previous.startsOnLocal);
  }

  void _showNext() {
    if (_period.isCurrentAt(DateTime.now())) return;
    setState(() => _anchorDay = _period.next.startsOnLocal);
  }

  void _showCurrent() {
    setState(() => _anchorDay = reviewDateOnly(DateTime.now()));
  }

  Future<void> _openReview(ReviewSummary summary) async {
    final PeriodReviewDraft? draft = await showDialog<PeriodReviewDraft>(
      context: context,
      builder: (BuildContext context) => _PeriodReviewDialog(
        period: summary.period,
        existing: summary.savedReview,
      ),
    );
    if (draft == null || !mounted) return;
    try {
      await ref.read(reviewRepositoryProvider).saveReview(draft);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${_cadenceLabel(draft.cadence)} review saved.'),
          ),
        );
      }
    } on Object catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_friendlyError(error))),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final ReviewPeriod period = _period;
    final AsyncValue<ReviewSummary> summary = ref.watch(
      reviewSummaryProvider(period),
    );
    final bool current = period.isCurrentAt(DateTime.now());

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 110),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1180),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const PageIntro(
                eyebrow: 'Review and improve',
                title: 'Learn from what actually happened',
                subtitle:
                    'Real planning, habit, school, money, and reflection data—without judgment.',
              ),
              const SizedBox(height: 20),
              _CadenceSelector(
                selected: _cadence,
                onSelected: _selectCadence,
              ),
              const SizedBox(height: 14),
              _PeriodNavigator(
                period: period,
                isCurrent: current,
                onPrevious: _showPrevious,
                onNext: current ? null : _showNext,
                onCurrent: current ? null : _showCurrent,
              ),
              const SizedBox(height: 18),
              summary.when(
                loading: () => const SurfaceCard(
                  child: Center(child: CircularProgressIndicator()),
                ),
                error: (Object error, StackTrace _) => SurfaceCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      const Text(
                        'Insights could not be calculated.',
                        style: TextStyle(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 6),
                      Text(_friendlyError(error)),
                    ],
                  ),
                ),
                data: (ReviewSummary data) => _InsightsDashboard(
                  summary: data,
                  onReview: () => _openReview(data),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CadenceSelector extends StatelessWidget {
  const _CadenceSelector({required this.selected, required this.onSelected});

  final ReviewCadence selected;
  final ValueChanged<ReviewCadence> onSelected;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: ReviewCadence.values
          .map(
            (ReviewCadence cadence) => ChoiceChip(
              selected: cadence == selected,
              label: Text(_cadenceLabel(cadence)),
              avatar: Icon(_cadenceIcon(cadence), size: 18),
              onSelected: (_) => onSelected(cadence),
            ),
          )
          .toList(growable: false),
    );
  }
}

class _PeriodNavigator extends StatelessWidget {
  const _PeriodNavigator({
    required this.period,
    required this.isCurrent,
    required this.onPrevious,
    required this.onNext,
    required this.onCurrent,
  });

  final ReviewPeriod period;
  final bool isCurrent;
  final VoidCallback onPrevious;
  final VoidCallback? onNext;
  final VoidCallback? onCurrent;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        IconButton(
          tooltip: 'Previous ${_cadenceNoun(period.cadence)}',
          onPressed: onPrevious,
          icon: const Icon(Icons.chevron_left_rounded),
        ),
        Expanded(
          child: Text(
            _periodLabel(period),
            style: Theme.of(context)
                .textTheme
                .titleLarge
                ?.copyWith(fontWeight: FontWeight.w800),
          ),
        ),
        IconButton(
          tooltip: 'Next ${_cadenceNoun(period.cadence)}',
          onPressed: onNext,
          icon: const Icon(Icons.chevron_right_rounded),
        ),
        if (!isCurrent)
          TextButton(onPressed: onCurrent, child: const Text('Current')),
      ],
    );
  }
}

class _InsightsDashboard extends StatelessWidget {
  const _InsightsDashboard({required this.summary, required this.onReview});

  final ReviewSummary summary;
  final VoidCallback onReview;

  @override
  Widget build(BuildContext context) {
    final int taskPercentage = (summary.taskCompletion * 100).round();
    final int habitPercentage = (summary.habitConsistency * 100).round();
    final double? mood = summary.averageMood;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        if (!summary.hasEvidence) ...<Widget>[
          SurfaceCard(
            color: Theme.of(context).colorScheme.primaryContainer,
            child: const Row(
              children: <Widget>[
                Icon(Icons.auto_graph_rounded),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'No evidence is recorded for this period yet. Schedule tasks, check in habits, record money, or close a day and the review will build itself.',
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
        ],
        ResponsiveCardGrid(
          children: <Widget>[
            MetricCard(
              label: 'Plan completion',
              value: summary.plannedTaskCount == 0 ? '—' : '$taskPercentage%',
              caption:
                  '${summary.completedTaskCount} of ${summary.plannedTaskCount} scheduled tasks',
              icon: Icons.task_alt_rounded,
              color: AppColors.primary,
            ),
            MetricCard(
              label: 'Completed planned time',
              value: _durationLabel(summary.completedMinutes),
              caption: '${_durationLabel(summary.plannedMinutes)} planned',
              icon: Icons.timer_outlined,
              color: AppColors.secondary,
            ),
            MetricCard(
              label: 'Habit consistency',
              value:
                  summary.habitScheduledCount == 0 ? '—' : '$habitPercentage%',
              caption:
                  '${summary.habitSuccessfulCount} of ${summary.habitScheduledCount} opportunities',
              icon: Icons.track_changes_rounded,
              color: const Color(0xFF8B5CF6),
            ),
            MetricCard(
              label: 'Money spent',
              value: _formatRwf(summary.spentRwf),
              caption:
                  'Income ${_formatRwf(summary.incomeRwf)} • net ${_signedRwf(summary.netCashFlowRwf)}',
              icon: Icons.account_balance_wallet_outlined,
              color: AppColors.warning,
            ),
          ],
        ),
        const SizedBox(height: 28),
        const SectionHeading(title: 'Plan versus reality'),
        const SizedBox(height: 10),
        SurfaceCard(child: _PlanRealityChart(summary: summary)),
        const SizedBox(height: 28),
        const SectionHeading(title: 'Life-area detail'),
        const SizedBox(height: 10),
        SurfaceCard(
          child: Column(
            children: <Widget>[
              ProgressLine(
                label: 'Scheduled tasks completed',
                valueLabel:
                    '${summary.completedTaskCount} / ${summary.plannedTaskCount}',
                progress: summary.taskCompletion,
                color: AppColors.primary,
              ),
              const SizedBox(height: 20),
              ProgressLine(
                label: 'Habit targets reached',
                valueLabel:
                    '${summary.habitSuccessfulCount} / ${summary.habitScheduledCount}',
                progress: summary.habitConsistency,
                color: AppColors.secondary,
              ),
              const SizedBox(height: 20),
              ProgressLine(
                label: 'Assignments due and completed',
                valueLabel:
                    '${summary.assignmentCompletedCount} / ${summary.assignmentDueCount}',
                progress: summary.assignmentCompletion,
                color: const Color(0xFF8B5CF6),
              ),
              const SizedBox(height: 20),
              ProgressLine(
                label: 'Days intentionally closed',
                valueLabel:
                    '${summary.dailyReflections.length} / ${summary.elapsedDays.length}',
                progress: summary.dayClosureRate,
                color: AppColors.warning,
              ),
              const SizedBox(height: 18),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '${summary.classCount} class occurrence${summary.classCount == 1 ? '' : 's'} • '
                  '${summary.examCount} exam${summary.examCount == 1 ? '' : 's'} • '
                  'average mood ${mood == null ? 'not recorded' : '${mood.toStringAsFixed(1)}/5'}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 28),
        const SectionHeading(title: 'Patterns worth noticing'),
        const SizedBox(height: 10),
        _PatternsGrid(summary: summary),
        const SizedBox(height: 28),
        SectionHeading(
          title: '${_cadenceLabel(summary.period.cadence)} review',
          actionLabel: summary.savedReview == null ? null : 'Edit review',
          onAction: summary.savedReview == null ? null : onReview,
        ),
        const SizedBox(height: 10),
        _SavedReviewCard(summary: summary, onReview: onReview),
        const SizedBox(height: 28),
        const SectionHeading(title: 'Daily reflections'),
        const SizedBox(height: 10),
        _DailyReflectionsCard(reflections: summary.dailyReflections),
      ],
    );
  }
}

class _PlanRealityChart extends StatelessWidget {
  const _PlanRealityChart({required this.summary});

  final ReviewSummary summary;

  @override
  Widget build(BuildContext context) {
    final List<PlanRealityBucket> values = summary.planRealityBuckets;
    final int maximum = values.fold<int>(
      0,
      (int current, PlanRealityBucket item) => math.max(
        current,
        math.max(item.plannedMinutes, item.completedMinutes),
      ),
    );
    if (maximum == 0) {
      return const Row(
        children: <Widget>[
          Icon(Icons.bar_chart_rounded),
          SizedBox(width: 12),
          Expanded(
            child: Text(
              'No scheduled task duration has been recorded for this period.',
            ),
          ),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            _Legend(
              color: AppColors.primary.withValues(alpha: 0.25),
              label: 'Planned',
            ),
            const SizedBox(width: 18),
            const _Legend(color: AppColors.primary, label: 'Completed'),
          ],
        ),
        const SizedBox(height: 20),
        SizedBox(
          height: 190,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: values
                .map(
                  (PlanRealityBucket item) => Expanded(
                    child: _BucketBars(item: item, maximum: maximum),
                  ),
                )
                .toList(growable: false),
          ),
        ),
        const SizedBox(height: 10),
        Text(
          'Completed time means duration attached to completed scheduled tasks. Future days are excluded.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        const SizedBox(width: 6),
        Text(label),
      ],
    );
  }
}

class _BucketBars extends StatelessWidget {
  const _BucketBars({required this.item, required this.maximum});

  final PlanRealityBucket item;
  final int maximum;

  @override
  Widget build(BuildContext context) {
    const double chartHeight = 150;
    return Semantics(
      label:
          '${item.label}: ${item.plannedMinutes} planned minutes and ${item.completedMinutes} completed minutes',
      child: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: <Widget>[
          SizedBox(
            height: chartHeight,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: <Widget>[
                Flexible(
                  child: Container(
                    width: 10,
                    height: chartHeight * item.plannedMinutes / maximum,
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.25),
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(5),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 3),
                Flexible(
                  child: Container(
                    width: 10,
                    height: chartHeight * item.completedMinutes / maximum,
                    decoration: const BoxDecoration(
                      color: AppColors.primary,
                      borderRadius: BorderRadius.vertical(
                        top: Radius.circular(5),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 9),
          Text(
            item.label,
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

class _PatternsGrid extends StatelessWidget {
  const _PatternsGrid({required this.summary});

  final ReviewSummary summary;

  @override
  Widget build(BuildContext context) {
    final List<_Observation> items = <_Observation>[
      _taskObservation(summary),
      _habitObservation(summary),
      _moneyObservation(summary),
      _reflectionObservation(summary),
    ];
    return ResponsiveCardGrid(
      children: items
          .map(
            (_Observation item) => SurfaceCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Icon(item.icon, color: item.color),
                  const SizedBox(height: 12),
                  Text(
                    item.title,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 6),
                  Text(item.body),
                ],
              ),
            ),
          )
          .toList(growable: false),
    );
  }
}

class _SavedReviewCard extends StatelessWidget {
  const _SavedReviewCard({required this.summary, required this.onReview});

  final ReviewSummary summary;
  final VoidCallback onReview;

  @override
  Widget build(BuildContext context) {
    final PeriodReview? review = summary.savedReview;
    if (review == null) {
      return SurfaceCard(
        color: Theme.of(context).colorScheme.primaryContainer,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              'Turn the evidence into your next decision.',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 7),
            Text(
              'Capture wins, obstacles, lessons, and the focus for the next ${_cadenceNoun(summary.period.cadence)}.',
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onReview,
              icon: const Icon(Icons.rate_review_outlined),
              label: Text(
                'Start ${_cadenceLabel(summary.period.cadence).toLowerCase()} review',
              ),
            ),
          ],
        ),
      );
    }
    return SurfaceCard(
      color: Theme.of(context).colorScheme.primaryContainer,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              const Icon(Icons.check_circle_outline_rounded),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Review saved • ${review.overallRating}/5',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _ReviewText(label: 'Wins', value: review.wins),
          if (review.challenges != null) ...<Widget>[
            const SizedBox(height: 12),
            _ReviewText(label: 'Challenges', value: review.challenges!),
          ],
          if (review.lessons != null) ...<Widget>[
            const SizedBox(height: 12),
            _ReviewText(label: 'Lessons', value: review.lessons!),
          ],
          const SizedBox(height: 12),
          _ReviewText(label: 'Next focus', value: review.nextFocus),
        ],
      ),
    );
  }
}

class _ReviewText extends StatelessWidget {
  const _ReviewText({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(label, style: const TextStyle(fontWeight: FontWeight.w800)),
        const SizedBox(height: 3),
        Text(value),
      ],
    );
  }
}

class _DailyReflectionsCard extends StatelessWidget {
  const _DailyReflectionsCard({required this.reflections});

  final List<DailyReflectionSummary> reflections;

  @override
  Widget build(BuildContext context) {
    if (reflections.isEmpty) {
      return const SurfaceCard(
        child: Row(
          children: <Widget>[
            Icon(Icons.nights_stay_outlined),
            SizedBox(width: 12),
            Expanded(
              child: Text(
                'No day closure is saved in this period. Use Today → Close day or Quick add → Reflection.',
              ),
            ),
          ],
        ),
      );
    }
    final List<DailyReflectionSummary> visible =
        reflections.take(6).toList(growable: false);
    final List<Widget> rows = <Widget>[];
    for (final DailyReflectionSummary item in visible) {
      if (rows.isNotEmpty) rows.add(const Divider(height: 24));
      rows.add(_DailyReflectionRow(item: item));
    }
    if (reflections.length > visible.length) {
      rows
        ..add(const Divider(height: 24))
        ..add(
          Text(
            'Showing the latest ${visible.length} of ${reflections.length} daily reflections.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        );
    }
    return SurfaceCard(child: Column(children: rows));
  }
}

class _DailyReflectionRow extends StatelessWidget {
  const _DailyReflectionRow({required this.item});

  final DailyReflectionSummary item;

  @override
  Widget build(BuildContext context) {
    final List<String> details = <String>[
      if (item.win != null) 'Win: ${item.win}',
      if (item.lesson != null) 'Lesson: ${item.lesson}',
      if (item.tomorrowFocus != null) 'Next: ${item.tomorrowFocus}',
    ];
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        CircleAvatar(
          backgroundColor: AppColors.warning.withValues(alpha: 0.14),
          foregroundColor: AppColors.warning,
          child: Text('${item.mood}'),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                _fullDayLabel(item.localDay),
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 3),
              Text(
                '${item.completedTaskCount} of ${item.scheduledTaskCount} tasks • '
                '${_durationLabel(item.completedMinutes)} of ${_durationLabel(item.plannedMinutes)}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              if (details.isNotEmpty) ...<Widget>[
                const SizedBox(height: 6),
                Text(details.join('\n')),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _PeriodReviewDialog extends StatefulWidget {
  const _PeriodReviewDialog({required this.period, required this.existing});

  final ReviewPeriod period;
  final PeriodReview? existing;

  @override
  State<_PeriodReviewDialog> createState() => _PeriodReviewDialogState();
}

class _PeriodReviewDialogState extends State<_PeriodReviewDialog> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  late final TextEditingController _wins;
  late final TextEditingController _challenges;
  late final TextEditingController _lessons;
  late final TextEditingController _nextFocus;
  late int _rating;

  @override
  void initState() {
    super.initState();
    final PeriodReview? existing = widget.existing;
    _rating = existing?.overallRating ?? 3;
    _wins = TextEditingController(text: existing?.wins);
    _challenges = TextEditingController(text: existing?.challenges);
    _lessons = TextEditingController(text: existing?.lessons);
    _nextFocus = TextEditingController(text: existing?.nextFocus);
  }

  @override
  void dispose() {
    _wins.dispose();
    _challenges.dispose();
    _lessons.dispose();
    _nextFocus.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.of(context).pop(
      PeriodReviewDraft(
        cadence: widget.period.cadence,
        periodStartsOnLocal: widget.period.startsOnLocal,
        overallRating: _rating,
        wins: _wins.text,
        challenges: _challenges.text,
        lessons: _lessons.text,
        nextFocus: _nextFocus.text,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final String cadence = _cadenceLabel(widget.period.cadence);
    return AlertDialog(
      title: Text(
        '${widget.existing == null ? 'Complete' : 'Edit'} $cadence review',
      ),
      content: SizedBox(
        width: 620,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  _periodLabel(widget.period),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 16),
                const Text(
                  'How would you rate this period?',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: <Widget>[
                    for (int rating = 1; rating <= 5; rating += 1)
                      ChoiceChip(
                        selected: rating == _rating,
                        label: Text('$rating'),
                        onSelected: (_) => setState(() => _rating = rating),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _wins,
                  autofocus: true,
                  maxLines: 3,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                    labelText: 'Wins',
                    hintText: 'What moved forward?',
                  ),
                  validator: _requiredValidator,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _challenges,
                  maxLines: 3,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                    labelText: 'Challenges (optional)',
                    hintText: 'What got in the way?',
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _lessons,
                  maxLines: 3,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                    labelText: 'Lessons (optional)',
                    hintText: 'What will you change or repeat?',
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _nextFocus,
                  maxLines: 3,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: InputDecoration(
                    labelText:
                        'Next ${_cadenceNoun(widget.period.cadence)} focus',
                    hintText: 'What matters most next?',
                  ),
                  validator: _requiredValidator,
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
        FilledButton(onPressed: _submit, child: const Text('Save review')),
      ],
    );
  }
}

class _Observation {
  const _Observation({
    required this.icon,
    required this.color,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String body;
}

_Observation _taskObservation(ReviewSummary summary) {
  if (summary.plannedTaskCount == 0) {
    return const _Observation(
      icon: Icons.event_note_outlined,
      color: AppColors.warning,
      title: 'No scheduled-task evidence',
      body: 'Schedule important work so plan-versus-reality can measure it.',
    );
  }
  final int percentage = (summary.taskCompletion * 100).round();
  if (percentage >= 80) {
    return _Observation(
      icon: Icons.task_alt_rounded,
      color: AppColors.secondary,
      title: 'Strong follow-through',
      body: '$percentage% of scheduled tasks were completed.',
    );
  }
  if (percentage >= 50) {
    return _Observation(
      icon: Icons.tune_rounded,
      color: AppColors.warning,
      title: 'Leave more breathing room',
      body:
          '$percentage% of scheduled tasks were completed. Review what kept the rest open.',
    );
  }
  return _Observation(
    icon: Icons.compress_rounded,
    color: AppColors.danger,
    title: 'The plan was heavier than reality',
    body:
        '$percentage% of scheduled tasks were completed. Try fewer, clearer commitments.',
  );
}

_Observation _habitObservation(ReviewSummary summary) {
  if (summary.habitScheduledCount == 0) {
    return const _Observation(
      icon: Icons.track_changes_outlined,
      color: AppColors.warning,
      title: 'No habit opportunities',
      body:
          'Create or schedule a habit in Track to reveal consistency patterns.',
    );
  }
  final int percentage = (summary.habitConsistency * 100).round();
  return _Observation(
    icon: percentage >= 70
        ? Icons.local_fire_department_outlined
        : Icons.restart_alt_rounded,
    color: percentage >= 70 ? AppColors.secondary : AppColors.warning,
    title: percentage >= 70
        ? 'Habits are building momentum'
        : 'Habits need recovery',
    body: '$percentage% of scheduled habit targets were reached.',
  );
}

_Observation _moneyObservation(ReviewSummary summary) {
  if (summary.spentRwf == 0 && summary.incomeRwf == 0) {
    return const _Observation(
      icon: Icons.receipt_long_outlined,
      color: AppColors.warning,
      title: 'No money entries',
      body: 'Record income and spending to understand the period’s cash flow.',
    );
  }
  final bool positive = summary.netCashFlowRwf >= 0;
  return _Observation(
    icon: positive ? Icons.trending_up_rounded : Icons.trending_down_rounded,
    color: positive ? AppColors.secondary : AppColors.danger,
    title: positive ? 'Cash flow stayed positive' : 'Spending exceeded income',
    body: 'Net cash flow was ${_signedRwf(summary.netCashFlowRwf)}.',
  );
}

_Observation _reflectionObservation(ReviewSummary summary) {
  final double? mood = summary.averageMood;
  if (summary.dailyReflections.isEmpty) {
    return const _Observation(
      icon: Icons.nights_stay_outlined,
      color: AppColors.warning,
      title: 'Close a day to preserve context',
      body: 'Daily reflections explain why the numbers changed.',
    );
  }
  return _Observation(
    icon: Icons.self_improvement_rounded,
    color: AppColors.primary,
    title:
        '${summary.dailyReflections.length} day${summary.dailyReflections.length == 1 ? '' : 's'} reflected',
    body: 'Average recorded mood was ${mood!.toStringAsFixed(1)}/5.',
  );
}

String? _requiredValidator(String? value) =>
    value == null || value.trim().isEmpty ? 'This field is required.' : null;

String _friendlyError(Object error) {
  final String message = error.toString();
  return message
      .replaceFirst('Bad state: ', '')
      .replaceFirst('Invalid argument(s): ', '')
      .replaceFirst(RegExp(r'^Invalid argument \([^)]*\): '), '');
}

String _cadenceLabel(ReviewCadence cadence) => switch (cadence) {
      ReviewCadence.weekly => 'Weekly',
      ReviewCadence.monthly => 'Monthly',
      ReviewCadence.annual => 'Annual',
    };

String _cadenceNoun(ReviewCadence cadence) => switch (cadence) {
      ReviewCadence.weekly => 'week',
      ReviewCadence.monthly => 'month',
      ReviewCadence.annual => 'year',
    };

IconData _cadenceIcon(ReviewCadence cadence) => switch (cadence) {
      ReviewCadence.weekly => Icons.view_week_outlined,
      ReviewCadence.monthly => Icons.calendar_month_outlined,
      ReviewCadence.annual => Icons.calendar_today_outlined,
    };

String _periodLabel(ReviewPeriod period) {
  switch (period.cadence) {
    case ReviewCadence.weekly:
      final DateTime end = period.lastDay;
      if (period.startsOnLocal.month == end.month) {
        return '${_months[period.startsOnLocal.month - 1]} '
            '${period.startsOnLocal.day}–${end.day}, ${end.year}';
      }
      return '${_shortDay(period.startsOnLocal)}–${_shortDay(end)}, ${end.year}';
    case ReviewCadence.monthly:
      return '${_months[period.startsOnLocal.month - 1]} ${period.startsOnLocal.year}';
    case ReviewCadence.annual:
      return '${period.startsOnLocal.year}';
  }
}

String _durationLabel(int minutes) {
  final int hours = minutes ~/ 60;
  final int remainder = minutes % 60;
  if (hours == 0) return '${remainder}m';
  if (remainder == 0) return '${hours}h';
  return '${hours}h ${remainder}m';
}

String _formatRwf(int value) {
  final bool negative = value < 0;
  final String digits = value.abs().toString();
  final StringBuffer grouped = StringBuffer();
  for (int index = 0; index < digits.length; index += 1) {
    if (index > 0 && (digits.length - index) % 3 == 0) grouped.write(',');
    grouped.write(digits[index]);
  }
  return '${negative ? '−' : ''}RWF $grouped';
}

String _signedRwf(int value) =>
    value >= 0 ? '+${_formatRwf(value)}' : _formatRwf(value);

String _shortDay(DateTime day) =>
    '${_months[day.month - 1].substring(0, 3)} ${day.day}';

String _fullDayLabel(DateTime day) =>
    '${_weekdays[day.weekday - 1]}, ${_months[day.month - 1]} ${day.day}';

const List<String> _months = <String>[
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

const List<String> _weekdays = <String>[
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
  'Sunday',
];
