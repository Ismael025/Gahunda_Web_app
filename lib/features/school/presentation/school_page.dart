import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/app_components.dart';
import '../../planner/application/planning_providers.dart';
import '../../planner/domain/planning_entities.dart';
import '../application/school_providers.dart';
import '../domain/school_entities.dart';

class SchoolPage extends ConsumerStatefulWidget {
  const SchoolPage({super.key});

  @override
  ConsumerState<SchoolPage> createState() => _SchoolPageState();
}

class _SchoolPageState extends ConsumerState<SchoolPage> {
  late DateTime _weekStart;

  @override
  void initState() {
    super.initState();
    _weekStart = startOfLocalWeek(DateTime.now());
  }

  void _changeWeek(int weeks) {
    setState(() {
      _weekStart = _weekStart.add(Duration(days: weeks * 7));
    });
  }

  Future<void> _createTerm() async {
    final AcademicTermDraft? draft = await showDialog<AcademicTermDraft>(
      context: context,
      builder: (BuildContext context) => const _TermDialog(),
    );
    if (draft == null || !mounted) return;
    await _runMutation(
      () async {
        await ref.read(schoolRepositoryProvider).createAcademicTerm(draft);
      },
      'Academic term created and activated.',
    );
  }

  Future<void> _createSubject(AcademicTerm? term) async {
    if (term == null) {
      _showMessage('Create an academic term first.');
      return;
    }
    final SubjectDraft? draft = await showDialog<SubjectDraft>(
      context: context,
      builder: (BuildContext context) => _SubjectDialog(termId: term.id),
    );
    if (draft == null || !mounted) return;
    await _runMutation(
      () async {
        await ref.read(schoolRepositoryProvider).createSubject(draft);
      },
      'Subject added to ${term.name}.',
    );
  }

  Future<void> _createSession(List<Subject> subjects) async {
    if (subjects.isEmpty) {
      _showMessage('Add at least one subject first.');
      return;
    }
    final ClassSessionDraft? draft = await showDialog<ClassSessionDraft>(
      context: context,
      builder: (BuildContext context) => _ClassSessionDialog(
        subjects: subjects,
      ),
    );
    if (draft == null || !mounted) return;
    await _runMutation(
      () async {
        await ref.read(schoolRepositoryProvider).createClassSession(draft);
      },
      'Weekly class added.',
    );
  }

  Future<void> _createAssignment(List<Subject> subjects) async {
    if (subjects.isEmpty) {
      _showMessage('Add at least one subject first.');
      return;
    }
    final SchoolAssignmentDraft? draft =
        await showDialog<SchoolAssignmentDraft>(
      context: context,
      builder: (BuildContext context) => _AssignmentDialog(
        subjects: subjects,
      ),
    );
    if (draft == null || !mounted) return;
    await _runMutation(
      () async {
        await ref.read(schoolRepositoryProvider).createAssignment(draft);
      },
      'Assignment added to School and Plan.',
    );
  }

  Future<void> _createExam(List<Subject> subjects) async {
    if (subjects.isEmpty) {
      _showMessage('Add at least one subject first.');
      return;
    }
    final ExamDraft? draft = await showDialog<ExamDraft>(
      context: context,
      builder: (BuildContext context) => _ExamDialog(subjects: subjects),
    );
    if (draft == null || !mounted) return;
    await _runMutation(
      () async {
        await ref.read(schoolRepositoryProvider).createExam(draft);
      },
      'Exam added to the school calendar.',
    );
  }

  Future<void> _setActiveTerm(String termId) {
    return _runMutation(
      () => ref.read(schoolRepositoryProvider).setActiveTerm(termId),
      'Active academic term changed.',
    );
  }

  Future<void> _toggleAssignment(SchoolAssignment assignment) {
    final PlanningTaskStatus next = assignment.isFinished
        ? PlanningTaskStatus.pending
        : PlanningTaskStatus.completed;
    return _runMutation(
      () => ref
          .read(planningRepositoryProvider)
          .changeTaskStatus(assignment.taskId, next),
      next == PlanningTaskStatus.completed
          ? 'Assignment completed.'
          : 'Assignment reopened.',
    );
  }

  Future<void> _deleteSession(ClassSession session) {
    return _runMutation(
      () => ref.read(schoolRepositoryProvider).deleteClassSession(session.id),
      'Class removed from the weekly timetable.',
    );
  }

