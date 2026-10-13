# Feature Implementation Matrix and Delivery Report

Date: 2026-10-13. Nothing in this work was committed, pushed or applied to the
production database. Every status below is backed by code in this repository and
a test that was actually run; "unverified" is stated where it applies.

## 1. Verification results

| Check | Result |
|---|---|
| `flutter pub get`, `dart format --set-exit-if-changed lib test`, `flutter analyze` (app) | clean |
| `flutter test` (app) | **790 passed**, 1 opt-in live test skipped (baseline was 583) |
| `flutter analyze` / `flutter test` (admin panel) | clean / **30 passed**, 1 opt-in live test skipped |
| Backend `pytest` against a disposable local PostgreSQL 17 holding the production schema | **152 passed** (baseline: 15 passed + 2 failing tests, both test defects, fixed without weakening assertions) |
| Migrations 0001–0006: upgrade → re-run → downgrade → upgrade | passed (local scratch DB) |
| Real `uvicorn` + real DB (committed writes), 39-step journey script | **39/39** |
| App repositories against that live server (`test/integration/live_contract_test.dart`) | passed |
| Admin API layer against that live server (`balkavach-admin/test/live_contract_test.dart`) | passed |
| OpenAPI backward-compatibility guard (70 published operations) | passed |
| Unauthenticated-access sweep over every non-public operation | passed |
| Tenant-isolation sweep (25 cross-family attempts) | passed |
| Debug APK (`flutter build apk --debug`, no Firebase file present) | built |
| Admin panel `flutter build web --release` | built |
| Responsive/accessibility suite (320, 360, 393, 600, 840 px; 2× text; Gujarati/Hindi; landscape; contrast; tap targets) incl. all new screens | passed |
| **Physical device or emulator** | **never run.** No device or AVD exists on this machine. No claim is made. |
| Real FCM delivery, real object storage | **not exercised** (need your accounts; see section 4) |

## 2. Feature matrix

`Done` = works and is tested end to end. Backend/DB/auth/test columns are summarised
per row; endpoints are listed in `api-integration-matrix.md`.

| # | Feature | App | Backend | DB | Auth / isolation | Evidence | Notes |
|---|---|---|---|---|---|---|---|
| 1 | Parent register / login | Done | Done | existing | public; 12+ char passwords | app + backend + live | Phone OTP and Google: **not built** (need provider accounts) |
| 2 | Session restore, expiry, refresh | Done | Done | `auth_sessions` (0002) | rotation, reuse detection, server-side revoke, `sid` claim | 17 app + 10 backend + live | Sign-in still works if the migration is missing |
| 3 | Family create/list | Done | Done | existing | parent, membership | backend + live | |
| 4 | Child profile create/edit/deactivate | Done | Done | existing | parent, family-scoped | app + backend | Avatar picture is device-only (labelled) |
| 5 | Secure child mode | Done | Done | `auth_sessions` | child token cannot reach parent routes; no parent credentials in child mode; parent can end a child's devices | app + backend + live | No parent PIN (leaving child mode signs out) |
| 6 | Mission create/edit/remove, due dates, categories, presets | Done | Done | `preset_tasks` (0005) | parent | app + backend | `repeat_rule` unused |
| 7 | Mission list + pagination | Done | Done | existing | child sees own/open | app + backend | App follows pages of 100, up to 500 |
| 8 | Child submits (note or photo) | Done | Done | `proof_uploads` (0004) | child; owner-only photo | app + backend + live | Duplicate pending/completed submissions refused |
| 9 | Photo proof | Done | Done | `proof_uploads` | owner child / family parents only; EXIF stripped; ≤5 MB; JPEG/PNG/WebP decoded | app + backend + live | **Production needs S3 storage** (local disk is ephemeral) |
| 10 | Parent pending notification | Done | Done | existing | recipient-only | all | In-app; push optional |
| 11 | Parent review: approve / reject / ask again, note | Done | Done | existing | family member | all | One family-wide queue endpoint replaces per-task fan-out (falls back for old servers) |
| 12 | Child sees status, history, parent's note | Done | Done | existing | child own | app + backend + live | |
| 13 | Stars / XP awarded once | Done | Done | ledger | idempotent keys | backend + live | |
| 14 | Levels | Done | Done | `levels` seed (0001) | – | backend + live | **Production `levels` was empty**; thresholds are proposed defaults needing sign-off |
| 15 | Badges | Done | Done | `badges` seed (0001) | – | backend + live | Fixed a 500 on `/progress` for any child with a badge |
| 16 | Streaks | Done | Done | existing | – | backend | Days cut in the family's time zone |
| 17 | Parent reward management | Done | Done | existing | parent, family | app + backend | `video_time` rewards remain admin-set-up |
| 18 | Child reward catalogue | Done | Done | existing | child → own family | app + backend + live | Old servers show "coming soon" |
| 19 | Redemption request (idempotent, no double-ask, stars reserved) | Done | Done | existing | child | app + backend + live | |
| 20 | Parent approve / decline / mark given / cancel+refund | Done | Done | existing | family | app + backend + live | Stars move only on the server |
| 21 | Reward status history | Done | Done | existing | child own | app + live | |
| 22 | Garden stage + unlockable items | Done | Done (derived) | none | – | app + backend + live | Stage from XP, items from badges; no client state |
| 23 | Weekly report (tz-correct, categories, pending, navigable) | Done | Done | existing | parent / child own | all | |
| 24 | Native sharing | Done | n/a | – | – | app (fake sharer) | Real share sheet **unverified on device** |
| 25 | Settings: persisted vs local | Done | Done | `user_settings`, `family_settings` | – | app + backend | Time zone auto-set once; email toggle replaced by an honest "not sent yet" note; "what is saved where" panel |
| 26 | Consent version handling | Done | Done | `app_settings` (0006) | admin-edited, public read | app + backend + live | Re-consent triggered by a new version; legal must confirm text |
| 27 | Privacy & safety information | Done | n/a | – | – | app | Every statement describes enforced behaviour |
| 28 | Sign-out and cleanup | Done | Done | – | unregisters push token first; ends server session | app | |
| 29 | Learning section (categories, list, detail, links, states) | Done | Done | existing | child | app + backend + live | Curated https links open outside the app; hosted video needs a playback provider (unverified) |
| 30 | Admin-managed content | Done | Done | existing | `content:*` | admin + backend + live | |
| 31 | Push notifications (all 9 flows) | Done | Done | `device_tokens` (0003) | per-user token; generic text only; honours preference | app + backend (fakes) | **Needs Firebase** (`push-notifications-setup.md`); not delivered to a real phone |
| 32 | Web admin panel | Done | Done | – | role/permission per section and per endpoint; audit log | 30 admin + 39 backend + live | Flutter Web; tokens in memory only |
| 33 | Localisation en / hi / gu | Done | push text too | – | – | parity test | Hindi/Gujarati strings written by me: **needs native-speaker review** |
| 34 | Responsive, 2× text, accessibility | Done | n/a | – | – | responsive suite | |
| 35 | Quizzes / learning progress | **Not built** | – | – | – | – | Outside the agreed scope notes; needs sign-off |
| 36 | Email notifications | **Not built** | – | – | – | – | Stated in the app |

