# Gahunda 1.1.0 web/PWA milestone

Gahunda 1.1 adapts the accepted 1.0 release candidate for browsers and
installable iPhone Home Screen use without replacing the native release.

## New in 1.1

- persistent Drift/SQLite browser storage through WebAssembly;
- installable PWA manifest, icons, standalone display, and offline shell;
- web-safe Supabase email-confirmation redirects;
- in-app installation guidance for iPhone, Android, and desktop;
- browser notification permission, test alerts, and open-app reminder timers;
- repeatable Windows setup and release-build scripts; and
- a free manual deployment path for the generated `build/web` folder.

The browser still calculates scheduled-task reminders at exactly five minutes
before start. Closed-app delivery is not claimed: browsers require a separate
server Web Push stage for reminders after the PWA is closed.

## Inherited from Gahunda 1.0

Gahunda 1.0 combines the complete Tasks 1–10 roadmap into one local-first
personal companion.

## New in this release

- scheduled task reminders fixed at exactly five minutes before start;
- class, assignment, exam, preferred-time habit, and optional daily closure
  reminders;
- notification permission, exact-timing, timezone, test, rebuild, and disable
  controls;
- automatic reminder reconciliation after edits, completion, cancellation,
  deletion, cloud restore, and restart;
- Android reboot recovery and exact-alarm configuration;
- Windows MSIX packaging and protocol activation;
- mobile email-confirmation deep links;
- a Gahunda launcher icon and consistent platform display name;
- database schema version 8 with device-local reminder preferences; and
- 73 automated tests across planning, Today, School, Track, Money, Insights,
  account sync, migrations, and reminder planning.

## Preserved behavior

All Task 8 planning, closure, school, habit, money, review, ownership, and cloud
snapshot data remains compatible. Notification preferences are not uploaded;
each device asks for permission and maintains its own reminder choices.

## Platform notes

- Android exact five-minute delivery needs both notification and exact-alarm
  permission. Some manufacturers may still restrict background alarms.
- iOS keeps a maximum of 64 pending notifications; Gahunda schedules at most
  the nearest 60.
- Windows notification cancellation is reliable in the installed MSIX build.
  An unpackaged debug build does not have full Windows package identity.
- Email confirmation requires the Gahunda callback URL to be allow-listed in
  the Supabase authentication settings.

See `docs/WEB_PWA_RELEASE_GUIDE.md` for browser setup, acceptance, deployment,
and iPhone installation commands.
