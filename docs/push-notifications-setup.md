# Push notifications: what exists and what you must set up

Status: **fully implemented and tested with fakes; not yet delivering to a real
phone** because it needs a Firebase project and a service account that this
repository does not (and must not) contain.

## What is built

| Piece | Where |
|---|---|
| Device registration, per signed-in user; a token follows whoever signed in last | `PUT /api/v1/notifications/devices`, `POST …/devices/unregister`; table `device_tokens` (migration 0003) |
| Sending | `app/integrations/fcm.py` (FCM HTTP v1, OAuth via the service account, cached access token) |
| When a push is sent | After the request that created the notification commits successfully; never for a rolled-back request; never raises into the request |
| Flows | mission assigned → child; mission submitted → parents; approved / rejected / resubmission → child; badge → child; reward requested → parents; reward approved / rejected / fulfilled → child |
| Privacy | The push text is a fixed, localised sentence (English, Hindi, Gujarati by the user's language). It **never** contains the child's name, a mission title, a review note or a reward name. The `data` payload is only `{type, notification_id}`. |
| Preferences | Honours `user_settings.push_enabled`; the app unregisters the device when it is turned off |
| Invalid tokens | FCM `UNREGISTERED` / invalid-argument → the token is deactivated |
| Sign-out | The app unregisters this device **before** dropping its credentials, so a shared phone never delivers one person's notifications to another |
| App | `lib/core/push/`, `lib/features/notifications/`; a push received while the app is open refreshes the visible data |

## What you need to provide

1. **A Firebase project** (console.firebase.google.com) with an Android app whose
   package name is `com.balkavach.balkavach_app`.
2. Download **`google-services.json`** and place it at
   `balkavach-frontend/android/app/google-services.json`. It is a public client
   configuration (not a secret). The Gradle build applies the Google services
   plugin only when this file exists, so the app builds either way.
3. A **service account** with the *Firebase Cloud Messaging API Admin* role
   (Project settings → Service accounts → Generate new private key). This one **is
   secret**. Give it to the backend only:

   ```
   NOTIFICATION_PROVIDER=app.integrations.fcm:create_provider
   FCM_SERVICE_ACCOUNT_JSON={"type":"service_account",…}      # or
   FCM_SERVICE_ACCOUNT_FILE=/etc/secrets/fcm.json
   ```
4. Apply migration `0003_device_tokens` (see `backend-operations.md`).
5. Install a build that includes `google-services.json` on a real Android 13+
   phone, sign in, accept the notification permission, then approve a mission
   from another device.

## How to confirm it works

- The app shows no error when push is unavailable (it simply stays in-app).
- On the server, a successful registration stores a row in `device_tokens`; a
  provider failure is logged as a warning and the request still succeeds.
- `test_api_push.py` covers registration, ownership transfer, preference,
  rollback, localisation, privacy of the payload and the FCM wire format. What it
  cannot cover is Google's real servers; that is the one remaining check.

## Not included

Tapping a notification just opens the app (no deep link). iOS needs APNs setup
and an iOS build, neither of which exists in this project.
