# Gahunda background Web Push patch

This is a patch for the existing Gahunda 1.1 web project. Do not delete the
project and do not start again. Copy the patch files over the matching paths in
your current `gahunda_app` folder.

## What this changes

- Keeps the existing open-app browser timers as a fallback.
- Registers each signed-in browser or installed iPhone PWA for Web Push.
- Copies the next reminders into a protected Supabase queue.
- Runs a Supabase Edge Function every minute to send due reminders.
- Uses the existing service worker to show a notification while Gahunda is
  closed.
- Keeps the task rule at five minutes before its start time.

The server checks once per minute. A reminder is queued for exactly five
minutes before a task, but actual Web Push delivery can be several seconds or
occasionally longer after that time because browsers and iOS control final
delivery.

## Patch files

Copy these files while preserving their folders:

```text
lib/features/notifications/application/notification_providers.dart
lib/features/notifications/data/notification_gateway_factory_native.dart
lib/features/notifications/data/notification_gateway_factory_web.dart
lib/features/notifications/data/web_notification_gateway.dart
lib/features/notifications/presentation/notification_panel.dart
web/index.html
web/gahunda_web_push.js
tool/build_web.ps1
tool/generate_web_push_keys.mjs
supabase/web_push_schema.sql
supabase/web_push_cron.sql
supabase/functions/send-gahunda-reminders/index.ts
```

The existing `web/gahunda_service_worker.js` already contains the required
`push` and `notificationclick` handlers, so it is intentionally not replaced.

## Step 1 — Copy the patch into the existing project

Extract the small patch download. Suppose it extracts to:

```text
C:\Users\Ismael\Downloads\gahunda_web_push_patch
```

In PowerShell, make a safety commit first if the project is tracked by Git:

```powershell
cd C:\Users\Ismael\Downloads\gahunda_1_1_web_pwa\gahunda_app
git add -A
git commit -m "Before background web push"
```

It is okay if Git says there is nothing to commit. Now overlay the patch:

```powershell
Copy-Item `
  "C:\Users\Ismael\Downloads\gahunda_web_push_patch\*" `
  "C:\Users\Ismael\Downloads\gahunda_1_1_web_pwa\gahunda_app" `
  -Recurse -Force
```

Do not delete any other project files.

## Step 2 — Generate one Web Push key pair

From `gahunda_app`, run:

```powershell
node .\tool\generate_web_push_keys.mjs
```

It prints:

1. `WEB_PUSH_VAPID_PUBLIC_KEY` — safe to put in the web build.
2. `GAHUNDA_VAPID_KEYS_JSON` — private; put it only in Supabase secrets.

Save both temporarily in a private text file outside GitHub. Never send or
commit `GAHUNDA_VAPID_KEYS_JSON`.

Generate a separate random cron secret:

```powershell
node -e "console.log(require('crypto').randomBytes(32).toString('base64url'))"
```

Save that value privately as `GAHUNDA_CRON_SECRET`.

## Step 3 — Create the Supabase push tables and RPCs

Open your Supabase project, then open **SQL Editor → New query**.

Copy the complete contents of:

```text
supabase/web_push_schema.sql
```

Paste it into the editor and press **Run**. The result should be successful.
This script does not delete planning, school, habit, money, review, or snapshot
data.

## Step 4 — Add the Edge Function secrets

In Supabase, open **Edge Functions → Secrets** and add:

| Name | Value |
|---|---|
| `GAHUNDA_VAPID_KEYS_JSON` | The complete private JSON printed in Step 2 |
| `GAHUNDA_VAPID_SUBJECT` | `mailto:YOUR_REAL_EMAIL_ADDRESS` |
| `GAHUNDA_CRON_SECRET` | The random cron secret printed in Step 2 |

Supabase provides `SUPABASE_URL` and `SUPABASE_SERVICE_ROLE_KEY` to the Edge
Function automatically. Do not put the service-role key in Flutter, Vercel, or
GitHub.

## Step 5 — Deploy the Edge Function from Windows

Still inside `gahunda_app`, run:

```powershell
npx.cmd supabase init
npx.cmd supabase login
npx.cmd supabase link --project-ref qxijmrvgqronreesfnan
npx.cmd supabase functions deploy send-gahunda-reminders --no-verify-jwt
```

If `supabase init` says the project is already initialized, continue with the
next command.

The browser may open for Supabase login. The `--no-verify-jwt` setting is
intentional: the scheduled request is authenticated with the long random cron
secret, and the function rejects requests without it.

## Step 6 — Store the scheduler values in Supabase Vault

Open **SQL Editor → New query**. Replace the example cron secret below with the
same `GAHUNDA_CRON_SECRET` value from Step 2, then run:

```sql
select vault.create_secret(
  'https://qxijmrvgqronreesfnan.supabase.co',
  'gahunda_project_url'
);

