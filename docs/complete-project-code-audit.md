# Bal Kavach AI — Complete Real-Code Audit (2026-11-04)

Read-only audit of `main @ df97e7d` (== `origin/main`). No source file was modified, nothing was committed, pushed, deployed or migrated, and no production database was contacted. **One side effect, disclosed in §2:** running `flutter build web --release` rewrote tracked files under `balkavach-admin/build/`.

**Scope and depth.** This is a code-level audit. I read in full: backend auth/session/security/permissions, video feed, classification, video-access, reward, task-review and upload services, the router list, and the Flutter repositories' endpoint lists. I sampled the Shorts/playable-video code and the admin API calls. I did **not** read every Flutter screen line by line, did not inspect the live DB schema, and did not run any app on a device. Anything resting only on that is marked UNVERIFIED.

---

## 1. Executive summary

1. **P0 regression: Shorts appear in both feeds.** Commit `48cbe56` ("PIPELINE DIAGNOSTIS", author Vandit Katbamna) silently reverted the Shorts/regular split that `cdd5cc3` had shipped. `GET /videos/feed` now calls `eligible_feed(...)` with no `video_format`, so 1–60 s videos appear in both feeds. `video_format` was dropped from `VideoFeedItem`, and `duration_seconds` is no longer nulled when unknown (a YouTube row with the "unknown" sentinel `1` is reported as a 1-second video). Two backend tests catch this and **fail at HEAD**: `test_each_endpoint_asks_for_its_own_format_and_keeps_paging` and `test_items_carry_the_backend_label_and_never_a_guessed_duration`. Evidence: `git diff cdd5cc3 HEAD -- balkavach-backend/app/api/v1/videos.py`.
2. **Most of the backend is solid.** Refresh-token rotation with replay detection, ownership checks, a ledger-based star/XP system with idempotency keys, row-locked redemption, EXIF-stripping photo uploads with ownership-checked private serving, and Fernet-encrypted child credentials are all present in code. But **~160 backend tests are skipped** (no `TEST_DATABASE_URL`), so none of the DB-level behaviour was exercised by me.
3. **Hosted MP4 in Shorts is not possible today**, by design plus missing infrastructure. The feed never exposes a URL; playback needs a parent-approved entitlement and a `VIDEO_PLAYBACK_PROVIDER` implementation. **No provider implementation exists in the repo**, and the Flutter app **never calls `/video-access/*`**.
4. **Advertised-but-absent features:** Google sign-in and OTP login do not exist in the backend or the app (the app comments say so). There is **no rate limiting** on login/register.
5. **Admin panel is a partial CMS.** It cannot create/publish hosted videos, manage video categories or collections, resolve content reports (`/admin/videos/reports`), import a YouTube URL, create rewards/tasks, or act on redemptions. These backend endpoints exist but have no UI.
6. **Tests:** Frontend analyze clean; 1004 tests passed on the clean rerun. One test (`push_registration_test: a server failure is reported, not thrown`) failed in the first full run and passed on rerun → **flaky**. Admin has **1 failing test** (hardcoded English strings in `youtube_reviews_page.dart`, introduced by `48cbe56`) and 4 analyzer infos.

**Release verdict: NO-GO** for overall production, until the P0 items in §9 are fixed and the DB-backed suite is run against a disposable database.

---

## 2. Repository and Git status

