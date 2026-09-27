import 'dart:math';

import 'package:drift/drift.dart';

import '../../planner/data/planning_database.dart';
import '../../planner/domain/planning_entities.dart';
import '../domain/school_entities.dart';
import '../domain/school_repository.dart';

typedef SchoolUtcClock = DateTime Function();
typedef SchoolIdFactory = String Function(String prefix);

final class DriftSchoolRepository implements SchoolRepository {
  DriftSchoolRepository(
    this._database, {
    SchoolUtcClock? clock,
    SchoolIdFactory? idFactory,
  })  : _clock = clock ?? DateTime.now,
        _idFactory = idFactory;

  final PlanningDatabase _database;
  final SchoolUtcClock _clock;
  final SchoolIdFactory? _idFactory;
  final Random _random = Random.secure();
  int _idCounter = 0;

  @override
  Stream<SchoolWeekData> watchSchoolWeek(DateTime weekContaining) {
    return _database.watchQuery(
      () => getSchoolWeek(weekContaining),
    );
  }

  @override
  Future<SchoolWeekData> getSchoolWeek(DateTime weekContaining) async {
    final DateTime weekStart = startOfLocalWeek(weekContaining);
    final DateTime weekEnd = weekStart.add(const Duration(days: 7));
    final List<AcademicTerm> terms = (await _database.readRows('''
      SELECT * FROM academic_terms
      ORDER BY is_active DESC, starts_on_local DESC
    ''')).map(_termFromRow).toList(growable: false);

    AcademicTerm? activeTerm;
    for (final AcademicTerm term in terms) {
      if (term.isActive) {
        activeTerm = term;
        break;
      }
    }
    if (activeTerm == null) {
      return SchoolWeekData(
        weekStartsOnLocal: weekStart,
        terms: terms,
        subjects: const <Subject>[],
        sessions: const <ClassSession>[],
        assignments: const <SchoolAssignment>[],
        exams: const <Exam>[],
      );
    }

    final List<Subject> subjects = (await _database.readRows('''
      SELECT * FROM subjects
      WHERE term_id = ?
      ORDER BY name COLLATE NOCASE ASC
    ''', variables: _strings(<String>[activeTerm.id])))
        .map(_subjectFromRow)
        .toList(growable: false);
    final DateTime weekLastDay = weekStart.add(const Duration(days: 6));
    final bool weekIntersectsTerm =
        !weekLastDay.isBefore(activeTerm.startsOnLocal) &&
            !weekStart.isAfter(activeTerm.endsOnLocal);
    final List<ClassSession> sessions = weekIntersectsTerm
        ? (await _database.readRows('''
            SELECT cs.*
            FROM class_sessions cs
            JOIN subjects s ON s.id = cs.subject_id
            WHERE s.term_id = ?
            ORDER BY cs.weekday ASC, cs.starts_at_minute ASC
          ''', variables: _strings(<String>[activeTerm.id])))
            .map(_sessionFromRow)
            .toList(growable: false)
        : const <ClassSession>[];
    final List<SchoolAssignment> assignments = (await _database.readRows('''
      SELECT
        a.id AS assignment_id,
        a.subject_id AS assignment_subject_id,
        a.task_id AS assignment_task_id,
        a.due_at_utc AS assignment_due_at_utc,
        a.created_at_utc AS assignment_created_at_utc,
        a.updated_at_utc AS assignment_updated_at_utc,
        t.title AS task_title,
        t.notes AS task_notes,
        t.status AS task_status
      FROM school_assignments a
      JOIN subjects s ON s.id = a.subject_id
      JOIN planning_tasks t ON t.id = a.task_id
      WHERE s.term_id = ?
        AND t.deleted_at_utc IS NULL
        AND a.due_at_utc >= ?
        AND a.due_at_utc < ?
      ORDER BY a.due_at_utc ASC
    ''',
            variables: _strings(<String>[
              activeTerm.id,
              _utc(weekStart.toUtc()),
              _utc(weekEnd.toUtc()),
            ])))
        .map(_assignmentFromRow)
        .toList(growable: false);
    final List<Exam> exams = (await _database.readRows('''
      SELECT e.*
      FROM exams e
      JOIN subjects s ON s.id = e.subject_id
      WHERE s.term_id = ?
        AND e.starts_at_utc >= ?
        AND e.starts_at_utc < ?
      ORDER BY e.starts_at_utc ASC
    ''',
            variables: _strings(<String>[
              activeTerm.id,
              _utc(weekStart.toUtc()),
              _utc(weekEnd.toUtc()),
            ])))
        .map(_examFromRow)
        .toList(growable: false);

    return SchoolWeekData(
      weekStartsOnLocal: weekStart,
      terms: terms,
      subjects: subjects,
      sessions: sessions,
      assignments: assignments,
      exams: exams,
    );
  }

