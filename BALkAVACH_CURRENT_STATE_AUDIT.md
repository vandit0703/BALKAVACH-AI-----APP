# BalKavach AI — Current-State Code Audit

**Audited commit:** `58b3545` on `main` (working tree clean at start and at end of the audit).
**Date:** 2026-11-18
**Repositories:** `balkavach-backend` (FastAPI/Python), `balkavach-frontend` (Flutter child + parent app), `balkavach-admin` (Flutter Web admin).
**Companion documents:** `BALkAVACH_GAP_ANALYSIS.md`, `BALkAVACH_IMPLEMENTATION_ROADMAP.md`, `BALkAVACH_TESTING_PLAN.md`.

---

## 0. How this audit was done (read this first)

| Item | Statement |
|---|---|
| What I did | Read source: auth/session/security, daily-mission service and migration, task review/approval, entitlement, playback, watch-history, streak, notification/push/FCM, YouTube review/trusted-channel service, feed endpoints, schemas, all migrations' revision chain, CLI jobs, Flutter session/router/parent-gate/learning/missions/push/l10n code, admin app API usage. |
| What I did **not** do | Run any app on a device or emulator. Open the live database (no `DATABASE_URL` was used). Read `.env` contents. Deploy, commit, push, migrate, reset, stash or switch branches. |
| Tests executed | **None.** `pytest` is not installed in this environment and I did not install packages. DB-backed backend tests also require `TEST_DATABASE_URL` (not set). I did not run `flutter test` / `flutter analyze` either, to avoid `pub get` side effects on tracked files. All test statements below are **static** (what the test files contain), never "passed". |
| Prior reports | `docs/*.md` (including `complete-project-code-audit.md`, 2026-11-04) were used only as leads. Where they disagree with the code I report the code. Example: that report says login has no rate limiting; the code now has Redis-backed limiters. |
| Evidence labels | **Verified-by-reading** = I read the code path end to end. **Suspected** = code reading suggests a defect that needs a test or device run to confirm. **Unverified** = depends on live data, deployment or a device I did not have. |
| Secrets | None are reproduced here. A local, gitignored `notes.txt` contains a transcript of a root-password SSH login to the production host (see SEC-08); host details are intentionally omitted. |
| Project instructions | The global `CLAUDE.md` rules (Grow Spark website) do not apply to this repository and were not used. |

### Size of the system

| Repo | Source size (excl. generated l10n) | Notes |
|---|---|---|
| Backend | ~13.3k lines Python, **155 routes** in `app/api/v1/*.py`, 18 Alembic files | `app/models/` is effectively empty (82 lines, no classes). Tables are **reflected at runtime** with SQLAlchemy `automap` (`app/db/base.py`, `MODEL_TABLES`). Schema drift cannot be caught at import time or by a type checker. |
| Frontend | ~24.4k lines Dart, 112 files | Riverpod 3, go_router 18, Dio, `youtube_player_iframe`, `video_player`, `firebase_messaging`, `share_plus`. |
| Admin | ~5.3k lines Dart, 25 files | Web, in-memory token store, sidebar breakpoint 900 px. |

### Migration chain (Verified-by-reading)

`0001 … 0014` linear → **two** files both numbered `0015` (`0015_daily_mission_engine`, `0015_trusted_channel_upload_discovery`), both with parent `0014_auth_security_controls` → merged by `alembic/versions/0017_child_video_daily_allowance.py` whose **revision id is `0016_child_video_daily_allowance`** (file name `0017`, id `0016`). Result is a single head, but the naming is misleading and a future `0017` revision id will collide visually with the file name. `ALLOW_SCHEMA_MIGRATIONS` must be set for Alembic to run (guard in `alembic/env.py`/`.env.example`).

---

## 1. Executive summary

1. **Backend foundations are strong** in several areas: refresh-token rotation with reuse detection, per-request session-revocation check, role dependencies on every parent/child/admin route, ownership checks on shared endpoints (`progress`, `rewards`, `uploads`), idempotent ledgers for stars/XP/video entitlements, family-timezone-aware streak grace state machine, layered YouTube safety screening.
2. **The mission system exists as an engine, not as a product.** The seeded catalogue is **placeholder text** (slug-derived titles, one identical instruction sentence for every mission and age band) and the Gujarati/Hindi text is **Latin-script transliteration**, not Gujarati/Hindi script (`alembic/versions/0015_daily_mission_engine.py`). Only 22 templates exist and a completed template is never offered again, so a child runs out of missions after about 20 approvals.
3. **Video-time enforcement is client-trusted for YouTube.** The server meters time through `POST /videos/watch-history/{id}/progress` and refuses progress when time is exhausted, but `GET /videos/feed` and `/videos/shorts` keep returning `youtube_video_id` regardless of allowance. The lock is a Flutter UI reaction. A second, entitlement-bound metering path (`/video-access/*`) exists in the backend, is never called by Flutter and has no playback provider; it is a double-deduction hazard if ever enabled alongside the first.
4. **Every child also gets a free 15 minutes per day with no mission** (`FREE_DAILY_ALLOWANCE_SECONDS = 900`), which contradicts "complete the mission to earn 15 minutes". This needs a product decision, not a code fix.
5. **Parent-mode security is the most important gap.** Leaving child mode calls an *unauthenticated* endpoint (`POST /auth/parent-pin/verify`) with parent email + a 4–8 digit PIN and receives a **full parent session**. Throttling is per `client-IP:email` only (5 attempts / 5 min); there is no per-account lockout or alert. If the parent never set a PIN, the parent is locked inside child mode because the parent token is discarded when child mode starts.
6. **Streak, activity-day and video entitlement are all dated by the moment of parent approval**, not by when the child did the mission. A late-night approval can make the 15 minutes expire within minutes; an approval the next morning can break a streak the child actually kept. `review_submission` also recomputes a streak inline (no grace) in addition to calling the grace-aware `streak_service`.
7. **Missing entirely:** companion animation/TTS/dialogue engine and server-side character choice, referral system, deep links, scheduled notifications, notification delivery log, account deletion/change-password, password-reset landing screen, recommendation API, trusted-channel stats/status workflow.
8. **Test evidence:** ~337 backend test functions exist statically, none executed by me. There are **no DB-level tests for the daily-mission lifecycle** (select/skip/submit/exhaustion), none for `POST /auth/parent-pin/verify`, none for `/auth/password/*` endpoints, none for the `/video-access/*` HTTP layer.

