# Backend operations and deployment

Audience: whoever deploys the FastAPI service and owns the PostgreSQL database.

## 1. Order of operations for this release

The code is written so that **deploying the new service before the migrations
are applied does not break sign-in** (it degrades: no refresh tokens, no push,
no uploads, no presets, no app config, until the tables exist). Even so, apply
the migrations first:

1. Back up the database (Neon: create a branch or use point-in-time restore).
2. Review `balkavach-backend/alembic/versions/0001…0006` (below).
3. Run the migrations with the guard lifted for that one run:

   ```bash
   cd balkavach-backend
   ALLOW_SCHEMA_MIGRATIONS=true DATABASE_URL=… alembic upgrade head
   ```

   Offline SQL generation is deliberately disabled. The run is transactional.
4. Deploy the new backend build.
5. Create the first administrator (section 4).
6. Configure CORS, storage and (optionally) push (sections 5–7).

Nothing in this audit was applied to production. The earlier delivery report
records local scratch-database migration checks, but they were not reproducible
or independently verified in this audit: no test or staging database was used.
The backend `.env` file was intentionally not inspected. See sections 11–13
before scheduling any database operation.

### The migrations

| Revision | Exact effect | Repeatability and downgrade / data risk |
|---|---|---|
| `0001_seed_progression` | Data-only inserts missing levels keyed by `level_number` and badges keyed by `name`. `seed_data.py` proposes levels 1–6 at 0/100/300/700/1500/3000 XP and badges First Mission (1 approved task), Mission Master (10), Star Collector (50 stars), XP Climber (500 XP), Three-Day Streak (3), Week Warrior (7). Existing matching rows are not updated. | Inserts use `ON CONFLICT ... DO NOTHING`, so rerunning the data operation is idempotent for those keys. Downgrade is deliberately a no-op: seeded rows remain. Existing users are not changed by the migration itself, but a later mission approval recalculates level from total XP and evaluates all active badges; a child could gain a level or newly qualify for a badge then. |
| `0002_auth_sessions` | Creates `auth_sessions`: `id UUID NOT NULL DEFAULT gen_random_uuid()` PK; `user_id UUID NOT NULL` cascade FK; `issued_by UUID NULL` set-null FK; `kind VARCHAR(10) NOT NULL`; `refresh_token_hash VARCHAR(64) NOT NULL`; `previous_token_hash VARCHAR(64) NULL`; `device_label VARCHAR(120) NULL`; `created_at TIMESTAMPTZ NOT NULL DEFAULT now()`; nullable `last_used_at TIMESTAMPTZ`; non-null `expires_at TIMESTAMPTZ`; nullable `revoked_at TIMESTAMPTZ`; unique current hash; indexes on `user_id` and `previous_token_hash`; check that kind is parent/child/admin. | Table creation is not manually idempotent; Alembic revision tracking makes a completed `upgrade head` a no-op. Downgrade drops the table and irreversibly removes all refresh sessions, including active sessions. |
| `0003_device_tokens` | Creates `device_tokens`: `id UUID NOT NULL DEFAULT gen_random_uuid()` PK; `user_id UUID NOT NULL` cascade FK; `token TEXT NOT NULL`; `platform VARCHAR(10) NOT NULL`; nullable `app_version VARCHAR(40)`; `is_active BOOLEAN NOT NULL DEFAULT true`; non-null `created_at` and `last_seen_at TIMESTAMPTZ DEFAULT now()`; globally unique token; user index; platform check (`android`, `ios`, `web`). | Alembic-tracked repeat only. Downgrade drops all registrations. Tokens are stored in plaintext for provider use; treat them as credentials and keep them out of API responses/logs. |
| `0004_proof_uploads` | Creates `proof_uploads`: `id UUID NOT NULL DEFAULT gen_random_uuid()` PK; non-null UUID `family_id`, `child_id`, `uploaded_by` cascade FKs; `content_type VARCHAR(40) NOT NULL`; `size_bytes INTEGER NOT NULL`; `sha256 VARCHAR(64) NOT NULL`; `storage_key VARCHAR(255) NOT NULL` unique; nullable UUID `submission_id` FK set null; non-null `created_at TIMESTAMPTZ DEFAULT now()`; `size_bytes > 0` check; child index. It stores metadata only, not photo bytes. | Alembic-tracked repeat only. Downgrade drops authorization/integrity metadata and makes stored objects inaccessible through the API; it does not delete object-store files, so it can leave orphaned objects and incur storage cost. |
| `0005_preset_tasks` | Creates `preset_tasks`: `id UUID NOT NULL DEFAULT gen_random_uuid()` PK; nullable UUID `category_id` and `created_by` FKs set null; `title VARCHAR(180) NOT NULL`; nullable `description TEXT`; `language_code VARCHAR(10) NOT NULL DEFAULT 'en'`; non-null integer suggested star/XP rewards defaulting to 1/10; non-null integer `age_min`/`age_max` defaulting to 3/17; `is_active BOOLEAN NOT NULL DEFAULT true`; non-null `created_at`/`updated_at TIMESTAMPTZ DEFAULT now()`; nonnegative rewards and valid-age-range checks; category index. | Alembic-tracked repeat only. Downgrade drops all admin-created presets. |
| `0006_app_settings` | Creates `app_settings`: `key VARCHAR(80) NOT NULL` PK; `value JSONB NOT NULL`; nullable UUID `updated_by` FK to users with `ON DELETE SET NULL`; non-null `updated_at TIMESTAMPTZ DEFAULT now()`. It does not insert initial settings; the service uses code defaults until values are written. | Alembic-tracked repeat only. Downgrade drops all database overrides; code defaults then apply. |

