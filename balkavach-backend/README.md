# BalKavach Backend

FastAPI backend for family task management, child progress, rewards, and the admin-managed video catalog.

## Setup

Use Python 3.10 or newer. Install dependencies and provide a PostgreSQL URL in the existing `.env` file:

```powershell
python -m pip install -r requirements.txt
if (-not (Test-Path .env)) { Copy-Item .env.example .env }
```

Keep the existing `.env` and its `DATABASE_URL`; do not replace it with the example. Set `JWT_SECRET_KEY` to a randomly generated value of at least 32 bytes before using registration or login. Configure `CORS_ORIGINS` as a JSON array of trusted frontend origins.

Start the API:

```powershell
uvicorn app.main:app --reload
```

Health endpoints are `GET /health` and `GET /ready`. The latter performs a read-only `SELECT 1`. Interactive API documentation is at `/docs`; API routes are under `/api/v1`.

## Implemented API Areas

- Authentication: `POST /api/v1/auth/register`, `POST /api/v1/auth/login`, `GET /api/v1/auth/me`.
- Families and children: `/api/v1/families`, including active membership checks and child deactivation.
- Tasks: `/api/v1/tasks`, `/api/v1/reviews`; child submissions and parent decisions are persisted transactionally.
- Progress: `/api/v1/progress`; balances are derived from ledgers, not client input.
- Rewards: `/api/v1/rewards` and `/api/v1/redemptions`; send an `Idempotency-Key` header when requesting redemption.
- Videos: `/api/v1/videos` for eligible child feed metadata, `/api/v1/video-access` for playback sessions, and `/api/v1/admin/videos` for admin-managed catalog operations.
- Notifications, settings, consent, educational content, and admin dashboard/user/audit endpoints are also available under `/api/v1`.

All protected routes validate the bearer token against the active user row. Parent resources are scoped through family membership. Admin writes additionally require an assigned database admin role containing the corresponding permission string (for example `video:write`, `users:write`, or `content:write`).

## Existing Database

The ORM registry reflects the existing `public` schema at first database-model access. This maps the live 32-table schema, including its actual column types, defaults, constraints, indexes, and foreign keys; the application does not call `create_all`, run migrations at startup, or modify the schema. PostgreSQL timestamps are `TIMESTAMP WITHOUT TIME ZONE`; connections are set to UTC, inputs must be timezone-aware where accepted, and API timestamps are serialized as UTC.

Alembic is deliberately guarded. There are no generated migrations in this repository. Offline migration generation is disabled, and online migration commands require `ALLOW_SCHEMA_MIGRATIONS=true`. Do not enable it or run a migration against the existing database without reviewing a schema diff and obtaining database-owner approval. No migration or write-path integration test is run against the configured Neon URL.

## Playback and Push Providers

Playback starts fail closed unless `VIDEO_PLAYBACK_PROVIDER` names a trusted `module:factory` implementing `issue_playback_url(video, session_id, expires_at)` and `revoke_playback(session_id)`. Provider URLs should be short-lived and bound to the server session. The backend accepts no client-reported watched-time value: heartbeats use server receipt time and credit at most 30 seconds per interval.

The backend can stop issuing URLs and reject future heartbeats, but cannot reliably stop a third-party player that already has an unrestricted URL. Strict limits require hosted media with provider-enforced, short-lived authorized playback and revocation. Direct YouTube/external URLs do not provide strict server-side playback enforcement. No media binaries are uploaded to PostgreSQL.

Push delivery is not enabled by default. `NOTIFICATION_PROVIDER` is an optional provider hook; in-app notifications are stored in PostgreSQL, and the API does not claim that a push was delivered.

## Tests

Run `python -m pytest`. Read-only schema parity uses the configured database and only inspects PostgreSQL metadata. Any future write integration tests must request the `isolated_test_engine` fixture, which requires an explicit `TEST_DATABASE_URL`, rejects the configured application URL, and requires a database name containing `test`. It never falls back to `DATABASE_URL` or creates/drops tables.
