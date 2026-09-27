# Task 4: School Mode

## Outcome

School Mode replaces the timetable mockup with a complete offline academic
workflow. A student can define a term, organize subjects, build a recurring
week, track assignment deadlines, schedule exams, and see today’s school work
alongside personal tasks.

## Academic structure

- An academic term has a local start and end date.
- Exactly one term can be active at a time.
- Subjects belong to a term and can store a code, teacher, default room, and
  display color.
- Class sessions belong to subjects, repeat on one weekday, and store local
  minute-of-day boundaries.
- Each occurrence is shown only when that exact local date falls within the
  term, including partial first and final weeks.
- Overlapping classes in the same term are rejected.

## Assignments and planning

An assignment is not a second copy of a task. Creating it writes one
`planning_tasks` record with `kind = assignment` and a required subject link,
plus a school association containing its deadline. It therefore appears in
School and in Plan’s task inbox. Completing or reopening it from either
workflow updates the same record and refreshes both screens immediately.

## Exams and Today

Exams store UTC start/end timestamps, while the interface collects and displays
local dates and times. The Today page reads the active school week and shows:

- today’s recurring classes;
- exams starting today; and
- assignments due today, including complete/reopen control.

## Local schema and migration

Database schema version 3 adds:

| Table | Purpose |
| --- | --- |
| `academic_terms` | Date range and active-term state |
| `subjects` | Courses inside a term |
| `class_sessions` | Recurring weekday timetable entries |
| `school_assignments` | Subject/deadline link to a planning task |
| `exams` | Timed subject assessments |

The version 3 migration adds these tables without recreating the existing
planning or daily-closure tables. Foreign keys protect the school relationships,
and a partial unique index enforces one active term.

## Acceptance path

1. Create a term covering the current date.
2. Add two or more subjects with different colors.
3. Add classes across Monday–Friday and verify an overlapping class is refused.
4. Add an assignment due this week and an exam during this week.
5. Navigate between weeks and return with **This week**.
6. Confirm the assignment appears as an unscheduled assignment in Plan.
7. Complete and reopen it in School or Today and confirm every view refreshes.
8. Check Today on an event date for its classes, exams, and deadlines.
9. Restart the app and confirm the term, subjects, week, assignment, and exam
   remain intact.

## Verification

Run from the project root:

```bash
flutter pub get
dart format lib test
flutter analyze
flutter test
flutter run -d windows
```

Repository coverage includes recurring sessions, exact term-date boundaries,
collision detection, shared assignment/task identity, exam dates and removal,
reactive refresh, and a full school week reopened from a file-backed SQLite
database.