The revisions are a strict chain: 0001 → 0002 → 0003 → 0004 → 0005 → 0006.
Only 0001 is data-only. The DDL revisions do not use `IF NOT EXISTS`; do not
execute revision functions manually or treat them as independently repeatable.
For PostgreSQL, Alembic runs them within its migration transaction, but that
transaction behavior and the full cycle were not exercised during this audit.

**Product decision needed:** approve or revise the six level thresholds and six
badge names/criteria above before running `0001`. The prior assertion that
production currently has no levels or badges was not verified in this audit;
do not rely on it as current production state.

The migration environment script commits the reflection transaction before
Alembic starts its migration transaction. Source review confirms that ordering;
successful commit behavior still requires a staging/scratch execution.

## 2. Environment variables

See `balkavach-backend/.env.example` for the complete annotated list. New in this
release: `REFRESH_TOKEN_EXPIRE_DAYS`, `CHILD_REFRESH_TOKEN_EXPIRE_DAYS`,
`FCM_SERVICE_ACCOUNT_JSON` / `_FILE`, `STORAGE_PROVIDER`, `UPLOAD_DIR`,
`MAX_UPLOAD_BYTES`, `MAX_UNATTACHED_UPLOADS`, `S3_*`. No secret belongs in the
Flutter apps.

## 3. Roles and permissions

`require_admin_permission` now understands the `resource:action` vocabulary and
maps the dotted names that were seeded in production (`videos.create`,
`categories.manage`, …) so the existing `content_manager` role works without
editing production role rows. Any `x:write` grants `x:read`; `*` grants all.

Permissions used: `dashboard:read`, `users:read|write`, `families:read|write`,
`tasks:read|write`, `rewards:read|write`, `redemptions:read`, `content:read|write`,
`video:read|write`, `badges:read|write`, `settings:read|write`, `reports:read`,
`audit:read`, `admin_roles:read|write`.

Before this release only `super_admin` (`*`) could pass any admin check;
`content_manager` could pass none because its permission strings never matched.
`content_manager` now covers content, categories, presets and video. It has **no**
`reports:read`, `settings:*`, `users:*` or `families:*`; assign `super_admin`
(or create a role) for those.

## 4. Creating the first administrator

There is no registration path for administrators by design.