---

## 2. Mission system and daily habit development (requirement §2)

### 2.1 Feature cards

#### 2.1.1 Seed catalogue and content quality
| Field | Finding |
|---|---|
| Backend | **Partial / content Broken.** Tables `daily_mission_templates`, `daily_mission_variations`, `daily_mission_assignments` and seeds exist (`alembic/versions/0015_daily_mission_engine.py`). Seed: 22 templates = 7 weekdays × 3 + 1 surprise. For each template × 3 age bands (`4_6`,`7_10`,`11_15`) × 3 locales the migration generates text from the slug: title `"{Slug Title} ({age} to {age})"`, description `"A {offline|interactive|creative} learning adventure for ages …"`, and the **same** instruction/safety/completion sentences for all missions. `required_materials` is always `["safe household objects"]`. |
| Localisation | `gu` and `hi` seed text is **romanised** ("Pagala ajmavo…", "Kadam aazmaiye…"), titles are identical to English. Not usable as Gujarati/Hindi. |
| Flutter | Renders whatever the API returns (`DailyMissionContent`). |
| Admin | **Partial.** `missions_page.dart` lists templates and toggles publish; no variation editor, no preview, no localisation-completeness view. Create/patch endpoints exist in the API only. |
| API integration | Verified for `GET /daily-missions/today`, `POST /daily-missions/{id}/select`. |
| Tests | `tests/test_daily_mission_service.py` (4 pure tests: age-band boundary, PII-requirement rejection, safe variation accepted, 9-combination publish rule). Not executed. |
| Problems | Placeholder content (MIS-01); transliterated gu/hi; no research-backed catalogue; developmental purpose per activity not stored anywhere in the schema (no `skill`/`purpose` columns). Live DB content may differ — **Unverified** (DB not opened). |
| Dependencies | Content research and authoring (non-code) → admin editor → seed/import. |
| Reusable | Schema, `DailyMissionVariationCreate` validators (rejects mandatory personal-data/location requirements), `has_complete_localized_variations`, `snapshot` JSON on assignments (content is frozen at issue time). |
| Recommended | See Roadmap Phase 5: curated 4-week catalogue first (28 days × 3 age bands × 3 locales), educator review of Gujarati/Hindi, add `skill_area`/`developmental_purpose`/`evidence_level` columns, admin editor, import tool. |

#### 2.1.2 Daily assignment, three-choice selection, age band, local date
| Field | Finding |
|---|---|
| Backend | **Implemented, with defects.** `ensure_daily_choices` (`app/services/daily_mission_service.py`) locks the child row, derives the family-local date (`timezone_service.local_today`) and age band (`age_band_for_birth_date`, server date), builds up to 3 deterministic choices (`sha256(child_id:date:template_id)` ordering), writes `snapshot`. DB constraints: unique current slot, unique "selected" per child/day. |
| Problems | (a) **Pool exhaustion**: templates already `approved` for the child are excluded forever; 22 templates ⇒ `<3` candidates after ~20 approvals ⇒ HTTP 503 `daily_missions_unavailable` (MIS-02). (b) Surprise template is forced into slot 1 **every day until approved once**, then never again (MIS-02). (c) `variation_key` is ignored by `_pick_variation`, so multiple variations of the same template/age/locale are picked arbitrarily; "mission variation management" exists in the schema only (MIS-06). (d) DOB is optional at child creation but required here (422 `birth_date_required`); ages outside 4–15 get 422, while the video feed serves 3–15 (MIS-09). (e) Family timezone defaults to **UTC** unless a parent saved a timezone (`family_timezone_name`) (VID-04). |
| Flutter | Uses `GET /today` and `POST /{id}/select` only (`missions_repository.dart`). Choice cards are a `Wrap` of `SizedBox(width: 280)` cards (`missions_screen.dart`). |
| Tests | None at DB/API level for this lifecycle. |
| Recommended | Rotation policy (cool-down window instead of permanent exclusion; reuse after N weeks), explicit surprise cadence, honour `variation_key`, DOB required for child creation or a clear UI state, timezone captured at registration. |

