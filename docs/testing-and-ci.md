# Testing and CI

Repeatable commands for all three projects. **Nothing here touches production**: the backend
tests run against a throw-away PostgreSQL and Redis, and the harness refuses any database whose
name does not contain `test` or that equals the configured application database
(`balkavach-backend/tests/conftest.py`).

## Baseline recorded 2026-11-18 (Phase 0, commit `58b3545` + Phase 1 work)

| Suite | Command | Result |
|---|---|---|
| Backend, before Phase 1, **no test schema** | `pytest -q -rs` | 298 passed, **177 skipped**, 0 failed |
| Backend, after Phase 1, **no test schema** | same | 321 passed, **199 skipped**, 0 failed |
| Frontend, before Phase 1 | `flutter analyze` / `flutter test` | analyze clean; 1019 passed, 1 skipped, 0 failed |
| Frontend, after Phase 1 | same | analyze clean; **1074 passed**, 1 skipped, 0 failed (19 new gate/reset tests + 36 new responsive cases) |
| Admin (untouched in Phase 1) | same | analyze clean; 67 passed, 1 skipped, 0 failed |

Re-run 2026-11-18 after Phase 1 verification fixes and the Phase 2 work (still **no baseline schema**):
backend **359 passed, 206 skipped**, 0 failed (+38 passed on an in-memory SQLite "world", see
`tests/sqlite_world.py`; +7 skipped PostgreSQL tests that have never run); frontend analyze clean, 1074 passed,
1 skipped; admin analyze clean, 67 passed, 1 skipped. Details: `docs/phase-2-mission-correctness.md`.

After milestone C1 (localized mission catalogue; still **no baseline schema**): backend **422 passed, 206 skipped**
(the 206 skips are unchanged PostgreSQL tests); frontend analyze clean, **1301 passed**, 1 skipped; admin analyze
clean, **74 passed**, 1 skipped. Catalogue details: `docs/mission-catalogue-inventory.md`.

After milestone C2 (rotation, 14-template catalogue, admin health; still **no baseline schema**): see the counts in
`docs/mission-rotation.md` and the final C2 report; the 206 PostgreSQL skips are unchanged.

The 177/199 backend skips are the database-backed tests. They **cannot run until the baseline
schema file exists** (see below). The only Flutter skip is a pre-existing opt-in test.

## The missing baseline schema

Alembic migrations only *add to* the production schema; no migration creates `users`,
`families`, `tasks`, ... A disposable database therefore needs `balkavach-backend/tests/schema/baseline.sql`
(schema-only; see `tests/schema/README.md`). Until it is added, DB-backed tests skip locally and the
CI backend job fails with an explicit message.

## Local backend (Windows/macOS/Linux)

```bash
cd balkavach-backend
python -m venv .venv && . .venv/Scripts/activate      # Windows Git Bash; use bin/activate on Linux/macOS
pip install -r requirements.txt "fakeredis[lua]"      # fakeredis is only for the local Redis stand-in

python scripts/testenv.py start                        # private PostgreSQL cluster + Redis stand-in
python scripts/testenv.py load-schema tests/schema/baseline.sql   # once the file exists
python scripts/testenv.py migrate                      # alembic upgrade head on the TEST database only
python scripts/testenv.py test -- -q -rs               # pytest with TEST_DATABASE_URL / REDIS_URL set
python scripts/testenv.py status | stop | reset
```

* `testenv.py` runs `initdb` into `%LOCALAPPDATA%\balkavach-testenv` (override with
  `BALKAVACH_TESTENV_DIR`), listens on `127.0.0.1:55432`, trust auth, database `balkavach_test`. It
  never uses the PostgreSQL service on port 5432 or any real credentials.
* Redis on Windows: no native build and no Docker/WSL were available, so `testenv.py` serves
  `fakeredis` over TCP (real `redis` client and Lua scripts, in-memory). It is a **stand-in**; CI uses
  a real `redis:7` container. Port `56379`.
* Pure tests (no database) run without any service:
  `pytest -q tests/test_attempt_lockout.py tests/test_authorization_boundaries.py tests/test_password_reset_page.py tests/test_rate_limit.py tests/test_auth_security.py`