  @override
  Future<AcademicTerm> createAcademicTerm(AcademicTermDraft draft) async {
    final String name = _requiredText(draft.name, 'Term name');
    final DateTime startsOn = _dateOnly(draft.startsOnLocal);
    final DateTime endsOn = _dateOnly(draft.endsOnLocal);
    if (endsOn.isBefore(startsOn)) {
      throw ArgumentError('The term end date cannot be before its start date.');
    }
    final DateTime now = _clock().toUtc();
    final String id = _newId('term');

    await _database.transaction(() async {
      await _database.updateRows(
        'UPDATE academic_terms SET is_active = 0, updated_at_utc = ? '
        'WHERE is_active = 1',
        variables: _strings(<String>[_utc(now)]),
      );
      await _database.insertRow('''
        INSERT INTO academic_terms (
          id, name, starts_on_local, ends_on_local, is_active,
          created_at_utc, updated_at_utc
        ) VALUES (?, ?, ?, ?, 1, ?, ?)
      ''',
          variables: _strings(<String>[
            id,
            name,
            _dayKey(startsOn),
            _dayKey(endsOn),
            _utc(now),
            _utc(now),
          ]));
    });
    _database.notifyChanged();
    return _readTerm(id);
  }

  @override
  Future<void> setActiveTerm(String termId) async {
    await _requireTerm(termId);
    final DateTime now = _clock().toUtc();
    await _database.transaction(() async {
      await _database.updateRows(
        'UPDATE academic_terms SET is_active = 0, updated_at_utc = ? '
        'WHERE is_active = 1',
        variables: _strings(<String>[_utc(now)]),
      );
      await _requireUpdated(
        _database.updateRows(
          'UPDATE academic_terms SET is_active = 1, updated_at_utc = ? '
          'WHERE id = ?',
          variables: _strings(<String>[_utc(now), termId]),
        ),
        'Academic term',
      );
    });
    _database.notifyChanged();
  }

  @override
  Future<Subject> createSubject(SubjectDraft draft) async {
    await _requireTerm(draft.termId);
    final String name = _requiredText(draft.name, 'Subject name');
    if (draft.colorValue < 0 || draft.colorValue > 0xFFFFFFFF) {
      throw ArgumentError.value(
        draft.colorValue,
        'colorValue',
        'Subject color must be a 32-bit ARGB value.',
      );
    }
    final DateTime now = _clock().toUtc();
    final String id = _newId('subject');
    await _database.insertRow('''
      INSERT INTO subjects (
        id, term_id, name, code, teacher, default_room, color_value,
        created_at_utc, updated_at_utc
      ) VALUES (?, ?, ?, NULLIF(?, ''), NULLIF(?, ''), NULLIF(?, ''), ?, ?, ?)
    ''', variables: <Variable<Object>>[
      Variable<String>(id),
      Variable<String>(draft.termId),
      Variable<String>(name),
      Variable<String>(_optionalText(draft.code)),
      Variable<String>(_optionalText(draft.teacher)),
      Variable<String>(_optionalText(draft.defaultRoom)),
      Variable<int>(draft.colorValue),
      Variable<String>(_utc(now)),
      Variable<String>(_utc(now)),
    ]);
    _database.notifyChanged();
    return _readSubject(id);
  }

