# Gahunda project blueprint

## 1. Product decision

Gahunda will be an offline-friendly personal operating system that connects:

1. long-term direction;
2. daily scheduling and execution;
3. school responsibilities;
4. behavior and habit tracking;
5. personal money management; and
6. reflection and plan-versus-reality insights.

The first audience is students. The domain model will remain general enough to
support employee, entrepreneur, freelancer, and wellness templates later.

## 2. Technology toolchain

Versions are deliberately not pinned in this document. Each implementation task
will lock compatible versions in `pubspec.lock` and CI after a successful build.

| Area | Selected tool | Why it fits Gahunda |
| --- | --- | --- |
| Mobile UI | Flutter | One Dart codebase for Android and iOS, strong custom UI, Material 3 |
| Language | Dart | Null safety, strong typing, readable async code, native Flutter tooling |
| Design | Figma + Material 3 | Fast flows and reusable components before expensive implementation |
| Code editor | Android Studio or VS Code | Flutter/Dart extensions, debugger, emulator and formatting |
| Android testing | Android Studio emulator + physical Android device | Fast iteration plus real notification, database and performance checks |
| iOS testing | Xcode simulator + physical iPhone on macOS | Required before an App Store release |
| Architecture | Feature-first, layered MVVM | Separates UI, application logic and data while keeping features understandable |
| State management | Riverpod | Testable shared state and explicit dependency access; add in Task 2 |
| Navigation | go_router | Declarative routing, guarded routes, deep links and nested navigation |
| Local database | Drift on SQLite | Typed relational data, queries, migrations and reactive offline reads |
| Small preferences | shared_preferences | Theme, language and simple non-sensitive settings only |
| Secrets/tokens | flutter_secure_storage | Platform-protected storage for authentication tokens |
| Cloud backend | Supabase | PostgreSQL, authentication, storage, realtime and Row Level Security in one service |
| API edge logic | Supabase Edge Functions | Server-only operations, scheduled summaries and protected integrations |
| Notifications | flutter_local_notifications + timezone | Local reminders that respect user timezone and recurring schedules |
| Charts | Flutter layout primitives | Accessible, dependency-light review charts; adopt a chart library only when interaction needs justify it |
| Data classes | freezed + json_serializable | Immutable models and safer serialization when cloud sync begins |
| Localization | Flutter gen_l10n + intl | English first; Kinyarwanda and other languages can be added without rewriting UI |
| Unit/widget tests | flutter_test + mocktail | Fast domain, repository, state and interface checks |
| End-to-end tests | integration_test | Real flows across screens, database and device capabilities |
| Source control | Git + GitHub | Reviewable history, branches, issues and recovery |
| Automation | GitHub Actions | Format, analyze and test every proposed change |
| Crash reporting | Sentry | Production errors and performance traces without logging financial content |
| Product analytics | PostHog, opt-in | Privacy-aware feature usage; never capture journal or transaction text |

### Why Supabase instead of building a custom backend first

The schedule is short and Gahunda's data is relational. PostgreSQL is a natural
fit for goals, plan periods, tasks, habits, check-ins, accounts, transactions,
classes and reviews. Supabase provides authentication and storage beside the
database, while Row Level Security can restrict each record to its owner.

A custom Dart or TypeScript API remains possible later. It is not needed for the
first beta and would slow down validation of the product itself.

### Why the app is offline-friendly

Schedules, habits and expenses must still work during poor or unavailable
connectivity. The local Drift database becomes the mobile source of truth for
the interface. A synchronization layer sends pending changes to Supabase and
pulls remote changes when a connection is available.

Sync is intentionally postponed until the local domain model and conflict rules
are tested. Starting with remote writes would hide important offline cases.

## 3. Architecture

Each feature will use the same small set of layers:

```text
feature/
├── presentation/    # Pages, widgets, controllers/view models
├── domain/          # Entities, value objects and repository contracts
└── data/            # Drift/Supabase models and repository implementations
```

Dependency direction:

```text
Presentation -> Domain <- Data
```

Rules:

- Widgets do not query SQLite or Supabase directly.
- Repositories are the only place that update source data.
- Money uses integer minor units, never floating-point values.
- Every stored date-time is UTC; the UI displays the user's timezone.
- IDs are generated locally so offline records can synchronize later.
- Feature code cannot import another feature's presentation layer.
- Generated code is reviewed through its source declarations and tests.

## 4. Core domain modules

| Module | First entities |
| --- | --- |
| Identity | UserProfile, UserSettings |
| Planning | Goal, Milestone, PlanPeriod, Task, TimeBlock |
| School | AcademicTerm, Subject, ClassSession, Assignment, Exam |
| Behavior | Habit, HabitSchedule, HabitCheckIn, MoodEntry |
| Money | Account, Category, Budget, Transaction, SavingsGoal |
| Reflection | DailyReview, WeeklyReview, MonthlyReview, AnnualReview |
| System | Reminder, SyncOperation, Attachment |