#### 2.1.3 Skip and replacement
| Field | Finding |
|---|---|
| Backend | **Suspected defect.** `skip_assignment` sets `row.is_current = False` and then calls `ensure_daily_choices` in the same session. `SessionLocal` is created with `autoflush=False` (`app/db/session.py`), so the pending change is not flushed before the "current choices" query; the query still sees three current rows (the skipped one is returned from the identity map) and returns early without creating a replacement. The replacement would only appear on the next `GET /today`. **Not executed — needs a DB test.** |
| Flutter | **Missing.** No call to `/daily-missions/{id}/skip`, `/active`, `/start`, `/history`, `/weekly`. |
| Limits | No daily cap on skips; no cool-down. |
| Tests | None. |

#### 2.1.4 Submission, parent approval, XP and stars
| Field | Finding |
|---|---|
| Backend | **Implemented (Verified-by-reading).** Selecting a choice creates a normal `Task` (`select_assignment`); the child submits via the generic `POST /tasks/{task_id}/submissions` (`submit_completion` flips the linked assignment to `pending_parent_approval`); parent approves via `POST /reviews/submissions/{id}` (`review_submission` writes `StarTransaction`/`XPTransaction` with idempotency keys `task-approved:{submission}:stars|xp`, level update, activity day, badges, streak, entitlement, notifications) and marks the assignment `approved`/`rejected`. Mystery bonus for the surprise template is an extra star transaction keyed `daily-surprise:{submission}:stars`. |
| Problems | Daily-mission `Task` rows are indistinguishable from parent chores in parent lists; **any approved task** grants video time (MIS-08). Time anchors use approval time (MIS-04). Duplicate streak computation (MIS-05). |
| Tests | `tests/test_api_mission_flow.py` (12), `test_api_rewards_flow.py` (10), `test_e2e_core_journey.py` exercise the generic task flow; none involve a `DailyMissionAssignment`. |

#### 2.1.5 Weekly progress, history, Daily Surprise, admin validation
| Field | Finding |
|---|---|
| Backend | `GET /daily-missions/history`, `/weekly` implemented (`weekly_summary`). Publish validation requires English+Gujarati+Hindi for all 3 age bands. Any edit to a template/variation un-publishes it (good). |
| Flutter | History/weekly not wired. Surprise shown only as an icon/colour; `mystery_bonus` amount not displayed. |
| Admin | Publish toggle only. |

### 2.2 Does Phase B (docs/phase-b-mission-engine.md) satisfy requirement §2?

| Requirement | Verdict |
|---|---|
| Seven-day schedule with weekday themes | **Engine yes** (`THEMES_BY_WEEKDAY`), content **placeholder**. |
| Good default missions every day | **No** (MIS-01). |
| Age bands 4–6 / 7–10 / 11–15 | Engine yes; content identical across bands. |
| Gujarati / Hindi / English | Engine yes; gu/hi seed is transliteration. |
| Home-safe, low-cost, safe | Validators help; actual content absent. |
| Rotation instead of weekly repetition | **No**: permanent exclusion → exhaustion. |
| Individual suitability | Per-child seed + age band; no interest/skill adaptivity (acceptable for MVP). |
| Research-backed, purpose per activity | **No** data model or content. |

---

## 3. Interactive cartoon companion (requirement §3)

| Field | Finding |
|---|---|
| Existing assets | `balkavach-frontend/assets/images/`: `BalKavach Panda Learning Logo.png` (preserved, untouched), `panda_cheering/drawing/hoodie/missions/welcome.jpg`, `garden_scene.jpg`, `treasure_chest.jpg`, `parent_auth_hero.jpg`; six child avatars in `assets/images/avatars/*.jpg`. All raster, static. |
| Name | Current copy calls the mascot **"Kavach Panda"** (`welcomeMascotLabel`, `pandaSays`, `submitPandaName`, `gardenImageLabel` in `lib/l10n/app_*.arb`). Requested primary mascot is **Mitu Panda**. |
| Dialogue | Hardcoded ARB strings (`mascotReady`, `mascotMissionsLeft`, `pandaEncourage`, `submitPandaMessage`, `gardenTipTitle`); a `MascotBubble` widget shows image + title + message. No name personalisation, no state machine, no variation, no age tone. |
| Animation / TTS / audio | **Missing.** `pubspec.yaml` has no Lottie/Rive/Flame, no `flutter_tts`, no audio package. |
| Character selection | **Local only.** Six avatars chosen by the parent and stored in `SharedPreferences` (`AppPreferences.setChildAvatarKey`, key `child.avatar.<childId>`); backend has `avatar_url` field on child but no `companion`/`character` column and no endpoint. Not synced across devices. |
| Localisation | Keys are at parity: 632 keys in each of `app_en/gu/hi.arb` (counted). Quality of the gu/hi text was not reviewed by a native speaker. |
| Performance | No animation cost yet; a single 1519-line `shorts_feed.dart` and 816-line `video_detail_player_screen.dart` are the heavy widgets. |
| Dialogue source | Hardcoded (not server-driven, not generated). |
| IP | No third-party characters found in assets. Keep it that way: see Roadmap Phase 6 for original character set and clearance step. |
| Reusable | `MascotBubble`, `AppImages`, `ChildAvatar`, `AppPreferences`, l10n pipeline, `SignOutHooks`. |
| Recommended | Server-driven dialogue catalogue + deterministic client state machine; pre-recorded or no audio at first; Rive/Lottie for 3–5 states; `child_profiles.companion_key` additive column. No per-message LLM calls. |

---

## 4. Video access and the 15-minute rule (requirement §4)

### 4.1 What exists

