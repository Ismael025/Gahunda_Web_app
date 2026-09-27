import 'school_entities.dart';

abstract interface class SchoolRepository {
  Stream<SchoolWeekData> watchSchoolWeek(DateTime weekContaining);

  Future<SchoolWeekData> getSchoolWeek(DateTime weekContaining);

  Future<AcademicTerm> createAcademicTerm(AcademicTermDraft draft);

  Future<void> setActiveTerm(String termId);

  Future<Subject> createSubject(SubjectDraft draft);

  Future<ClassSession> createClassSession(ClassSessionDraft draft);

  Future<SchoolAssignment> createAssignment(SchoolAssignmentDraft draft);

  Future<Exam> createExam(ExamDraft draft);

  Future<void> deleteClassSession(String sessionId);

  Future<void> deleteExam(String examId);
}