Planning hierarchy:

```text
Annual goal
  -> monthly milestone
    -> weekly outcome
      -> daily task or time block
```

Tasks may exist without a goal, but the interface will encourage users to
connect important work to a larger outcome.

## 5. Security and privacy baseline

- Enable Row Level Security on every user-owned remote table.
- Never ship a Supabase service-role key in the mobile application.
- Keep authentication material in secure platform storage.
- Avoid recording descriptions, journal text, or financial values in analytics.
- Provide data export and account deletion before public release.
- Make biometric locking optional for money and journal areas.
- Use explicit opt-in for analytics, cloud backup and future automatic imports.
- Redact personal data from crash reports and developer logs.
- Test database migrations against a copied dataset before release.

Gahunda initially records expenses manually. Mobile-money or banking imports are
a later investigation because access, consent, security and regulatory needs
must be confirmed first.

## 6. Delivery roadmap: one task at a time

| Task | Outcome | Exit check |
| --- | --- | --- |
| 1. Foundation | Product blueprint, theme, responsive shell and mock screens | Navigation flow reviewed; source analyzes and tests pass in Flutter environment |
| 2. Planning domain | Goal hierarchy, task and time-block models plus local database | Create/edit/reschedule persists after restart; repository tests pass |
| 3. Today workflow | Real dashboard, quick add and end-of-day closure | Today's data reflects database changes immediately |
| 4. School mode | Terms, subjects, timetable, assignments and exams | A student can build and use one complete school week |
| 5. Behavior tracking | Flexible habits, check-ins, reduction targets and recovery | Daily and weekly completion is calculated correctly |
| 6. Money | Accounts, integer RWF transactions, categories, budgets, savings | Balances and budget totals reconcile in tests |
| 7. Reviews and insights | Daily/weekly/monthly/annual reviews and plan-versus-reality | Metrics reproduce known test datasets |
| 8. Authentication and sync | Sign-in, RLS, offline queue and conflict rules | Two devices converge without losing offline edits |
| 9. Reminders | Local reminders, timezone handling and preferences | Notifications survive restart and timezone changes |
| 10. Beta hardening | Accessibility, localization, performance, security and release QA | Physical-device acceptance suite passes |

## 7. Short MVP sprint

If only a few days are available, the beta should be local-first and Android
first. A realistic compressed sequence is:

- **Day 1:** review Task 1 and complete the local planning database;
- **Day 2:** connect Today, school timetable and behavior check-ins;
- **Day 3:** connect manual expenses, budgets and weekly review;
- **Day 4:** reminders, error states, tests and accessibility;
- **Day 5:** physical Android-device QA and beta package.

Authentication, multi-device sync, AI suggestions, social features and automatic
financial imports should not block this first local beta.

## 8. Current implementation status

Implemented in the foundation prototype:

- Material 3 light/dark themes;
- responsive mobile bottom navigation and wide-screen navigation rail;
- Today, Plan, School, Track, Money and Insights pages;
- RWF-oriented examples;
- annual-to-daily planning path;
- plan-versus-reality visualization;
- quick-add interaction;
- starter widget tests; and
- dependency-light Flutter source.

Implemented in Task 2:

- Goal, milestone, plan-period, task, and time-block domain entities;
- a repository contract with a Drift/SQLite implementation;
- Riverpod dependency injection and reactive local reads;
- transactional create/edit/reschedule planning flows;
- scheduled and unscheduled task creation;
- completed, skipped, and cancelled task outcomes;
- UTC persistence with local-time display;
- history-preserving goal archival; and
- repository tests for the Task 2 acceptance path.

Implemented in Task 3:

- live Today totals calculated from scheduled tasks and time blocks;
- immediate cross-feature refresh after Quick Add or task status changes;
- scheduled and unscheduled Quick Add with notes and duration;
- explicit complete, reopen, move-to-tomorrow, skip, and cancel actions;
- a locally persisted end-of-day closure with mood, win, lesson, and tomorrow
  focus;
- explicit outcomes for every unfinished task during day closure;
- schema version 2 migration that preserves existing Task 2 planning data; and
- repository and widget tests for reactive changes, closure decisions, and
  restart persistence.

Implemented in Task 4:

- academic terms with one explicit active term;
- subjects with course, teacher, room, and color details;
- reusable Monday–Sunday class sessions with overlap protection;
- week navigation and a complete school timetable;
- subject-linked assignments stored as shared planning tasks;
- exams with local date/time, duration, room, and notes;
- today’s classes, exams, and assignment deadlines on the Today page;
- schema version 3 migration that preserves Tasks 2–3 data; and
- repository and widget tests for the complete school-week acceptance path.

