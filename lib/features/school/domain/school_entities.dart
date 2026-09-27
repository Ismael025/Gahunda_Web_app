import '../../planner/domain/planning_entities.dart';

class AcademicTerm {
  const AcademicTerm({
    required this.id,
    required this.name,
    required this.startsOnLocal,
    required this.endsOnLocal,
    required this.isActive,
    required this.createdAtUtc,
    required this.updatedAtUtc,
  });

  final String id;
  final String name;
  final DateTime startsOnLocal;
  final DateTime endsOnLocal;
  final bool isActive;
  final DateTime createdAtUtc;
  final DateTime updatedAtUtc;

  bool contains(DateTime localDate) {
    final DateTime day = DateTime(
      localDate.year,
      localDate.month,
      localDate.day,
    );
    return !day.isBefore(startsOnLocal) && !day.isAfter(endsOnLocal);
  }
}

class Subject {
  const Subject({
    required this.id,
    required this.termId,
    required this.name,
    required this.colorValue,
    required this.createdAtUtc,
    required this.updatedAtUtc,
    this.code,
    this.teacher,
    this.defaultRoom,
  });

  final String id;
  final String termId;
  final String name;
  final String? code;
  final String? teacher;
  final String? defaultRoom;
  final int colorValue;
  final DateTime createdAtUtc;
  final DateTime updatedAtUtc;
}

class ClassSession {
  const ClassSession({
    required this.id,
    required this.subjectId,
    required this.weekday,
    required this.startsAtMinute,
    required this.endsAtMinute,
    required this.createdAtUtc,
    required this.updatedAtUtc,
    this.room,
    this.notes,
  });

  final String id;
  final String subjectId;
  final int weekday;
  final int startsAtMinute;
  final int endsAtMinute;
  final String? room;
  final String? notes;
  final DateTime createdAtUtc;
  final DateTime updatedAtUtc;

  Duration get duration => Duration(
        minutes: endsAtMinute - startsAtMinute,
      );
}

class SchoolAssignment {
  const SchoolAssignment({
    required this.id,
    required this.subjectId,
    required this.taskId,
    required this.title,
    required this.status,
    required this.dueAtUtc,
    required this.createdAtUtc,
    required this.updatedAtUtc,
    this.notes,
  });

  final String id;
  final String subjectId;
  final String taskId;
  final String title;
  final String? notes;
  final PlanningTaskStatus status;
  final DateTime dueAtUtc;
  final DateTime createdAtUtc;
  final DateTime updatedAtUtc;

  bool get isFinished =>
      status == PlanningTaskStatus.completed ||
      status == PlanningTaskStatus.skipped ||
      status == PlanningTaskStatus.cancelled;
}

class Exam {
  const Exam({
    required this.id,
    required this.subjectId,
    required this.title,
    required this.startsAtUtc,
    required this.endsAtUtc,
    required this.createdAtUtc,
    required this.updatedAtUtc,
    this.room,
    this.notes,
  });

  final String id;
  final String subjectId;
  final String title;
  final DateTime startsAtUtc;
  final DateTime endsAtUtc;
  final String? room;
  final String? notes;
  final DateTime createdAtUtc;
  final DateTime updatedAtUtc;

  Duration get duration => endsAtUtc.difference(startsAtUtc);
}

class SchoolWeekData {
  const SchoolWeekData({
    required this.weekStartsOnLocal,
    required this.terms,
    required this.subjects,
    required this.sessions,
    required this.assignments,
    required this.exams,
  });

  final DateTime weekStartsOnLocal;
  final List<AcademicTerm> terms;
  final List<Subject> subjects;
  final List<ClassSession> sessions;
  final List<SchoolAssignment> assignments;
  final List<Exam> exams;

  AcademicTerm? get activeTerm {
    for (final AcademicTerm term in terms) {
      if (term.isActive) return term;
    }
    return null;
  }

  Subject? subjectById(String subjectId) {
    for (final Subject subject in subjects) {
      if (subject.id == subjectId) return subject;
    }
    return null;
  }

  List<ClassSession> sessionsForWeekday(int weekday) {
    return sessions
        .where((ClassSession session) => session.weekday == weekday)
        .toList(growable: false);
  }

  List<ClassSession> sessionsForLocalDay(DateTime day) {
    final AcademicTerm? term = activeTerm;
    if (term == null || !term.contains(day)) {
      return const <ClassSession>[];
    }
    return sessionsForWeekday(day.weekday);
  }

  List<Exam> examsForLocalDay(DateTime day) {
    return exams.where((Exam exam) {
      final DateTime local = exam.startsAtUtc.toLocal();
      return local.year == day.year &&
          local.month == day.month &&
          local.day == day.day;
    }).toList(growable: false);
  }

  List<SchoolAssignment> assignmentsDueOnLocalDay(DateTime day) {
    return assignments.where((SchoolAssignment assignment) {
      final DateTime local = assignment.dueAtUtc.toLocal();
      return local.year == day.year &&
          local.month == day.month &&
          local.day == day.day;
    }).toList(growable: false);
  }
}

class AcademicTermDraft {
  const AcademicTermDraft({
    required this.name,
    required this.startsOnLocal,
    required this.endsOnLocal,
  });

  final String name;
  final DateTime startsOnLocal;
  final DateTime endsOnLocal;
}

class SubjectDraft {
  const SubjectDraft({
    required this.termId,
    required this.name,
    required this.colorValue,
    this.code,
    this.teacher,
    this.defaultRoom,
  });

  final String termId;
  final String name;
  final String? code;
  final String? teacher;
  final String? defaultRoom;
  final int colorValue;
}

class ClassSessionDraft {
  const ClassSessionDraft({
    required this.subjectId,
    required this.weekday,
    required this.startsAtMinute,
    required this.endsAtMinute,
    this.room,
    this.notes,
  });

  final String subjectId;
  final int weekday;
  final int startsAtMinute;
  final int endsAtMinute;
  final String? room;
  final String? notes;
}

class SchoolAssignmentDraft {
  const SchoolAssignmentDraft({
    required this.subjectId,
    required this.title,
    required this.dueAtUtc,
    this.notes,
  });

  final String subjectId;
  final String title;
  final String? notes;
  final DateTime dueAtUtc;
}

class ExamDraft {
  const ExamDraft({
    required this.subjectId,
    required this.title,
    required this.startsAtUtc,
    required this.endsAtUtc,
    this.room,
    this.notes,
  });

  final String subjectId;
  final String title;
  final DateTime startsAtUtc;
  final DateTime endsAtUtc;
  final String? room;
  final String? notes;
}

DateTime startOfLocalWeek(DateTime date) {
  final DateTime day = DateTime(date.year, date.month, date.day);
  return day.subtract(Duration(days: day.weekday - DateTime.monday));
}