  @override
  Future<ClassSession> createClassSession(ClassSessionDraft draft) async {
    if (draft.weekday < DateTime.monday || draft.weekday > DateTime.sunday) {
      throw ArgumentError.value(draft.weekday, 'weekday', 'Invalid weekday.');
    }
    if (draft.startsAtMinute < 0 ||
        draft.endsAtMinute > 24 * 60 ||
        draft.startsAtMinute >= draft.endsAtMinute) {
      throw ArgumentError('A class must end after it starts on the same day.');
    }
    final _SubjectReference subject = await _requireSubject(draft.subjectId);
    final List<QueryRow> conflicts = await _database.readRows('''
      SELECT cs.id
      FROM class_sessions cs
      JOIN subjects s ON s.id = cs.subject_id
      WHERE s.term_id = ?
        AND cs.weekday = ?
        AND cs.starts_at_minute < ?
        AND cs.ends_at_minute > ?
      LIMIT 1
    ''', variables: <Variable<Object>>[
      Variable<String>(subject.termId),
      Variable<int>(draft.weekday),
      Variable<int>(draft.endsAtMinute),
      Variable<int>(draft.startsAtMinute),
    ]);
    if (conflicts.isNotEmpty) {
      throw StateError('This class overlaps another class in the active term.');
    }

    final DateTime now = _clock().toUtc();
    final String id = _newId('session');
    await _database.insertRow('''
      INSERT INTO class_sessions (
        id, subject_id, weekday, starts_at_minute, ends_at_minute,
        room, notes, created_at_utc, updated_at_utc
      ) VALUES (?, ?, ?, ?, ?, NULLIF(?, ''), NULLIF(?, ''), ?, ?)
    ''', variables: <Variable<Object>>[
      Variable<String>(id),
      Variable<String>(draft.subjectId),
      Variable<int>(draft.weekday),
      Variable<int>(draft.startsAtMinute),
      Variable<int>(draft.endsAtMinute),
      Variable<String>(
        _optionalText(draft.room).isEmpty
            ? subject.defaultRoom ?? ''
            : _optionalText(draft.room),
      ),
      Variable<String>(_optionalText(draft.notes)),
      Variable<String>(_utc(now)),
      Variable<String>(_utc(now)),
    ]);
    _database.notifyChanged();
    return _readSession(id);
  }

  @override
  Future<SchoolAssignment> createAssignment(
    SchoolAssignmentDraft draft,
  ) async {
    final _SubjectReference subject = await _requireSubject(draft.subjectId);
    final String title = _requiredText(draft.title, 'Assignment title');
    final DateTime dueAt = draft.dueAtUtc.toUtc();
    if (!subject.termContains(dueAt.toLocal())) {
      throw ArgumentError('The assignment deadline must be inside its term.');
    }
    final DateTime now = _clock().toUtc();
    final String taskId = _newId('task');
    final String assignmentId = _newId('assignment');

    await _database.transaction(() async {
      await _database.insertRow('''
        INSERT INTO planning_tasks (
          id, goal_id, milestone_id, subject_id, title, notes, kind, status,
          scheduled_at_utc, due_at_utc, completed_at_utc, created_at_utc,
          updated_at_utc, deleted_at_utc
        ) VALUES (
          ?, NULL, NULL, ?, ?, NULLIF(?, ''), 'assignment', 'pending',
          NULL, ?, NULL, ?, ?, NULL
        )
      ''',
          variables: _strings(<String>[
            taskId,
            draft.subjectId,
            title,
            _optionalText(draft.notes),
            _utc(dueAt),
            _utc(now),
            _utc(now),
          ]));
      await _database.insertRow('''
        INSERT INTO school_assignments (
          id, subject_id, task_id, due_at_utc, created_at_utc, updated_at_utc
        ) VALUES (?, ?, ?, ?, ?, ?)
      ''',
          variables: _strings(<String>[
            assignmentId,
            draft.subjectId,
            taskId,
            _utc(dueAt),
            _utc(now),
            _utc(now),
          ]));
    });
    _database.notifyChanged();
    return _readAssignment(assignmentId);
  }

  @override
  Future<Exam> createExam(ExamDraft draft) async {
    final _SubjectReference subject = await _requireSubject(draft.subjectId);
    final String title = _requiredText(draft.title, 'Exam title');
    final DateTime startsAt = draft.startsAtUtc.toUtc();
    final DateTime endsAt = draft.endsAtUtc.toUtc();
    if (!endsAt.isAfter(startsAt)) {
      throw ArgumentError('An exam must end after it starts.');
    }
    if (!subject.termContains(startsAt.toLocal())) {
      throw ArgumentError('The exam date must be inside its term.');
    }
    final DateTime now = _clock().toUtc();
    final String id = _newId('exam');
    await _database.insertRow('''
      INSERT INTO exams (
        id, subject_id, title, starts_at_utc, ends_at_utc, room, notes,
        created_at_utc, updated_at_utc
      ) VALUES (?, ?, ?, ?, ?, NULLIF(?, ''), NULLIF(?, ''), ?, ?)
    ''',
        variables: _strings(<String>[
          id,
          draft.subjectId,
          title,
          _utc(startsAt),
          _utc(endsAt),
          _optionalText(draft.room),
          _optionalText(draft.notes),
          _utc(now),
          _utc(now),
        ]));
    _database.notifyChanged();
    return _readExam(id);
  }