  Future<void> _deleteExam(Exam exam) {
    return _runMutation(
      () => ref.read(schoolRepositoryProvider).deleteExam(exam.id),
      'Exam removed.',
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

  @override
  Widget build(BuildContext context) {
    final AsyncValue<SchoolWeekData> school = ref.watch(
      schoolWeekProvider(_weekStart),
    );

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 110),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1280),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const PageIntro(
                eyebrow: 'School mode',
                title: 'Own your school week',
                subtitle:
                    'Keep classes, coursework, and exams in one offline plan.',
              ),
              const SizedBox(height: 22),
              school.when(
                loading: () => const SurfaceCard(
                  child: Center(child: CircularProgressIndicator()),
                ),
                error: (Object error, StackTrace _) => SurfaceCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      const Text(
                        'School data could not be loaded.',
                        style: TextStyle(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 6),
                      Text('$error'),
                      const SizedBox(height: 12),
                      OutlinedButton.icon(
                        onPressed: () => ref.invalidate(
                          schoolWeekProvider(_weekStart),
                        ),
                        icon: const Icon(Icons.refresh_rounded),
                        label: const Text('Try again'),
                      ),
                    ],
                  ),
                ),
                data: _buildSchoolContent,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSchoolContent(SchoolWeekData data) {
    final AcademicTerm? term = data.activeTerm;
    final int classCount = data.sessions.length;
    final int openAssignments = data.assignments
        .where((SchoolAssignment assignment) => !assignment.isFinished)
        .length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _TermAndActions(
          terms: data.terms,
          activeTerm: term,
          onTermChanged: _setActiveTerm,
          onAddTerm: _createTerm,
          onAddSubject: () => _createSubject(term),
          onAddClass: () => _createSession(data.subjects),
          onAddAssignment: () => _createAssignment(data.subjects),
          onAddExam: () => _createExam(data.subjects),
        ),
        const SizedBox(height: 22),
        ResponsiveCardGrid(
          children: <Widget>[
            MetricCard(
              label: 'Active term',
              value: term?.name ?? 'Not set',
              caption: term == null
                  ? 'Create your first term'
                  : '${_shortDate(term.startsOnLocal)} – '
                      '${_shortDate(term.endsOnLocal)}',
              icon: Icons.school_outlined,
              color: AppColors.primary,
            ),
            MetricCard(
              label: 'Subjects',
              value: '${data.subjects.length}',
              caption: 'In the active term',
              icon: Icons.menu_book_outlined,
              color: const Color(0xFF8B5CF6),
            ),
            MetricCard(
              label: 'Weekly classes',
              value: '$classCount',
              caption: 'Recurring sessions',
              icon: Icons.calendar_view_week_outlined,
              color: AppColors.secondary,
            ),
            MetricCard(
              label: 'Due this week',
              value: '${openAssignments + data.exams.length}',
              caption: '$openAssignments assignments • '
                  '${data.exams.length} exams',
              icon: Icons.assignment_outlined,
              color: AppColors.warning,
            ),
          ],
        ),
        const SizedBox(height: 28),
        _WeekNavigator(
          weekStart: _weekStart,
          onPrevious: () => _changeWeek(-1),
          onToday: () => setState(() {
            _weekStart = startOfLocalWeek(DateTime.now());
          }),
          onNext: () => _changeWeek(1),
        ),
        const SizedBox(height: 10),
        if (term == null)
          _SchoolEmptyState(
            icon: Icons.school_outlined,
            title: 'Create your academic term',
            message:
                'A term is the container for subjects, classes, assignments, '
                'and exams.',
            buttonLabel: 'Add academic term',
            onPressed: _createTerm,
          )
        else if (data.subjects.isEmpty)
          _SchoolEmptyState(
            icon: Icons.menu_book_outlined,
            title: 'Add your first subject',
            message:
                'Subjects connect every class, assignment, and exam to the '
                'right course.',
            buttonLabel: 'Add subject',
            onPressed: () => _createSubject(term),
          )
        else
          _WeeklyTimetable(
            data: data,
            onDeleteSession: _deleteSession,
            onDeleteExam: _deleteExam,
          ),
        const SizedBox(height: 28),
        SectionHeading(
          title: 'Subjects',
          actionLabel: term == null ? null : 'Add subject',
          onAction: term == null ? null : () => _createSubject(term),
        ),
        const SizedBox(height: 10),
        _SubjectsCard(subjects: data.subjects),
        const SizedBox(height: 28),
        SectionHeading(
          title: 'Assignments due this week',
          actionLabel: data.subjects.isEmpty ? null : 'Add assignment',
          onAction: data.subjects.isEmpty
              ? null
              : () => _createAssignment(data.subjects),
        ),
        const SizedBox(height: 10),
        _AssignmentsCard(
          assignments: data.assignments,
          subjects: data.subjects,
          onToggle: _toggleAssignment,
        ),
        const SizedBox(height: 28),
        SectionHeading(
          title: 'Exams this week',
          actionLabel: data.subjects.isEmpty ? null : 'Add exam',
          onAction:
              data.subjects.isEmpty ? null : () => _createExam(data.subjects),
        ),
        const SizedBox(height: 10),
        _ExamsCard(
          exams: data.exams,
          subjects: data.subjects,
          onDelete: _deleteExam,
        ),
      ],
    );
  }
}

