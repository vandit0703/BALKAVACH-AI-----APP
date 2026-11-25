# BALKAVACH — Security & Child-Safety Audit

**Audit Date:** 2026-11-25
**Repository:** `C:\Users\PC\BALKAVACH-AI-----APP`
**Branch / HEAD:** `main` @ `36a7c069d69cb7a5b1ac148bbcb3ee7fd46cb8bf` (plus uncommitted working-tree changes)
**Scope:** FastAPI backend (`balkavach-backend`), Flutter Android app (`balkavach-frontend`), Flutter Web Admin (`balkavach-admin`), database schema/migrations, and deployment configuration.

---

## 1. Executive Security Summary

BALKAVACH is a child-focused product where security, family isolation, and child-safety enforcement are **P0 release gates**.

### What Improved Recently (Verified in Code)
1. **Unsafe Parent-PIN Bypass Removed (`SEC-01` fixed):** The previously vulnerable unauthenticated `POST /api/v1/auth/parent-pin/verify` endpoint has been removed and replaced with a `410 Gone` tombstone (`verify_parent_pin_removed` in `balkavach-backend/app/api/v1/auth.py`). Leaving child mode now requires `POST /api/v1/auth/parent-mode/enter`, which requires an active child bearer token (`require_child`) and verifies the parent's email + password against the child's family (`enter_parent_mode`), with per-account, per-family, and per-session failure tracking (`parent_mode_service.py`, `attempt_lockout.py`).
2. **Session Revocation & Token Security:** Access tokens use HS256 JWTs with `sub`, `iat`, `exp`, and `sid` (`app/core/security.py`). Every authenticated request checks `is_session_revoked(session, sid)` (`app/core/dependencies.py`). Refresh tokens use rotation with reuse detection.
3. **Quiz Reward & Grading Integrity:** Quiz grading is 100% server-side (`app/services/quiz_service.py`). Correct answers are never sent before submission. Quiz rewards use `quiz_reward_grants` with `UNIQUE (child_id, quiz_id)` and idempotent ledger keys.
4. **Password Change & Logout-All:** `POST /api/v1/auth/password/change` and `POST /api/v1/auth/logout-all` are implemented (`auth.py`).

### Remaining Critical & High Security Risks
1. **P0 — Client-Trusted YouTube Playback Metering:** `GET /api/v1/videos/feed` and `GET /api/v1/videos/shorts` return `youtube_video_id` regardless of remaining video allowance. The playback lock is a Flutter UI reaction (`_stopForExhaustedAllowance`), while server-side enforcement only rejects `POST /videos/watch-history/{id}/progress` with `403 video_time_exhausted`. A modified client or direct API consumer can still retrieve YouTube IDs and watch outside the app.
2. **P0 — Unconfigured Production Secret / Deployment Verification:** `NOTES` and `BALkAVACH_CURRENT_STATE_AUDIT.md` flagged a gitignored `notes.txt` containing a production SSH root-password login transcript (`SEC-08`). Root password SSH access must be disabled, credentials rotated, and `.env` / FCM / S3 / JWT secrets verified in production.
3. **P1 — Custom Mission Reward Amounts Not Fixed Server-Side:** `TaskCreate` (`app/schemas/task.py`) accepts arbitrary `star_reward` (`0..10000`) and `xp_reward` (`0..100000`) from parents rather than enforcing the product rule of 10 Stars / 15 XP.
4. **P1 — Free Daily Video Allowance Conflicts with Policy:** `FREE_DAILY_ALLOWANCE_SECONDS = 900` (`video_entitlement_service.py`) gives every child 15 free minutes/day without completing a mission.
5. **P1 — Runtime SQLAlchemy `automap` Reflection (`app/db/base.py`):** Models are reflected from the database at runtime rather than declared statically, meaning schema drift or missing migrations (e.g., `0021_quiz_system.py` not yet applied to production) can cause runtime 500s or subtle bugs.
6. **P1 — Admin Panel Test Failures & Missing Inactivity Timeout:** The syntax error in `balkavach-admin/lib/pages/youtube_reviews_page.dart:26` has been fixed so `balkavach-admin` compiles, but 5 widget/unit tests fail (including 4 in `youtube_reviews_test.dart`). Admin tokens are stored in memory (`TokenStore`), which is good against XSS persistence, but there is no idle session timeout.

---

## 2. Vulnerability & Child-Safety Register

