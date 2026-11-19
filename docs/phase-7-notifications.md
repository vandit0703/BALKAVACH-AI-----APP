# Phase 7 — Notification preferences, quiet hours, push deep links and delivery

Status as of 2026-11-19. Built on existing tables and APIs only. **No migration was created or run** and
no database was connected (`docs/deferred-database-integration.md`).

## Status labels

| Label | Meaning |
|---|---|
| **Implemented** | Code exists in this repository. |
| **Automated-test verified** | Covered by tests that passed in this session: backend on in-memory SQLite with a fake push provider, Flutter with a fake backend and a fake push source. **Not** PostgreSQL, **not** Firebase. |
| **Provider verified** | Sent through real Firebase Cloud Messaging. **Nothing in this phase is provider verified.** |
| **Real-device verified** | Seen on a physical phone. **Nothing in this phase is real-device verified.** |
| **Deferred** | Needs schema or infrastructure the owner has not authorised. |

## Summary

| Feature | Implemented | Automated-test verified | Provider verified | Real-device verified |
|---|---|---|---|---|
| Notification centre, bell, unread badge, categories, mark read / mark all (existing, preserved) | yes (earlier) | yes (existing tests still pass) | n/a | no |
| Family notification preferences (per category, parent only) | yes | yes | n/a | no |
| Quiet hours (family time zone, overnight, DST) | yes | yes | no | no |
| Push gating by preference and quiet hours | yes | yes (fake provider) | no | no |
| Duplicate-send guard, bounded retry, outcome logging | yes | yes (fake provider) | no | no |
| Item-level navigation from the notification centre | yes | yes | n/a | no |
| Push deep links: cold start, background, expired session, deleted item, duplicate open | yes | yes (fake push source) | no | no |
| Token register / refresh / move / unregister / invalid-token deactivation | yes (earlier; re-tested) | yes (SQLite + existing fake tests) | no | no |
| Delivery trail, durable retries, delayed delivery after quiet hours, admin delivery view | — | — | — | **deferred** |

## 1. Preferences

**Where they are stored.** The prompt assumed `user_settings` is a JSON document. **It is not**: the code reads and writes only
`language_code`, `push_enabled` and `email_notifications_enabled` (scalar columns). Adding a JSON column would be a schema change.
The family's existing JSON document `family_settings.mission_settings` already holds the family time zone, so preferences are stored
next to it under the key `notification_preferences`:

```json
{
  "version": 1,
  "categories": {"new_missions": true, "mission_reviews": true, "rewards": true, "streaks": false,
                  "video_allowance": true, "video_time_up": true, "safety": true},
  "quiet_hours": {"enabled": true, "start": "21:30", "end": "07:00"},
  "updated_by": "<parent user id>",
  "updated_at": "2026-11-19T15:00:00+00:00"
}
```

Preferences are **per family** and **parent controlled**. They govern pushes to every member (parents and children). Per-parent
overrides need their own storage (deferred). Each user's existing `push_enabled` switch still applies on top.

**API (new):** `GET` / `PATCH /api/v1/settings/families/{family_id}/notification-preferences`

* parent only (`require_parent`: a child account gets 403); the parent must be an **active member** of that family or the answer is
  404 (no existence oracle);
* `PATCH` is partial: `{"categories": {"streaks": false}}`, `{"quiet_hours": {"start": "22:00"}}`; unknown fields, unknown categories,
  non-boolean values (strict, `"off"` is rejected), `null`, times outside `HH:MM` 24-hour, and enabled quiet hours with equal
  start and end are rejected with 422 and nothing is saved;
* `safety` cannot be set to `false` (422);
* the response includes `locked_categories`, `quiet_hours_exempt_categories`, the family `timezone` and `timezone_is_default`
  (true when no zone is saved and UTC is used);
* the row lock (`FOR UPDATE`) is taken on PostgreSQL; SQLite ignores it, so concurrency is **not** tested here.

**Protection against stale writes.** The app saves the time zone by sending back its copy of `mission_settings`. The generic
`PATCH /settings/families/{id}` now ignores any `notification_preferences` value it receives and keeps the stored one, so an old
copy cannot undo a newer preference change.