class _TermAndActions extends StatelessWidget {
  const _TermAndActions({
    required this.terms,
    required this.activeTerm,
    required this.onTermChanged,
    required this.onAddTerm,
    required this.onAddSubject,
    required this.onAddClass,
    required this.onAddAssignment,
    required this.onAddExam,
  });

  final List<AcademicTerm> terms;
  final AcademicTerm? activeTerm;
  final ValueChanged<String> onTermChanged;
  final VoidCallback onAddTerm;
  final VoidCallback onAddSubject;
  final VoidCallback onAddClass;
  final VoidCallback onAddAssignment;
  final VoidCallback onAddExam;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: <Widget>[
        if (terms.isNotEmpty)
          SizedBox(
            width: 230,
            child: DropdownButtonFormField<String>(
              key: ValueKey<String?>(activeTerm?.id),
              initialValue: activeTerm?.id,
              decoration: const InputDecoration(
                labelText: 'Active term',
                prefixIcon: Icon(Icons.school_outlined),
              ),
              items: terms
                  .map(
                    (AcademicTerm term) => DropdownMenuItem<String>(
                      value: term.id,
                      child: Text(term.name),
                    ),
                  )
                  .toList(growable: false),
              onChanged: (String? value) {
                if (value != null && value != activeTerm?.id) {
                  onTermChanged(value);
                }
              },
            ),
          ),
        OutlinedButton.icon(
          onPressed: onAddTerm,
          icon: const Icon(Icons.add_rounded),
          label: const Text('Term'),
        ),
        OutlinedButton.icon(
          onPressed: onAddSubject,
          icon: const Icon(Icons.menu_book_outlined),
          label: const Text('Subject'),
        ),
        FilledButton.tonalIcon(
          onPressed: onAddClass,
          icon: const Icon(Icons.add_alarm_outlined),
          label: const Text('Class'),
        ),
        FilledButton.tonalIcon(
          onPressed: onAddAssignment,
          icon: const Icon(Icons.assignment_outlined),
          label: const Text('Assignment'),
        ),
        FilledButton.tonalIcon(
          onPressed: onAddExam,
          icon: const Icon(Icons.quiz_outlined),
          label: const Text('Exam'),
        ),
      ],
    );
  }
}

class _WeekNavigator extends StatelessWidget {
  const _WeekNavigator({
    required this.weekStart,
    required this.onPrevious,
    required this.onToday,
    required this.onNext,
  });

  final DateTime weekStart;
  final VoidCallback onPrevious;
  final VoidCallback onToday;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    final DateTime end = weekStart.add(const Duration(days: 6));
    return Row(
      children: <Widget>[
        Expanded(
          child: Text(
            '${_shortDate(weekStart)} – ${_shortDate(end)}',
            style: Theme.of(context)
                .textTheme
                .titleLarge
                ?.copyWith(fontWeight: FontWeight.w800),
          ),
        ),
        IconButton(
          onPressed: onPrevious,
          tooltip: 'Previous week',
          icon: const Icon(Icons.chevron_left_rounded),
        ),
        TextButton(onPressed: onToday, child: const Text('This week')),
        IconButton(
          onPressed: onNext,
          tooltip: 'Next week',
          icon: const Icon(Icons.chevron_right_rounded),
        ),
      ],
    );
  }
}

class _WeeklyTimetable extends StatelessWidget {
  const _WeeklyTimetable({
    required this.data,
    required this.onDeleteSession,
    required this.onDeleteExam,
  });

  final SchoolWeekData data;
  final ValueChanged<ClassSession> onDeleteSession;
  final ValueChanged<Exam> onDeleteExam;

  @override
  Widget build(BuildContext context) {
    return SurfaceCard(
      padding: const EdgeInsets.all(12),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: List<Widget>.generate(7, (int index) {
            final DateTime date = data.weekStartsOnLocal.add(
              Duration(days: index),
            );
            final List<ClassSession> sessions = data.sessionsForLocalDay(date);
            final List<Exam> exams = data.examsForLocalDay(date);
            return SizedBox(
              width: 172,
              child: Padding(
                padding: const EdgeInsets.all(6),
                child: _SchoolDayColumn(
                  date: date,
                  sessions: sessions,
                  exams: exams,
                  data: data,
                  onDeleteSession: onDeleteSession,
                  onDeleteExam: onDeleteExam,
                ),
              ),
            );
          }),
        ),
      ),
    );
  }
}

class _SchoolDayColumn extends StatelessWidget {
  const _SchoolDayColumn({
    required this.date,
    required this.sessions,
    required this.exams,
    required this.data,
    required this.onDeleteSession,
    required this.onDeleteExam,
  });