## Frontend and admin

```bash
cd balkavach-frontend   # and again in balkavach-admin
flutter pub get --enforce-lockfile      # never rewrites pubspec.lock
flutter analyze
flutter test --no-pub
```

Note: running the admin tests rewrites two **tracked build-cache files** under
`balkavach-admin/build/` (`.filecache`, a `*.track.dill`). They are generated; consider untracking
`balkavach-admin/build/` (only `build/web` needs to be tracked, if at all).

## CI (`.github/workflows/ci.yml`)

* `backend`: PostgreSQL 16 + Redis 7 service containers → pure tests → loads
  `tests/schema/baseline.sql` → `alembic upgrade head` (disposable DB, `ALLOW_SCHEMA_MIGRATIONS=true`)
  → full pytest with JUnit → **skipped-test gate** (`scripts/ci_skip_gate.py`, `MAX_SKIPPED_TESTS`,
  default 1 for the `test_health` check that needs `DATABASE_URL`; lower it to 0 after the first green run).
* `frontend`, `admin`: `pub get --enforce-lockfile`, `flutter analyze`, `flutter test`.
* The Flutter version is `stable`; pin it to the version your team builds with (the local SDK is 3.44.x).
* Not run in CI by design: anything needing Firebase, SMTP, YouTube API keys or a device.

## Test commands that must never be run

* any `pytest` with `DATABASE_URL`/`TEST_DATABASE_URL` pointing at Render/Neon/production;
* `alembic upgrade` against anything but the disposable database;
* `python -m app.cli ...` jobs against production from a developer machine.

## Milestone C2 part 2 (42-template catalogue): results and the PostgreSQL test plan

Results are recorded in the milestone report (actual counts from this run, not historical ones). `tests/schema/baseline.sql` is **still missing**, so
every PostgreSQL-dependent test is skipped and **nothing below has been verified on PostgreSQL**.

### What still needs PostgreSQL (do not claim these are verified)

The 206 backend skips are the tests that call `tests/conftest.py`'s database fixture (`TEST_DATABASE_URL`); for missions they are
`test_api_mission_flow.py`, `test_api_mission_dates.py` and the PostgreSQL-only tests in the daily-mission and rotation files. Once the baseline
schema exists, run `python scripts/testenv.py load-schema tests/schema/baseline.sql`, `migrate`, then these, against the disposable database only:

| Topic | Test to write or run | What it must show |
|---|---|---|
| Concurrent assignment requests | N threads (e.g. 8) call `GET /daily-missions/today` for one child at the same moment, then a second child at the same moment | exactly 3 current assignments per child per local date, no 500, no duplicate `(child, date, slot)` rows |
| `SELECT ... FOR UPDATE` behaviour | two sessions: A locks the child row and sleeps, B requests choices | B waits (observe via `pg_locks`/timing), then returns A's rows; with the lock removed the test fails (mutation check). SQLite ignores `FOR UPDATE`, so this cannot be proven there |
| Unique slot constraints | insert a second current row for the same `(child_id, local_date, choice_slot)`; insert two selected rows for one child/date | `IntegrityError` from the partial unique indexes created by migration 0015, not from Python code |
| Rotation queries | run the 42-day history query and per-template counts on 50,000 assignment rows | results equal the SQLite world's for the same data; `EXPLAIN` uses `ix_daily_assignment_history` |
| Catalogue seeding | `python -m app.cli seed-daily-missions --apply` twice on the disposable database; then with `--publish` | 42 templates and 378 variations after run 1, 0 created after run 2; the code's match on template + age band + locale + `variation_key` finds every row on run 2 (no database constraint enforces it, so check for duplicates with a `GROUP BY`); the 0015 placeholders are untouched without `--retire-placeholders` |
| Admin health query performance | seed 42 templates and 1,000,000 synthetic assignment rows in the disposable database, call `GET /admin/daily-missions/catalogue-health` | target under 500 ms; if not, add `(template_id)` index in a later additive migration, as noted in `docs/mission-rotation.md` |

None of these was run. SQLite results (in-memory "world") are logic checks only and must not be reported as PostgreSQL proof.
