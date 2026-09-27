# Task 3: Today workflow

## Outcome

Today is no longer a mock dashboard. It reads the local planning database,
calculates task and time totals, updates immediately after writes, and stores a
structured end-of-day closure.

## Real dashboard data

The Today page calculates these values from scheduled tasks and their time
blocks:

- scheduled and completed task counts;
- open and resolved task counts;
- planned duration;
- duration attached to completed tasks; and
- completion, time, and resolution progress.

Money and habit totals are intentionally not presented as real data yet. Those
become database-driven in Tasks 5 and 6.

## Quick Add

Quick Add supports:

- an unscheduled task saved to the planning inbox; and
- a scheduled task with a title, optional notes, local date/time, and duration.

Scheduled tasks appear on Today immediately through the database change stream.
All dates are converted to UTC for storage and back to local time for display.

## Task resolution

A scheduled task can be:

- completed;
- reopened;
- moved to the same local time tomorrow;
- skipped; or
- cancelled.

Moving a task preserves its time-block duration.

## End-of-day closure

A daily closure stores:

- a mood score from 1 to 5;
- a win;
- a lesson or obstacle;
- tomorrow's main focus;
- a snapshot of task and time totals; and
- the UTC time when the closure was saved.

Every unfinished task receives an explicit decision: keep open, move to
tomorrow, skip, or cancel. The decisions and closure are written together in a
database transaction.

## Migration

The database schema advances from version 1 to version 2 by adding the
`daily_closures` table. Existing goals, milestones, tasks, and time blocks are
not recreated or deleted.

## Acceptance path

1. Add a scheduled task for today through Quick Add.
2. Confirm the Today list, task count, and planned duration update immediately.
3. Complete the task and confirm completed count and completed time update.
4. Reopen it and confirm the values reverse immediately.
5. Add another unfinished task and close the day.
6. Move that task to tomorrow and save a mood, win, lesson, and tomorrow focus.
7. Confirm Today shows the saved closure and tomorrow contains the moved task.
8. Restart the app and confirm both the closure and task outcomes persist.

Automated coverage checks the shared reactive stream, metric calculation,
transactional task resolution, time-block duration preservation, and closure
persistence after reopening SQLite.