```bash
cd balkavach-backend
DATABASE_URL=… ADMIN_PASSWORD='a-strong-password' \
  python -m app.cli create-admin --email you@example.com --name "Your Name"
```

The password is taken from the environment or a prompt, never from an argument.
It refuses duplicate emails and passwords shorter than 12 characters.

## 5. CORS for the admin panel

Set `CORS_ORIGINS` to the exact origin that serves the panel, as a JSON array,
for example `["https://admin.example.com"]`. The mobile apps do not use CORS.
The middleware is configured with the origin list and allows `Authorization`,
`Content-Type` and `Idempotency-Key`. Configuration is not validated against
wildcard `"*"`; do not use a wildcard for the admin API. The previous delivery
report says the allowed/denied-origin check passed; it was not run in this audit.

## 6. Photo storage (mission proof)

- Development: `STORAGE_PROVIDER=local` (files under `UPLOAD_DIR`).
- **Production must use object storage.** On a host with an ephemeral disk
  (Render's default), local files are lost on every deploy. Use
  `STORAGE_PROVIDER=s3` with any S3-compatible service and
  `pip install -r requirements-storage-s3.txt`.
- Objects are private. Photos are only served by
  `GET /api/v1/uploads/task-proofs/{id}`, which requires the owning child or a
  parent of the same family, and sends `nosniff` and a restrictive CSP.
- The app's `proof_url` is an authenticated API path, not a signed URL or public
  object URL. The S3 adapter does not request a public ACL or generate signed
  URLs. S3 persistence and access policy still require a real bucket test.
- Uploads are decoded and re-encoded with Pillow: only JPEG/PNG/WebP, all
  metadata (EXIF/GPS) removed, longest edge ≤ 2048 px, input ≤ `MAX_UPLOAD_BYTES`.
- `UploadFile` is read with a `MAX_UPLOAD_BYTES + 1` bound. Configure and verify
  an ingress/request-body limit as well; no proxy or server request-size setting
  was inspected in this audit.
- There is no cleanup job yet for photos that were uploaded but never attached
  to a submission (each child is capped at `MAX_UNATTACHED_UPLOADS`).

## 7. Push notifications

See `push-notifications-setup.md`. Without a provider the system is unchanged:
notifications are stored and shown in the app.

## 8. Backward-compatibility review

The repository's captured OpenAPI baseline contains 70 operations dated
2026-10-13, and `tests/test_api_contract.py` checks that operation paths/methods
are not removed. That guard does not assert full request/response compatibility
or behavior and was not run in this audit. No current production OpenAPI was
retrieved. Documented behavior changes to existing operations:

| Operation | Change | Impact on an older client |
|---|---|---|
| `POST /auth/register`, `/auth/login`, `/auth/children/{id}/session` | Response gains `refresh_token`, `refresh_expires_at`. | None (additive). |
| `GET /rewards` | Now also allowed for a **child** (own family). Parents still must send `family_id`; its absence is now `422 http_error` instead of `422 validation_error`. | Error code string differs in that one case. |
| `POST /tasks/{id}/submissions` | New `409 submission_pending` / `task_already_completed`; new optional `proof_upload_id`; `proof_type: image` now requires an upload (or the legacy `proof_url`). | A client that re-sent a submission, or sent a bare `image` proof, now gets a clear error (it previously created duplicates / an empty image proof). |
| `POST /redemptions` | New `409 redemption_pending`; `insufficient_stars` now counts stars already reserved by the child's other pending requests. | Intended; prevents over-asking. |
| `GET /admin/users`, `PATCH /admin/users/{id}/status` | Response is a superset (`is_active`, `created_at`, `last_login_at`). | None. |
| `GET /progress/children/{id}` | Adds `garden`. **Fixes a 500** for any child holding a badge (a row-attribute bug that production never hit only because no badge existed). | None. |
| `GET/PATCH /settings/me`, `PATCH /settings/families/{id}` | **Fixes a 500** whenever a settings row already existed (missing `from_attributes`). | None. |
| Review/approval logic | The activity day and streak now use the **family's** time zone (default `UTC`, i.e. previous behaviour). | Same until a zone is set. |
| New notification types | `task_assigned`, `reward_requested`. | Clients must tolerate unknown types (the Flutter app does). |

## 9. Historical database verification notes (not re-verified in this audit)

The statements in this section are from an earlier delivery report. They are
not evidence of current staging or production state and were not independently
verified during the 2026-10-14 audit below.

The only production access was a read-only session (`default_transaction_read_only=on`)
to reflect table definitions and copy five non-personal reference tables.
A schema-only copy was loaded into a throwaway local PostgreSQL 17, then:

- `alembic upgrade head` → re-run (no-op) → `downgrade` → `upgrade`;
- the integration suite (`TEST_DATABASE_URL=…`) ran inside rolled-back
  transactions;
- a real `uvicorn` process with committed writes was driven by
  `smoke.py`-style scripts and by the Flutter apps' own repository classes.

To reproduce: create a database whose name contains `test`, load the production
schema, run the migrations, then
`TEST_DATABASE_URL=… DATABASE_URL=… JWT_SECRET_KEY=… python -m pytest`.

## 10. Known limits (not done, by decision or dependency)

- No rate limiting or lockout on `/auth/login`, `/auth/register` or uploads.
- Refresh rotation stores the current digest and only one `previous_token_hash`.
  Reuse of the immediately previous token revokes that session; reuse of a token
  from an older rotation is rejected as invalid but does not revoke the current
  session. If the security promise is to revoke on replay of any rotated token,
  token-family history or an equivalent design is required.
- No phone-OTP or Google sign-in (needs a provider account and a separate flow).
- No parent PIN gate in child mode: leaving child mode signs the child out and a
  parent signs in again.
- No quiz/learning-progress API; learning content is admin-curated links.
- Hosted-video playback still requires `VIDEO_PLAYBACK_PROVIDER` and a real provider; none is configured or tested end to end. A bug that made `start_playback` and heartbeats raise `TypeError` on any row loaded from PostgreSQL (timezone-aware vs naive comparison) was found and fixed in this release; it is covered by `tests/test_video_timezone.py`.
- Email notifications are not implemented (the preference exists, and the app
  says so).

## 11. Staging and database-test evidence

**Staging result for this audit: not run.** No staging database/API was used;
the `TEST_DATABASE_URL`, `DATABASE_URL`, and `JWT_SECRET_KEY` process
environment variables were unset. A backend `.env` file exists but was
intentionally not inspected or used, so its database target is unknown. The
generic IDE test runner reported no tests found for the Python test paths; it
did not execute backend tests. No production database was contacted or modified.

`tests/conftest.py` skips database-backed tests if `TEST_DATABASE_URL` is absent.
When set, it rejects a database name without `test`, and rejects an exact
host/port/database match with `DATABASE_URL` if the latter is configured. It
wraps each `isolated_test_session` in a transaction and rolls it back, including
endpoint commits via savepoints. These guards reduce risk but do **not** prove
the target is disposable: the fixture does not verify ownership, server identity,
or disposable status; if `DATABASE_URL` is unset, it cannot compare against it.
`tests/test_health.py::test_reflected_model_metadata_matches_database` uses the
application `DATABASE_URL` directly and is not protected by that fixture. Point
both variables to approved disposable infrastructure before running the suite.

Required staging sequence: prepare a disposable PostgreSQL database with the
staging schema; independently confirm its host and database name; snapshot it;
run `alembic upgrade head`, run it again, verify `alembic current`, rehearse
`downgrade` → `upgrade` only on that disposable copy, then run the complete
backend suite with no unexpected database skips. Record command output, revision
state, PostgreSQL version, and test skip counts in the release record. Do not
infer success from the presence of tests or from the earlier delivery report.

## 12. Required owner decisions and external credentials

- Product owner: approve progression level thresholds, badge criteria/names,
  whether `task_resubmission_requested` is a distinct push from rejection, and
  whether push is required for launch.
- Database owner: approve the production migration window, backup/PITR plan,
  migration target verification, retention, and an explicit rollback decision.
- Legal/product owner: provide final consent wording and version values; obtain
  native-speaker review of Hindi and Gujarati.
- Security/operations owner: choose and configure login/register/upload rate
  limits and lockout/abuse response; set an owner for unattached-photo cleanup.
- Firebase: Android app configuration (`google-services.json`) and a server-only
  FCM service-account private key with the minimum required FCM role. Never put
  the private key in the mobile app, repository, or logs.
- Storage: S3-compatible bucket, region/endpoint, access key and secret, lifecycle
  and backup/retention policy; keep the bucket private. Test using a nonproduction
  bucket first.
- Operations: exact admin-panel CORS origin; first administrator identity and
  one-time password delivery; secret manager entries for database, JWT, FCM,
  and S3 credentials. Set `JWT_SECRET_KEY` to at least 32 random bytes.
- Release owner: decide whether phone/Google auth, quizzes, parent PIN, email,
  iOS, and hosted video are explicitly out of scope for this release.

## 13. Production deployment checklist and rollback

### Before deployment

1. Close every owner decision above; publish the approved seed values and consent
   versions. Review the old-client behavior changes in section 8 with the client
   owner.
2. Complete the disposable-database migration cycle and full backend tests in
   section 11. Run the app/admin format, analysis, test, and release-build checks
   in CI with pinned dependency lockfiles. Install the APK on a test device and
   launch the admin panel in a browser; capture results rather than relying on
   prior notes.
3. In staging, test an actual S3-compatible private bucket: upload, read as the
   owning child and family parent, reject another family, verify no public
   access, and verify object persistence across backend restart/deploy. Test
   cleanup/retention. Test FCM with a real test device only if push is in scope.
4. Verify staging CORS from the exact admin origin and a denied origin; exercise
   each admin section with allowed and denied roles; verify audit rows for every
   mutation. Test login/session refresh, reuse revocation, logout, and
   deactivation. Run old supported clients through login, mission submission,
   reward requests, and settings.
5. Set maintenance/feature controls as needed. Store credentials in the host's
   secret manager. Check that production is configured with `STORAGE_PROVIDER=s3`
   (not ephemeral local storage), correct `CORS_ORIGINS`, and the intended
   notification provider. Do not print secret values in deployment logs.
6. Take and verify a restorable database backup/PITR checkpoint. Confirm the
   production host/database identity using a read-only connection and a second
   operator. Production execution requires explicit database-owner approval.

### Deployment

1. Apply `ALLOW_SCHEMA_MIGRATIONS=true` only for the reviewed migration process,
   target the confirmed production database, run `alembic upgrade head`, record
   the final revision, and immediately remove/disable the migration flag.
   Never use offline SQL or run revision functions manually.
2. Deploy the backend; verify `/health`, `/ready`, logs, admin authentication,
   CORS, and data access. Create the first administrator through the CLI using
   an interactive password prompt or a protected short-lived environment
   variable, then remove the variable.
3. Deploy the admin web build and mobile release only after backend checks.
   Validate one test-family mission/photo/reward journey; verify photo reads
   remain private and check notification delivery only if Firebase is configured.
4. Monitor migration state, API errors, storage failures, authentication errors,
   and push provider failures. Record evidence, owner, time, and decision.

### Rollback

- Stop or pause rollout and disable optional push/storage integration if it is
  causing errors; preserve logs and database state. Roll back application
  binaries only after confirming the prior backend tolerates the added tables.
- Prefer a forward fix for schema/data issues. Do **not** automatically run
  `alembic downgrade`: 0001 intentionally leaves its seed data, while downgrades
  0002–0006 drop tables and permanently remove refresh sessions, device tokens,
  upload metadata, preset tasks, or app-setting overrides. Dropping 0004 metadata
  leaves photo objects orphaned.
- If restoration is necessary, require database-owner approval, use the verified
  backup/PITR point, record the recovery point and expected write loss, and
  coordinate API/app compatibility before reopening traffic. Reconcile external
  object storage separately; database restore does not roll back object writes.