  final DateTime date;
  final List<ClassSession> sessions;
  final List<Exam> exams;
  final SchoolWeekData data;
  final ValueChanged<ClassSession> onDeleteSession;
  final ValueChanged<Exam> onDeleteExam;

  @override
  Widget build(BuildContext context) {
    final bool today = _sameLocalDay(date, DateTime.now());
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: today
                ? Theme.of(context).colorScheme.primaryContainer
                : Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                _weekdayName(date.weekday),
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              Text('${date.day}/${date.month}'),
            ],
          ),
        ),
        const SizedBox(height: 8),
        if (sessions.isEmpty && exams.isEmpty)
          const Padding(
            padding: EdgeInsets.all(8),
            child: Text('No classes'),
          ),
        ...sessions.map((ClassSession session) {
          final Subject? subject = data.subjectById(session.subjectId);
          return _SchoolEventCard(
            color: Color(subject?.colorValue ?? 0xFF4F46E5),
            label: _minuteRange(
              session.startsAtMinute,
              session.endsAtMinute,
            ),
            title: subject?.name ?? 'Unknown subject',
            detail: session.room,
            icon: Icons.class_outlined,
            onDelete: () => onDeleteSession(session),
          );
        }),
        ...exams.map((Exam exam) {
          final Subject? subject = data.subjectById(exam.subjectId);
          return _SchoolEventCard(
            color: AppColors.danger,
            label: _timeRange(exam.startsAtUtc, exam.endsAtUtc),
            title: exam.title,
            detail: subject?.name,
            icon: Icons.quiz_outlined,
            onDelete: () => onDeleteExam(exam),
          );
        }),
      ],
    );
  }
}

class _SchoolEventCard extends StatelessWidget {
  const _SchoolEventCard({
    required this.color,
    required this.label,
    required this.title,
    required this.icon,
    required this.onDelete,
    this.detail,
  });

  final Color color;
  final String label;
  final String title;
  final String? detail;
  final IconData icon;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final String? detailText = detail;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(10, 9, 4, 9),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        border: Border(left: BorderSide(color: color, width: 3)),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(icon, size: 17, color: color),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(label, style: Theme.of(context).textTheme.labelSmall),
                Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                if (detailText != null && detailText.isNotEmpty)
                  Text(
                    detailText,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
              ],
            ),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            tooltip: 'Remove',
            onPressed: onDelete,
            icon: const Icon(Icons.close_rounded, size: 17),
          ),
        ],
      ),
    );
  }
}

class _SubjectsCard extends StatelessWidget {
  const _SubjectsCard({required this.subjects});

  final List<Subject> subjects;

  @override
  Widget build(BuildContext context) {
    if (subjects.isEmpty) {
      return const SurfaceCard(child: Text('No subjects in the active term.'));
    }
    return SurfaceCard(
      child: Wrap(
        spacing: 10,
        runSpacing: 10,
        children: subjects.map((Subject subject) {
          final Color color = Color(subject.colorValue);
          final String code = subject.code?.trim() ?? '';
          final String teacher = subject.teacher?.trim() ?? '';
          final String room = subject.defaultRoom?.trim() ?? '';
          final List<String> details = <String>[
            if (code.isNotEmpty) code,
            if (teacher.isNotEmpty) teacher,
            if (room.isNotEmpty) room,
          ];
          return Container(
            width: 230,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: color.withValues(alpha: 0.35)),
            ),
            child: Row(
              children: <Widget>[
                CircleAvatar(
                  backgroundColor: color,
                  foregroundColor: Colors.white,
                  child: Text(subject.name.substring(0, 1).toUpperCase()),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        subject.name,
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      if (details.isNotEmpty)
                        Text(
                          details.join(' • '),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                    ],
                  ),
                ),
              ],
            ),
          );
        }).toList(growable: false),
      ),
    );
  }
}

class _AssignmentsCard extends StatelessWidget {
  const _AssignmentsCard({
    required this.assignments,
    required this.subjects,
    required this.onToggle,
  });

  final List<SchoolAssignment> assignments;
  final List<Subject> subjects;
  final ValueChanged<SchoolAssignment> onToggle;