Implemented in Task 5:

- yes/no, count/quantity, and time measurement with guided unit choices;
- build targets and reduction limits with distinct success rules;
- weekday schedules, optional start/end dates, preferred times, and colors;
- daily check-ins available from both Today and Track;
- weekly completion that excludes future opportunities;
- current/best streaks over scheduled days;
- yesterday recovery with editable historical check-ins;
- Quick add integration and reactive cross-screen refresh;
- schema version 4 migration preserving Tasks 2–4 data; and
- repository/widget coverage for calculation and persistence rules.

Implemented in Task 6:

- active cash, mobile-money, bank, and savings accounts with calculated RWF
  balances;
- integer-only income, expense, and account-transfer ledger entries;
- useful seeded income and expense categories plus custom categories;
- monthly category budgets driven only by matching expense entries;
- savings goals whose deposits and withdrawals preserve total net worth;
- insufficient-funds protection, history-preserving transaction voids, and
  safe archive rules;
- Quick add expense plus today’s spending, income, and spendable balance on
  the Today page;
- schema version 5 migration preserving Tasks 2–5 data; and
- repository/widget coverage for reconciliation, migration, reactivity, and
  restart persistence.

Implemented in Task 7:

- live weekly, monthly, and annual review periods with calendar navigation;
- task completion and planned-versus-completed duration from saved schedule
  data;
- historical day-closure snapshots that remain accurate after carryover;
- habit consistency that counts only scheduled days that have occurred;
- income, spending, and net cash flow with transfers excluded from both totals;
- recurring class occurrences, assignment completion, exams, and average mood;
- evidence-based pattern prompts without invented or predictive claims;
- saved and editable period reviews with rating, wins, challenges, lessons, and
  the next focus;
- Quick add reflection connected to the existing Today closure workflow;
- schema version 6 migration preserving Tasks 2–6 data; and
- repository/widget coverage using known datasets, migration, reactivity, and
  restart persistence.

Implemented in Task 8:

- optional Supabase email/password accounts without blocking local-only use;
- an offline-first SQLite working copy with background and manual sync;
- authenticated, Row-Level-Security-protected cloud snapshots;
- revision checks and SHA-256 integrity fingerprints;
- automatic restore onto an empty second device;
- explicit device-versus-cloud decisions for simultaneous changes;
- account ownership that locks retained local data after sign-out;
- schema version 7 migration preserving Tasks 2–7 data; and
- repository/widget coverage for migration, integrity, restore and conflicts.

Implemented in Tasks 9 and 10 for the Gahunda 1.0 release candidate:

- scheduled personal-task reminders fixed at exactly five minutes before the
  current task start;
- configurable class, assignment, and exam lead times;
- habit reminders at each habit's preferred time and an optional daily closure
  reminder;
- automatic reminder replacement after edits, status changes, cloud restores,
  and application restart;
- device-local permission, timezone, exact-timing, pending-count, test, rebuild,
  and disable controls;
- Android reboot recovery and exact-alarm configuration, iOS notification and
  auth-deep-link configuration, and Windows MSIX packaging metadata;
- production email-confirmation redirect support;
- schema version 8 migration preserving Tasks 2–8 data; and
- final release commands, security notes, limitations, and acceptance QA.

## 9. Task 2 definition — implemented

Task 2 is **Planning domain and local persistence**. Its confirmed rules are:

1. a goal may have annual, monthly, weekly or daily scope;
2. a task can be scheduled or unscheduled;
3. unfinished tasks can be completed, rescheduled, skipped or cancelled;
4. school assignments can link to a subject and also behave like tasks; and
5. deleting a goal will not silently delete completed history.

The Task 2 acceptance demo is: create an annual school goal, attach a monthly
milestone, create a weekly outcome and schedule a task today; close and reopen
the app; all four records and their relationships remain intact.

See [TASK_2_PLANNING_AND_PERSISTENCE.md](TASK_2_PLANNING_AND_PERSISTENCE.md)
for implementation and verification details.

## 10. Official technical references

- [Flutter architecture guide](https://docs.flutter.dev/app-architecture/guide)
- [Flutter offline-first guidance](https://docs.flutter.dev/app-architecture/design-patterns/offline-first)
- [Riverpod documentation](https://riverpod.dev/)
- [Drift documentation](https://drift.simonbinder.eu/)
- [Supabase Flutter quickstart](https://supabase.com/docs/guides/getting-started/quickstarts/flutter)
- [Supabase Row Level Security](https://supabase.com/docs/guides/database/postgres/row-level-security)