| Layer | Component | Status |
|---|---|---|
| Ledger | `video_access_entitlements` (migration 0013), `grant_mission_video_entitlement` in `app/services/video_entitlement_service.py` | **Implemented.** 900 s per approved task, daily cap of mission grants default 3600 s (family-configurable 900–14400 via `family_settings.video_settings.daily_limit_seconds`), idempotent on `submission_id`, `expires_at` = end of family-local day. |
| Free time | `FREE_DAILY_ALLOWANCE_SECONDS = 900` tracked in `child_video_daily_usage` (migration 0016/`0017_…py`) | **Implemented but conflicts with requirement** (VID-03). |
| Grant trigger | `review_submission` → `grant_mission_video_entitlement` for **any** approved task; notification `mission_video_time_granted` | Implemented. |
| Metering A | `POST /video-access/sessions`, `/heartbeats`, `/sessions/{id}/interrupt` (`video_access_service.py`) | Implemented; requires `VIDEO_PLAYBACK_PROVIDER` (none in repo); **Flutter never calls it**; allowance GET is the only `/video-access/*` call used. |
| Metering B | `POST /videos/watch-history/{id}/progress` (`video_watch_history_service.record_progress`) | **This is the live path.** Uses wall-clock delta since `child_video_daily_usage.last_heartbeat_at`, capped at 30 s per call, only if the previous call reported `is_playing`; spends free allowance first then entitlements (`consume_video_allowance`). Returns 403 `video_time_exhausted` when nothing remains. |
| Allowance API | `GET /video-access/allowance` (child), `/children/{id}/allowance` (parent) | Implemented. |
| Flutter lock | `video_detail_player_screen.dart` (`_recordWatchProgress`, `_stopForExhaustedAllowance`), `shorts_feed.dart`, `video_time_exhausted_dialog.dart`, `video_allowance_card.dart` | Implemented as **reactive** UI: pause + dialog after the server says exhausted. |

### 4.2 Anti-bypass matrix (requirement §4 "must not allow")

| Threat | Result | Evidence |
|---|---|---|
| Restart app to reset time | **Protected** (state is server-side counters) | `child_video_daily_usage`, `video_access_entitlements.consumed_seconds` |
| Switch account | **Protected per child**; each child has its own free 15 min by design | allowance keyed by `child_id` |
| Switch device | **Partially**: same child_id budget on any device, but metering B has **no per-child active-session/device exclusivity**; two devices playing simultaneously consume only wall-clock once (benefit to child). A is exclusive but unused | `record_progress` vs `start_playback` |
| Paused/background counted as watch time | **Mostly protected**: time is credited only if the previous report said `is_playing`; client claims `is_playing` (client-controlled, VID-06). Up to one 30 s interval can be credited after the app stops reporting | `record_progress` |
| Repeated API calls to mint time | **Protected**: grants are idempotent per `submission_id` and capped per local day; progress credit is server-clock based | `grant_mission_video_entitlement` |
| Client clock manipulation | **Protected** (server clock) | `datetime.now(timezone.utc)` in services |
| Double deduction from two mechanisms | **Not protected by design, currently dormant** (A and B both mutate `consumed_seconds`; only B is used) | VID-02 |
| Modified client plays YouTube anyway | **Not protected**: feeds hand out `youtube_video_id` irrespective of allowance; YouTube IFrame plays entirely on the device | VID-01 |
| Playback starts before lock | **Yes**: no pre-launch gate found; lock triggers after the first progress response | `video_detail_player_screen.dart` |

### 4.3 Missing for reliable enforcement
Server must stop *issuing* playable IDs when time is zero, and meter against a server-issued, short-lived play ticket with a heartbeat deadline; unify A and B; pre-launch gate in Flutter; emit `video_time_nearly_exhausted`/`video_time_exhausted` notifications (templates exist in `notification_service.py` and `push_service.GENERIC_TEXT` but nothing creates them); anchor entitlement to mission date (MIS-04); set timezone at registration (VID-04); decide on free time (VID-03). Detailed tasks: Roadmap Phase 3.

---

## 5. Push notifications (requirement §5)