  @override
  Future<void> deleteClassSession(String sessionId) async {
    await _requireUpdated(
      _database.updateRows(
        'DELETE FROM class_sessions WHERE id = ?',
        variables: _strings(<String>[sessionId]),
      ),
      'Class session',
    );
    _database.notifyChanged();
  }

  @override
  Future<void> deleteExam(String examId) async {
    await _requireUpdated(
      _database.updateRows(
        'DELETE FROM exams WHERE id = ?',
        variables: _strings(<String>[examId]),
      ),
      'Exam',
    );
    _database.notifyChanged();
  }

  Future<AcademicTerm> _readTerm(String id) async {
    final List<QueryRow> rows = await _database.readRows(
      'SELECT * FROM academic_terms WHERE id = ?',
      variables: _strings(<String>[id]),
    );
    return _termFromRow(rows.single);
  }

  Future<Subject> _readSubject(String id) async {
    final List<QueryRow> rows = await _database.readRows(
      'SELECT * FROM subjects WHERE id = ?',
      variables: _strings(<String>[id]),
    );
    return _subjectFromRow(rows.single);
  }

  Future<ClassSession> _readSession(String id) async {
    final List<QueryRow> rows = await _database.readRows(
      'SELECT * FROM class_sessions WHERE id = ?',
      variables: _strings(<String>[id]),
    );
    return _sessionFromRow(rows.single);
  }

  Future<SchoolAssignment> _readAssignment(String id) async {
    final List<QueryRow> rows = await _database.readRows('''
      SELECT
        a.id AS assignment_id,
        a.subject_id AS assignment_subject_id,
        a.task_id AS assignment_task_id,
        a.due_at_utc AS assignment_due_at_utc,
        a.created_at_utc AS assignment_created_at_utc,
        a.updated_at_utc AS assignment_updated_at_utc,
        t.title AS task_title,
        t.notes AS task_notes,
        t.status AS task_status
      FROM school_assignments a
      JOIN planning_tasks t ON t.id = a.task_id
      WHERE a.id = ?
    ''', variables: _strings(<String>[id]));
    return _assignmentFromRow(rows.single);
  }

  Future<Exam> _readExam(String id) async {
    final List<QueryRow> rows = await _database.readRows(
      'SELECT * FROM exams WHERE id = ?',
      variables: _strings(<String>[id]),
    );
    return _examFromRow(rows.single);
  }

  Future<AcademicTerm> _requireTerm(String id) async {
    final List<QueryRow> rows = await _database.readRows(
      'SELECT * FROM academic_terms WHERE id = ?',
      variables: _strings(<String>[id]),
    );
    if (rows.isEmpty) throw StateError('Academic term was not found.');
    return _termFromRow(rows.single);
  }

  Future<_SubjectReference> _requireSubject(String id) async {
    final List<QueryRow> rows = await _database.readRows('''
      SELECT s.id, s.term_id, s.default_room,
             t.starts_on_local, t.ends_on_local
      FROM subjects s
      JOIN academic_terms t ON t.id = s.term_id
      WHERE s.id = ?
    ''', variables: _strings(<String>[id]));
    if (rows.isEmpty) throw StateError('Subject was not found.');
    final QueryRow row = rows.single;
    return _SubjectReference(
      termId: row.read<String>('term_id'),
      defaultRoom: row.readNullable<String>('default_room'),
      termStartsOnLocal: _localDay(row.read<String>('starts_on_local')),
      termEndsOnLocal: _localDay(row.read<String>('ends_on_local')),
    );
  }

  AcademicTerm _termFromRow(QueryRow row) {
    return AcademicTerm(
      id: row.read<String>('id'),
      name: row.read<String>('name'),
      startsOnLocal: _localDay(row.read<String>('starts_on_local')),
      endsOnLocal: _localDay(row.read<String>('ends_on_local')),
      isActive: row.read<int>('is_active') == 1,
      createdAtUtc: _date(row, 'created_at_utc'),
      updatedAtUtc: _date(row, 'updated_at_utc'),
    );
  }

