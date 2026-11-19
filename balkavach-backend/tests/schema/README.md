# Baseline schema for the disposable test database

The Alembic migrations in `alembic/versions/` only **add to** a schema that already exists in
production: no migration creates `users`, `families`, `family_members`, `child_profiles`, `tasks`,
`task_submissions`, `star_transactions`, `levels`, `badges`, `notifications`, `videos`, ... (the app
reflects them at runtime, see `app/db/base.py`). A fresh database therefore cannot be built from
the repository alone.

## What goes here

`baseline.sql` — a **schema-only** dump (no row data, no credentials) of those pre-existing
tables, taken at the state migration `0001_seed_progression` expects (i.e. *before* any migration
in `alembic/versions/` ran), or any later state when you also remove the already-applied
migrations' effects. The simplest correct input is a schema-only dump of production *or* of a
database at the revision you want to test, with `alembic_version` removed:

```bash
# Run by a person with access; this reads schema only and writes nothing.
pg_dump --schema-only --no-owner --no-privileges "$SOURCE_DATABASE_URL" > baseline.sql
```

If the dump already includes the migrated tables, `alembic upgrade head` must start from the matching
revision (`alembic stamp <revision>` on the disposable database, **never** on production).

## How it is used

* locally: `python scripts/testenv.py load-schema tests/schema/baseline.sql`, then
  `python scripts/testenv.py migrate`, then `python scripts/testenv.py test`;
* CI: `.github/workflows/ci.yml` refuses to run the backend job without this file.

Never commit data, connection strings or secrets. Review the file before committing it.
