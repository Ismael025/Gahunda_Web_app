# Task 5: Behavior tracking

## Outcome

Track is no longer a mock screen. Gahunda stores flexible habits and daily
check-ins in its local SQLite database, calculates daily and weekly progress,
and keeps Today and Track synchronized without a restart.

## Habit rules

- A habit can be measured as yes/no, a count/quantity, or time.
- Count/quantity habits use a guided unit list such as repetitions, sets,
  steps, pages, glasses, cups, servings, sessions, items, laps, meters, or
  kilometers.
- Time habits use a guided choice of minutes, hours, or seconds.
- A **build** target succeeds when the recorded value is at least the target.
- A **reduce** target succeeds when the value is at most the limit; a limit of
  zero is valid.
- Yes/no habits are build targets with a stored value and target of one.
- Every habit selects one or more weekdays and has a local start date.
- An optional end date stops future occurrences without deleting history.
- Preferred time and color are display metadata and do not create a planning
  time block.
- Only today or a past scheduled day can receive a check-in.
- Archiving removes a habit from active tracking but preserves its check-ins.

## Daily, weekly, and recovery calculations

Daily completion is the number of scheduled habits whose recorded value meets
their target. An unrecorded habit is incomplete. Weekly consistency divides
successful check-ins by scheduled opportunities from Monday through today;
future days are excluded from both totals.

Streaks advance only over days on which a habit is scheduled. An unrecorded
current day is treated as still open, while a missed past scheduled day breaks
the streak. Recovery lists habits that were scheduled yesterday but were not
recorded successfully. Selecting yesterday in Track allows that check-in to be
added or corrected.

## Product workflow

1. Create a habit from **Track → New habit** or **Quick add → Habit**.
2. Choose build/reduce, measurement, a provided unit, target, weekdays, date
   range, preferred time, and color. Units are selected instead of typed.
3. Complete a yes/no habit or log a numeric value from Today or Track.
4. Navigate to a past day to correct or clear a check-in.
5. Use the week card for completion and the recovery card for yesterday.
6. Edit future habit settings or archive the habit while retaining history.

## Local schema and migration

Database schema version 4 adds:

| Table | Purpose |
| --- | --- |
| `habits` | Habit definition, schedule, target, display data, archive state |
| `habit_check_ins` | One numeric check-in per habit and local calendar day |

The migration only adds tables and indexes. Existing planning, day-closure,
and school records from Tasks 2–4 are not recreated or removed.

## Acceptance path

1. Create an every-day yes/no habit through Quick add.
2. Mark it complete on Today and confirm Track updates immediately.
3. Clear the check-in and confirm both screens return to incomplete.
4. Create a build habit with a numeric target and record values below and at
   the target.
5. Create a reduction habit and record values above and at/below its limit.
6. Confirm future days are excluded from this week's denominator.
7. Leave yesterday incomplete, review recovery, then backfill yesterday.
8. Restart the app and confirm definitions, check-ins, totals, and history
   remain available.

## Verification

Run from the project root:

```bash
flutter pub get
dart format lib test
flutter analyze
flutter test
flutter run -d windows
```

Repository tests cover build/reduction rules, schedules, end dates, future-day
exclusion, streaks, recovery, validation, check-in replacement, archival, and
file-backed SQLite persistence.