**Categories** (derived from the notification types the backend actually creates):

| Category | Types | Default | Switchable | Quiet hours |
|---|---|---|---|---|
| `new_missions` | `task_assigned` | on | yes | respected |
| `mission_reviews` | `task_submitted`, `task_approved`, `task_rejected`, `task_resubmission_requested` | on | yes | respected |
| `streaks` | `streak_at_risk`, `streak_one_day_left`, `streak_continued`, `streak_milestone`, `streak_new_after_break` | on | yes | respected |
| `video_allowance` | `mission_video_time_granted`, `video_time_nearly_exhausted` | on | yes | respected |
| `video_time_up` | `video_time_exhausted` | on | yes | respected |
| `rewards` | `reward_requested`, `reward_approved`, `reward_rejected`, `reward_fulfilled`, `badge_unlocked` | on | yes | respected |
| `safety` | `parent_mode_locked` | on | **no** (always on) | **exempt** |
| (unknown type) | anything not listed | — | never muted | respected |

A test fails if a push template is added without a category.

**Not offered:** "App and product announcements" — the backend has no announcement sender, so a switch would control nothing.
Add the category when an admin broadcast exists.

## 2. Quiet hours

* Enable/disable, start and end (`HH:MM`, 24-hour), stored with the preferences.
* Evaluated in the **family time zone** (`family_settings.mission_settings.timezone`, the same value missions and streaks use; UTC if
  none is saved; the app already saves the parent phone's zone once). The device zone is never used on the server.
* The window is `[start, end)`. Start later than end runs overnight (22:00 → 07:00 covers 23:59, 00:00 and 06:59, not 07:00).
* The decision uses the family's local wall-clock time at the moment of sending, so it is correct on both sides of a
  daylight-saving change (tested with America/New_York in March and November). India has no DST.

| What happens during quiet hours | Notification types |
|---|---|
| **Push suppressed**, in-app notification kept | every type except safety |
| **Exempt** (push sent) | `parent_mode_locked` |
| **Delayed** until quiet hours end | **none** — needs a durable queue (deferred) |

Preferences and quiet hours **never stop the in-app notification from being created**. That record is durable and the app depends on
some of them (a `mission_video_time_granted` notification refreshes the allowance).

## 3. Push delivery (`app/services/push_service.py`)

Three different facts, never to be confused:

| Fact | Observable? | Where |
|---|---|---|
| **Created** | yes | `notifications` row (in-app centre) |
| **Accepted by the provider** | yes, per token | FCM answered `ok`; counted as `provider_ok` in the log |
| **Delivered to the device** | **no** | the server cannot observe it; FCM acceptance is not delivery |

Changes:

* push skipped when `push_enabled` is false (existing), the category is muted, or quiet hours apply; each skip is counted;
* one push per (recipient, notification id) per run and one send per token (duplicate guard using existing ids);
* a `retry` answer is retried up to 3 attempts in the same worker (0.5 s, 2 s backoff); still failing → `retry_exhausted`;
* `invalid_token` deactivates the token (existing); the token comes back if the app registers it again;
* a provider exception is logged and counted as `error`, never retried, never raised into the request;
* if the preferences cannot be read the push is sent (fail open) with a warning — the in-app notification exists either way;
* one summary log line per run, e.g. `Push run finished: {'provider_ok': 2, 'suppressed_quiet_hours': 1}`. Logs carry the
  notification type and id only: no names, titles, tokens or child data.

Limits (unchanged): delivery runs in a 2-thread in-process pool after the request; there is **no durable queue**, so a process restart
loses pending pushes, and retries do not survive the worker. That needs `notification_deliveries` (deferred).

## 4. Deep links

**Payload is unchanged:** `{type, notification_id}` — still no names or titles.

**Resolver** (`locationFor` in `lib/features/notifications/domain/notification_category.dart`):

| Notification | Child | Parent |
|---|---|---|
| `task_approved` / `task_rejected` / `task_resubmission_requested` | that mission's details (`/child/missions/{id}`) if the id is a valid UUID, else Missions | Approvals |
| `task_assigned` | Missions | Approvals |
| `task_submitted` | Missions | Approvals |
| streak types | Streak screen for this child | Parent home |
| video types | Watch (home) | Parent home |
| rewards / badge | Rewards / Profile | Parent rewards |
| `parent_mode_locked` | Child home | **Parent settings** |
| unknown or malformed type | Child home | Parent home |

The router's role guard still applies, so a child can never reach `/parent/...` even with forged data.

**Push opens** (`NotificationOpenCoordinator`, `lib/features/notifications/presentation/notification_open_coordinator.dart`;
source `lib/core/push/notification_open_source.dart`):

* **Cold start** (`getInitialMessage`): waits until the stored session is restored, then navigates.
* **Running / background** (`onMessageOpenedApp`): navigates at once.
* The app looks the notification up with the new owner-scoped `GET /api/v1/notifications/{id}` (404 for anyone else's or a deleted
  one) and navigates to the item; marks it read.
* **Deleted or another account's notification** → the user's own home.
* **Offline / server error** → the category screen from the payload type.
* **Signed out or session expired** → the push waits; after sign-in it is looked up as the new user (so another account's push opens
  nothing private). A push waiting longer than 30 minutes is dropped. A 401 during lookup re-queues it.
* **Opened twice** (launch message and opened event for the same tap) → navigates once.
* Malformed payloads (non-UUID id, odd type) are ignored.

The notification centre now uses the same resolver, so tapping a mission review in the list opens that mission.

**Not built:** a foreground banner while the app is open (needs `flutter_local_notifications` and Android channels; today a
foreground push refreshes the visible data, as before). iOS (no APNs setup or iOS build exists).

## 5. Flutter UI

`NotificationSettingsScreen` (`/parent/settings/notifications`), opened from Parent settings → Preferences →
"Notification preferences". Parent-only by route guard and by an in-screen check. Grouped cards (Missions, Streaks, Video time,
Rewards and badges, Safety), parent-friendly descriptions, switches that change immediately and roll back with a message if the
server refuses, saves sent one at a time, locked "always on" safety switch, quiet-hours switch with start/end time pickers, overnight
explanation, family time zone shown with a notice when UTC is only a default, notices when this phone cannot show pushes
(turned off, permission denied, no Firebase in this build), loading and retryable error states. English, Hindi and Gujarati.
**Hindi and Gujarati strings need native-speaker review.**

## 6. Tests run in this session

| Suite | Result |
|---|---|
| Backend full (`pytest -q -rs`) | see the roadmap status block for the exact figures |
| Backend new: `tests/test_notification_preferences.py` (SQLite + fake provider) | 47 passed |
| Flutter full (`flutter test`) | see the roadmap status block |
| Flutter new: `test/features/notification_preferences_test.dart` (fake backend + fake push source) | 27 passed |
| Flutter changed: `test/features/notification_center_test.dart` (router gains the mission route; new item-navigation test) | 16 passed |

Database-dependent tests (`tests/test_api_push.py` and others) remain **skipped** without `TEST_DATABASE_URL`.

## 7. Remaining real-device checks (Android 13+, Firebase configured)

1. Grant / deny notification permission: the settings notice matches; denied phones get no push.
2. Approve a mission from the parent phone; tap the push on the child phone: (a) app killed → opens the mission details;
   (b) app in background → same; (c) tap the same push again → no second navigation.
3. Turn `mission_reviews` off; approve again: no push, item appears in the centre.
4. Quiet hours spanning the current time: no push for a mission review; 5 wrong parent sign-ins still push `parent_mode_locked`.
5. Sign out, tap an old push, sign in as a different account: lands on home, nothing private shown.
6. Delete or archive a mission, tap its old approval push: mission "not found" view, no crash.
7. Hindi and Gujarati: push text and settings screen render correctly at 1.3× and 2.0× font scale.
8. Backend logs show `Push run finished` lines with `provider_ok` counts and no names or tokens.