  @override
  Widget build(BuildContext context) {
    if (assignments.isEmpty) {
      return const SurfaceCard(
        child: Text('No assignment deadline falls in this week.'),
      );
    }
    return SurfaceCard(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      child: Column(
        children: assignments.map((SchoolAssignment assignment) {
          final Subject? subject = _subject(subjects, assignment.subjectId);
          final bool completed =
              assignment.status == PlanningTaskStatus.completed;
          return ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 4),
            leading: CircleAvatar(
              backgroundColor: Color(
                subject?.colorValue ?? 0xFF4F46E5,
              ).withValues(alpha: 0.15),
              child: const Icon(Icons.assignment_outlined),
            ),
            title: Text(
              assignment.title,
              style: TextStyle(
                fontWeight: FontWeight.w700,
                decoration: completed ? TextDecoration.lineThrough : null,
              ),
            ),
            subtitle: Text(
              '${subject?.name ?? 'Unknown subject'} • due '
              '${_formatLocalDateTime(assignment.dueAtUtc.toLocal())}',
            ),
            trailing: IconButton(
              tooltip: assignment.isFinished
                  ? 'Reopen assignment'
                  : 'Complete assignment',
              onPressed: () => onToggle(assignment),
              icon: Icon(
                assignment.isFinished
                    ? Icons.check_circle_rounded
                    : Icons.circle_outlined,
                color: completed ? AppColors.secondary : AppColors.primary,
              ),
            ),
          );
        }).toList(growable: false),
      ),
    );
  }
}

class _ExamsCard extends StatelessWidget {
  const _ExamsCard({
    required this.exams,
    required this.subjects,
    required this.onDelete,
  });

  final List<Exam> exams;
  final List<Subject> subjects;
  final ValueChanged<Exam> onDelete;

  @override
  Widget build(BuildContext context) {
    if (exams.isEmpty) {
      return const SurfaceCard(child: Text('No exams scheduled this week.'));
    }
    return SurfaceCard(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      child: Column(
        children: exams.map((Exam exam) {
          final Subject? subject = _subject(subjects, exam.subjectId);
          final String room = exam.room?.trim() ?? '';
          return ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 4),
            leading: const CircleAvatar(child: Icon(Icons.quiz_outlined)),
            title: Text(
              exam.title,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            subtitle: Text(
              '${subject?.name ?? 'Unknown subject'} • '
              '${_formatLocalDateTime(exam.startsAtUtc.toLocal())}'
              '${room.isEmpty ? '' : ' • $room'}',
            ),
            trailing: IconButton(
              tooltip: 'Remove exam',
              onPressed: () => onDelete(exam),
              icon: const Icon(Icons.delete_outline_rounded),
            ),
          );
        }).toList(growable: false),
      ),
    );
  }
}

class _SchoolEmptyState extends StatelessWidget {
  const _SchoolEmptyState({
    required this.icon,
    required this.title,
    required this.message,
    required this.buttonLabel,
    required this.onPressed,
  });

