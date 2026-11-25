# BALKAVACH — Complete Repository Audit, Gap Analysis & Production Readiness Assessment

**Audit Date:** 2026-11-25
**Repository:** `C:\Users\PC\BALKAVACH-AI-----APP`
**Branch / HEAD:** `main` @ `36a7c069d69cb7a5b1ac148bbcb3ee7fd46cb8bf` (`TRUSTED CHANNEL`)
**Working Tree at Audit Start & End:** Dirty with preserved user/developer work (uncommitted Quiz system, migration `0021_quiz_system.py`, `achievement_service.py`, parent quiz history, admin `quizzes_page.dart`, and `0017` revision-id fix; **0** staged changes; **0** files modified by this audit outside the 5 new report files in `docs/`).

---

## 1. Executive Summary (Report A)

| Metric | Result |
|---|---|
| **Production Readiness Verdict** | **NO-GO** |
| **Critical Blockers (P0)** | 5 (Admin test failures [5 failed incl. 4 YouTube trusted-channel tests + 1 l10n], Backend test failures [6 failed incl. 3 YouTube safety tests], Client-trusted YouTube video IDs when allowance=0, Unverified `0021` migration & `alembic_version` column width, Missing Play Store Account Deletion & Prod Secret Rotation) |
| **Features Inspected (Master Matrix)** | **31** (excluding 1 Out-of-Scope row) |
| **Done** | **15** (verified end-to-end in code & local tests, though live DB/FCM remain unverified) |
| **Partial** | **13** |
| **Missing** | **2** (Code/QR child linking [design divergence], Account deletion & data export) |
| **Broken** | **0** (Admin compile error in `youtube_reviews_page.dart:26` was fixed at `12:13`; 5 admin tests and 6 backend tests still fail) |
| **Unverified Live Integrations** | Production Neon DB schema, live FCM push delivery, live SMTP password reset, S3 uploads, Android `bundleRelease` |

### Highest Security & Child-Safety Risks
1. **YouTube Feed Exposes `youtube_video_id` at 0s Allowance (`SEC-01`):** `GET /api/v1/videos/feed` and `/shorts` return `youtube_video_id` even when a child's video allowance is exhausted. The lock is a Flutter UI reaction.
2. **YouTube Trusted-Channel Safety Test Failures (`test_youtube_auto_review.py`):** 3 tests for `test_trusted_discovery_never_publishes_confirmed_safety_restrictions` and `test_trusted_discovery_preserves_explicit_video_rights_denial` **failed** (`assert 0 == 1`) after the `36a7c06 TRUSTED CHANNEL` commit.
3. **Production SSH / Secret Hygiene (`SEC-02`):** A gitignored `notes.txt` in the repo root documents historical root-password SSH access to the production host. Secrets must be rotated and password SSH disabled.
4. **Admin Panel Test Failures (`SEC-03`):** The `youtube_reviews_page.dart:26` syntax error was fixed, so `balkavach-admin` now compiles (`flutter analyze`: 0 errors), but 5 tests fail in `flutter test` (4 in `youtube_reviews_test.dart`, 1 hardcoded string literal in `localization_ui_test.dart`).
5. **Custom Task Reward Amounts (`SEC-04`):** `TaskCreate` (`app/schemas/task.py`) allows `star_reward` up to `10000` and `xp_reward` up to `100000` instead of enforcing 10 Stars / 15 XP server-side.

### Main Integration & Scope Gaps
- **Admin Technology Divergence:** Signed agreement specifies **React / Next.js Web Admin Panel**; repository implements **Flutter Web (`balkavach-admin`)**.
- **Admin Missing Pages:** Notifications management and Reports pages are missing from `balkavach-admin`.
- **Daily Mission Content Quality:** `0015_daily_mission_engine.py` seeds 22 placeholder templates with **romanized** Gujarati/Hindi text and exhausts the pool after ~20 approvals (`503 daily_missions_unavailable`).
- **Garden & Badge Rules:** `GardenScreen` uses weekly missions (4 stages) while backend `garden_service.py` uses lifetime XP (6 stages); `achievement_service.py` uses current `star_balance` instead of lifetime earned stars.
- **Free 15-Minute Allowance:** `FREE_DAILY_ALLOWANCE_SECONDS = 900` grants 15 free minutes/day without completing a mission.

---

## 2. Companion Audit Reports

