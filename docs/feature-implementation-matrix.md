# Feature Implementation Matrix and Release Readiness

Audit date: 2026-10-14. Nothing was committed, pushed, merged, or applied to
production. The working tree was clean at audit start.

## 1. Release-readiness decision and current evidence

**NO-GO for production deployment.** The implementation contains substantial
release functionality, but this audit could not establish a passing staging
run, current migration execution, installable builds, real storage durability,
or device push delivery. Product and operational decisions listed below are
also outstanding.

| Area | Verified in this audit | Not verified / evidence limit |
|---|---|---|
| Migrations and progression seeds | Read all six migration scripts and `seed_data.py`; exact effects and rollback risks are recorded in `backend-operations.md`. The chain is 0001 → 0002 → 0003 → 0004 → 0005 → 0006. | No database was configured, so no upgrade, repeat, downgrade, schema comparison, or production-data inspection was performed in this audit. Prior delivery notes' scratch-DB results are historical claims, not reproduced here. |
| Database tests | `tests/conftest.py` requires `TEST_DATABASE_URL`, checks for `test` in the database name, compares host/port/database with `DATABASE_URL` when configured, and wraps API tests in a rolled-back outer transaction. | The `TEST_DATABASE_URL` environment variable was unset. A backend `.env` file exists but was not inspected or used. The fixture's name/equality checks do not prove that a database is disposable. The `test_health.py` schema reflection test uses `DATABASE_URL`, not the isolated fixture. No DB integration tests ran here. |
| Backend auth/admin | Source implements Argon2 password hashing, signed expiring access tokens, hashed refresh-token storage, rotation, role checks, per-route permission dependencies, and audit writes on admin mutations. CORS uses configured origins. | No live/staging API or end-to-end permission/CORS/audit test was run here. Replay detection stores only the immediately previous refresh-token digest; replay of an older rotated token is rejected but does not revoke the session. Login/register/upload rate limiting and lockout are absent. |
| Photos | Source validates decoded JPEG/PNG/WebP, strips metadata, resizes, enforces byte and unattached-count limits, authorizes owner/family reads, and serves through a private authenticated API URL with restrictive headers. S3 objects are written without a public ACL. | Upload tests configure temporary local storage. Neither S3-compatible storage nor durable production persistence was exercised; no signed/public URL is implemented. A request-body cap at the proxy/server layer and orphan cleanup remain operational requirements. |
| Push | Source contains generic localized payload text and exactly `{type, notification_id}` data; authenticated registration assigns a token to the latest registering user. Ten notification type strings exist in source. | Existing tests use fakes. The `task_resubmission_requested` path has no explicit assertion; FCM delivery, Firebase configuration, token invalidation at Google, and real-device receipt were not verified. Transient provider failures and failed sign-out unregisters have no durable retry; a stale server token can remain. |
| API/client compatibility | The repository has an OpenAPI operation-presence baseline test and documents known behavior changes for old clients. | No tests ran here. The baseline protects operation names only; it does not establish full request/response or deployed-client compatibility. |
| App/admin builds | Tool discovery found Java only; `flutter`, `dart`, and `adb` were unavailable, and no existing APK/web build artifact was found. | Debug APK build/install, admin web build/launch, emulator/device testing, and responsive runtime checks could not be performed. |
| Staging | None. No staging endpoint was used. The backend `.env` file was not inspected, so its configured targets are unknown. | The earlier report's pass counts and migration/live-server results cannot be represented as staging evidence for this audit. |

The IDE test runner attempt reported “No tests found in the files” for the
Python backend test paths. It did not execute tests. No assertions were changed
or weakened. See `backend-operations.md` for the required staging gates,
migration-by-migration risk, owner decisions, and rollback plan.

## 2. Feature matrix

`Done` reflects the implementation status recorded in the earlier delivery
report; it is not a claim that a test ran or that a feature passed staging in
this audit. Backend/DB/auth/test columns are summarised per row; endpoints are
listed in `api-integration-matrix.md`.