  final IconData icon;
  final String title;
  final String message;
  final String buttonLabel;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SurfaceCard(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Column(
            children: <Widget>[
              Icon(icon, size: 44, color: AppColors.primary),
              const SizedBox(height: 12),
              Text(
                title,
                textAlign: TextAlign.center,
                style: Theme.of(context)
                    .textTheme
                    .titleLarge
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 6),
              Text(message, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: onPressed,
                icon: const Icon(Icons.add_rounded),
                label: Text(buttonLabel),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TermDialog extends StatefulWidget {
  const _TermDialog();

  @override
  State<_TermDialog> createState() => _TermDialogState();
}

class _TermDialogState extends State<_TermDialog> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _nameController = TextEditingController();
  late DateTime _start;
  late DateTime _end;

  @override
  void initState() {
    super.initState();
    final DateTime now = DateTime.now();
    _start = DateTime(now.year, now.month, now.day);
    _end = DateTime(now.year, now.month + 4, now.day);
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _pickStart() async {
    final DateTime? selected = await showDatePicker(
      context: context,
      initialDate: _start,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (selected != null) setState(() => _start = selected);
  }

  Future<void> _pickEnd() async {
    final DateTime? selected = await showDatePicker(
      context: context,
      initialDate: _end,
      firstDate: _start,
      lastDate: DateTime(2100),
    );
    if (selected != null) setState(() => _end = selected);
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.of(context).pop(
      AcademicTermDraft(
        name: _nameController.text.trim(),
        startsOnLocal: _start,
        endsOnLocal: _end,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add academic term'),
      content: SizedBox(
        width: 480,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              TextFormField(
                controller: _nameController,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Term name',
                  hintText: 'Term 1, 2026–2027',
                ),
                validator: _requiredValidator,
              ),
              const SizedBox(height: 12),
              _DateButton(label: 'Starts', date: _start, onPressed: _pickStart),
              const SizedBox(height: 8),
              _DateButton(label: 'Ends', date: _end, onPressed: _pickEnd),
            ],
          ),
        ),
      ),
      actions: _dialogActions(context, _submit),
    );
  }
}

class _SubjectDialog extends StatefulWidget {
  const _SubjectDialog({required this.termId});

  final String termId;

  @override
  State<_SubjectDialog> createState() => _SubjectDialogState();
}

class _SubjectDialogState extends State<_SubjectDialog> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _name = TextEditingController();
  final TextEditingController _code = TextEditingController();
  final TextEditingController _teacher = TextEditingController();
  final TextEditingController _room = TextEditingController();
  int _color = _subjectColors.first.$1;

  @override
  void dispose() {
    _name.dispose();
    _code.dispose();
    _teacher.dispose();
    _room.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.of(context).pop(
      SubjectDraft(
        termId: widget.termId,
        name: _name.text.trim(),
        code: _code.text.trim(),
        teacher: _teacher.text.trim(),
        defaultRoom: _room.text.trim(),
        colorValue: _color,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add subject'),
      content: SizedBox(
        width: 500,
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                _FormTextField(
                  controller: _name,
                  label: 'Subject name',
                  hint: 'Database Systems',
                  isRequired: true,
                ),
                const SizedBox(height: 10),
                _FormTextField(
                  controller: _code,
                  label: 'Subject code (optional)',
                  hint: 'INSY 312',
                ),
                const SizedBox(height: 10),
                _FormTextField(
                  controller: _teacher,
                  label: 'Teacher (optional)',
                  hint: 'Lecturer name',
                ),
                const SizedBox(height: 10),
                _FormTextField(
                  controller: _room,
                  label: 'Default room (optional)',
                  hint: 'Lab 2',
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<int>(
                  initialValue: _color,
                  decoration: const InputDecoration(labelText: 'Color'),
                  items: _subjectColors
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
      actions: _dialogActions(context, _submit),
    );
  }
}

class _ClassSessionDialog extends StatefulWidget {
  const _ClassSessionDialog({required this.subjects});

  final List<Subject> subjects;

  @override
  State<_ClassSessionDialog> createState() => _ClassSessionDialogState();
}

class _ClassSessionDialogState extends State<_ClassSessionDialog> {
  final TextEditingController _room = TextEditingController();
  final TextEditingController _notes = TextEditingController();
  late String _subjectId;
  int _weekday = DateTime.monday;
  TimeOfDay _start = const TimeOfDay(hour: 8, minute: 0);
  TimeOfDay _end = const TimeOfDay(hour: 9, minute: 0);

  @override
  void initState() {
    super.initState();
    _subjectId = widget.subjects.first.id;
  }

  @override
  void dispose() {
    _room.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _pickStart() async {
    final TimeOfDay? selected = await showTimePicker(
      context: context,
      initialTime: _start,
    );
    if (selected != null) setState(() => _start = selected);
  }

  Future<void> _pickEnd() async {
    final TimeOfDay? selected = await showTimePicker(
      context: context,
      initialTime: _end,
    );
    if (selected != null) setState(() => _end = selected);
  }

  void _submit() {
    final int start = _minuteOfDay(_start);
    final int end = _minuteOfDay(_end);
    if (end <= start) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Class end time must be after start time.')),
      );
      return;
    }
    Navigator.of(context).pop(
      ClassSessionDraft(
        subjectId: _subjectId,
        weekday: _weekday,
        startsAtMinute: start,
        endsAtMinute: end,
        room: _room.text.trim(),
        notes: _notes.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add weekly class'),
      content: SizedBox(
        width: 500,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              _SubjectDropdown(
                subjects: widget.subjects,
                initialValue: _subjectId,
                onChanged: (String value) => _subjectId = value,
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<int>(
                initialValue: _weekday,
                decoration: const InputDecoration(labelText: 'Weekday'),
                items: List<DropdownMenuItem<int>>.generate(
                  7,
                  (int index) => DropdownMenuItem<int>(
                    value: index + DateTime.monday,
                    child: Text(_weekdayName(index + DateTime.monday)),
                  ),
                ),
                onChanged: (int? value) {
                  if (value != null) _weekday = value;
                },
              ),
              const SizedBox(height: 10),
              Row(
                children: <Widget>[
                  Expanded(
                    child: _TimeButton(
                      label: 'Starts',
                      time: _start,
                      onPressed: _pickStart,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _TimeButton(
                      label: 'Ends',
                      time: _end,
                      onPressed: _pickEnd,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              _FormTextField(
                controller: _room,
                label: 'Room (optional)',
                hint: 'Uses the subject room if empty',
              ),
              const SizedBox(height: 10),
              _FormTextField(
                controller: _notes,
                label: 'Notes (optional)',
                hint: 'Bring the lab workbook',
              ),
            ],
          ),
        ),
      ),
      actions: _dialogActions(context, _submit),
    );
  }
}

class _AssignmentDialog extends StatefulWidget {
  const _AssignmentDialog({required this.subjects});

  final List<Subject> subjects;

  @override
  State<_AssignmentDialog> createState() => _AssignmentDialogState();
}

class _AssignmentDialogState extends State<_AssignmentDialog> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _title = TextEditingController();
  final TextEditingController _notes = TextEditingController();
  late String _subjectId;
  late DateTime _due;

  @override
  void initState() {
    super.initState();
    _subjectId = widget.subjects.first.id;
    final DateTime tomorrow = DateTime.now().add(const Duration(days: 1));
    _due = DateTime(tomorrow.year, tomorrow.month, tomorrow.day, 17);
  }

  @override
  void dispose() {
    _title.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _pickDue() async {
    final DateTime? value = await _pickLocalDateTime(context, _due);
    if (value != null) setState(() => _due = value);
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.of(context).pop(
      SchoolAssignmentDraft(
        subjectId: _subjectId,
        title: _title.text.trim(),
        notes: _notes.text.trim(),
        dueAtUtc: _due.toUtc(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add assignment'),
      content: SizedBox(
        width: 500,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                _SubjectDropdown(
                  subjects: widget.subjects,
                  initialValue: _subjectId,
                  onChanged: (String value) => _subjectId = value,
                ),
                const SizedBox(height: 10),
                _FormTextField(
                  controller: _title,
                  label: 'Assignment title',
                  hint: 'Normalization exercises',
                  isRequired: true,
                ),
                const SizedBox(height: 10),
                _FormTextField(
                  controller: _notes,
                  label: 'Notes (optional)',
                  hint: 'Questions 1–10',
                ),
                const SizedBox(height: 10),
                _DateTimeButton(
                  label: 'Due',
                  value: _due,
                  onPressed: _pickDue,
                ),
              ],
            ),
          ),
        ),
      ),
      actions: _dialogActions(context, _submit),
    );
  }
}

class _ExamDialog extends StatefulWidget {
  const _ExamDialog({required this.subjects});

  final List<Subject> subjects;

  @override
  State<_ExamDialog> createState() => _ExamDialogState();
}

class _ExamDialogState extends State<_ExamDialog> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _title = TextEditingController();
  final TextEditingController _room = TextEditingController();
  final TextEditingController _notes = TextEditingController();
  late String _subjectId;
  late DateTime _startsAt;
  int _durationMinutes = 120;

  @override
  void initState() {
    super.initState();
    _subjectId = widget.subjects.first.id;
    final DateTime nextWeek = DateTime.now().add(const Duration(days: 7));
    _startsAt = DateTime(nextWeek.year, nextWeek.month, nextWeek.day, 9);
  }

  @override
  void dispose() {
    _title.dispose();
    _room.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _pickStart() async {
    final DateTime? value = await _pickLocalDateTime(context, _startsAt);
    if (value != null) setState(() => _startsAt = value);
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.of(context).pop(
      ExamDraft(
        subjectId: _subjectId,
        title: _title.text.trim(),
        startsAtUtc: _startsAt.toUtc(),
        endsAtUtc: _startsAt.add(Duration(minutes: _durationMinutes)).toUtc(),
        room: _room.text.trim(),
        notes: _notes.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add exam'),
      content: SizedBox(
        width: 500,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                _SubjectDropdown(
                  subjects: widget.subjects,
                  initialValue: _subjectId,
                  onChanged: (String value) => _subjectId = value,
                ),
                const SizedBox(height: 10),
                _FormTextField(
                  controller: _title,
                  label: 'Exam title',
                  hint: 'Database Systems midterm',
                  isRequired: true,
                ),
                const SizedBox(height: 10),
                _DateTimeButton(
                  label: 'Starts',
                  value: _startsAt,
                  onPressed: _pickStart,
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<int>(
                  initialValue: _durationMinutes,
                  decoration: const InputDecoration(labelText: 'Duration'),
                  items: const <DropdownMenuItem<int>>[
                    DropdownMenuItem<int>(value: 60, child: Text('1 hour')),
                    DropdownMenuItem<int>(value: 90, child: Text('1h 30m')),
                    DropdownMenuItem<int>(value: 120, child: Text('2 hours')),
                    DropdownMenuItem<int>(value: 180, child: Text('3 hours')),
                  ],
                  onChanged: (int? value) {
                    if (value != null) _durationMinutes = value;
                  },
                ),
                const SizedBox(height: 10),
                _FormTextField(
                  controller: _room,
                  label: 'Room (optional)',
                  hint: 'Main Hall',
                ),
                const SizedBox(height: 10),
                _FormTextField(
                  controller: _notes,
                  label: 'Notes (optional)',
                  hint: 'Chapters 1–5',
                ),
              ],
            ),
          ),
        ),
      ),
      actions: _dialogActions(context, _submit),
    );
  }
}

class _SubjectDropdown extends StatelessWidget {
  const _SubjectDropdown({
    required this.subjects,
    required this.initialValue,
    required this.onChanged,
  });

  final List<Subject> subjects;
  final String initialValue;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<String>(
      initialValue: initialValue,
      decoration: const InputDecoration(labelText: 'Subject'),
      items: subjects
          .map(
            (Subject subject) => DropdownMenuItem<String>(
              value: subject.id,
              child: Text(subject.name),
            ),
          )
          .toList(growable: false),
      onChanged: (String? value) {
        if (value != null) onChanged(value);
      },
    );
  }
}

class _FormTextField extends StatelessWidget {
  const _FormTextField({
    required this.controller,
    required this.label,
    required this.hint,
    this.isRequired = false,
  });

  final TextEditingController controller;
  final String label;
  final String hint;
  final bool isRequired;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      textCapitalization: TextCapitalization.sentences,
      decoration: InputDecoration(labelText: label, hintText: hint),
      validator: isRequired ? _requiredValidator : null,
    );
  }
}

class _DateButton extends StatelessWidget {
  const _DateButton({
    required this.label,
    required this.date,
    required this.onPressed,
  });

  final String label;
  final DateTime date;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.calendar_today_outlined),
      title: Text(label),
      subtitle: Text(_shortDate(date)),
      trailing: TextButton(onPressed: onPressed, child: const Text('Change')),
    );
  }
}

