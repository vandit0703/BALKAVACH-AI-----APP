# BALKAVACH — Production Release Checklist & Roadmap

**Audit Date:** 2026-11-25
**Verdict:** **NO-GO** (Multiple P0 blockers across Admin build, Video security, Database migrations, and Play Store compliance).

---

## 1. Release Prerequisites Checklist

| Area | Item | Status | Evidence / Blocker |
|---|---|---|---|
| **Admin Panel** | Compiles and passes `flutter analyze` + `flutter test` | **FAIL (TESTS)** | Compiles (`flutter analyze`: 0 errors, 1 warning), but `flutter test` has **5 failures** (4 in `youtube_reviews_test.dart`, 1 in `localization_ui_test.dart`; 94 passed, 1 skipped) |
| **Admin Panel** | Contract alignment: React/Next.js vs Flutter Web | **OPEN** | Signed agreement specifies React/Next.js; repo has Flutter Web |
| **Admin Panel** | Missing pages: Notifications & Reports | **MISSING** | Not present in `kSections` (`balkavach-admin/lib/app.dart`) |
| **Backend** | Pure unit tests pass | **RUNNING / PARTIAL** | DB-backed tests skipped locally without `TEST_DATABASE_URL` |
| **Backend** | Gate `youtube_video_id` when video allowance is 0 | **FAIL** | `GET /videos/feed` & `/shorts` still return `youtube_video_id` |
| **Backend** | Unify video metering (`/videos/watch-history` vs `/video-access`) | **PARTIAL** | Dual metering paths exist |
| **Backend** | Enforce 10 Stars / 15 XP on custom tasks server-side | **FAIL** | `TaskCreate` allows `star_reward` 0..10000 |
| **Database** | Apply `0021_quiz_system.py` + `0017` fix safely | **UNVERIFIED** | Uncommitted locally; production Neon DB state not verified |
| **Database** | `alembic_version.version_num` column width >= 64 | **FAIL / RISK** | Revision IDs up to 37 chars exceed Alembic's default `VARCHAR(32)` |
| **Mobile App** | `flutter analyze` zero errors | **PASS (1 info)** | 1 `unawaited_futures` info in `shorts_navigation_regression_test.dart` |
| **Mobile App** | Android release signing (`android/key.properties` + keystore) | **PRESENT (LOCAL)** | `key.properties` exists locally; actual `flutter build appbundle --release` not run |
| **Mobile App** | `API_BASE_URL` production endpoint (`https://api.balkavach.tech`) | **CONFIGURED** | `app_config.dart` default; live TLS/health unverified |
| **Mobile App** | Privacy Policy, Terms & Account Deletion workflow | **MISSING** | No account deletion endpoint/UI (Play Store Data Safety blocker) |
| **Mobile App** | Replace romanized `gu`/`hi` daily mission seed text | **FAIL** | `0015_daily_mission_engine.py` uses Latin transliteration |
| **Security** | Rotate prod secrets & disable root password SSH (`SEC-08`) | **UNVERIFIED** | Local `notes.txt` historical SSH transcript flagged |
| **Push / Email** | Verify live FCM delivery & SMTP password reset in staging | **UNVERIFIED** | No live credentials/device test performed |

---

## 2. Prioritized Remaining Work Roadmap

### P0 — Critical Security, Data Integrity & Release Blockers
1. **Fix 5 Failing Admin Panel Tests (`balkavach-admin`)** — *Complexity: S*
   - **Files:** `balkavach-admin/lib/pages/youtube_reviews_page.dart`, `lib/pages/youtube_channel_detail_page.dart`, `lib/l10n/`
   - **Fix:** (`youtube_reviews_page.dart:26` compile error is already fixed.) Resolve the `category_id` vs `category` contract mismatch, channel detail/Discover More failures in `youtube_reviews_test.dart`, and hardcoded string literal in `localization_ui_test.dart`.
   - **Acceptance:** `flutter analyze` = 0 errors; `flutter test` = 100% pass; `flutter build web` succeeds.
2. **Enforce Server-Side Video Allowance on Feed Responses** — *Complexity: M*
   - **Files:** `balkavach-backend/app/api/v1/videos.py`, `app/services/video_service.py`
   - **Fix:** Omit `youtube_video_id` (and playable URLs) when `remaining_seconds <= 0`, or require short-lived play tickets. Decide whether `FREE_DAILY_ALLOWANCE_SECONDS = 900` should be `0`.
   - **Tests:** Backend API test verifying `youtube_video_id` is null/redacted when allowance is 0.
