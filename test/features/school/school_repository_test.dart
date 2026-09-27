import 'dart:async';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gahunda/features/planner/data/drift_planning_repository.dart';
import 'package:gahunda/features/planner/data/planning_database.dart';
import 'package:gahunda/features/planner/domain/planning_entities.dart';
import 'package:gahunda/features/school/data/drift_school_repository.dart';
import 'package:gahunda/features/school/domain/school_entities.dart';

void main() {
  final DateTime fixedNow = DateTime.utc(2026, 9, 6, 8);
  final DateTime schoolWeek = DateTime(2026, 9, 7);
  int id = 0;

  DriftSchoolRepository schoolRepository(PlanningDatabase database) {
    return DriftSchoolRepository(
      database,
      clock: () => fixedNow,
      idFactory: (String prefix) => '$prefix-${id++}',
    );
  }

  DriftPlanningRepository planningRepository(PlanningDatabase database) {
    return DriftPlanningRepository(
      database,
      clock: () => fixedNow,
      idFactory: (String prefix) => '$prefix-${id++}',
    );
  }

  Future<(AcademicTerm, Subject)> createSchoolSetup(
    DriftSchoolRepository repository,
  ) async {
    final AcademicTerm term = await repository.createAcademicTerm(
      AcademicTermDraft(
        name: 'Term 1',
        startsOnLocal: DateTime(2026, 9, 1),
        endsOnLocal: DateTime(2026, 12, 18),
      ),
    );
    final Subject subject = await repository.createSubject(
      SubjectDraft(
        termId: term.id,
        name: 'Database Systems',
        code: 'INSY 312',
        teacher: 'Dr Mugisha',
        defaultRoom: 'Lab 2',
        colorValue: 0xFF4F46E5,
      ),
    );
    return (term, subject);
  }

  setUp(() => id = 0);

  test('builds an active term, subject, and recurring school week', () async {
    final PlanningDatabase database = PlanningDatabase(NativeDatabase.memory());
    final DriftSchoolRepository school = schoolRepository(database);
    addTearDown(database.close);

    final (AcademicTerm term, Subject subject) =
        await createSchoolSetup(school);
    await school.createClassSession(
      ClassSessionDraft(
        subjectId: subject.id,
        weekday: DateTime.monday,
        startsAtMinute: 8 * 60,
        endsAtMinute: 9 * 60 + 30,
      ),
    );

    final SchoolWeekData week = await school.getSchoolWeek(schoolWeek);
    expect(week.activeTerm?.id, term.id);
    expect(week.subjects.single.code, 'INSY 312');
    expect(week.sessionsForWeekday(DateTime.monday), hasLength(1));
    expect(week.sessions.single.room, 'Lab 2');
    expect(week.sessions.single.duration, const Duration(minutes: 90));
  });

  test('a class repeats at the same weekday and time throughout the term',
      () async {
    final PlanningDatabase database = PlanningDatabase(NativeDatabase.memory());
    final DriftSchoolRepository school = schoolRepository(database);
    addTearDown(database.close);
    final (_, Subject subject) = await createSchoolSetup(school);
    final ClassSession session = await school.createClassSession(
      ClassSessionDraft(
        subjectId: subject.id,
        weekday: DateTime.monday,
        startsAtMinute: 14 * 60,
        endsAtMinute: 15 * 60 + 30,
      ),
    );

    final SchoolWeekData firstWeek = await school.getSchoolWeek(
      DateTime(2026, 9, 7),
    );
    final SchoolWeekData secondWeek = await school.getSchoolWeek(
      DateTime(2026, 9, 14),
    );

    expect(
      firstWeek.sessionsForLocalDay(DateTime(2026, 9, 7)).single.id,
      session.id,
    );
    expect(
      secondWeek.sessionsForLocalDay(DateTime(2026, 9, 14)).single.id,
      session.id,
    );
    expect(secondWeek.sessions.single.startsAtMinute, 14 * 60);
    expect(secondWeek.sessions.single.endsAtMinute, 15 * 60 + 30);
  });

  test('partial term weeks hide occurrences outside exact term dates',
      () async {
    final PlanningDatabase database = PlanningDatabase(NativeDatabase.memory());
    final DriftSchoolRepository school = schoolRepository(database);
    addTearDown(database.close);
    final AcademicTerm term = await school.createAcademicTerm(
      AcademicTermDraft(
        name: 'Short term',
        startsOnLocal: DateTime(2026, 9, 9),
        endsOnLocal: DateTime(2026, 9, 18),
      ),
    );
    final Subject subject = await school.createSubject(
      SubjectDraft(
        termId: term.id,
        name: 'Discrete Mathematics',
        colorValue: 0xFF8B5CF6,
      ),
    );
    for (final int weekday in <int>[
      DateTime.tuesday,
      DateTime.thursday,
      DateTime.saturday,
    ]) {
      await school.createClassSession(
        ClassSessionDraft(
          subjectId: subject.id,
          weekday: weekday,
          startsAtMinute: 10 * 60,
          endsAtMinute: 11 * 60,
        ),
      );
    }

    final SchoolWeekData firstWeek = await school.getSchoolWeek(
      DateTime(2026, 9, 7),
    );
    expect(
      firstWeek.sessionsForLocalDay(DateTime(2026, 9, 8)),
      isEmpty,
    );
    expect(
      firstWeek.sessionsForLocalDay(DateTime(2026, 9, 10)),
      hasLength(1),
    );

    final SchoolWeekData finalWeek = await school.getSchoolWeek(
      DateTime(2026, 9, 14),
    );
    expect(
      finalWeek.sessionsForLocalDay(DateTime(2026, 9, 17)),
      hasLength(1),
    );
    expect(
      finalWeek.sessionsForLocalDay(DateTime(2026, 9, 19)),
      isEmpty,
    );
  });

  test('rejects overlapping classes in the same academic term', () async {
    final PlanningDatabase database = PlanningDatabase(NativeDatabase.memory());
    final DriftSchoolRepository school = schoolRepository(database);
    addTearDown(database.close);
    final (_, Subject subject) = await createSchoolSetup(school);

    await school.createClassSession(
      ClassSessionDraft(
        subjectId: subject.id,
        weekday: DateTime.tuesday,
        startsAtMinute: 10 * 60,
        endsAtMinute: 11 * 60,
      ),
    );

    expect(
      () => school.createClassSession(
        ClassSessionDraft(
          subjectId: subject.id,
          weekday: DateTime.tuesday,
          startsAtMinute: 10 * 60 + 30,
          endsAtMinute: 12 * 60,
        ),
      ),
      throwsStateError,
    );
  });

  test('an assignment is one shared task in School and Plan', () async {
    final PlanningDatabase database = PlanningDatabase(NativeDatabase.memory());
    final DriftSchoolRepository school = schoolRepository(database);
    final DriftPlanningRepository planning = planningRepository(database);
    addTearDown(() async {
      planning.dispose();
      await database.close();
    });
    final (_, Subject subject) = await createSchoolSetup(school);

    final SchoolAssignment assignment = await school.createAssignment(
      SchoolAssignmentDraft(
        subjectId: subject.id,
        title: 'Normalization exercises',
        notes: 'Questions 1–10',
        dueAtUtc: DateTime(2026, 9, 9, 17).toUtc(),
      ),
    );

    final PlanningTask task =
        (await planning.watchUnscheduledTasks().first).single;
    expect(task.id, assignment.taskId);
    expect(task.kind, PlanningTaskKind.assignment);
    expect(task.subjectId, subject.id);

    await planning.changeTaskStatus(task.id, PlanningTaskStatus.completed);
    final SchoolWeekData updated = await school.getSchoolWeek(schoolWeek);
    expect(updated.assignments.single.status, PlanningTaskStatus.completed);
  });

  test('exams appear on the correct local school day and can be removed',
      () async {
    final PlanningDatabase database = PlanningDatabase(NativeDatabase.memory());
    final DriftSchoolRepository school = schoolRepository(database);
    addTearDown(database.close);
    final (_, Subject subject) = await createSchoolSetup(school);
    final DateTime start = DateTime(2026, 9, 11, 9);

    final Exam exam = await school.createExam(
      ExamDraft(
        subjectId: subject.id,
        title: 'Database midterm',
        startsAtUtc: start.toUtc(),
        endsAtUtc: start.add(const Duration(hours: 2)).toUtc(),
        room: 'Main Hall',
      ),
    );
    SchoolWeekData week = await school.getSchoolWeek(schoolWeek);
    expect(week.examsForLocalDay(start).single.id, exam.id);
    expect(week.exams.single.duration, const Duration(hours: 2));

    await school.deleteExam(exam.id);
    week = await school.getSchoolWeek(schoolWeek);
    expect(week.exams, isEmpty);
  });

  test('a complete school week persists after reopening SQLite', () async {
    final Directory directory = await Directory.systemTemp.createTemp(
      'gahunda-school-',
    );
    final File file = File('${directory.path}/school.sqlite');
    addTearDown(() => directory.delete(recursive: true));

    final PlanningDatabase firstDatabase =
        PlanningDatabase(NativeDatabase(file));
    final DriftSchoolRepository firstSchool = schoolRepository(firstDatabase);
    final (AcademicTerm term, Subject databases) =
        await createSchoolSetup(firstSchool);
    final Subject networks = await firstSchool.createSubject(
      SubjectDraft(
        termId: term.id,
        name: 'Computer Networks',
        colorValue: 0xFF0F9D8A,
      ),
    );
    for (int weekday = DateTime.monday;
        weekday <= DateTime.friday;
        weekday += 1) {
      await firstSchool.createClassSession(
        ClassSessionDraft(
          subjectId: weekday.isEven ? networks.id : databases.id,
          weekday: weekday,
          startsAtMinute: 8 * 60,
          endsAtMinute: 9 * 60,
        ),
      );
    }
    await firstSchool.createAssignment(
      SchoolAssignmentDraft(
        subjectId: databases.id,
        title: 'Schema design report',
        dueAtUtc: DateTime(2026, 9, 10, 17).toUtc(),
      ),
    );
    await firstSchool.createExam(
      ExamDraft(
        subjectId: networks.id,
        title: 'Networks quiz',
        startsAtUtc: DateTime(2026, 9, 11, 10).toUtc(),
        endsAtUtc: DateTime(2026, 9, 11, 11).toUtc(),
      ),
    );
    await firstDatabase.close();

    final PlanningDatabase reopenedDatabase = PlanningDatabase(
      NativeDatabase(file),
    );
    final DriftSchoolRepository reopenedSchool = schoolRepository(
      reopenedDatabase,
    );
    addTearDown(reopenedDatabase.close);
    final SchoolWeekData week = await reopenedSchool.getSchoolWeek(schoolWeek);

    expect(week.activeTerm?.name, 'Term 1');
    expect(week.subjects, hasLength(2));
    expect(week.sessions, hasLength(5));
    expect(week.assignments.single.title, 'Schema design report');
    expect(week.exams.single.title, 'Networks quiz');
  });

  test('school week stream refreshes after a write', () async {
    final PlanningDatabase database = PlanningDatabase(NativeDatabase.memory());
    final DriftSchoolRepository school = schoolRepository(database);
    addTearDown(database.close);
    final StreamIterator<SchoolWeekData> iterator =
        StreamIterator<SchoolWeekData>(
      school.watchSchoolWeek(schoolWeek),
    );
    addTearDown(iterator.cancel);

    expect(await iterator.moveNext(), isTrue);
    expect(iterator.current.activeTerm, isNull);

    await createSchoolSetup(school);
    expect(await iterator.moveNext(), isTrue);
    expect(iterator.current.activeTerm?.name, 'Term 1');
  });
}