class _DateTimeButton extends StatelessWidget {
  const _DateTimeButton({
    required this.label,
    required this.value,
    required this.onPressed,
  });

  final String label;
  final DateTime value;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.event_outlined),
      title: Text(label),
      subtitle: Text(_formatLocalDateTime(value)),
      trailing: TextButton(onPressed: onPressed, child: const Text('Change')),
    );
  }
}

class _TimeButton extends StatelessWidget {
  const _TimeButton({
    required this.label,
    required this.time,
    required this.onPressed,
  });

  final String label;
  final TimeOfDay time;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: const Icon(Icons.schedule_outlined),
      label: Text('$label ${time.format(context)}'),
    );
  }
}

List<Widget> _dialogActions(BuildContext context, VoidCallback onSave) {
  return <Widget>[
    TextButton(
      onPressed: () => Navigator.of(context).pop(),
      child: const Text('Cancel'),
    ),
    FilledButton(onPressed: onSave, child: const Text('Save locally')),
  ];
}

Future<DateTime?> _pickLocalDateTime(
  BuildContext context,
  DateTime initial,
) async {
  final DateTime? date = await showDatePicker(
    context: context,
    initialDate: initial,
    firstDate: DateTime(2020),
    lastDate: DateTime(2100),
  );
  if (date == null || !context.mounted) return null;
  final TimeOfDay? time = await showTimePicker(
    context: context,
    initialTime: TimeOfDay.fromDateTime(initial),
  );
  if (time == null) return null;
  return DateTime(date.year, date.month, date.day, time.hour, time.minute);
}

