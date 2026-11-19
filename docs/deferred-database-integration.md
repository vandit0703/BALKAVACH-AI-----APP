# Deferred database integration

**Product-owner instruction (2026-11-19): all schema changes are held until a final integration phase.**
Until that phase is explicitly authorised, nobody creates or edits Alembic migrations, alters a database,
runs migrations, or connects to production. Everything below is *documented, not implemented*. Frontend
and backend work in the meantime reuses existing tables, columns and APIs only.

Last updated after the "no-schema" milestone (Phases 4, 6, 7, 8, 9 groundwork). Items are tagged with the
roadmap phase that needs them.

## 1. What shipped without any schema change (for contrast)

| Area | Uses only |
|---|---|
| Trusted channel **detail** and **history** (`GET /admin/videos/youtube/channels/{id}` and `/history`) | `youtube_trusted_channels`, `youtube_content_reviews`, `videos`, `audit_logs` (existing) |
| Channel status shown as *approved / revoked* | derived from `is_active` |
| Up-next recommendations (`GET /videos/{id}/next`) | the existing eligible-feed query, `youtube_content_reviews.channel_id`, watch history |
| Notification centre (categories, mark read, navigation) | `GET /notifications`, `POST /notifications/{id}/read`; categories derived from `notification_type` on the device |
| Notification preferences, quiet hours, push gating, push deep links (Phase 7) | `family_settings.mission_settings` (JSON key `notification_preferences`), `family_settings` time zone, `device_tokens`, `notifications`; new owner-scoped `GET /notifications/{id}` |
| Invite / share card | no server data at all; card and message are generated on the device |
| Panda dialogue | bundled in the app's localization files |
| Animated Panda companion on Watch home, Missions, mission detail and the waiting screen; lines personalised with the child's first name, the mission title and the star reward | the existing session, mission and allowance data on the device; line choice and anti-repeat memory live in the app session; nothing is stored or sent |
| Parent allowance summary | `video_access_entitlements`, `child_video_daily_usage`, `tasks` |
| Talk to Panda (`POST /companion/chat`, voice in/out, see `docs/panda-talking-companion.md`) | read-only: `users.preferred_language`, `child_profiles.display_name`, `daily_mission_assignments`, the allowance calculation, `child_streaks`. No conversation, transcript or audio is stored; duplicate-turn cache and rate limit are in process memory |

## 2. Required new tables

| Table | Phase | Purpose | Key columns |
|---|---|---|---|
| `referral_codes` | 9 | one short code per parent | `id`, `parent_user_id` (unique), `code` (unique), `created_at` |
| `referral_attributions` | 9 | who installed from which code, once | `id`, `code_id`, `installer_user_id` (unique), `first_seen_at`, `registered_at`, `status`, `device_fingerprint_hash` |
| `notification_deliveries` | 7 | delivery trail and retries | `id`, `notification_id`, `device_token_id`, `status` (`queued/sent/failed/invalid`), `attempt`, `error_code`, `sent_at` |
| `notification_templates` (optional) | 7 | localisable templates managed in admin | `type`, `locale`, `title`, `body`, `updated_at` |
| `companion_dialogue_packs` | 6 | server-driven, versioned Panda dialogue | `id`, `version`, `locale`, `payload` (JSONB), `published_at` |
| `companion_safety_events` (optional, needs a parent-consent decision) | 6 | lets a parent see that Panda redirected a distress / unsafe / personal-information message. Category and time only, **never the child's words** | `id`, `child_id`, `category`, `created_at`, `notified_parent_at` |
| `companion_preferences` (optional) | 6 | parent switch to turn Panda's microphone or voice off per child. **Not required for release:** a parent opt-in/opt-out can use the existing `consent_records` (`consent_type = "panda_voice"`) with no schema change; this table is only for richer per-setting history. Today the device permission is the only switch | `child_id` (PK), `voice_input_enabled`, `voice_output_enabled`, `updated_by`, `updated_at` |
| `youtube_channel_events` (optional) | 4 | richer channel history than the audit log | `id`, `channel_id`, `actor_id`, `action`, `reason`, `created_at` |
| `video_play_tickets` | 3 | **Adopted (D6, 2026-11-19); creation still deferred.** One active playback ticket per child; heartbeat accounting becomes the single deduction path. It fixes two gaps: two devices playing at once are charged about once, and reports more than 30 s apart get the excess free. Design: `docs/video-play-tickets.md` | see the schema below |
| `video_topics` / tags (optional) | 8 | topic-based recommendations | `video_id`, `topic` |

### `video_play_tickets` schema (D6; not created)