| Capability | Backend | Flutter | Admin | Evidence / gap |
|---|---|---|---|---|
| FCM integration | **Implemented** (`app/integrations/fcm.py`, HTTP v1, service-account JWT, returns `ok/invalid_token/retry/error`) | **Partial**: `firebase_messaging` token source, foreground refresh only | N/A | Provider is enabled only when `NOTIFICATION_PROVIDER` is set. Firebase config files (`google-services.json`, `firebase_options.dart`) are **absent from this workspace**, so the app falls back to `NoopPushTokenSource` (`PushStatus.notConfigured`); push could not be exercised. |
| Device tokens | **Implemented** (`device_service.py`, `PUT /notifications/devices`, `POST /notifications/devices/unregister`; a token belongs to one user, last sign-in wins) | Registered after sign-in, unregistered via `SignOutHooks` | N/A | OK. |
| Preferences | `user_settings.push_enabled`, `email_notifications_enabled` | Settings toggle | N/A | **No per-category preferences, no quiet hours, no child/parent split of preferences.** |
| Event notifications | Created for task assigned/submitted/approved/rejected, rewards, badges, streak events, video time granted (`notification_service.py`) | Foreground message triggers provider invalidation | N/A | Fine. |
| Scheduled notifications | **Missing.** Only CLI `streak-check` (`app/cli.py`). No "good morning", "mission waiting", "weekly challenge", "new videos". | — | — | NOT-01. |
| Deep links | **Missing.** Payload is `{type, notification_id}`. | No `onMessageOpenedApp`, `getInitialMessage`, router mapping, local notifications or channels | — | NOT-02. |
| History | `GET /notifications` + `POST /{id}/read` | Providers exist (`childNotificationsProvider`, `parentNotificationsProvider`); no dedicated notification-centre screen found | — | NOT-06. |
| Localisation | Push text localised en/hi/gu (real scripts) in `push_service.GENERIC_TEXT`; **in-app title/message stored in English only** | — | — | NOT-05. |
| Delivery/failure logging | **Missing.** Delivery runs in a 2-worker in-process `ThreadPoolExecutor` after request teardown (`deliver_ready`); `retry` results are dropped; no outbox, no log table. | — | — | NOT-03. |
| Parent vs child separation | By recipient user only; no taxonomy or UI separation | Separate providers | — | Needs explicit type→audience map. |
| Admin capabilities | None (no broadcast, templates, delivery view) | — | **Missing** | NOT-07. |
| Tests | `tests/test_api_push.py` (15), `test_streak_notifications.py` (2), frontend `push_registration_test.dart`. Not executed. |

---

## 6. WhatsApp sharing, referrals, promotion (requirement §6)

| Capability | Status | Evidence |
|---|---|---|
| Generic text share | **Implemented** | `lib/shared/platform/text_sharer.dart` (`share_plus`), used by `widgets/video_actions.dart` (video title + link) and `weekly_report_screen.dart` (summary). The system share sheet already lists WhatsApp. |
| WhatsApp-specific intent | Missing | — |
| Referral codes / attribution / rewards | **Missing** (no table, endpoint, schema, UI; grep for referral/invite/whatsapp in backend returns only unrelated words) | SHR-01 |
| Deep links / app links / store links | **Missing** (no `app_links`/`uni_links`, no `assetlinks.json`, manifest has only a `queries` https entry) | SHR-02 |
| Promotion card (image + description + links) | Missing | — |
| Achievement/badge share cards | Missing; weekly report share is plain text | — |
| Privacy | Sharing a child's achievement needs a parent gate and no PII/identifiers in links; not designed yet | SHR-03 |
| Reusable | `TextSharer` abstraction (testable), weekly-report summary builder, `link_opener.dart`, l10n pipeline, badge data from `/progress` |

---

## 7. Streak system (requirement §7)

| Field | Finding |
|---|---|
| Backend | **Implemented.** `app/services/streak_service.py` (520 lines): states active / at-risk / broken / recovered, 3-day grace (`_GRACE_DAYS = 3`, deadline = local midnight of last_activity+3 days in the family timezone), row-locked `record_qualifying_activity`, idempotent per local day, read-only `compute_streak_state`, `check_and_update_streak_states` for the cron. CLI: `python -m app.cli streak-check`. |
| Qualifying activity | `review_submission` on an **approved** submission (any task). Parent approval is required. |
| Problems | (1) Local date comes from the **approval time** (`now_utc=datetime.now()`), not the mission/submission day (MIS-04). (2) `review_submission` also computes `current_streak` **inline without grace** for badge criteria (`yesterday` rule) next to the grace-aware service → two sources of truth (MIS-05). (3) `streak-check` needs an external scheduler; no evidence in the repo that it is scheduled (OPS-02). (4) Streak-at-risk copy: "Complete a mission today…" with a hard 20-hour dedupe window (fine) — wording could create pressure; review with child-development input (Phase 6/7). |
| Flutter | `streak_screen.dart`, `streak_card.dart`, `/progress/children/{id}/streak` wired. |
| Tests | `tests/test_streak_system.py` (17), `test_streak_notifications.py` (2), frontend `streak_test.dart`. Not executed. No test exercises "approval after local midnight" or the inline-vs-service disagreement. |
| Conflicting rules | Documented rule (grace) vs inline rule in `task_service.py`. Do **not** add new rules; remove the inline computation and read from `streak_service`. |

---

## 8. Authentication and account security (requirement §8)

### 8.1 What exists (Verified-by-reading)

| Area | Evidence |
|---|---|
| Password hashing | `pwdlib` recommended hasher (argon2) — `app/core/security.py` |
| Registration/login | `POST /auth/register`, `/auth/login` (email for parents, username for children). Registration password min length 12. |
| Sessions | `auth_sessions` table; refresh tokens are random, stored as SHA-256 digests, rotated each use, reuse of a rotated token revokes the session (`session_service.rotate`). Access tokens carry `sid`; `get_current_user` checks revocation on **every request**. Parent refresh 30 d, child 14 d, access 30 min. |
| Logout / revoke | `POST /auth/logout`; parent can revoke all of a child's sessions (`DELETE /auth/children/{id}/sessions`); password reset revokes all user sessions. |
| Role separation | `require_parent`, `require_child` (also requires active profile), `require_admin`, `require_admin_permission(...)`; every route file uses them. Shared endpoints (`progress`, `rewards`, `uploads`, `notifications`) enforce ownership (verified for the first three). |
| Rate limiting | Redis Lua limiter for login, registration, password reset and parent PIN; **fails closed (503)** when Redis is unavailable or `REDIS_URL` unset. |
| Parent PIN | `POST /auth/parent-pin` (set, parent bearer), `POST /auth/parent-pin/verify` (see gaps), hash stored with the same hasher. |
| Flutter session | Secure storage (`flutter_secure_storage`), refresh on 401, local drop only when the server refuses, parent token **discarded** when child mode starts (`SessionController.startChildMode`). Admin accounts are refused in the mobile app. |
| Admin | In-memory tokens only (page reload signs out), permission-gated pages. |

