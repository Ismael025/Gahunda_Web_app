# Gahunda 1.0 release guide

This release combines Task 9 (reminders and notifications) and Task 10
(release hardening). The SQLite database remains the working copy. Reminder
settings are kept locally per installation and are intentionally excluded from
the cloud snapshot.

## Prepare generated platform runners

The source archive does not include generated Flutter runners. From the
`gahunda_app` directory on Windows, run:

```powershell
flutter create --platforms=android,windows .
powershell -ExecutionPolicy Bypass -File tool/configure_platforms.ps1
flutter pub get
dart run flutter_launcher_icons -f flutter_launcher_icons.yaml
dart format lib test
flutter analyze
flutter test
```

The expected suite contains **73 tests**. You can run the same preparation and
quality checks with one command:

```powershell
powershell -ExecutionPolicy Bypass -File tool/release_check.ps1
```

Run the configuration script after any future `flutter create` repair. It is
idempotent and adds Android scheduled-alarm declarations, Android reboot
recovery, the app auth deep link, desugaring, and iOS configuration when an iOS
runner exists.

On macOS, generate the iOS runner and branded icon with:

```bash
flutter create --platforms=ios .
flutter pub get
dart run flutter_launcher_icons -f flutter_launcher_icons-ios.yaml
```

## Reminder behavior

- Scheduled personal tasks: exactly 5 minutes before the start time. This lead
  time is fixed.
- Classes: 10 minutes by default and configurable.
- Assignments: 1 day before the deadline by default and configurable.
- Exams: 1 hour before the start by default and configurable.
- Habits: at the preferred time saved on the habit.
- Daily closure: optional, defaulting to 8:30 PM when enabled.

Open the bell in the top app bar, select **Enable reminders**, grant the system
permissions, and use **Send test**. The app rebuilds pending reminders after
relevant local edits, cloud restores, and each app start. Completed, cancelled,
skipped, deleted, or unscheduled tasks do not keep a task reminder.

The nearest 60 notifications are scheduled. This stays below Apple's 64
pending-notification limit and is refreshed whenever the app is opened or data
changes.

On Android 13+, notification permission must be granted. On recent Android
versions, also allow exact alarms for precise five-minute delivery. If exact
alarms are denied, Gahunda clearly reports that Android may deliver reminders
late and uses an inexact fallback.

Windows testing works from `flutter run`, but reliable cancellation of old
Windows toasts requires the installed MSIX build because Windows associates
that capability with package identity.

## Supabase production authentication

In Supabase Dashboard, open **Authentication → URL Configuration** and add:

```text
io.gahunda.app://login-callback/**
```

Before public release, enable **Confirm email** again under the email provider
settings and configure a production SMTP sender. Never put a Supabase service
role key in the Flutter app. The publishable/anon key is the client key; data
protection continues to depend on the supplied Row Level Security policies.

## Run with cloud sync

```powershell
flutter run -d windows `
  --dart-define=SUPABASE_URL=https://YOUR_PROJECT.supabase.co `
  --dart-define=SUPABASE_PUBLISHABLE_KEY=YOUR_PUBLISHABLE_KEY
```

For a production build, pass the same two definitions to the build command.

## Release builds

Android App Bundle:

```powershell
flutter build appbundle --release `
  --dart-define=SUPABASE_URL=https://YOUR_PROJECT.supabase.co `
  --dart-define=SUPABASE_PUBLISHABLE_KEY=YOUR_PUBLISHABLE_KEY
```

The output is under `build/app/outputs/bundle/release/`. Configure a private
upload keystore before Play Store publication.

Windows MSIX:

```powershell
flutter build windows --release `
  --dart-define=SUPABASE_URL=https://YOUR_PROJECT.supabase.co `
  --dart-define=SUPABASE_PUBLISHABLE_KEY=YOUR_PUBLISHABLE_KEY
dart run msix:create
```

Replace the placeholder MSIX identity and publisher settings in `pubspec.yaml`
with the values assigned by Microsoft Partner Center before Store submission.

## Final acceptance check

1. Analyzer reports no issues and the complete test suite passes.
2. Enable reminders and confirm **Send test** reaches the system notification
   center.
3. Create a task at least 10 minutes in the future and confirm its reminder is
   scheduled for exactly 5 minutes before it.
4. Reschedule the task and verify the pending reminder follows the new time.
5. Complete or cancel the task and verify it no longer contributes a reminder.
6. Verify class, assignment, exam, timed-habit, and optional closure reminders.
7. Restart while offline and confirm local data and reminders remain usable.
8. Sign in on a clean second installation, restore the cloud copy, and confirm
   reminders are rebuilt using that device's own permission settings.
9. Test the Android release bundle and installed Windows MSIX, not only debug
   builds.
