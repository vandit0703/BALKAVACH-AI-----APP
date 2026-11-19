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
| Invite / share card | no server data at all; card and message are generated on the device |
| Panda dialogue | bundled in the app's localization files |
| Parent allowance summary | `video_access_entitlements`, `child_video_daily_usage`, `tasks` |

## 2. Required new tables

| Table | Phase | Purpose | Key columns |
|---|---|---|---|
| `referral_codes` | 9 | one short code per parent | `id`, `parent_user_id` (unique), `code` (unique), `created_at` |
| `referral_attributions` | 9 | who installed from which code, once | `id`, `code_id`, `installer_user_id` (unique), `first_seen_at`, `registered_at`, `status`, `device_fingerprint_hash` |
| `notification_deliveries` | 7 | delivery trail and retries | `id`, `notification_id`, `device_token_id`, `status` (`queued/sent/failed/invalid`), `attempt`, `error_code`, `sent_at` |
| `notification_templates` (optional) | 7 | localisable templates managed in admin | `type`, `locale`, `title`, `body`, `updated_at` |
| `companion_dialogue_packs` | 6 | server-driven, versioned Panda dialogue | `id`, `version`, `locale`, `payload` (JSONB), `published_at` |
| `youtube_channel_events` (optional) | 4 | richer channel history than the audit log | `id`, `channel_id`, `actor_id`, `action`, `reason`, `created_at` |
| `video_play_tickets` | 3 | **only if** the roadmap's ticket model is adopted (not built) | `id`, `child_id`, `video_id`, `entitlement_id`, `device_id`, `started_at`, `last_heartbeat_at`, `ended_at`, `status`, `credited_seconds` |
| `video_topics` / tags (optional) | 8 | topic-based recommendations | `video_id`, `topic` |

## 3. Required new columns

| Table | Column(s) | Phase | Why |
|---|---|---|---|
| `youtube_trusted_channels` | `status` (`pending/approved/suspended/revoked`), `status_reason`, `approved_by`, `approved_at`, `suspended_at` | 4 | real suspend vs revoke; today only `is_active` exists |
| `youtube_trusted_channels` | `last_checked_at`, `last_successful_sync_at`, `last_error` | 4 | sync visibility and the "recheck older than 48 h" alert |
| `videos` | `orientation`, `aspect_ratio` | 8 | classify Shorts as short **and** portrait; today duration only |
| `child_profiles` | `companion_key` | 6 | remember the child's chosen companion on the server (Panda is the only one now, so the app needs nothing yet) |
| `auth_sessions` | `device_id`, `mode` | 1 | device-bound child/parent sessions (if the roadmap's design is revived) |
| `users` | `deleted_at`, `email_verified_at` | 1 | account deletion and optional verification |
| mission variations / templates | `skill_area`, `developmental_purpose`, `evidence_level`, `parent_tip`, `estimated_minutes` | 5 | catalogue metadata (not started) |

`user_settings` is a JSON document, so notification preferences and quiet hours (Phase 7) probably need **no**
schema change, only new keys; confirm during integration.

## 4. Existing API contracts that need database support

| Contract | Today | Needs |
|---|---|---|
| `POST /admin/videos/youtube/channels/{id}/suspend` and `/revoke` | not present; only trust/untrust | `status` columns (section 3) |
| `YouTubeTrustedChannelDetailPublic.status` | returns only `approved` or `revoked` | allow `pending`, `suspended` |
| Channel counts and `last_*` fields | counts are live queries; `last_discovered_at` / `last_verified_at` are the newest review timestamps | dedicated sync columns |
| `GET /referrals/me`, `POST /referrals/attribute` | not present | referral tables |
| `GET /companion/dialogue`, `GET/PUT /companion` | not present | dialogue packs, `companion_key` |
| `GET/PATCH /notifications/preferences`, `GET /notifications/unread-count` | not present (unread count is computed on the device from the list) | settings keys; optional index |
| `VideoFeedItem.orientation` | not present | `videos.orientation` |
| `POST /video-access/play`, `/tickets/{id}/heartbeat` | not built; the shipped model withholds ids at zero allowance and meters in `record_progress` | `video_play_tickets` (only if the ticket model is chosen) |

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
8. `video_play_tickets` last, and only if the ticket model is adopted.

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