| Column | Type | Notes |
|---|---|---|
| `id` | uuid PK | |
| `child_id` | uuid FK → `child_profiles.id`, not null | |
| `video_id` | uuid FK → `videos.id`, not null | |
| `device_session_id` | varchar(64), not null | supplied by the app |
| `token_hash` | char(64), not null, unique | HMAC-SHA256 of the opaque token; the token itself is never stored |
| `state` | varchar(16), not null | `issued`, `playing`, `paused`, `superseded`, `expired`, `revoked`, `exhausted`, `ended` (check constraint) |
| `issued_at`, `expires_at` | timestamptz, not null | `expires_at` = min(issue + 60 s, family-local midnight) until the first heartbeat |
| `started_at`, `last_heartbeat_at`, `ended_at` | timestamptz, null | server clock only |
| `last_sequence` | integer, not null, default -1 | duplicate/replay detection |
| `charged_seconds` | integer, not null, default 0 | per-ticket total, for audit and support |
| `free_charged_seconds` | integer, not null, default 0 | the part taken from the free daily allowance |
| `local_date` | date, not null | family-local day the ticket belongs to |
| `superseded_by` | uuid FK → `video_play_tickets.id`, null | |
| `end_reason` | varchar(32), null | e.g. `missed_heartbeats`, `midnight`, `video_unpublished`, `parent_revoked` |
| `created_at` | timestamptz, not null | |

Indexes: a **partial unique** `(child_id) WHERE state IN ('issued','playing','paused')`, which is the database guarantee of one active ticket per child; `(child_id, local_date)`; `(state, last_heartbeat_at)` for a sweeper that expires stale tickets.

Additional requirements found while implementing the service (2026-11-19):
- `MODEL_TABLES` already maps `VideoPlayTicket` → `video_play_tickets`. Until the table exists, `has_model("VideoPlayTicket")` is false and tickets stay inactive whatever the setting says.
- The migration must create the **partial unique index**. The service relies on it (`ActiveTicketConflict` retry) to guarantee one active ticket per child across instances.
- A small **sweeper job** (scheduler, D9) should mark `issued/playing/paused` tickets with `last_heartbeat_at` (or `issued_at`) older than 45 s as `expired`, so stale rows don't block analytics. Correctness doesn't depend on it, since a heartbeat on a stale ticket lapses it.
- **Rate limits** for ticket starts and heartbeats are per process (`FixedWindowLimiter`). Multiple API instances need the Redis limiter.
- Rollout order: migrate → PostgreSQL concurrency suite (two devices starting at once, concurrent heartbeats on one ticket, supersede during a heartbeat) → turn the setting on → ship the app build with `VIDEO_PLAY_TICKETS=true` and the players wired to `PlayTicketSession`. Older app builds get 409 `play_ticket_required` and can no longer play videos once tickets are on, which is a deliberate trade-off for enforcement.

No existing table changes. `child_video_daily_usage.free_watched_seconds` and `video_access_entitlements.consumed_seconds` stay the allowance ledgers; the ticket heartbeat writes them instead of `record_progress` once the flag is on. `video_watch_sessions` is **not** reused: its live schema could not be checked (reflected, not in the repo), its rows require an entitlement that free viewing does not have, and `learning_gate_service` sums it.

## 3. Required new columns

| Table | Column(s) | Phase | Why |
|---|---|---|---|
| `youtube_trusted_channels` | `status` (`pending/approved/suspended/revoked`), `status_reason`, `approved_by`, `approved_at`, `suspended_at` | 4 | real suspend vs revoke; today only `is_active` exists |
| `youtube_trusted_channels` | `last_checked_at`, `last_successful_sync_at`, `last_error` | 4 | sync visibility and the "recheck older than 48 h" alert |
| `videos` | `orientation`, `aspect_ratio` | 8 | classify Shorts as short **and** portrait; today duration only |
| `child_profiles` | `companion_key` | 6 | remember the child's chosen companion on the server (Panda is the only one now, so the app needs nothing yet) |