### 8.2 Security gap register

| ID | Severity | Gap | Where |
|---|---|---|---|
| SEC-01 | **P0** | `POST /auth/parent-pin/verify` is **unauthenticated**, takes `email` + `pin` (4–8 digits, `^\d{4,8}$`) and returns a full parent `TokenResponse` including refresh token. It does not require a child session, device binding, or the parent password. Throttle is 5 attempts / 300 s per `client-ip:email`; no per-account counter, no lock-out, no alert, no audit row. A 4-digit PIN is a 10⁴ space. | `app/api/v1/auth.py`, `app/schemas/auth.py` |
| SEC-02 | P1 | Parent can be **trapped in child mode**: child mode never checks that a PIN exists, the parent token is dropped, child sessions have no sign-out, and verify fails when `parent_pin_hash` is empty. Gate dialog labels the PIN field "Password" (`l10n.authPassword`), requires typing the parent's email each time, and the PIN-saved snackbar shows the text "Parent gate". | `child_shell.dart` (`ParentGateButton`), `parent_settings_screen.dart` (`_ParentPinCard`), `session_controller.dart` |
| SEC-03 | P1 | Limiter key uses `request.client.host`. Nothing in the repo/docs configures proxy headers (`--proxy-headers`, trusted forwarded IPs). Behind a reverse proxy all users may share one key (global lock-out) or the key may be spoofable. **Unverified** (deployment). Redis is mandatory or all auth calls return 503. | `app/api/v1/auth.py`, `app/core/rate_limit.py` |
| SEC-04 | P1 | Password-reset is **incomplete end to end**: API + SMTP sender exist; the email link points to `PASSWORD_RESET_URL/?token=…` but no Flutter screen, deep link or web page in these repos consumes the token (`auth_repository.dart` has a call, no UI). | `app/integrations/email.py`, `auth_repository.dart` |
| SEC-05 | P2 | No change-password, no "sign out all my devices" for the parent, no list-my-sessions, no account deletion / data export, no email verification at registration. | `app/api/v1/auth.py` |
| SEC-06 | P2 | Access tokens without a `sid` claim skip revocation (legacy fallback when `auth_sessions` is missing). Child passwords are stored **reversibly encrypted** so a parent can read them (Fernet key = single point of compromise). | `dependencies.py`, `session_service.start_session`, `child_credentials.py` |
| SEC-07 | P2 | Changing the PIN requires only a parent bearer token (no current PIN or password). | `auth.py:update_parent_pin` |
| SEC-08 | P3 | `notes.txt` (gitignored, local) contains a transcript of an interactive root-password SSH login to the production host. Move to key-based, non-root access and delete the transcript. | repo root |
| SEC-09 | P2 | Parent-mode switching is a **UI convention**, not a server concept: the server cannot tell "parent on a child's device" from "parent on own phone". | design |

### 8.3 Direct answers to the audit questions
* *Is parent mode protected on the backend?* Parent **data** endpoints are protected by role (child tokens get 403). The **transition** child → parent is protected only by SEC-01's PIN endpoint.
* *Do child tokens reach parent endpoints?* No: `require_parent` checks `user.role == "parent"`; test `test_child_session_refreshes_as_a_child_and_never_gains_parent_rights` exists (not executed).
* *Is PIN verification secure?* Hashing is fine; the endpoint design and throttling are not (SEC-01).
* *Are repeated attempts rate-limited?* Per IP+email only.
* *Do logout and revocation work?* Yes by code and tests (not executed): `test_logout_revokes_the_session_and_its_access_token`, `test_refresh_rotates_and_old_token_reuse_revokes_the_session`.

---

## 9. Admin: trusted YouTube channels (requirement §9)

### 9.1 What exists
* Table `youtube_trusted_channels`: `channel_id` (UC-pattern check), `channel_title`, `thumbnail_url`, optional `age_min/age_max`, `language_code`, `category_id`, `rights_status` (unreviewed/cleared/not_cleared), `is_active`, `created_by`, timestamps, `notes`, upload-scan cursors (`uploads_scan_complete`, `uploads_page_token`, `uploads_latest_video_id`).
* API (all `video:write`/`video:read`): `GET /admin/videos/youtube/channels`, `GET …/channels/discover` (search), `POST …/channels/trust`, `POST …/channels/{id}/untrust`, review actions (approve/reject/quarantine/reevaluate/reopen/revoke), `POST …/recheck`, `POST …/auto-review`, `POST …/discover`, `GET …/diagnostics`.
* CLI jobs: `youtube-discover`, `youtube-recheck`, `youtube-auto-review`, `youtube-report`.
* Admin UI: search + trust/untrust **inside** `youtube_reviews_page.dart`.

