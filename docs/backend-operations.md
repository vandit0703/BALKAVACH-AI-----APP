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

Nothing in this repository has been applied to the production database. Every
migration was exercised only against local scratch databases (see section 9).

### The migrations

| Revision | What it does | Reversible |
|---|---|---|
| `0001_seed_progression` | Inserts 6 default levels and 6 default badges **only if missing** (production currently has none, so no child could ever level up or earn a badge). Idempotent; never edits existing rows. | No-op downgrade (removing rows a child may have earned would orphan them) |
| `0002_auth_sessions` | `auth_sessions`: refresh-token sessions (SHA-256 digests only). | Yes |
| `0003_device_tokens` | `device_tokens`: push addresses, unique per token. | Yes |
| `0004_proof_uploads` | `proof_uploads`: owner/family/size/SHA-256 of each mission photo. | Yes |
| `0005_preset_tasks` | `preset_tasks`: admin-managed mission ideas. | Yes |
| `0006_app_settings` | `app_settings`: allow-listed global settings (consent versions, maintenance). | Yes |

**Product decision needed:** the default level thresholds (0/100/300/700/1500/3000
XP) and badge names/thresholds live in `app/db/seed_data.py`. They are proposed
defaults; confirm or edit them before running `0001`.

The migration environment script (`alembic/env.py`) had a latent bug that made
every run roll back silently (reflection opened a transaction Alembic then never
committed). It is fixed (`connection.commit()` after reflecting); verified by
upgrade → re-run → downgrade → upgrade on a scratch database.

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
Verified: the configured origin gets `Access-Control-Allow-Origin` with
`Authorization`, `Content-Type` and `Idempotency-Key` allowed; other origins are
refused.

## 6. Photo storage (mission proof)

- Development: `STORAGE_PROVIDER=local` (files under `UPLOAD_DIR`).
- **Production must use object storage.** On a host with an ephemeral disk
  (Render's default), local files are lost on every deploy. Use
  `STORAGE_PROVIDER=s3` with any S3-compatible service and
  `pip install -r requirements-storage-s3.txt`.
- Objects are private. Photos are only served by
  `GET /api/v1/uploads/task-proofs/{id}`, which requires the owning child or a
  parent of the same family, and sends `nosniff` and a restrictive CSP.
- Uploads are decoded and re-encoded with Pillow: only JPEG/PNG/WebP, all
  metadata (EXIF/GPS) removed, longest edge ≤ 2048 px, input ≤ `MAX_UPLOAD_BYTES`.
- There is no cleanup job yet for photos that were uploaded but never attached
  to a submission (each child is capped at `MAX_UNATTACHED_UPLOADS`).

## 7. Push notifications

See `push-notifications-setup.md`. Without a provider the system is unchanged:
notifications are stored and shown in the app.

## 8. Backward-compatibility review

Every existing operation published at
`https://balkavach-ai-app.onrender.com/openapi.json` (70 on 2026-10-13) is still
present; `tests/test_api_contract.py` fails if one is removed. Behavioural
changes to existing operations:

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

## 9. How the database was verified without touching production

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
- No phone-OTP or Google sign-in (needs a provider account and a separate flow).
- No parent PIN gate in child mode: leaving child mode signs the child out and a
  parent signs in again.
- No quiz/learning-progress API; learning content is admin-curated links.
- Hosted-video playback still requires `VIDEO_PLAYBACK_PROVIDER` and a real provider; none is configured or tested end to end. A bug that made `start_playback` and heartbeats raise `TypeError` on any row loaded from PostgreSQL (timezone-aware vs naive comparison) was found and fixed in this release; it is covered by `tests/test_video_timezone.py`.
- Email notifications are not implemented (the preference exists, and the app
  says so).
