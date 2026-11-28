"""Store ``tasks.repeat_rule`` as JSON, the representation the API has always used.

Evidence (2026-11-28): ``TaskCreate`` / ``TaskUpdate.repeat_rule`` have been ``dict[str, Any] | None`` since the first
commit, and ``create_task`` / ``update_task`` pass that dict straight to the reflected ORM column. No migration ever
created or altered the column (``tasks`` predates 0001), so its type in a given database is not knowable from the
repository. A ``text`` column cannot store a dict (psycopg refuses to adapt it), so on such a database creating a
repeating mission through the API fails.

Guarded and data-preserving:
  - ``text`` / ``character varying``: converted to ``jsonb`` in place (``USING repeat_rule::jsonb``; empty strings become
    NULL). A value that is not valid JSON makes the migration fail and change nothing, rather than lose data.
  - ``json`` / ``jsonb`` or anything else: left exactly as it is (no-op).
The conversion is recorded in the column comment, so the downgrade converts back to ``text`` only when this migration
did the conversion, and never touches a column that was already JSON.
"""

import os

import sqlalchemy as sa
from alembic import op

revision = "0028_task_repeat_rule_jsonb"
down_revision = "0027_daily_missions_all_selectable"
branch_labels = None
depends_on = None

MARKER = "balkavach:0028 converted repeat_rule from text to jsonb"


def _column_type(bind) -> str | None:
	return bind.execute(
		sa.text(
			"select data_type from information_schema.columns "
			"where table_schema = current_schema() and table_name = 'tasks' and column_name = 'repeat_rule'"
		)
	).scalar()


def upgrade() -> None:
	if os.getenv("ALLOW_SCHEMA_MIGRATIONS", "true").lower() in ("false", "0"):
		raise RuntimeError("Schema migrations are disabled; set ALLOW_SCHEMA_MIGRATIONS=true")
	bind = op.get_bind()
	if _column_type(bind) not in ("text", "character varying"):
		return  # already JSON (or absent): nothing to do
	op.execute(
		sa.text(
			"ALTER TABLE tasks ALTER COLUMN repeat_rule TYPE jsonb "
			"USING NULLIF(btrim(repeat_rule::text), '')::jsonb"
		)
	)
	op.execute(sa.text(f"COMMENT ON COLUMN tasks.repeat_rule IS '{MARKER}'"))


def downgrade() -> None:
	bind = op.get_bind()
	comment = bind.execute(
		sa.text(
			"select col_description('tasks'::regclass, a.attnum) from pg_attribute a "
			"where a.attrelid = 'tasks'::regclass and a.attname = 'repeat_rule'"
		)
	).scalar()
	if comment != MARKER:
		return  # this migration did not convert the column: leave it as it was
	op.execute(sa.text("ALTER TABLE tasks ALTER COLUMN repeat_rule TYPE text USING repeat_rule::text"))
	op.execute(sa.text("COMMENT ON COLUMN tasks.repeat_rule IS NULL"))
