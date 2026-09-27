# Gahunda

Gahunda is a Flutter prototype for connected life planning: goals, schedules,
school, behavior, money, and reflection in one personal system.

This repository contains the Gahunda 1.1 web/PWA milestone based on the accepted
Gahunda 1.0 release candidate: the product/UI foundation, planning domain,
Today workflow, School Mode, behavior tracking, Money, Reviews and Insights,
authenticated cloud synchronization, and local reminders.
Planning paths, daily execution, academic work, habits, financial records,
reflections, and period reviews use one offline SQLite database through Drift
and reactive Riverpod providers.

## Prototype screens

- **Today** — live schedule, task and habit progress, today’s school and money
  activity, task resolution, and end-of-day reflection
- **Plan** — annual-to-daily goal hierarchy, tasks, and time blocks
- **School** — academic terms, subjects, recurring weekly classes,
  assignments, and exams
- **Track** — flexible habits, guided count/time units, build/reduction
  targets, check-ins, weekly consistency, streaks, and recovery
- **Money** — reconciled RWF accounts, income, expenses, transfers, monthly
  category budgets, and savings goals
- **Insights** — live weekly, monthly, and annual evidence, plan-versus-reality,
  pattern prompts, daily reflections, and saved period reviews
- **Account** — optional Supabase sign-in, revision-safe cloud backup,
  cross-device restore, and visible conflict decisions
- **Notifications** — device-local task, school, habit, and daily closure
  reminders with permission and timing status

## Run as a web app on Windows

Install the current Flutter stable SDK and confirm the installation:

```bash
flutter doctor
```

From the project root, prepare the browser database runtime:

```powershell
powershell -ExecutionPolicy Bypass -File .\tool\configure_web.ps1
```

Then run in Chrome with the same Supabase configuration used in Task 8:

```powershell
flutter run -d chrome `
  --dart-define=SUPABASE_URL="YOUR_PROJECT_URL" `
  --dart-define=SUPABASE_PUBLISHABLE_KEY="YOUR_PUBLISHABLE_KEY"
```

Build the tested release with:

```powershell
powershell -ExecutionPolicy Bypass -File .\tool\build_web.ps1 `
  -SupabaseUrl "YOUR_PROJECT_URL" `
  -SupabasePublishableKey "YOUR_PUBLISHABLE_KEY"
```

Deploy the generated `build\web` folder. See
[`docs/WEB_PWA_RELEASE_GUIDE.md`](docs/WEB_PWA_RELEASE_GUIDE.md) for the complete
free deployment and iPhone installation flow.

## Native development

The working native release remains supported. On Windows, create the Android
and Windows runners from the project root:

```bash
flutter create --platforms=android,windows .
powershell -ExecutionPolicy Bypass -File tool/configure_platforms.ps1
flutter pub get
dart run flutter_launcher_icons -f flutter_launcher_icons.yaml
dart format lib test
flutter analyze
flutter test
flutter run -d windows
```

To run Android, start an Android Studio emulator or connect a phone
with USB debugging, check it with `flutter devices`, and run
`flutter run -d <device-id>`.

The Dart/Flutter source also supports iPhone. Apple requires macOS with Xcode
to build, run, sign, and submit an iOS app. On a Mac, add and test iOS with:

```bash
flutter create --platforms=ios .
flutter pub get
dart run flutter_launcher_icons -f flutter_launcher_icons-ios.yaml
flutter run -d ios
```

## Current boundary

The planning path editor, task/habit/expense/reflection quick add, task outcomes,
task rescheduling, live Today metrics, end-of-day closure, school week, behavior
tracking, reconciled personal money, review metrics, and saved period reviews
are functional and persist locally. Authentication and remote synchronization
are available when Supabase is configured. Scheduled personal tasks always use
a five-minute lead time. Native builds schedule device-local notifications. The
web build delivers timed browser notifications while it remains open;
closed-app background delivery requires the separate Web Push stage.

## Structure

```text
lib/
├── core/                 # Shared theme and foundational models
├── features/             # Feature-first product areas
│   ├── shell/
│   ├── account/         # Authentication, local snapshots, sync and account UI
│   ├── notifications/   # Reminder planning, native delivery and settings UI
│   ├── today/
│   ├── planner/
│   │   ├── application/ # Riverpod providers
│   │   ├── data/        # Drift database and repository implementation
│   │   ├── domain/      # Entities and repository contract
│   │   └── presentation/
│   ├── school/          # Term, subject, timetable and assessment layers
│   ├── behavior/        # Habit domain, local repository and providers
│   ├── track/           # Behavior tracking interface
│   ├── money/           # Accounts, ledger, budgets, savings and providers
│   └── insights/
└── shared/widgets/       # Reusable visual components
```

Read [docs/PROJECT_BLUEPRINT.md](docs/PROJECT_BLUEPRINT.md) for the full roadmap.
Implementation and verification details are in:

- [Task 2 planning and persistence](docs/TASK_2_PLANNING_AND_PERSISTENCE.md)
- [Task 3 Today workflow](docs/TASK_3_TODAY_WORKFLOW.md)
- [Task 4 School Mode](docs/TASK_4_SCHOOL_MODE.md)
- [Task 5 behavior tracking](docs/TASK_5_BEHAVIOR_TRACKING.md)
- [Task 6 Money](docs/TASK_6_MONEY.md)
- [Task 7 Reviews and Insights](docs/TASK_7_REVIEWS_AND_INSIGHTS.md)
- [Task 8 authentication and sync](docs/TASK_8_AUTH_AND_SYNC.md)
- [Gahunda 1.0 release guide](docs/FINAL_RELEASE_GUIDE.md)
- [Web/PWA release guide](docs/WEB_PWA_RELEASE_GUIDE.md)

Gahunda 1.0 verification begins with:

1. Confirm local-only mode still saves every existing feature.
2. Apply `supabase/task8_auth_and_sync.sql` to a Supabase project.
3. Run with `SUPABASE_URL` and `SUPABASE_PUBLISHABLE_KEY` definitions.
4. Create an account, synchronize, and restore it on a clean installation.
5. Confirm concurrent device changes require an explicit copy choice.
6. Sign out and confirm the retained local data is locked.
7. Enable reminders, send a test notification, and verify a scheduled task
   notifies five minutes before its start.

Gahunda 1.0 adds database schema version 8 for local notification preferences.
Existing Task 2–8 databases migrate in place and keep all planning, closure,
school, habit, money, review, ownership, and synchronization data. Notification
preferences intentionally remain local to each device.