- **Master Feature Matrix (Report B):** [FEATURE_COMPLETION_MATRIX.md](file:///C:/Users/PC/BALKAVACH-AI-----APP/docs/FEATURE_COMPLETION_MATRIX.md)
- **Screen-by-Screen & Responsive UI Audit (Report C):** [RESPONSIVE_UI_AUDIT.md](file:///C:/Users/PC/BALKAVACH-AI-----APP/docs/RESPONSIVE_UI_AUDIT.md)
- **Security & Child-Safety Audit (Report F):** [SECURITY_AUDIT.md](file:///C:/Users/PC/BALKAVACH-AI-----APP/docs/SECURITY_AUDIT.md)
- **Production Release Checklist & P0–P3 Roadmap (Reports H & I):** [PRODUCTION_RELEASE_CHECKLIST.md](file:///C:/Users/PC/BALKAVACH-AI-----APP/docs/PRODUCTION_RELEASE_CHECKLIST.md)

---

## 3. Backend, API & Database Audit (Report D)

### Architecture & Route Surface
- **Framework:** FastAPI (`balkavach-backend/app/main.py`), **199** HTTP route decorators across `app/api/v1/*.py`.
- **ORM / Reflection:** SQLAlchemy `automap` (`app/db/base.py`, `MODEL_TABLES`) reflects tables at runtime from `public` schema. No static ORM class definitions exist in `app/models/`. Missing migrations in a target database cause runtime failures rather than import-time errors.
- **Auth & Session Security:** `app/core/security.py` (Argon2 + HS256 JWT), `app/core/dependencies.py` (per-request `is_session_revoked` check, `require_parent`, `require_child`, `require_admin_permission`), `POST /auth/parent-mode/enter` (replaces removed `/auth/parent-pin/verify` which now returns `410`).

### Business Logic & Reward Integrity
- **Missions:** `review_submission` (`app/services/task_service.py`) uses idempotency keys `task-approved:{submission.id}:stars` and `:xp`. However, `TaskCreate` (`app/schemas/task.py`) does not lock `star_reward=10` / `xp_reward=15` server-side. `review_submission` also computes an inline streak alongside `streak_service`.
- **Quizzes (Uncommitted):** `app/services/quiz_service.py` grades attempts server-side (`_grade`), never leaks `is_correct` before submission, snapshots `pass_percent`/`star_reward`/`xp_reward` on attempt start, rejects stale quiz revisions (`409 quiz_changed`), and enforces one-time rewards via `quiz_reward_grants` (`UNIQUE (child_id, quiz_id)`). **Not yet tested against a live/test Postgres DB in this environment.**
- **Video Metering:** Dual metering paths exist: live `POST /videos/watch-history/{id}/progress` (`video_watch_history_service.py`) vs unused `POST /video-access/sessions` + `/heartbeats` (`video_access.py`).

### Database & Migration Graph
- **Alembic Chain:** `0001`–`0014` → branch (`0015_daily_mission_engine`, `0015_trusted_channel_upload_discovery`) → merge `0017_child_video_daily_allowance.py` (revision ID `0016_child_video_daily_allowance`) → `0018` → `0019` → `0020` → uncommitted `0021_quiz_system.py`.
- **Version Column Width Risk:** Revision IDs reach 37 chars (`0015_trusted_channel_upload_discovery`), exceeding Alembic's default `VARCHAR(32)` `alembic_version.version_num` on fresh PostgreSQL databases.

---

## 4. Admin Panel Audit (Report E)

- **Framework:** Flutter Web (`balkavach-admin`), **not** React/Next.js as stated in the signed agreement.
- **Current Build Status:** **COMPILES (TESTS FAILING)** — The `youtube_reviews_page.dart:26` syntax error was fixed; `flutter analyze` reports 0 errors (1 unused-element warning in `test/youtube_reviews_test.dart`), and `flutter test` runs with **94 passed, 1 skipped, 5 failed** (1 hardcoded string in `localization_ui_test.dart` + 4 failures in `youtube_reviews_test.dart`, including `category_id` vs `category` key mismatch).
- **Implemented Sections (`lib/app.dart`):** Dashboard, Users, Families, Missions, Categories, Presets, Rewards, Redemptions, Content, YouTube Reviews, Quizzes (uncommitted), Badges, Settings, Audit.
- **Missing Sections:** Notifications management, Reports/Analytics export.

---

## 5. Test & Build Execution Report (Report G)

All commands below were executed directly during this audit on `2026-11-25`:

| Component | Exact Command | Exit Code | Passed | Failed | Skipped | Notes / Root Cause |
|---|---|---|---|---|---|---|
| **Frontend Analyze** | `flutter analyze` (in `balkavach-frontend`) | `0` | — | 0 errors | — | 1 info (`unawaited_futures` in `test/features/shorts_navigation_regression_test.dart:88`) |
| **Frontend Responsive** | `flutter test test/responsive/responsive_screens_test.dart test/responsive/oem_foldable_compatibility_test.dart test/responsive/video_responsive_test.dart --reporter=compact` | `0` | **1000** | 0 | 0 | Verified 320–840px, landscape, OEM/foldables, 1.0x/2.0x text, en/hi/gu |
| **Frontend Core Features** | `flutter test test/features/parent_progress_history_test.dart test/features/progress_milestones_test.dart test/features/learning_hub_quiz_test.dart test/features/approval_flow_test.dart test/features/rewards_flow_test.dart test/features/parent_mode_test.dart --reporter=compact` | `0` | **143** | 0 | 0 | Verified with mocked repositories/Dio adapters |
| **Frontend Localization** | `flutter test test/localization/localization_audit_test.dart test/localization/language_switching_test.dart --reporter=compact` | `0` | **18** | 0 | 0 | 632 ARB keys at parity across en/gu/hi |
| **Admin Analyze** | `flutter analyze` (in `balkavach-admin`) | `0` | — | **0 errors, 1 warning** | — | Unused `_detail` warning in `test/youtube_reviews_test.dart:298` |
| **Admin Tests** | `flutter test --reporter=compact` (in `balkavach-admin`) | `0` (test runner reported failures) | **94** | **5** | **1** | 1 l10n hardcoded string (`localization_ui_test.dart`); 4 in `youtube_reviews_test.dart` (`category_id` vs `category`, channel detail & Discover More) |
| **Backend Pytest** | `.\.venv\Scripts\python.exe -m pytest -q --tb=short` (in `balkavach-backend`) | `1` | **1115** | **6** | **284** | 284 DB tests skipped (`TEST_DATABASE_URL` unset). 6 failures: 1 `UnicodeDecodeError` in `test_play_ticket_rules.py`, 2 `seed` arg mismatches in `test_video_classification.py`, 3 trusted-channel safety failures in `test_youtube_auto_review.py`. |
| **Android Release Build** | *Not run* | — | — | — | — | `android/key.properties` exists locally; `flutter build appbundle --release` not executed in audit |
| **Full Frontend Suite** | *Partial (1,161 tests run across 3 batches)* | — | **1161** | 0 | 0 | Remaining widget/integration test files not executed |