| # | Feature | App | Backend | DB | Auth / isolation | Evidence | Notes |
|---|---|---|---|---|---|---|---|
| 1 | Parent register / login | Done | Done | existing | public; 12+ char passwords | app + backend + live | Phone OTP and Google: **not built** (need provider accounts) |
| 2 | Session restore, expiry, refresh | Done | Done | `auth_sessions` (0002) | rotation, immediate-previous-token replay revocation, server-side revoke, `sid` claim | Earlier report records app/backend/live tests; not rerun here | Older rotated refresh-token replay is rejected but does not revoke the session; sign-in degrades if migration is missing |
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
| 14 | Levels | Done | Done | `levels` seed (0001) | – | Earlier report records backend/live tests; not rerun here | Earlier report claimed production `levels` was empty; not checked in this audit. Thresholds are proposed defaults needing sign-off |
| 15 | Badges | Done | Done | `badges` seed (0001) | – | Earlier report records backend/live tests; not rerun here | Badge-related `/progress` fix is recorded in the earlier report; production badge rows were not inspected here |
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
| 31 | Push notifications (10 type strings / event variants) | Implemented in source | Implemented in source | `device_tokens` (0003) | per-user token; generic text only; honours preference | Existing tests use fakes; not run in this audit | **Needs Firebase** (`push-notifications-setup.md`); not delivered to a real phone; resubmission push lacks an explicit test assertion |
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
- Confirm whether push is a launch requirement; decide whether the resubmission-request event is a separate push type from rejection.
- Decide and implement login/register/upload abuse controls (rate limits and lockout policy); these are currently absent.
- Decide whether session-theft detection must cover every rotated refresh token. Current schema retains one prior digest only, so earlier-token replay does not revoke the session.
- Confirm old-client behavior changes documented in section 8 of `backend-operations.md`.
- Decisions on out-of-scope items: phone OTP / Google sign-in, quizzes, parent PIN, and email notifications.

## 5. Remaining release blockers

| Gate | Status / action required |
|---|---|
| Staging and database safety | No staging test or migration cycle ran in this audit. Run all migrations and backend tests against independently verified disposable PostgreSQL; inspect skips and record evidence before production approval. |
| Product/data approval | The level and badge defaults are proposed and can alter progression/badge outcomes on later mission approvals. Product owner must approve them and database owner must approve the migration window and backup/PITR plan. |
| Photo persistence | Production must use private object storage. Configure and verify a nonproduction S3-compatible bucket, authorization, persistence across deploy/restart, and retention before enabling photo proof in production. |
| Authentication abuse controls | Login, registration, and upload have no rate limiting or lockout. Security/operations must implement or explicitly accept an approved mitigation before public release. Decide whether refresh-token replay detection must cover all prior rotations; current code only revokes on replay of the immediately previous token. |
| Installable clients | This environment had no Flutter, Dart, or ADB tools and no built artifacts. Build app/admin, install and exercise the APK on a test device, and launch/smoke-test admin web in a browser in CI/staging. |
| Client compatibility | Review stricter submission and redemption behaviors with supported older clients and execute staging smoke tests; the OpenAPI baseline alone checks operation presence. |
| Conditional: push | If push is in scope, provide Firebase client configuration and server-only credentials, add/assert the resubmission event test, exercise real FCM delivery on Android, and decide whether transient delivery and sign-out unregistration require durable retry. Verify shared-device behavior on unregister failure. Otherwise explicitly launch with in-app notifications only. |
| Legal/localization | Approve consent text/version and obtain native-speaker review of Hindi/Gujarati before releasing those user-facing strings. |

Unattached-photo cleanup, iOS/APNs, hosted-video provider, share-sheet behavior,
and out-of-scope phone/Google sign-in, quizzes, parent PIN, and email remain
follow-up or scope decisions. No production migration, device test, push
delivery, or durable photo-storage test was performed here.

## 6. Changes in this audit

At audit start `git status --short` was empty. The release-readiness documentation
was updated locally only; no application source, migration, database, build
artifact, or production environment was changed.