### 9.2 Channel trust vs child safety (already layered)
`auto_approval_blocker` (`youtube_review_service.py`) is the single policy. For a trusted channel to auto-publish a video **all** must hold: channel `is_active`, `channel_id` matches, channel `rights_status == "cleared"`, review `pending_review`, **no screening flags**, YouTube `madeForKids == true`, duration ≤ `YOUTUBE_TRUSTED_AUTO_PUBLISH_MAX_SECONDS` (3600), supported audience age band. `screen_candidate` quarantines age-restricted/not-made-for-kids/denylist hits and marks non-embeddable/private/region-blocked as unavailable. The child feed shows a YouTube video only if the review is `approved`, `made_for_kids`, rights `cleared` and **re-verified within `YOUTUBE_REVERIFY_HOURS` (72 h)** (`youtube_visibility_clause`). `untrust_channel` quarantines that channel's *automatic* publications. This is the correct model: **trust is a routing signal, never a bypass**.

### 9.3 Gaps against the requested workflow

| Requested | Status |
|---|---|
| Approval status (pending/approved/suspended/revoked) | **Missing**: single boolean `is_active`; no reason, no reversible "suspend" distinct from "revoke" (CHAN-01) |
| Added date / added by | Present (`created_at`, `created_by`) |
| Approved by / approved at | **Missing** (only created_by; re-trust overwrites `updated_at`) |
| Channel URL | Missing (derivable from `channel_id`; not stored/returned) |
| Last checked / last successful sync | **Missing** (only scan cursors; no timestamps) |
| Counts: discovered / approved / pending / quarantined, Shorts vs regular | **Missing** (no per-channel aggregate endpoint or UI) |
| Trust history | Partial: `audit_logs` rows `youtube.channel_trusted` / `youtube.channel_untrusted`, no per-channel history API/UI |
| Review channel details before approving | Partial: search results show title/thumbnail; no description, no made-for-kids ratio, no sample videos |
| Dedicated "Trusted Channels" page | **Missing** (embedded), hard-coded English strings such as `'Channel trusted. $count videos discovered.'` bypass l10n |
| Automatic rechecking | **Partial**: logic exists, depends on an external scheduler; if it stops, **every YouTube video disappears from the child feed after 72 h** (fail-closed) with no alert (CHAN-03) |
| Duplicate prevention | Present: unique `channel_id`; feed de-dupes YouTube IDs; discovery counts `skipped_existing` |
| Keyword safety net | English-only denylist; Hindi/Gujarati titles rely on `madeForKids` alone (CHAN-04) |
| Tests | `test_api_youtube.py` (38), `test_youtube_rules.py` (47), `test_youtube_auto_review.py` (36), admin `youtube_reviews_test.dart`. Not executed. Many skip when migrations 0008/0010/0011 are absent from the test DB. |

---

## 10. Video feed and playback experience (requirement §10)