3. **Database Migration Graph & `alembic_version` Width + `0021` Rollout** — *Complexity: M*
   - **Files:** `balkavach-backend/alembic/versions/0017_child_video_daily_allowance.py`, `0021_quiz_system.py`, `alembic/env.py`
   - **Fix:** Ensure `alembic_version.version_num` is `VARCHAR(64)+` before running migrations; run full `pytest` against disposable Postgres with `baseline.sql` + `alembic upgrade head`; commit uncommitted quiz/achievement changes cleanly.
4. **Account Deletion & Data Safety Compliance (Play Store)** — *Complexity: L*
   - **Files:** `balkavach-backend/app/api/v1/auth.py`, `balkavach-frontend/lib/features/settings/`
   - **Fix:** Implement authenticated `DELETE /api/v1/auth/account` (with password confirmation & cascade/anonymization) and wire it into `ParentSettingsScreen`, plus hosted Privacy Policy / Terms URLs.
5. **Production Secret Rotation & SSH Hardening** — *Complexity: S*
   - **Fix:** Disable root password SSH, rotate DB/JWT/SMTP/YouTube/FCM secrets, delete `notes.txt`.

### P1 — Core Functionality & Integration
6. **Enforce Mission Reward Constants Server-Side** — *Complexity: S*
   - **Files:** `balkavach-backend/app/schemas/task.py`, `app/services/task_service.py`
   - **Fix:** Force `MISSION_STAR_REWARD = 10` and `MISSION_XP_REWARD = 15` on task creation/update unless admin-overridden.
7. **Fix Daily Mission Pool Exhaustion & Gujarati/Hindi Seed Content** — *Complexity: L*
   - **Files:** `balkavach-backend/app/services/daily_mission_service.py`, `alembic/versions/0015_daily_mission_engine.py`
   - **Fix:** Replace permanent exclusion with N-day rotation cooldown; replace romanized `gu`/`hi` strings with proper Gujarati/Hindi script; flush session in `skip_assignment` before `ensure_daily_choices`.
8. **Align Garden Stage, Badge `total_stars`, and Weekly Quiz Reporting** — *Complexity: M*
   - **Files:** `balkavach-frontend/lib/features/garden/presentation/garden_screen.dart`, `balkavach-backend/app/services/achievement_service.py`, `app/services/task_service.py`, `app/services/progress_service.py`
   - **Fix:** Implement the recorded 2026-11-24 product decisions: hybrid XP+weekly garden stage, lifetime earned stars for `total_stars` badges, and quiz summary in weekly reports.
9. **Verify Android Release Build & Live FCM / SMTP** — *Complexity: M*
   - **Fix:** Run `flutter build appbundle --release` locally with `key.properties`, verify Play Store targetSdk/icons/ProGuard, and test live FCM + SMTP reset deep-link on a real Android device.

### P2 — UX, Responsive, Reliability & Quality Improvements
10. **Add Responsive Matrix Tests for New Phase 5/6 Screens & Admin Panel** — *Complexity: M*
    - Add `LearningHubScreen`, `Quiz*Screen`, `StreakScreen`, and `ChildProfileScreen` quiz/achievement cards to `responsive_screens_test.dart`; add responsive tests for `balkavach-admin`.
11. **Implement Admin Notifications & Reports Pages + Help & Support Screen** — *Complexity: M*
    - Add `/notifications` and `/reports` to `balkavach-admin`; add `Help & Support` content in `ParentSettingsScreen`.
12. **Clean Up Duplicate Streak Logic & Dual Video Metering** — *Complexity: S*
    - Remove inline streak calculation in `task_service.py`; deprecate unused `/video-access/sessions` if `/videos/watch-history/{id}/progress` is canonical.

### P3 — Future / Scope-Decision Items
13. **Contract Clarification: Flutter Web Admin vs React/Next.js Admin** — *Client sign-off required.*
14. **Screen 10 (Code/QR Child Linking) & Animated Mitu Panda (Lottie/Rive + TTS)** — *Scope decision required.*
