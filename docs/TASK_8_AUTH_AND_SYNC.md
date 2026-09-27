# Task 8: Authentication and synchronization

## Outcome

Gahunda remains an offline-first application. Its SQLite database is always the
working copy, so Plan, Today, School, Track, Money, and Insights continue to work
without a connection. A Supabase account adds an authenticated cloud backup and
the ability to restore the same records on another device.

## User workflow

1. Open the avatar in the top-right corner.
2. Continue in **Local-only mode**, or create an account when cloud configuration
   is available.
3. After signing in, Gahunda claims the current local database for that account
   and performs the first synchronization.
4. Continue using every feature normally. Saved local changes schedule a
   background sync, and **Sync now** is always available from the account panel.
5. Sign in with the same account on another device. An empty installation
   restores the cloud copy automatically.
6. If both devices changed independently, choose **Keep device copy** or
   **Use cloud copy**. Neither side is overwritten before that explicit choice.

Signing out keeps the SQLite database on the device but locks it. Only the
account that claimed the device data can unlock it again. A different signed-in
account cannot view or synchronize those records.

## Synchronization rules

- The complete user dataset is backed up as a versioned JSON snapshot.
- The snapshot contains all Task 2–7 domain tables, but never authentication
  tokens or local synchronization metadata.
- Each cloud write uses an expected revision. The PostgreSQL function rejects
  the write when another device has already advanced that revision.
- A SHA-256 fingerprint detects whether the local working copy changed since
  its last successful sync.
- Cloud payload fingerprints are verified before import.
- Imports validate the expected table and column set and run a SQLite foreign-key
  check before committing.
- A remote-only change is downloaded automatically when the local copy is still
  unchanged.
- A local-only change is uploaded automatically when the remote revision is
  unchanged.
- Simultaneous changes become a visible conflict and require a decision.

## Local schema migration

Database schema version 7 adds only `sync_metadata`. It stores the owning user
ID, a random device ID, the last accepted cloud revision, the synchronized
fingerprint, the last successful time, and the latest error. Existing feature
tables are not recreated and their records are preserved.

## Supabase setup

1. Create a Supabase project.
2. Open **SQL Editor**, paste
   `supabase/task8_auth_and_sync.sql`, and run the complete script once.
3. Under **Authentication → Providers**, keep Email enabled. For the quickest
   local acceptance test, disable email confirmation. For production, leave
   confirmation enabled and confirm the email before signing in.
4. Copy the project URL and the client-safe publishable key. Never place the
   `service_role` secret in a Flutter application.
5. Run Gahunda with compile-time configuration:

```powershell
flutter run -d windows `
  --dart-define=SUPABASE_URL=https://YOUR_PROJECT.supabase.co `
  --dart-define=SUPABASE_PUBLISHABLE_KEY=YOUR_PUBLISHABLE_KEY
```

For Android, use the same definitions with the device ID:

```powershell
flutter run -d YOUR_ANDROID_DEVICE `
  --dart-define=SUPABASE_URL=https://YOUR_PROJECT.supabase.co `
  --dart-define=SUPABASE_PUBLISHABLE_KEY=YOUR_PUBLISHABLE_KEY
```

Without those definitions the app deliberately starts in local-only mode. The
publishable key is designed for client applications; Row Level Security ensures
that an authenticated user can only access the row whose `user_id` matches
their Supabase identity.

## Acceptance path

1. Start without cloud definitions and confirm every existing feature remains
   usable and the account panel reports **Local-only mode**.
2. Run the Supabase SQL and restart with the two `--dart-define` values.
3. Create an account, or sign in when email confirmation is enabled.
4. Press **Sync now** and confirm **Up to date** plus a last-sync time.
5. Add a task or habit while offline; confirm it saves locally.
6. Reconnect and press **Sync now**; confirm the new record is uploaded.
7. Start a clean installation on another device and sign in with the same
   account; confirm the data restores.
8. Change the same account independently on two devices, then sync both; confirm
   Gahunda asks which copy to keep instead of overwriting silently.
9. Sign out; confirm the local data remains but is locked.
10. Sign back into the owning account and confirm the data returns.

## Verification

```powershell
flutter create --platforms=android,windows .
flutter pub get
dart format lib test
flutter analyze
flutter test
```

Automated coverage includes schema migration, snapshot round-trip and integrity,
first-device upload, empty-device restore, remote-only download, explicit
conflict decisions, account mismatch protection, and the local-only interface.
The complete Task 8 project contains 63 automated tests.

Supabase implementation follows its official Flutter initialization and email
authentication APIs and protects the cloud row with PostgreSQL Row Level
Security:

- <https://supabase.com/docs/reference/dart/initializing>
- <https://supabase.com/docs/reference/dart/auth-signup>
- <https://supabase.com/docs/reference/dart/auth-signinwithpassword>
- <https://supabase.com/docs/guides/database/postgres/row-level-security>