| Field | Finding |
|---|---|
| Feed APIs | `GET /videos/feed` (regular), `GET /videos/shorts`, `GET /videos/categories`, watch-history endpoints. `eligible_feed` filters by child age (3–15), language (preferred + `en`), category, YouTube visibility, duplicates; orders by "parent replay, partially watched, language match, display_order, published_at". |
| Recommendation logic | **None.** No related/next endpoint. "Up next" in Flutter is built **client-side** from the list already loaded: same-category first, then others, max 20 (`watch_home_screen.dart::_openVideo`). |
| Empty feed risk | Completed videos are excluded forever unless a parent authorises replay; paging is offset-based over a filter that changes as the child watches → skipped/duplicated items (client de-dupes by id). The catalogue can run dry (FEED-02). |
| After a video ends | `onEnded` only records progress; no end-of-video suggestion overlay or autoplay-next found (**Verified-by-reading**, not on device). |
| Description in viewing area | `video_detail_player_screen.dart` renders `detail.description` under the player (FEED-04). |
| Players | YouTube IFrame (`youtube_player_screen.dart`, `OfficialYouTubeEmbed`, `strictRelatedVideos: true`, navigation delegate sends outbound links through a grown-up gate); MP4 via `video_player` (`video_playback_controller.dart`). Detail player AspectRatio is fixed **16:9**; custom fullscreen/landscape lock (`_setFullscreen`) is wired to the MP4 controls only; YouTube fullscreen relies on the embed's own button. Shorts feed passes the screen's aspect to the embed and uses `shortsFitFor` for MP4. |
| Orientation | Manifest handles `configChanges` (orientation, screenSize…) and sets no `screenOrientation` lock. |
| Why horizontal videos may fail or look wrong (hypotheses, **not reproduced**) | (1) Classification is **duration-only** (`video_classification.py` states there is no aspect-ratio column), so any landscape clip ≤ 60 s is a "Short" and is letterboxed inside a vertical full-height page. (2) Regular player is a fixed 16:9 box; portrait content >60 s is pillarboxed small. (3) Fullscreen/landscape logic does not cover the YouTube embed path (the app's `_fullscreen` state is not driven by the iframe), so layout around the player (description, up-next) may not respond when the embed goes fullscreen. (4) Embeds that refuse playback (`not_embeddable`, error 101/150/153) are handled as "blocked" notices — verify what the child sees. A device reproduction matrix is in the Testing Plan. |
| Playback history | Persistent per-child history with resume position, completion threshold rules (short 80 %/≥6 s, long 90 %) — **Implemented**. |
| Entitlement enforcement | See §4. |
| Logout placement | Parent: logout icon in the Parent Hub app bar (one tap, **no confirmation**) and a "Log out" button in Parent Settings. Child: **none** — only the Parent Gate button in the app bar (`child_shell.dart`). No logout control appears on any viewing screen (**Verified-by-reading**). The note in `notes.txt` ("logout option") suggests the owner expects a deliberate location; decide: child never sees logout; parent logout lives only in account/settings, behind confirmation. |
| Tests | Frontend: `video_feed_test`, `shorts_feed_test`, `video_detail_player_test`, `video_player_test`, `watch_home_test`, `video_allowance_test`. Backend: `test_video_classification.py` (7), `test_video_access_rules.py` (12), `test_video_timezone.py` (5), `test_api_learning.py`. Not executed. |

---

## 11. UI/UX and responsiveness (requirement §11)

**Limits:** I did not run the apps, so visual overflow was **not observed**. Findings below are static.

| Area | Finding |
|---|---|
| Breakpoints | Child/parent app: `WindowSize` compact <600, medium ≥600, expanded ≥840 (`core/responsive/breakpoints.dart`), `ResponsiveContent` caps content width (form 560, list 720, wide 960), `ChildShell` switches bottom bar ↔ navigation rail. Admin: sidebar at 900/1200 px (`shell.dart`). |
| Fixed dimensions | `missions_screen.dart` daily choices: `SizedBox(width: 280)` cards in a `Wrap`; admin dialogs fixed 480/520 px (`families_page.dart`, `youtube_reviews_page.dart`, `ui/widgets.dart`); `shorts_feed.dart` and `watch_home_screen.dart` contain several fixed sizes (many are intentional canvas sizes). Needs device review. |
| Localisation fit | ARB parity 632/632/632 keys. Existing tests: `test/localization/localization_audit_test.dart`, `language_switching_test.dart`, `test/responsive/responsive_screens_test.dart` (static; not executed). No evidence of tests at text scale ≥1.3 with Gujarati/Hindi on the densest screens. Admin: hard-coded English strings (e.g. channel trust message). |
| Large widgets / perf | `shorts_feed.dart` 1519 lines, `video_detail_player_screen.dart` 816, `watch_home_screen.dart` 728, `youtube_player_screen.dart` 681: rebuild/state-ownership risks; each `_recordWatchProgress` is network-throttled to 10 s (good). |
| Network chatter | `videoAllowanceProvider` is `autoDispose` and invalidated after playback; `VideoFeedPager` seeds from already-loaded Home list (good). Notification list refresh on every foreground push (acceptable). |
| Loading/empty/error states | Shared `state_views.dart` (`LoadingView`, `EmptyView`, `ErrorView`, `InlineNotice`) used broadly; skeleton loaders are not present (spinners only). |
| Touch targets | Default Material sizes; `dense: true` buttons (Parent Gate pill) may be <48 dp — verify. |
| Accessibility | Semantics labels exist in places (`semanticLabel`); no systematic audit. |

---

## 12. Cross-cutting findings

| ID | Finding |
|---|---|
| OPS-01 | Migration naming (two `0015`, file `0017` with id `0016`). |
| OPS-02 | Everything time-based depends on **external cron** that is not defined in the repo: `youtube-discover`, `youtube-recheck`, `youtube-auto-review`, `streak-check`. If absent: YouTube feed empties after 72 h; streak at-risk pushes never fire. Deployment state **Unverified**. |
| OPS-03 | Runtime table reflection means CI cannot detect schema drift; `has_model` guards exist for optional tables (fail-closed). |
| OPS-04 | Test posture: DB tests are skipped unless `TEST_DATABASE_URL` points at a dedicated database whose name contains `test`; `.env.example` documents it. A previous report states ~160 tests were skipped for that reason. |
| OPS-05 | Firebase and SMTP configuration are not in the workspace; push and password-reset email are therefore unverifiable here. |
| OPS-06 | `docs/` contains 14 earlier reports with overlapping claims; treat this file set as the baseline and archive the rest. |

---

## 13. Verified vs unverified

**Verified-by-reading:** auth/session lifecycle, role dependencies, ownership checks listed in §8, daily-mission engine logic, review-approval side effects, entitlement grant/cap/idempotency math, metering B accrual rules, trusted-channel policy layering, push pipeline, Flutter session handling and parent gate, Flutter API surface used for missions/videos/push, ARB parity.

**Suspected (needs a test/run):** MIS-03 skip response; FEED-03 landscape causes; VID late-night entitlement expiry in practice.

**Unverified:** live DB contents (mission text actually served; trusted channels present; applied migration state), cron jobs on the server, Redis/SMTP/FCM configuration, reverse-proxy IP handling, any on-device behaviour (overflow, fullscreen, orientation, keyboard, TalkBack), all test outcomes.

---

## 14. Test inventory (static counts; none executed)

| Suite | Count | Needs |
|---|---|---|
| Backend `tests/test_*.py` | 337 test functions across 30 files | `TEST_DATABASE_URL` (disposable DB, name contains "test") for API/DB tests; pure tests run without |
| Frontend `test/**` | 41 Dart files (incl. helpers) | `flutter test` |
| Admin `test/**` | 5 files (`live_contract_test.dart` is opt-in against a live server via `--dart-define`) | `flutter test` |

**Coverage holes confirmed by grep of the test tree:** daily-missions API/service lifecycle; `/auth/parent-pin*`; `/auth/password/forgot|reset`; `/video-access/*` HTTP routes; `cli streak-check`; scheduled/related notifications (do not exist); mascot (does not exist).