## 3. Bugs found in existing code and fixed

1. `/progress` returned 500 for any child with a badge (wrong row attribute names).
2. `GET/PATCH /settings/me` and `PATCH /settings/families/{id}` returned 500 whenever a row existed (missing `from_attributes`). Production already holds a `user_settings` row, so the live parent-settings screen would have failed.
3. Alembic never committed (reflection opened a transaction), so no migration could ever take effect.
4. Hosted-video playback and heartbeats raised `TypeError` on rows loaded from PostgreSQL (aware vs naive datetimes).
5. Admin permission strings never matched the seeded `content_manager` role.
6. Production `levels` and `badges` were empty, so no child could level up or earn a badge.
7. Two backend tests had defects (reserved `.test` e-mail domain; missing flush).
8. Found by my own checks along the way: admin panel `setState` returning a Future; admin `204` replies crashing the API layer; a spurious unauthenticated settings call from push registration.

I also made one mistake worth disclosing: a patch script of mine truncated
`create_mission_screen.dart` (which held uncommitted work). I recovered the exact
original from the compiled kernel artefact, verified it compiles and that the
existing suite passed unchanged, and re-applied my change. Please diff that file
against your own copy if it matters to you.

## 4. What you must supply or decide

- **Database owner approval** to run migrations 0001–0006 (`backend-operations.md`); confirm the default level/badge numbers.
- **Firebase project**, `google-services.json`, and an FCM service account for push.
- **S3-compatible bucket** and credentials for production photo storage.
- First admin via `python -m app.cli create-admin`; set `CORS_ORIGINS` to the panel's origin.
- Legal text/version for consent; native review of Hindi and Gujarati wording.
- Decisions on out-of-scope items: phone OTP / Google sign-in, quizzes, parent PIN, email notifications, rate limiting.

## 5. Remaining risks

No rate limiting or lockout on login/register/upload; no cleanup job for unattached
photos; no iOS build; push, S3 and share sheet unverified against real services;
nothing run on a device.

## 6. Files changed

Counts from `git status` (all uncommitted). Run `git status --short` for the exact
list; the groups are:

- **Backend** (`balkavach-backend/`): new `app/api/v1/{admin_manage,app_config,uploads}.py`, `app/cli.py`, `app/core/permissions.py`, `app/db/seed_data.py`, `app/integrations/{fcm,storage}.py`, `app/schemas/{admin_manage,upload}.py`, `app/services/{app_settings,device,garden,push,report,session,timezone,upload}_service.py`, `alembic/versions/0001–0006`, `requirements-storage-s3.txt`, 14 new test files plus `tests/contracts/openapi_baseline.json`; edited `alembic/env.py`, routers (auth, tasks, rewards, reviews, progress, notifications, admin, educational_content), services (auth, task, reward, notification, progress, video_access), schemas, `core/{config,dependencies,security}.py`, `db/{base,session}.py`, `integrations/__init__.py`, `requirements.txt`, `.env.example`, `.gitignore`, `tests/conftest.py`, `tests/test_flows_integration.py` (two test defects).
- **App** (`balkavach-frontend/`): new `lib/core/{config/runtime_config,push}`, `lib/features/{learning,notifications,rewards/presentation/parent_rewards_screen,reward_form_screen}`, `lib/shared/{media,platform}`, 14 new test files; edited session/auth, network, missions, approvals, rewards, progress/report, garden, settings, parent hub, child shell, routing, `app.dart`, `bootstrap.dart`, l10n (en/hi/gu), `pubspec.yaml`, Android manifest and Gradle files, shared test helpers, and the existing tests whose contracts intentionally changed (photo proof, rewards shop, email row, onboarding request).
- **Admin panel**: new `balkavach-admin/` project.
- **Docs**: this file, `backend-operations.md`, `push-notifications-setup.md`; `api-integration-matrix.md`, `frontend-functional-audit.md`, `frontend-architecture.md` carry update notes pointing here.
