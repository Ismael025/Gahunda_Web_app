# Task 7: Reviews and Insights

## Outcome

Insights is no longer a mock page. It calculates review evidence from the same
local records used by Today, Plan, School, Track, and Money. A user can inspect
one week, month, or year, write a review, edit it, and reopen the app without
losing either the evidence or reflection.

## How to use it

1. Use the rest of Gahunda normally: schedule and finish tasks, check in
   habits, record income or expenses, add school work, and close days.
2. Open **Insights**.
3. Choose **Weekly**, **Monthly**, or **Annual**.
4. Use the left and right arrows to inspect earlier periods. **Current** returns
   to the period containing today.
5. Read the summary cards, plan-versus-reality chart, life-area detail, and
   evidence-based observations.
6. Select **Start review**, choose a rating from 1 to 5, record wins and the
   next focus, and optionally add challenges and lessons.
7. Select **Edit review** whenever the saved reflection needs correction.

**Quick add → Reflection** opens Today's existing day-closure form. That daily
reflection appears in Insights automatically and contributes to closure rate
and average mood.

## Exact calculation rules

### Periods

- A week runs Monday through Sunday.
- A month uses its exact calendar start and end, including leap years.
- A year runs January 1 through December 31.
- Future days are displayed as context but never lower a completion rate.

### Plan versus reality

- A planned task is a non-deleted task with a saved scheduled start inside the
  selected period.
- Planned time is the duration between that task's saved start and end.
- Completed work counts only tasks whose status is `completed`.
- Skipped and cancelled tasks are resolved, but are not reported as completed.
- For a closed day, the saved closure snapshot replaces the live task view for
  that date. This preserves what was actually planned that day even if an
  unfinished task was moved to tomorrow afterward.

The chart groups values by day for a weekly review, seven-day segment for a
monthly review, and month for an annual review.

### Habits

- Only a habit's selected weekdays inside its start/end dates count.
- Only days up to and including today count.
- A build habit succeeds at or above its target.
- A reduction habit succeeds at or below its limit, but only when a value was
  actually recorded.
- Archived habits still contribute to their valid historical days, while days
  after archive do not.

### Money

- Income is the sum of non-voided income entries in the period.
- Spending is the sum of non-voided expense entries in the period.
- Net cash flow is income minus spending.
- Account transfers are excluded because they move existing money rather than
  create income or spending.
- Savings movements are also excluded from cash-flow totals because they move
  money between spendable and saved locations.

### School and reflection

- A recurring class counts once on each matching weekday that is inside its
  academic term and the elapsed part of the review period.
- Assignments count on their due date; completion comes from their shared Plan
  task status.
- Exams count on their scheduled date.
- Closure rate is saved daily closures divided by elapsed days in the period.
- Average mood uses only days with a saved closure.

## Saved period review

One review can be saved for each cadence and period start. Saving again updates
that review instead of creating a duplicate. Required fields are:

- rating from 1 to 5;
- wins; and
- next focus.

Challenges and lessons are optional. Review text stays on the device in this
local-first milestone.

## Local schema and migration

Database schema version 6 adds:

| Table | Purpose |
| --- | --- |
| `period_reviews` | One saved weekly, monthly, or annual reflection per period |

The migration creates the review table and index without recreating any earlier
table. Existing planning, daily closure, school, habit, and money information
is preserved.

## Acceptance path

1. Schedule two tasks this week with durations and complete one.
2. Check in a habit on some elapsed days but leave another elapsed opportunity
   incomplete.
3. Record one income, one expense, and one transfer.
4. Add a class, assignment, or exam inside the selected period.
5. Close today through **Quick add → Reflection**.
6. Open Insights and confirm task counts/durations, habit consistency, cash
   flow, school counts, and mood reproduce those records exactly.
7. Switch cadence and inspect a prior period.
8. Save and edit a period review.
9. Quit and reopen the app; confirm the review and all metrics remain.

## Verification

Run from the project root:

```bash
flutter create --platforms=android,windows .
flutter pub get
dart format lib test
flutter analyze
flutter test
flutter run -d windows
```

The Task 7 suite contains 54 tests. New coverage includes calendar boundaries,
plan-versus-reality, closed-day history, future-safe habit rates, transfer-neutral
cash flow, school events, review validation and editing, reactive updates,
file-backed persistence, the schema 5-to-6 migration, the Insights interface,
and Quick add reflection.