select vault.create_secret(
  'PASTE_THE_SAME_GAHUNDA_CRON_SECRET_HERE',
  'gahunda_cron_secret'
);
```

Next, create another query, paste the complete contents of:

```text
supabase/web_push_cron.sql
```

Press **Run**. It creates one job named
`gahunda-web-push-every-minute`.

Verify it:

```sql
select jobid, jobname, schedule, active
from cron.job
where jobname = 'gahunda-web-push-every-minute';
```

You should see one active row with the schedule `* * * * *`.

## Step 7 — Format, analyze, and test

Run from `gahunda_app`:

```powershell
dart format lib test
flutter analyze
flutter test
```

Expected:

```text
No issues found!
73 tests passed
```

If analysis or tests fail, stop here and keep the exact error text.

## Step 8 — Build the new web release

Use the same Supabase publishable key as before and the public VAPID key from
Step 2:

```powershell
powershell -ExecutionPolicy Bypass -File .\tool\build_web.ps1 `
  -SupabaseUrl "https://qxijmrvgqronreesfnan.supabase.co" `
  -SupabasePublishableKey "PASTE_YOUR_PUBLISHABLE_KEY" `
  -WebPushVapidPublicKey "PASTE_WEB_PUSH_VAPID_PUBLIC_KEY"
```

The final line should be:

```text
Release ready: build\web
```

Only `WEB_PUSH_VAPID_PUBLIC_KEY` goes into the client build. The private JSON
must never appear in this command.

## Step 9 — Update the GitHub repository used by Vercel

Open the local folder that is connected to the GitHub repository used by your
Vercel project. Its root should currently contain the deployed Flutter web
files such as `index.html`, `main.dart.js`, `flutter.js`, and `assets`.

Copy the complete new build over that repository folder:

```powershell
Copy-Item `
  "C:\Users\Ismael\Downloads\gahunda_1_1_web_pwa\gahunda_app\build\web\*" `
  "C:\PATH\TO\YOUR\VERCEL_GITHUB_REPOSITORY" `
  -Recurse -Force
```

Then commit and push:

```powershell
cd C:\PATH\TO\YOUR\VERCEL_GITHUB_REPOSITORY
git add -A
git commit -m "Enable background Web Push"
git push
```

Vercel should deploy automatically. In Vercel, wait until the deployment shows
**Ready**, then open:

```text
https://gahunda.vercel.app
```

If your Vercel GitHub repository instead contains the full Flutter source and
does not have `index.html` at its root, do not guess or delete files. Stop and
show its top-level file list before continuing this step.

## Step 10 — Verify Supabase authentication URLs

In **Supabase → Authentication → URL Configuration**, keep:

```text
Site URL: https://gahunda.vercel.app
Redirect URL: https://gahunda.vercel.app/**
```

Save if you changed anything.

## Step 11 — Refresh the PWA on iPhone

Web Push on iPhone requires iOS 16.4 or newer and a Home Screen web app.

1. Remove the old Gahunda icon from the iPhone Home Screen. This does not
   delete the cloud backup.
2. Open `https://gahunda.vercel.app` in **Safari**.
3. Tap **Share → Add to Home Screen → Add**.
4. Launch Gahunda from the new Home Screen icon, not from a Safari tab.
5. Sign in to your existing Gahunda account.
6. Open the bell panel and tap **Enable reminders**.
7. Tap **Allow** on the iPhone notification prompt.
8. Tap **Rebuild reminders**.

If iPhone never shows the permission prompt, open **Settings → Notifications →
Gahunda** and verify notifications are allowed. Also confirm Gahunda was opened
from its Home Screen icon.

## Step 12 — Closed-app acceptance test

1. Create a uniquely named task starting at least 10 minutes from now.
2. Open the bell and tap **Rebuild reminders**.
3. Confirm the panel reports queued reminders.
4. Close Gahunda completely.
5. Wait for five minutes before the task start, allowing about one additional
   minute for the server check and push delivery.

While waiting, you may verify the subscription and queue in Supabase SQL:

```sql
select count(*) as browser_subscriptions
from public.gahunda_push_subscriptions;

select source_key, scheduled_at_utc, status, attempts, last_error
from public.gahunda_push_reminders
order by scheduled_at_utc desc
limit 20;
```

After delivery, the test reminder should show `delivered`. Supabase **Edge
Functions → send-gahunda-reminders → Logs** also shows each scheduled call.

## Important operating limits

- The iPhone must have internet access when the notification is sent.
- iOS Focus modes and notification settings can suppress or delay display.
- The installed PWA and notification permission are required on iPhone.
- Supabase Cron has minute-level timing, so delivery is not guaranteed to the
  exact second.
- Keep the Vercel domain stable. Changing the domain creates a different PWA
  origin and requires users to subscribe again.