Panda items that stay deferred because they need persistence: a parent switch to turn Panda off per child, and anti-repeat memory that survives an app restart. Both are doable on-device with local storage; they are listed here only if the owner wants them stored server-side.
| `auth_sessions` | `device_id`, `mode` | 1 | device-bound child/parent sessions (if the roadmap's design is revived) |
| `users` | `deleted_at`, `email_verified_at` | 1 | account deletion and optional verification |
| mission variations / templates | `skill_area`, `developmental_purpose`, `evidence_level`, `parent_tip`, `estimated_minutes` | 5 | catalogue metadata (not started) |

**Correction (Phase 7, 2026-11-19):** `user_settings` is **not** a JSON document; the code uses only the scalar columns
`language_code`, `push_enabled` and `email_notifications_enabled`. Phase 7 therefore stores **family-level** notification
preferences and quiet hours under the key `notification_preferences` inside the existing JSON column
`family_settings.mission_settings` (next to the family time zone). The generic family-settings PATCH cannot overwrite that key.
See `docs/phase-7-notifications.md`.

### Newly identified Phase 7 requirements (deferred)

| Need | Why it needs schema / infrastructure | Proposed shape |
|---|---|---|
| Per-parent (per-user) notification preferences | today one family-level document governs everyone; `user_settings` has no JSON column | `user_settings.notification_preferences JSONB NULL` (user overrides on top of the family document) |
| Dedicated home for family preferences | `mission_settings` is an interim location | `family_settings.notification_settings JSONB NOT NULL DEFAULT '{}'`, backfilled from `mission_settings.notification_preferences` |
| Deliver after quiet hours end (instead of suppressing) | needs a durable queue and a scheduler run | `notification_deliveries` with `status = 'held'` and `not_before`; dispatcher job |
| Durable retries and delivery history, admin failure view | retries today live only inside one worker | `notification_deliveries` (section 2) |
| Scheduled reminders (`daily_mission_ready`, `mission_waiting`, `weekly_challenge`, `new_videos`) idempotent per child/day | needs a unique key per child/day/type and the scheduler | `notification_deliveries` or a `notification_schedules (child_id, type, local_date)` unique table |
| "Announcements" preference category | no announcement sender exists | admin broadcast endpoint + optional `notification_templates` |


## 4. Existing API contracts that need database support

| Contract | Today | Needs |
|---|---|---|
| `POST /admin/videos/youtube/channels/{id}/suspend` and `/revoke` | not present; only trust/untrust | `status` columns (section 3) |
| `YouTubeTrustedChannelDetailPublic.status` | returns only `approved` or `revoked` | allow `pending`, `suspended` |
| Channel counts and `last_*` fields | counts are live queries; `last_discovered_at` / `last_verified_at` are the newest review timestamps | dedicated sync columns |
| `GET /referrals/me`, `POST /referrals/attribute` | not present | referral tables |
| `GET /companion/dialogue`, `GET/PUT /companion` | not present | dialogue packs, `companion_key` |
| `GET/PATCH /notifications/preferences`, `GET /notifications/unread-count` | preferences shipped as `GET/PATCH /settings/families/{id}/notification-preferences` (family JSON, no schema); unread count still computed on the device | per-user preferences column (see Phase 7 table above); optional index for unread count |
| `VideoFeedItem.orientation` | not present | `videos.orientation` |
| `POST /video-access/tickets`, `/tickets/{id}/heartbeat`, `/tickets/{id}/end` (D6 contract in `docs/video-play-tickets.md`) | not built; pure rules ready in `app/services/play_ticket_rules.py` (unwired); the shipped model withholds ids at zero allowance and meters in `record_progress` | `video_play_tickets` |

## 5. Data backfills (after the schema exists)

1. `youtube_trusted_channels.status`: `approved` where `is_active`, else `revoked`; copy `updated_at` into `approved_at`/`suspended_at` as appropriate.
2. `videos.orientation` / `aspect_ratio`: from YouTube thumbnails or oEmbed dimensions (job), admin override afterwards. Re-run Shorts classification.
3. `referral_codes`: generate for existing parents lazily on first open of the invite screen (not in the migration).
4. `notification_deliveries`: none (new trail only).
5. Companion packs: seed the bundled English/Hindi/Gujarati lines as version 1 so server and bundle agree.

## 6. Proposed migration order

All **additive and reversible**, each its own revision, each with a downgrade:

1. `videos` orientation columns (independent, low risk).
2. `youtube_trusted_channels` status and sync columns (+ backfill 1).
3. `youtube_channel_events` (optional).
4. `notification_deliveries` (+ optional templates).
5. `companion_dialogue_packs` and `child_profiles.companion_key`.
6. `referral_codes`, `referral_attributions`.
7. Phase 1 and 5 columns, only if those designs are still wanted.
8. `video_play_tickets` (adopted under D6). Ship it behind `VIDEO_PLAY_TICKETS_ENABLED`; with the flag on, ticket heartbeats deduct and `record_progress` stops deducting (never both). Run the PostgreSQL concurrency tests (two devices starting at once, concurrent heartbeats) before enabling.

**Revision chain warning.** `alembic/versions` has two files numbered `0015` (`0015_daily_mission_engine`,
`0015_trusted_channel_upload_discovery`) that branch from `0014`, merged by the file named
`0017_child_video_daily_allowance.py` whose revision id is `0016_child_video_daily_allowance`.
Run `alembic heads` and `alembic history` on the disposable database first and give new revisions an id that
follows that merge head. No migration has been changed in this work.

## 7. Integration tests required after the migrations

Run on a disposable PostgreSQL only (never production), with `TEST_DATABASE_URL` set and a reviewed
`tests/schema/baseline.sql`:

* the existing **206 skipped** database tests (entitlement locking, concurrent heartbeats and exhaustion,
  daily stacking, midnight and family-timezone expiry, parent authorization, exactly-once reward grants);
* channel status transitions: trust, suspend, revoke, restore; suspended channel videos vanish from child feeds in one
  request; a flagged upload from an approved channel lands in quarantine;
* `channel_detail` counts against real rows (the mocked tests cover the shape only);
* `/videos/{id}/next` against real data: eligibility parity with `/videos/feed` and `/shorts` (every recommended
  video is feed-eligible), zero allowance returns nothing, no completed or unpublished video appears;
* notification deliveries: retry, invalid-token deactivation, no duplicate sends;
* referral attribution: self-referral, duplicate device, expired code, one reward per verified registration;
* a CI check that `get_model` resolves every `MODEL_TABLES` entry on the migrated database;
* OpenAPI contract baseline updated deliberately for every new route.

Nothing in this document has been run against a database.