| Item | Finding |
|---|---|
| Branch / HEAD / origin | `main` / `df97e7d` / `df97e7d` (in sync) |
| Working tree at start | Clean |
| Working tree now | 4 tracked files modified under `balkavach-admin/build/` (`web/main.dart.js`, `web/flutter_bootstrap.js`, `web/.last_build_id`, `test_cache/...track.dill`). **Caused by my `flutter build web --release`** (requested in Phase 8). I did not revert them (rule 8 forbids checkout). To undo: `git checkout -- balkavach-admin/build`. |
| Tracked build artifacts | 82 files under `balkavach-admin/build/` are tracked, including `test_cache/` and `.filecache`. Intentional for web deploy? If so, only `build/web` should be tracked. Fix: `.gitignore` + `git rm --cached`. |
| Secrets in Git | None tracked (`.env`, `google-services.json`, keystores not in `git ls-files`). `.env` is gitignored. `.env.example` exists. Values not inspected. |
| Docs | `docs/` has 9 prior reports (`feature-implementation-matrix.md`, `api-integration-matrix.md`, etc.). Not trusted; superseded by this file. |
| Authorship | HEAD~1 (`48cbe56`) is by a different author from the rest. It touched backend video code, `youtube_review_service.py` (+300 lines) and the admin page without reconciling with `cdd5cc3`. This is the likely source of the regression. |

---

## 3. Feature matrix (code-verified)

Legend: C = COMPLETE (verified end to end by code reading; **DB behaviour UNVERIFIED unless noted**), P = PARTIAL, UI = UI ONLY, BE = BACKEND ONLY, B = BROKEN, BL = BLOCKED, U = UNVERIFIED.

| Feature | Frontend UI | API | Backend service | Admin | Tests run by me | Status |
|---|---|---|---|---|---|---|
| Parent auth (email/password) | `parent_auth_screen.dart` | `/auth/register,login,refresh,logout,me` | `auth_service`, `session_service` | Admin login separate | Unit passed; DB tests skipped | **C** (code), DB U |
| Google / OTP auth | Not built (comment B1) | None | None | — | — | **Not implemented** |
| Child auth | `child_login_screen.dart` | `/auth/login` (username), `/auth/children/{id}/session` | Same + `child_credentials.py` (Fernet) | Child status toggle | Skipped (DB) | **C** (code), DB U |
| Refresh rotation / replay | `interceptors.dart` retries once on 401 | `/auth/refresh` | `session_service.rotate` revokes on reuse | — | Unit passed | **C** (code) |
| Rate limiting | — | — | None | — | — | **Missing (P1)** |
| Missions | `missions/*`, `create_mission_screen` | `/tasks*` | `task_service` | List + toggle active only | Skipped (DB) | **P** |
| Photo proof | `mission_submit_screen` → `/uploads/task-proofs` | yes | `upload_service` (decode, strip EXIF, 2048 px cap, owner/parent-only GET, `no-store`) | — | Skipped (DB) | **C** (code), DB U |
| Parent approval | `approvals_screen` | `/reviews/submissions/{id}` | `task_service` (stars+XP+streak+badges, idempotency keys) | — | Skipped (DB) | **C** (code), DB U |
| Stars / XP | `progress_repository` | `/progress/children/{id}` | `ledger_service` (sum of ledger) | Analytics overview | Unit passed | **C** (code) |
| Rewards / redemption | `rewards/*` | `/rewards`, `/redemptions*` | `reward_service` (row locks, idempotency key, refund on cancel) | Toggle active only | Skipped (DB) | **C** (code), DB U |
| Garden | `garden_screen.dart`, derived from weekly approvals | `/progress/...` | `garden_service` exists; `garden_progress` not exposed | — | Skipped | **P** — stage computed client-side, not persisted |
| Shorts | `shorts_feed.dart` (1348 lines) | `/videos/shorts` | `eligible_feed(short)` + classification | YouTube review only | 2 related backend tests **FAIL** | **P** (shorts feed correct; regular feed leaks) |
| Regular videos | `video_feed_screen.dart` | `/videos/feed` | **no format filter** | — | Failing test | **B** (duplicates Shorts) |
| Hosted MP4 | `DirectStreamSource` type exists, never fed | `/video-access/*` never called by app | `video_access_service` complete; **provider missing** | No upload/publish UI | Skipped | **BL / BE** |
| YouTube | `youtube_player_iframe`, `youtube_embed_policy` | `/videos/*`, `/admin/videos/youtube/*` | `youtube_review_service` (1178 lines) | Review page (strong) | Unit passed; DB skipped | **C** (code); real playback U |
| Admin content | 13 pages | ~30 endpoints used of ~60 | `admin_manage` | See §6 | 1 admin test fails | **P** |
| Notifications / FCM | `push_registration`, `device_repository` | `/notifications/*` | `push_service` (en/hi/gu), `fcm.py` | — | Flaky frontend test | **P**; real FCM BL (no `google-services.json`, no `NOTIFICATION_PROVIDER` evidence) |
| Reports | `weekly_report_screen` | `/progress/.../weekly` | `report_service` | — | — | **C** (code) |
| Localization | en/hi/gu ARB, 605 keys each, parity | — | Push localized | Admin en/hi/gu | Parity tests passed; admin literal-string test **fails** | **P** |
| Settings / consent | `parent_settings_screen`, `consent_screen` | `/settings/*` | yes | `settings` page | — | **C** (code) |

