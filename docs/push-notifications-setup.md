# Push notifications: what exists and what you must set up

Status: **implemented; fake-provider tests exist but were not run in the
2026-10-14 release-readiness audit. No real phone delivery has been verified.**
It needs a Firebase project and a service account that this repository does not
(and must not) contain.

## What is built

| Piece | Where |
|---|---|
| Device registration, per signed-in user; a token follows whoever signed in last | `PUT /api/v1/notifications/devices`, `POST …/devices/unregister`; table `device_tokens` (migration 0003) |
| Sending | `app/integrations/fcm.py` (FCM HTTP v1, OAuth via the service account, cached access token) |
| When a push is sent | After the request that created the notification commits successfully; never for a rolled-back request; never raises into the request |
| Flows | Ten notification type strings: `task_assigned`, `task_submitted`, `task_approved`, `task_rejected`, `task_resubmission_requested`, `badge_unlocked`, `reward_requested`, `reward_approved`, `reward_rejected`, `reward_fulfilled`. Recipients are the assigned/eligible child, active family parent(s), or child as appropriate. |
| Privacy | The push text is a fixed, localised sentence (English, Hindi, Gujarati by the user's language). It **never** contains the child's name, a mission title, a review note or a reward name. The `data` payload is only `{type, notification_id}`. |
| Preferences | Honours `user_settings.push_enabled` (the app unregisters the device when it is turned off) **and**, since Phase 7, the family's per-category preferences and quiet hours (`docs/phase-7-notifications.md`). Muted or quiet-hour pushes are skipped; the in-app notification is always kept. Safety alerts (`parent_mode_locked`) are always sent. |
| Invalid tokens | FCM `UNREGISTERED` / invalid-argument → the token is deactivated |
| Sign-out | The app awaits an unregister attempt before dropping credentials, then deletes the local FCM token. Unregister is best-effort: an API error is ignored and there is no durable retry, so a stale server token can remain until re-registration or provider invalidation. Do not treat shared-device isolation on network failure as guaranteed. |
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
- The repository's `test_api_push.py` covers registration, ownership transfer,
  preference, rollback, localisation, privacy of the payload and FCM wire
  format; `test_e2e_core_journey.py` covers several event variants. These tests
  were not executed in the 2026-10-14 audit. A search of the current test
  assertions found no explicit check for `task_resubmission_requested`.
- These fake-provider tests cannot establish delivery through Google's servers.
  A real Firebase project, credentials and Android device test remain required
  if push is a launch requirement.

Delivery is asynchronous after the database commit and has no durable queue.
The FCM adapter classifies transient failures; the dispatcher retries a `retry`
answer up to three times in the same worker (Phase 7), but nothing survives a
process restart; in-app notifications remain the durable record. Provider
acceptance (`ok`) is not proof that the phone showed the notification.
Device unregistration has the same reliability limitation: if the app is offline
or the unregister call fails, the backend can retain the previous user's token.
Verify this failure mode and decide whether durable client/server cleanup is
required before enabling push on shared devices.

## Deep links and retries (Phase 7)

Tapping a push opens the matching screen (mission details, Missions, Streak,
Watch, Parent settings…) on cold start and while running; see
`docs/phase-7-notifications.md`. A provider `retry` answer is now retried up
to three times inside the worker; it is still not durable. **None of this has
been verified with real Firebase or on a phone.**

## Not included

A banner while the app is in the foreground (needs `flutter_local_notifications`).
iOS needs APNs setup and an iOS build, neither of which exists in this project.