String? _requiredValidator(String? value) {
  return value == null || value.trim().isEmpty
      ? 'This field is required'
      : null;
}

Subject? _subject(List<Subject> subjects, String id) {
  for (final Subject subject in subjects) {
    if (subject.id == id) return subject;
  }
  return null;
}

int _minuteOfDay(TimeOfDay time) => time.hour * 60 + time.minute;

String _minuteRange(int start, int end) {
  return '${_minuteLabel(start)}–${_minuteLabel(end)}';
}

String _minuteLabel(int minute) {
  final String hour = (minute ~/ 60).toString().padLeft(2, '0');
  final String minutes = (minute % 60).toString().padLeft(2, '0');
  return '$hour:$minutes';
}

String _timeRange(DateTime startUtc, DateTime endUtc) {
  final DateTime start = startUtc.toLocal();
  final DateTime end = endUtc.toLocal();
  return '${_clockTime(start)}–${_clockTime(end)}';
}

String _clockTime(DateTime value) {
  final String hour = value.hour.toString().padLeft(2, '0');
  final String minute = value.minute.toString().padLeft(2, '0');
  return '$hour:$minute';
}

String _formatLocalDateTime(DateTime value) {
  return '${_shortDate(value)} at ${_clockTime(value)}';
}

String _shortDate(DateTime value) {
  final String day = value.day.toString().padLeft(2, '0');
  final String month = value.month.toString().padLeft(2, '0');
  return '${value.year}-$month-$day';
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

bool _sameLocalDay(DateTime first, DateTime second) {
  return first.year == second.year &&
      first.month == second.month &&
      first.day == second.day;
}

const List<(int, String)> _subjectColors = <(int, String)>[
  (0xFF4F46E5, 'Indigo'),
  (0xFF0F9D8A, 'Teal'),
  (0xFFF59E0B, 'Amber'),
  (0xFF8B5CF6, 'Purple'),
  (0xFF2563EB, 'Blue'),
  (0xFFEF4444, 'Red'),
];