---

## 4. Video and Shorts findings

**Classification (correct).** `video_classification.py`: Short = known duration 1–60 s; YouTube stored `1` = unknown; unknown → regular; SQL clauses `short_clause`/`regular_clause` are explicit twins (NULL-safe). `/videos/shorts` uses `short_clause` correctly. **`/videos/feed` does not use `regular_clause`** (see §1.1), so the "never in both feeds" rule is currently violated. `eligible_feed` does still apply age, language, publication, category, `youtube_visibility_clause` and de-dup of YouTube IDs.

**Pagination:** offset/limit with `ge/le` bounds on both feeds. Ordering is stable (`display_order, published_at, id`).

**Shorts UI.** Code exists for full-screen paging, `VideoFeedPager`, and single active player (`ShortsPlayerPager`). I confirmed structure only. **UNVERIFIED on a device:** swipe, preloading, one-player-at-a-time disposal, background pause, rotation, Android back. The tests use fake players and prove nothing about real playback.

**YouTube embed limits.** `youtube_player_iframe` renders YouTube's own iframe. Custom overlays on top of it (description, share, report) are possible as Flutter widgets above the WebView, but the iframe's own controls, ads and end-screen suggestions cannot be removed. Some videos disable embedding, and `youtube_embed_policy.dart` handles that; the external-app fallback was not exercised.

**Hosted MP4: exact gap.**
1. Feed items deliberately omit `video_url`/`storage_key` (asserted by a test).
2. `POST /video-access/sessions` requires a child, a published eligible video, and an `active` entitlement matching the video or a published collection. Entitlements are created only by `fulfill_redemption` for `reward_type == "video_time"`. They are never free.
3. URL issuance goes through `get_video_playback_provider()`, which raises 503 `playback_unavailable` when `VIDEO_PLAYBACK_PROVIDER` is unset. **No provider class ships in the repo.** Storage (`integrations/storage.py`) only handles proof photos.
4. Admin can create a hosted record (`POST /admin/videos`) only with a pre-existing HTTPS `video_url`; there is no upload endpoint and no admin UI.
5. The Flutter app has no client for `/video-access/*` (heartbeats, interrupt).

Work required: (a) a signed-URL provider (S3/CloudFront or similar) implementing `issue_playback_url`/`revoke_playback`; (b) an admin upload flow plus private storage; (c) an app playback-session client with 30 s heartbeats and interrupt on pause/background; (d) a product decision on whether Shorts consume entitlement time. Do not weaken the entitlement checks.

---

## 5. Security findings

