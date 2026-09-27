# Gahunda Web/PWA release guide

This milestone preserves Gahunda 1.0's planning, Today, School, Track, Money,
Insights, accounts, conflict-safe cloud sync, and offline-first database. It
adds browser persistence, web authentication redirects, responsive web use,
and an installable Home Screen experience for iPhone.

## Current notification boundary

The web build calculates the same reminder schedule, including the fixed
five-minute task lead time. Browser notifications are delivered while Gahunda
is open. Browsers do not provide scheduled local notifications after a web app
is closed, so closed-app iPhone alerts require a later server Web Push stage.
No existing native reminder behavior was removed.

## 1. Prepare the project on Windows

Open PowerShell in `gahunda_app` and run:

```powershell
powershell -ExecutionPolicy Bypass -File .\tool\configure_web.ps1
```

The script resolves packages, compiles the matching Drift worker, and downloads
the matching SQLite WebAssembly runtime.

## 2. Test in the browser

Use the same Supabase URL and publishable key as Task 8:

```powershell
flutter run -d chrome `
  --dart-define=SUPABASE_URL="YOUR_PROJECT_URL" `
  --dart-define=SUPABASE_PUBLISHABLE_KEY="YOUR_PUBLISHABLE_KEY"
```

Check every main area, then sign in and press **Sync now**. Existing Windows
data is not copied automatically because browser storage is a separate device.
Signing in restores the accepted cloud snapshot.

## 3. Build the tested release

```powershell
powershell -ExecutionPolicy Bypass -File .\tool\build_web.ps1 `
  -SupabaseUrl "YOUR_PROJECT_URL" `
  -SupabasePublishableKey "YOUR_PUBLISHABLE_KEY"
```

The command formats, analyzes, tests, and builds the release. The only folder
to deploy is:

```text
build\web
```

The publishable key is intended for client applications. Never use or publish
the Supabase `service_role` key.

## 4. Deploy free with Netlify Drop

1. Sign in at <https://app.netlify.com/>.
2. Open <https://app.netlify.com/drop>.
3. Drag the complete `build\web` folder into the drop area.
4. Wait for the `https://...netlify.app` address.
5. Open that address and confirm Gahunda loads.

## 5. Configure Supabase email confirmation

In Supabase, open **Authentication → URL Configuration**:

1. Set **Site URL** to the exact Netlify address.
2. Add the same address followed by `/**` under **Redirect URLs**.
3. Save.
4. Re-enable email confirmation when ready for public users.

Create a new test account and confirm that the email link returns to the web
app instead of `localhost:3000`.

## 6. Install on iPhone

1. Open the deployed address in Safari.
2. Tap **Share**.
3. Tap **Add to Home Screen**.
4. Tap **Add**.
5. Open Gahunda from the new Home Screen icon.
6. Sign in and press **Sync now**.

The installed PWA opens in its own window and keeps a browser-local database.
Use cloud sync before clearing Safari website data or changing phones.

## Acceptance checklist

- Gahunda loads from HTTPS on Safari and desktop Chrome/Edge.
- The Home Screen icon installs and opens in standalone mode.
- Sign-up confirmation returns to the deployed URL.
- Sign-in restores the cloud snapshot on a clean browser.
- Plan, Today, School, Track, Money, and Insights create and retain data.
- Offline reopening works after one successful online load.
- Reconnection syncs changes and conflict choices remain explicit.
- Test notifications work after a user grants browser permission.
- A five-minute reminder works while the PWA remains open.