  Subject _subjectFromRow(QueryRow row) {
    return Subject(
      id: row.read<String>('id'),
      termId: row.read<String>('term_id'),
      name: row.read<String>('name'),
      code: row.readNullable<String>('code'),
      teacher: row.readNullable<String>('teacher'),
      defaultRoom: row.readNullable<String>('default_room'),
      colorValue: row.read<int>('color_value'),
      createdAtUtc: _date(row, 'created_at_utc'),
      updatedAtUtc: _date(row, 'updated_at_utc'),
    );
  }

  ClassSession _sessionFromRow(QueryRow row) {
    return ClassSession(
      id: row.read<String>('id'),
      subjectId: row.read<String>('subject_id'),
      weekday: row.read<int>('weekday'),
      startsAtMinute: row.read<int>('starts_at_minute'),
      endsAtMinute: row.read<int>('ends_at_minute'),
      room: row.readNullable<String>('room'),
      notes: row.readNullable<String>('notes'),
      createdAtUtc: _date(row, 'created_at_utc'),
      updatedAtUtc: _date(row, 'updated_at_utc'),
    );
  }

  SchoolAssignment _assignmentFromRow(QueryRow row) {
    return SchoolAssignment(
      id: row.read<String>('assignment_id'),
      subjectId: row.read<String>('assignment_subject_id'),
      taskId: row.read<String>('assignment_task_id'),
      title: row.read<String>('task_title'),
      notes: row.readNullable<String>('task_notes'),
      status: PlanningTaskStatus.values.byName(
        row.read<String>('task_status'),
      ),
      dueAtUtc: _date(row, 'assignment_due_at_utc'),
      createdAtUtc: _date(row, 'assignment_created_at_utc'),
      updatedAtUtc: _date(row, 'assignment_updated_at_utc'),
    );
  }

  Exam _examFromRow(QueryRow row) {
    return Exam(
      id: row.read<String>('id'),
      subjectId: row.read<String>('subject_id'),
      title: row.read<String>('title'),
      startsAtUtc: _date(row, 'starts_at_utc'),
      endsAtUtc: _date(row, 'ends_at_utc'),
      room: row.readNullable<String>('room'),
      notes: row.readNullable<String>('notes'),
      createdAtUtc: _date(row, 'created_at_utc'),
      updatedAtUtc: _date(row, 'updated_at_utc'),
    );
  }

  String _newId(String prefix) {
    final SchoolIdFactory? factory = _idFactory;
    if (factory != null) return factory(prefix);
    _idCounter += 1;
    final String time =
        _clock().toUtc().microsecondsSinceEpoch.toRadixString(36);
    final String random = _random.nextInt(0x7fffffff).toRadixString(36);
    return '$prefix-$time-$random-$_idCounter';
  }
}

class _SubjectReference {
  const _SubjectReference({
    required this.termId,
    required this.defaultRoom,
    required this.termStartsOnLocal,
    required this.termEndsOnLocal,
  });

  final String termId;
  final String? defaultRoom;
  final DateTime termStartsOnLocal;
  final DateTime termEndsOnLocal;

  bool termContains(DateTime localDate) {
    final DateTime day = _dateOnly(localDate);
    return !day.isBefore(termStartsOnLocal) && !day.isAfter(termEndsOnLocal);
  }
}

String _requiredText(String value, String field) {
  final String text = value.trim();
  if (text.isEmpty) {
    throw ArgumentError.value(value, field, '$field cannot be empty.');
  }
  return text;
}

String _optionalText(String? value) => value?.trim() ?? '';

DateTime _dateOnly(DateTime value) => DateTime(
      value.year,
      value.month,
      value.day,
    );

String _dayKey(DateTime value) {
  final String month = value.month.toString().padLeft(2, '0');
  final String day = value.day.toString().padLeft(2, '0');
  return '${value.year}-$month-$day';
}

DateTime _localDay(String value) {
  final List<int> parts = value.split('-').map(int.parse).toList();
  return DateTime(parts[0], parts[1], parts[2]);
}

String _utc(DateTime value) => value.toUtc().toIso8601String();

DateTime _date(QueryRow row, String column) {
  return DateTime.parse(row.read<String>(column)).toUtc();
}

Future<void> _requireUpdated(Future<int> operation, String recordName) async {
  final int count = await operation;
  if (count == 0) throw StateError('$recordName was not found.');
}

List<Variable<Object>> _strings(List<String> values) {
  return values
      .map<Variable<Object>>((String value) => Variable<String>(value))
      .toList(growable: false);
}
