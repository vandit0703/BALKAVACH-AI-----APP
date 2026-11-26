# BALKAVACH — Firebase CLI Login & FCM Readiness Audit

Date: 2026-11-26 · Branch: `main` @ `e4ca3d3` · Read-only audit: no source files changed, nothing installed, enabled, deployed or committed.

## Update — 2026-11-26 re-verification (Phases 2 and 5)

Re-run after the owner installed the tools and signed in. Every row was checked with a read-only command in this session:

| Item | Verified result | Command |
|---|---|---|
| Firebase CLI | ✅ 15.37.0 at `%APPDATA%\npm\firebase.cmd` (not yet on this editor session's PATH; restart VS Code) | `firebase --version` |
| Firebase account | ✅ BALKAVACH owner account signed in | `firebase login:list` |
| Firebase project | ✅ **`balkavach-vk`**, display name BALKAVACH, project number 944002524542; the only project visible | `firebase projects:list` |
| Android app | ✅ "BalKavach" `1:944002524542:android:c1873f042866f4b0e03f2f`, identical to `mobilesdk_app_id` in `google-services.json`; project number matches | `firebase apps:list ANDROID` |
| Google Cloud CLI | ✅ SDK 594.0.1 at `%USERPROFILE%\google-cloud-sdk\bin` (not on this session's PATH); same account active; default project `balkavach-vk` | `gcloud auth list`, `gcloud config get-value project` |
| FCM API | ✅ `fcm.googleapis.com` and `firebase.googleapis.com` enabled | `gcloud services list --enabled` |
| Dedicated service account | ✅ `balkavach-fcm-sender@…`, enabled; **only** project role is `roles/firebasecloudmessaging.admin` | `gcloud projects get-iam-policy` (filtered) |
| Key | ✅ exactly one user-managed key (created 2026-11-26 11:58 UTC, no expiry). No key material found in the repository; the only `private_key` hit is a test that generates a throwaway key (`tests/test_api_push.py:202`) | `gcloud iam service-accounts keys list` (metadata only), repo search |

Blocking items 1-5 of section 8 are now **resolved**. Still open:

- Backend FCM env vars are not set on the VPS. Hosting was not inspected or changed.
- The two notification jobs are not scheduled.
- `streak-check` can still push at night.
- No real-device push yet.

The key never expires, so plan a rotation, and delete the old key after each rotation. The default `firebase-adminsdk-fbsvc@…` account also exists. It is unused by this backend, so don't hand out its keys.

**Status after re-verification: NOT READY. The project side is ready; the backend configuration and the device test are pending.**

---

**Original conclusion (before re-verification): NOT READY.** The app and backend code for FCM are complete. What blocks it is tooling and access: the Firebase CLI and Google Cloud CLI are not installed, and the Google account that is signed in to the Firebase tools cannot see project `balkavach-vk`. FCM is **not** shown to work. That can only be claimed after a real Android device receives a test push.

---

## 1. Firebase CLI installation and authentication

| Tool | Status |
|---|---|
| `firebase` (Firebase CLI) | **Not installed** (`firebase` not on PATH) |
| `gcloud` (Google Cloud CLI) | **Not installed** (`gcloud` not on PATH) |
| `flutter` | 3.44.6 (Dart 3.12.2) |
| `node` / `npm` | v24.19.0 / 11.4.2, so `npm install -g firebase-tools` will work |

`firebase login:list` could not run because the CLI is missing. The Firebase MCP server in this editor, which shares firebase-tools' credential store, reports:

- Authenticated user: **a personal Google account**. Its address is not repeated here.
- Projects visible to that account: **only `one-stop-72ee5` ("one-stop")**.
- `balkavach-vk` is **not visible** to the signed-in account.

So once the CLI is installed it will probably show the same account. You need to sign in with the Google account that owns or has access to the BALKAVACH Firebase project. See section 9.

## 2. Firebase project ID

| Source | Value |
|---|---|
| `google-services.json` → `project_info.project_id` | `balkavach-vk` |
| Firebase API (`projects:list`) | **Not verified.** The signed-in account cannot see the project |

`balkavach-vk` is what the client config says. Treat it as **unverified** until `firebase projects:list` run as the right account shows it.

## 3. Android Firebase configuration

| Check | Result | Reference |
|---|---|---|
| `google-services.json` exists | ✅ | `balkavach-frontend/android/app/google-services.json` |
| Package name is exactly `com.balkavach.balkavach_app` | ✅ one client, matching | same file |
| `applicationId` / `namespace` match | ✅ | `android/app/build.gradle.kts:26`, `:39` |
| Project ID matches selected project | ⚠️ File says `balkavach-vk`; not yet confirmed via the Firebase API | — |
| Google Services plugin declared | ✅ `com.google.gms.google-services` 4.4.2, `apply false` | `android/settings.gradle.kts:23` |
| Google Services plugin applied | ✅ conditionally: applied only when `google-services.json` exists | `android/app/build.gradle.kts:104-106` |
| `firebase_core` / `firebase_messaging` / `flutter_local_notifications` | ✅ `^4.15.0` / `^16.7.0` / `^21.0.0` | `pubspec.yaml:46`, `:47`, `:53` |
| Core library desugaring (needed by local notifications) | ✅ | `android/app/build.gradle.kts:34`, `:98` |
| `POST_NOTIFICATIONS` permission | ✅ | `android/app/src/main/AndroidManifest.xml:3` |
| Default FCM icon / colour / channel meta-data | ✅ `ic_stat_balkavach`, `@color/notification_accent`, `balkavach_missions` (all three resources exist) | `AndroidManifest.xml:43-51` |

Note: `google-services.json` is **untracked and not git-ignored**. It is a public client config and not a secret, but it does contain the Android API key. Decide on purpose whether to commit it. A broad `git add .` will sweep it in.

## 4. Flutter FCM implementation

| Item | Status | Where |
|---|---|---|
| Firebase init before `runApp()` | ✅ `createPushTokenSource()` → `Firebase.initializeApp()`. Falls back to a no-op source if config is missing | `lib/bootstrap.dart:14`, `lib/core/push/push_token_source.dart:103-117` |
| Android 13+ notification permission | ✅ `FirebaseMessaging.requestPermission()` (shows the POST_NOTIFICATIONS prompt on 13+) | `push_token_source.dart:67-71`, called from `push_registration.dart:86` |
| FCM token retrieval | ✅ `getToken()` | `push_token_source.dart:74`, `push_registration.dart:90` |
| Token registration with authenticated backend user | ✅ `PUT /api/v1/notifications/devices` with `{token, platform}` through the authenticated Dio client | `lib/features/notifications/data/device_repository.dart:16-22`, `push_registration.dart:95` |
| Token refresh | ✅ `onTokenRefresh` → re-`PUT` | `push_registration.dart:99-101`, `:110-117` |
| Foreground notifications | ✅ `FirebaseMessaging.onMessage` → banner via `flutter_local_notifications` + refresh of visible data | `push_token_source.dart:80-87`, `lib/core/push/local_notifications.dart:115-146`, `push_registration.dart:102`, `:137-152` |
| Background message handler (`onBackgroundMessage`) | ⚪ **Not implemented**. Not needed for the current server payload: the server sends *notification* messages, which Android shows itself when the app is backgrounded or closed. Only needed if data-only pushes are added later | — |
| Notification tap handling | ✅ `getInitialMessage()` (cold start), `onMessageOpenedApp` (background), local-banner taps; resolved via the server record, not the payload | `lib/core/push/notification_open_source.dart:63-77`, `lib/features/notifications/presentation/notification_open_coordinator.dart` |
| Android notification channels | ✅ 5 channels created at start-up; ids match the server map | `local_notifications.dart:30-53`, `:97-106`; server `app/integrations/fcm.py:34-50` |
| Logout token handling | ✅ Sign-out hook runs **before** the access token is cleared: server unregister, then `deleteToken()` and clearing the notification shade | `lib/features/authentication/presentation/session_controller.dart:196-198`, `push_registration.dart:70`, `:119-133`, `push_token_source.dart:90-97` |
| Account switch | ✅ Session change rebuilds the notifier, which re-`PUT`s the same token. The server reassigns the token row to the new user | `push_registration.dart:53-72`; server `device_service.py:17-40` |
| Push-enabled preference off | ✅ Unregisters | `push_registration.dart:63-69` |
| Duplicate token/device prevention | ✅ Server upsert by token (`SELECT … FOR UPDATE`) + DB `UNIQUE(token)` | `app/services/device_service.py:21`, `alembic/versions/0003_device_tokens.py:37` |

Minor gaps (none block a first test):

- `push_registration.dart:99-102`: the refresh and message listeners are attached only after a successful first registration. If that fails (offline), a token rotation isn't picked up until the next launch.
- `push_registration.dart:110-117`: `_replace` catches only `ApiException`. Any other error ends up unhandled in an `unawaited` future.
- The docs already note that unregister is best-effort. If sign-out happens offline, the server can keep the old user's token until another sign-in on that phone or until FCM invalidates it (`docs/push-notifications-setup.md:19`, `:63-66`).

Backend token endpoints exist (not invented; verified in code):

- `PUT /api/v1/notifications/devices` → `app/api/v1/notifications.py:48-56`
- `POST /api/v1/notifications/devices/unregister` → `app/api/v1/notifications.py:59-66` (deletes only the caller's own token)

## 5. Backend FCM provider

| Item | Status | Where |
|---|---|---|
| Settings fields | ✅ `notification_provider`, `fcm_service_account_json` (`repr=False`), `fcm_service_account_file` | `app/core/config.py:83-85` |
| `.env.example` | ✅ `NOTIFICATION_PROVIDER=` (FCM line commented), `FCM_SERVICE_ACCOUNT_JSON=`, `FCM_SERVICE_ACCOUNT_FILE=` | `balkavach-backend/.env.example:57-60` |
| Provider loader | ✅ Imports `module:factory`, caches it, and fails as a logged 503 without breaking requests | `app/integrations/__init__.py:25-41` |
| `app.integrations.fcm:create_provider` | ✅ FCM **HTTP v1**, OAuth2 JWT-bearer (RS256) with scope `firebase.messaging`, access token cached about 1 h | `app/integrations/fcm.py:59-102`, `:152-158` |
| Credential format | Standard Google service-account JSON. Required keys: `project_id`, `client_email`, `private_key` (`token_uri` optional). JSON goes in the env var, or a file path goes in `FCM_SERVICE_ACCOUNT_FILE`; JSON wins if both are set | `fcm.py:28`, `:61-66`, `:153-158` |
| Send target | `projects/{project_id from the service account}/messages:send`, so **the service account must belong to the same project as `google-services.json`** (`balkavach-vk`) | `fcm.py:125` |
| Error mapping | `ok` / `invalid_token` (deactivates the row) / `retry` (3 attempts) / `error` | `fcm.py:132-149`, `app/services/push_service.py:267-279`, `:344-345` |
| Delivery pipeline | After commit, in a background thread pool. Honours `push_enabled`, family categories and quiet hours. Payload is only `{type, notification_id}` | `push_service.py:200-233`, `:301-350` |
| Python deps | ✅ `PyJWT`, `cryptography` (needed for RS256), `httpx` in `requirements.txt`; local venv has pyjwt 2.15.1, cryptography 50.0.2, httpx 0.28.1 | `balkavach-backend/requirements.txt` |
| Local configuration | Repository-root `.env` has **no** `NOTIFICATION_PROVIDER` / `FCM_*` entries; there is no `balkavach-backend/.env`. Push is therefore **off locally** (provider `None`, so pushes are silently skipped) | — |
| Production code | The push code (`fcm.py`, `push_service.py`, `device_service.py`, `notifications.py`) is identical between `a1d19f5` (last known production) and `HEAD` | `git diff a1d19f5 HEAD` |

Cosmetic: `streak_continued`, `streak_milestone` and `streak_new_after_break` are not in `_CHANNEL_BY_TYPE`, so they go to the Missions channel instead of Reminders (`fcm.py:34-50`).

## 6. Service-account requirements

Use a **dedicated** service account in project `balkavach-vk` with **only** the role *Firebase Cloud Messaging API Admin* (`roles/firebasecloudmessaging.admin`). Do not use the default `firebase-adminsdk-…` account, which has much broader rights.

Steps for you to run. Nothing here was created:

```powershell
# after gcloud is installed and you are logged in as a project owner
gcloud iam service-accounts create balkavach-fcm-sender --project balkavach-vk --display-name "BALKAVACH FCM sender"
gcloud projects add-iam-policy-binding balkavach-vk `
  --member "serviceAccount:balkavach-fcm-sender@balkavach-vk.iam.gserviceaccount.com" `
  --role "roles/firebasecloudmessaging.admin"
```

Then create a JSON key yourself. Use Cloud Console → IAM → Service accounts → `balkavach-fcm-sender` → Keys → Add key, or `gcloud iam service-accounts keys create <path outside the repo> --iam-account …`. If your organisation enforces `iam.disableServiceAccountKeyCreation`, key creation will be refused. In that case the hosting provider would need workload identity, which the current provider does not support.

Handling rules:

- The backend only: `FCM_SERVICE_ACCOUNT_JSON` (whole JSON as one line) or `FCM_SERVICE_ACCOUNT_FILE` (a secret-file path, for example `/etc/secrets/fcm.json`).
- Never in Flutter, never in the repo, never in `.env.example`. The `.gitignore` covers `.env` / `.env.*` but **not** `*.json`, so keep the key file outside the repository.
- Set the same variables on the **web service and on the `streak-check` / `daily-missions-notify` cron jobs**.

## 7. Scheduler

Both jobs exist in `balkavach-backend/app/cli.py` (also at production commit `a1d19f5`). **Neither is scheduled anywhere in the repo.** `deploy/render-cron-jobs.example.yaml` lists only the three YouTube jobs. Line 7 of that file says "no notification variables are needed", which is true only for those YouTube jobs.

| | `daily-missions-notify` | `streak-check` |
|---|---|---|
| Exists | ✅ `cli.py:453-492`, parser `:754-758`, dispatch `:809-815` | ✅ `cli.py:367-450`, parser `:753`, dispatch `:846-847` |
| Expected schedule | Hourly (`docs/push-notifications-setup.md:89`); only families whose local hour is in `[--from-hour 8, --to-hour 19)` | Hourly (`docs/scheduler-deployment.md:14`) |
| Uses FCM provider | ✅ commit → `push_service.deliver_ready` (`cli.py:486-487`) | ✅ (`cli.py:437-440`) |
| Required env | `DATABASE_URL`, `NOTIFICATION_PROVIDER`, `FCM_SERVICE_ACCOUNT_JSON` or `_FILE` (+ whatever `Settings` needs at import, same as the web service) | Same |
| Duplicate prevention | At most one `daily_missions_ready` per child per **family-local day** (`notification_service.py:179-201`) | At most one notification per child per event type per **rolling 20 h** (`notification_service.py:120-141`) |
| Safe to re-run | ✅ Sequential re-runs are idempotent. Overlapping runs are check-then-insert with no lock and could, in a narrow race, create a duplicate | ✅ Same caveat |
| Night-time behaviour | Daytime window built in | ⚠️ **No daytime window.** Family quiet hours default to **disabled** (`notification_preferences_service.py:88`), so an hourly run can push a "streak at risk" to a child's phone at night |

Also note:

- The CLI's "N notification(s) sent" counts notifications **created**, not FCM-accepted. Accepted/failed counts appear only in the `Push run finished` log line (`push_service.py:349`).
- Pushes are sent from a thread pool after the command body returns. Python waits for those threads before exiting, so the job's runtime includes FCM calls.

## 8. Exact missing items

Blocking:

1. Firebase CLI not installed.
2. Google Cloud CLI not installed.
3. The signed-in Google account has no access to `balkavach-vk`. Project ID unverified.
4. FCM API (`fcm.googleapis.com`) enablement unverified (needs 2 + 3).
5. No FCM service account or key exists for the backend, as far as this audit can see.
6. `NOTIFICATION_PROVIDER` / `FCM_SERVICE_ACCOUNT_*` not set locally. Hosting not inspected, by rule.
7. No real-device test has been done.

Not blocking for a first test, but needed before launch:

8. `streak-check` and `daily-missions-notify` are not scheduled anywhere, and the example Render file doesn't include them.
9. `streak-check` can push at night (no daytime window, quiet hours off by default).
10. Minor Flutter robustness gaps in section 4 (refresh listener only after first success; `_replace` catches only `ApiException`).
11. Decide whether `google-services.json` is committed or git-ignored.

## 9. Safe next commands for you to run

```powershell
# 1. Install the Firebase CLI (asks npm for a global install)
npm install -g firebase-tools
firebase --version

# 2. Sign in with the account that owns BALKAVACH. A browser window opens, so complete it yourself.
firebase login:list
firebase login:add            # add the BALKAVACH-owning account alongside the current one
firebase login:use <that-account-email>
#   (or: firebase logout ; firebase login)

# 3. Verify the project and the Android app
firebase projects:list                          # expect balkavach-vk
firebase apps:list ANDROID --project balkavach-vk   # expect com.balkavach.balkavach_app

# 4. Install the Google Cloud CLI (asks winget; or use Google's installer)
winget install --id Google.CloudSDK
gcloud auth login
gcloud auth list
gcloud config set project balkavach-vk
gcloud services list --enabled --filter="name:fcm.googleapis.com"
#   if it is missing, tell me before running:
#   gcloud services enable fcm.googleapis.com

# 5. Debug build (safe; see below)
cd balkavach-frontend
flutter pub get
flutter build apk --debug
```

**Is the debug build safe?** Yes. A debug build ignores `key.properties` (the release guard at `build.gradle.kts:70-85` only triggers on release tasks), applies the Google Services plugin because the file is present, and the package name matches. `flutter pub get` may update `pubspec.lock` if it is out of date. I did not run the build in this audit, so AGP 9.0.1 with google-services 4.4.2 is unverified in this tree. Do not run release builds.

**First real push test (after steps 1-5):**

1. Install the debug APK on an Android 13+ phone, sign in, and allow notifications. The Notification settings screen should show the push status as registered.
2. Quick FCM-only check: Firebase Console → Messaging → new notification campaign targeting app `com.balkavach.balkavach_app`. This reaches every install of the app, which is fine pre-launch.
3. End-to-end check: point a **local** backend (local PostgreSQL, not production) at the service account via `FCM_SERVICE_ACCOUNT_FILE`, use a debug build pointed at it, and approve a mission from another device. Expect a `provider_ok` count in the `Push run finished` log, then the notification on the phone.

## 10. Conclusion

**NOT READY.** The code is ready on both sides: init, permission, token registration and refresh, foreground/background/tap handling, channels, logout and account switch, token de-duplication, the HTTP v1 provider and idempotent jobs. The project is not:

- Firebase CLI and gcloud are missing.
- The signed-in account cannot see `balkavach-vk`.
- The FCM API, the service account and the backend env vars are unconfigured or unverified.
- No device has received a push.

Re-run this audit's Phases 2 and 5 after section 9 steps 1-4. FCM can be called working only after a real Android device shows a test notification.