| ID | Severity | Category | Affected Location | Realistic Impact / Exploit Scenario | Safe Local Verification | Remediation |
|---|---|---|---|---|---|---|
| **SEC-01** | **P0** | Child Safety / Video Limits | `balkavach-backend/app/api/v1/videos.py`, `video_watch_history_service.py` | `GET /videos/feed` and `/videos/shorts` return `youtube_video_id` even when `remaining_seconds == 0`. A child or modified client can extract the YouTube ID and watch unrestrictedly. | Inspect `/videos/feed` response when allowance is 0. | Omit `youtube_video_id` / playback URLs when `remaining_seconds <= 0`, or gate playback behind short-lived play tickets (`video_play_tickets`). |
| **SEC-02** | **P0** | Infrastructure / Credentials | `notes.txt` (gitignored), production host | Historical root-password SSH transcript in local `notes.txt` indicates password-based root SSH was used. Compromise grants full DB/JWT/FCM access. | Confirm `notes.txt` is gitignored; do not read/expose secrets. | Disable SSH password auth (`PasswordAuthentication no`), disable root SSH login, rotate DB/JWT/SMTP/YouTube/FCM secrets. |
| **SEC-03** | **P0** | Admin Availability / RBAC | `balkavach-admin/lib/pages/youtube_reviews_page.dart`, `test/youtube_reviews_test.dart` | Compile error (`C  onsumerStatefulWidget`) was fixed, but 4 YouTube moderation tests fail (`category_id` vs `category` contract mismatch, channel detail & Discover More) + 1 l10n test fails, indicating YouTube moderation regressions. | Run `flutter test` in `balkavach-admin`. | Align `youtube_reviews_page.dart` payload/UI with backend contract and fix the 5 failing tests. |
| **SEC-04** | **P1** | Business Logic / Reward Integrity | `balkavach-backend/app/schemas/task.py:32-33`, `app/api/v1/tasks.py:151-152` | `TaskCreate` allows `star_reward` up to `10000` and `xp_reward` up to `100000`. A compromised or scripted parent client can mint inflated Stars/XP. | Submit `POST /tasks` with `star_reward=10000` in local test. | Enforce server-side `MISSION_STAR_REWARD = 10` and `MISSION_XP_REWARD = 15` (or explicit admin-capped policy) in `task_service.py`. |
| **SEC-05** | **P1** | Database / Migration Safety | `balkavach-backend/alembic/versions/0015_*`, `0017_*`, `0020_*` | Revision IDs exceed 32 characters (up to 37 chars). Default Alembic `alembic_version.version_num` is `VARCHAR(32)`, causing `alembic upgrade head` to fail on a fresh Postgres DB. | Run `alembic upgrade head` on a fresh Postgres DB. | Add an early/pre-flight migration or `env.py` check ensuring `alembic_version.version_num` is `VARCHAR(64)+`. |
| **SEC-06** | **P1** | Child Safety / Video Allowance | `balkavach-backend/app/services/video_entitlement_service.py` | `FREE_DAILY_ALLOWANCE_SECONDS = 900` grants 15 minutes/day before any mission is approved, contradicting "complete a mission to earn 15 minutes". | Check `GET /video-access/allowance` for a child with 0 approved missions. | Confirm product policy; if strict mission-gated, set `FREE_DAILY_ALLOWANCE_SECONDS = 0`. |
| **SEC-07** | **P2** | Privacy / Account Deletion | `balkavach-frontend`, `balkavach-backend` | No self-service account deletion or data export endpoint/UI exists (required by Google Play Store Data Safety policy for child-directed / family apps). | Search `app/api/v1/` for `delete` account/family routes. | Implement `DELETE /auth/account` (or family deletion workflow with grace period) and privacy policy / data deletion URLs. |
| **SEC-08** | **P2** | Security / Dual Metering Path | `balkavach-backend/app/api/v1/video_access.py`, `video_watch_history_service.py` | Two separate metering systems exist (`/video-access/sessions`+`heartbeats` vs `/videos/watch-history/{id}/progress`). Enabling `VIDEO_PLAYBACK_PROVIDER` without disabling the other risks double deduction. | Inspect `video_access.py` and `video_watch_history_service.py`. | Consolidate onto a single server-authoritative metering path and remove or disable the unused one. |
| **SEC-09** | **P2** | Audit / Admin | `balkavach-admin/lib/core/session.dart` | Admin panel has no idle session timeout or explicit CSRF/origin lock documentation beyond CORS `cors_origins`. | Inspect `session.dart`. | Add idle timeout warning/sign-out in admin web app and verify `CORS_ORIGINS` in production. |

---

## 3. Authentication, Authorization & Child-Safety Verification Checklist

| Control | Status | Evidence |
|---|---|---|
| Password hashing (Argon2 via `pwdlib`) | **DONE** | `balkavach-backend/app/core/security.py` (`PasswordHash.recommended()`) |
| JWT expiry & signature validation | **DONE** | `decode_access_token` requires `sub`, `exp`, validates `HS256`, secret >= 32 bytes |
| Session revocation check on every request | **DONE** | `get_current_user` calls `is_session_revoked(session, sid)` |
| Refresh token rotation & reuse detection | **DONE** | `session_service.py` + `POST /auth/refresh` |
| Rate limiting & lockout (Redis-backed) | **DONE** | `app/core/rate_limit.py`, `app/services/attempt_lockout.py` |
| Parent-mode step-up auth (`email` + `password` from child session) | **DONE** | `POST /auth/parent-mode/enter`; legacy `POST /auth/parent-pin/verify` returns `410` |
| Role isolation (`require_parent`, `require_child`, `require_admin_permission`) | **DONE** | `app/core/dependencies.py` |
| Family ownership checks on child data | **DONE** | `progress.py`, `quizzes.py` (`parent_child_quiz_history`), `rewards.py`, `tasks.py` |
| Child self-signup disabled (parent creates child) | **DONE** | `POST /families/{id}/children` (`require_parent`) |
| Server-side quiz grading & one-time reward grant | **DONE** | `quiz_service.py` (`_grade`, `uq_quiz_reward_grants_child_quiz`) |
| Mission approval idempotency (10 Stars / 15 XP once) | **PARTIAL** | Idempotency keys in `task_service.py`, but `TaskCreate` allows custom `star_reward`/`xp_reward` |
| Client-side secure token storage | **DONE** | `SecureSessionStorage` (`flutter_secure_storage`, Android Keystore) |
| Server-side YouTube video lock (anti-bypass) | **PARTIAL** | Progress metering enforced, but `youtube_video_id` still returned in feed when allowance is 0 |
| Account deletion & data export | **MISSING** | Not implemented in backend or Flutter |