| # | Severity | Finding | Location |
|---|---|---|---|
| S1 | **High** | No rate limiting or lockout on `/auth/login` and `/auth/register`. Child passwords are low-entropy by nature, so this is the main brute-force vector. | `app/api/v1/auth.py`; grep found no limiter outside the YouTube client |
| S2 | Medium | Regular feed leaks Shorts and unknown-duration values (child-safety rule on "never guess"). | `app/api/v1/videos.py` `_feed_item`, `video_feed` |
| S3 | Medium | If `auth_sessions` is missing, `start_session` silently issues access tokens with no `sid`, which are unrevocable. Documented fallback, but it is a security downgrade. | `session_service.py:start_session` |
| S4 | Medium | Account enumeration: register returns 409 `email_in_use`; login runs the password hash only when a user is found (timing). | `auth_service.py` |
| S5 | Low | `is_session_revoked` ignores `expires_at`; access-token lifetime (30 min) bounds it. | `session_service.py` |
| S6 | Low | Unattached proof uploads are capped (10/child) but never cleaned up. | `upload_service.py`; no cleanup job found |
| S7 | Low | CORS: `allow_origins=[]` by default, credentials only if set. OK; confirm the production origin list. | `main.py` |
| S8 | Info | `/api/v1/videos/report` lets a *child* token file reports (comment says "behind the parent gate" — that gate is client-side only). | `videos.py:report_video` |

**Verified good (code):** parent→child ownership via `FamilyMember` on every child/family route reviewed; admin routes use `require_admin_permission` with a permission vocabulary; password hashing via `pwdlib` recommended (Argon2); refresh tokens stored as SHA-256 only; redemption debits use unique idempotency keys; approval path locks the child row; JWT secret must be ≥32 bytes; photo EXIF stripped and decompression-bomb capped. **Not verified:** the DB constraints behind those idempotency keys, and production environment values.

---

## 6. Admin coverage

Used by admin UI: dashboard, users (status/roles), families (+detail, child status), tasks (list/toggle), task categories, preset tasks (CRUD), rewards (list/toggle), redemptions (list), badges, educational content, settings (consent versions, maintenance), audit logs, analytics, YouTube reviews/discover/trust/recheck/publish-approved.

**Backend endpoints with no admin UI:** `POST/PATCH /admin/videos` (hosted), `/admin/videos/{id}/publish|unpublish`, video categories (create/update), collections (create/items/publish), `/admin/videos/reports` + resolve, `/admin/videos/youtube/import`, `/admin/videos/youtube/channels` (list). **No admin endpoint at all** for creating rewards/tasks (family-scoped via parent API) and for acting on redemptions. The admin therefore **cannot manage all content the child app consumes** (hosted videos, categories, collections).

---

## 7. Test results (what I actually ran)

| Suite | Command | Result |
|---|---|---|
| Backend | `.venv pytest -q` with `DATABASE_URL`/`TEST_DATABASE_URL` unset | **190 passed, 2 failed, 159 skipped** (all skips = no `TEST_DATABASE_URL`, plus `test_health` needing `DATABASE_URL`). DB-backed suites (auth sessions, missions, rewards, uploads, YouTube API, e2e journey) **NOT EXECUTED**. |
| Backend failures | `test_video_classification.py` ×2 | Genuine regression (§1.1). Assertions not touched. |
| Frontend | `pub get`, `dart format` (145 files, 0 changed), `flutter analyze` | Clean |
| Frontend | `flutter test` | Run 1: 1003 passed, 1 skipped, **1 failed** (`push_registration_test: a server failure is reported, not thrown`). Run 2: **1004 passed, 1 skipped**. → **FLAKY**. The responsive-screens file passed in isolation. |
| Admin | `pub get`, format (30 files, 0 changed) | OK |
| Admin | `flutter analyze` | 4 infos (`youtube_reviews_page.dart` lines 95, 118, 637, 661) |
| Admin | `flutter test` | 65 passed, 1 skipped, **1 failed**: `localization_ui_test: no widget builds user-facing text from a string literal`. Hardcoded English in `youtube_reviews_page.dart` (≈16 literals, e.g. 'Trust YouTube channel', 'Publish Approved Unpublished Videos'). The `hi`/`gu` copies are missing for this page. |
| Admin | `flutter build web --release` | Built OK (see §2 side effect) |

