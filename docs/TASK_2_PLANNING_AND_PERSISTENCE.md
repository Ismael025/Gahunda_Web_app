# Task 2 — Planning domain and local persistence

## Outcome

Task 2 replaces the planning mock data with a local-first planning feature.
The Plan and Today screens now read through a repository, and planning changes
are stored in the `gahunda.sqlite` database on the device.

## Domain decisions

1. Goals support annual, monthly, weekly, and daily scopes.
2. The first complete hierarchy is `Goal -> Milestone -> Milestone -> Task`.
3. `PlanPeriod` records define the UTC boundaries behind annual, monthly, and
   weekly planning.
4. A task is unscheduled when it has no scheduled timestamp or time block.
5. A scheduled task has one `TimeBlock`; rescheduling updates that block.
6. Task outcomes are pending, in progress, completed, skipped, or cancelled.
7. An assignment is a planning task with `kind = assignment` and a required
   `subjectId`. The School feature can add the Subject table in Task 4 without
   duplicating task behavior.
8. Goal removal is archival. The goal row and its completed task history remain
   intact for reviews and future synchronization.

## Dependency direction

```text
Plan / Today widgets
        |
Riverpod application providers
        |
PlanningRepository contract
        ^
DriftPlanningRepository -> Drift -> SQLite
```

Widgets do not import the database layer. The repository converts SQLite rows
into domain entities and emits updated streams after successful transactions.

## Local schema

| Table | Purpose | Important relationships |
| --- | --- | --- |
| `goals` | Long-term direction and archive state | Optional parent goal |
| `plan_periods` | UTC year/month/week boundaries | Goal and optional parent period |
| `milestones` | Monthly and weekly outcomes | Goal, period, optional parent milestone |
| `planning_tasks` | General tasks and school assignments | Optional goal, milestone, and subject |
| `time_blocks` | Scheduled execution windows | At most one time block per task |

Foreign keys use `ON DELETE SET NULL` as a second layer of history protection.
Normal product behavior archives goals instead of physically deleting them.

## Persistence and time rules

- IDs are generated locally before insertion so records can later sync offline.
- All timestamps are converted to UTC before storage.
- The UI converts timestamps back to the device's local timezone.
- Creating a connected planning path is one database transaction. A partial
  hierarchy is rolled back if any insert fails.
- SQLite foreign-key checks are enabled every time the database opens.
- Schema version 1 is explicit so later tasks can add tested migrations.

## Acceptance demo

1. Open **Plan**.
2. Select **New planning path**.
3. Enter an annual school goal, monthly milestone, weekly outcome, task, and
   task schedule.
4. Save the path.
5. Use the task menu to complete, reschedule, skip, cancel, or remove its
   schedule.
6. Close the application completely and reopen it.
7. Confirm the goal, both milestones, task, time block, and relationships are
   still present.
8. Archive the goal and confirm it leaves the active plan without deleting
   completed task history.

Quick add also stores scheduled or unscheduled tasks. Today's schedule reacts
to tasks that fall on the current local date.

## Verification

Run from the project root:

```bash
flutter pub get
dart format lib test
flutter analyze
flutter test
```

The repository tests cover hierarchy creation, database reopen, rescheduling,
unscheduled tasks, subject-linked assignments, and archive-safe history.