`live_contract_test.dart` (admin) was not run against any live server. The backend OpenAPI baseline (`tests/contracts/openapi_baseline.json`) is covered by `test_api_contract.py`, which passed in the DB-free run; the 48cbe56 route additions mean the baseline should be re-checked after fixing §1.1.

---

## 8. Localization and UI

- Frontend ARBs: en/hi/gu each have **605 keys** (parity). Push notification titles are localized server-side (`push_service.py`), but in-app notification rows created by `reward_service` use hardcoded English titles/messages ("Reward requested").
- Admin: en/hi/gu parity tests pass, but the YouTube review page bypasses them (failure above).
- Responsive: the frontend has a 500-case responsive test matrix (phones, 840 px rail, landscape, 2× text, hi/gu). It passes, but it is a widget-test result, not a device check.
- Language-persistence-after-restart and RTL: UNVERIFIED (RTL not applicable to these languages).
- Font glyph coverage for Devanagari/Gujarati on device: UNVERIFIED.

---

## 9. Prioritized remaining work

**P0**
1. **Restore the Shorts/regular split** (Small). Re-apply `cdd5cc3`'s changes to `videos.py` and `schemas/video.py` on top of `48cbe56`'s additions: `video_format="regular"` in `/feed`; `video_format` + `known_duration_or_none` in `_feed_item`; field on `VideoFeedItem`. Tests: the 2 failing tests plus a DB test that no id appears in both feeds. Review the other `48cbe56` hunks in `youtube_review_service.py` for further reverted behaviour.
2. **Run the DB-backed suite** against a verified disposable Postgres (`TEST_DATABASE_URL` with "test" in the name; migrations 0001–0010 applied by you). Until then the auth/reward/upload/ledger guarantees are code-read only. (Medium, no code change.)
3. **Login/register rate limiting** (Medium): per-IP and per-username throttling, with lockout/backoff for child logins. No DB impact if in-memory or Redis; add tests.

**P1 (MVP gaps)**
4. Admin UI for hosted videos, categories, collections and content reports, and admin YouTube URL import (Medium–Large).
5. Hosted playback end to end (Large): provider, upload/storage, app session client and heartbeats, decision on entitlement vs Shorts.
6. Google/OTP sign-in **if contractually promised** (Large; confirm scope, since the Stitch design shows it).
7. Fix the admin localization test (add en/hi/gu strings for the YouTube review page; Small) and the 4 analyzer infos.
8. Garden: persist or expose `garden_progress` or accept client-derived stage (Small–Medium).

**P2**
9. De-flake `push_registration_test`. 10. Untrack `balkavach-admin/build/test_cache` and `.filecache`. 11. Localize `reward_service` in-app notification text. 12. Upload cleanup job. 13. Device verification of Shorts behaviour (swipe, one player, lifecycle, rotation, back).

**P3.** Hosted-video Shorts with hardware-accelerated preloading, richer analytics, aspect-ratio column for true vertical detection.

---

## 10. Release readiness

| Area | Verdict | Why |
|---|---|---|
| Flutter Android app | **CONDITIONAL GO** | Analyze/tests green (one flaky); core flows coded against real APIs; device behaviour of Shorts/FCM unverified; hosted video and Google/OTP absent. |
| FastAPI backend | **NO-GO** | Shorts regression with failing tests; no rate limiting; DB suite not run. |
| Flutter Web admin | **CONDITIONAL GO** | Builds; 1 failing test; content-management gaps. |
| Database | **UNVERIFIED** | Schema reflected from live DB (no models in code); migrations not inspected for drift; not executed. |
| Push notifications | **NO-GO (unproven)** | Code complete and tested with fakes; no evidence of real FCM configuration. |
| Video and Shorts | **NO-GO** | Feed duplication; hosted playback blocked. |
| **Overall production** | **NO-GO** | Resolve P0 1–3, then re-audit. |

*Not claimed:* anything about production configuration, real FCM delivery, S3 storage, live YouTube API behaviour, or on-device Shorts playback. None could be observed from source.
