"""Migration 0019 and the Alembic graph, checked WITHOUT any database.

Static checks of the revision chain plus the exact PostgreSQL DDL Alembic renders for upgrade and downgrade (offline
rendering with the PostgreSQL dialect; nothing is executed anywhere). The disposable-PostgreSQL behaviour test is
``test_mission_structured_postgres.py`` (skipped unless TEST_DATABASE_URL is a disposable database).
"""

import importlib.util
import io
from pathlib import Path

import pytest
import sqlalchemy as sa
from alembic.config import Config
from alembic.migration import MigrationContext
from alembic.operations import Operations
from alembic.script import ScriptDirectory
from sqlalchemy.dialects import postgresql

BACKEND = Path(__file__).resolve().parent.parent
NEW_COLUMNS = ("learning_objective", "steps", "observation_guidance", "submission_requirements")


def _script() -> ScriptDirectory:
    config = Config(str(BACKEND / "alembic.ini"))
    config.set_main_option("script_location", str(BACKEND / "alembic"))
    return ScriptDirectory.from_config(config)


def _migration():
    path = BACKEND / "alembic" / "versions" / "0019_mission_instruction_fields.py"
    spec = importlib.util.spec_from_file_location("m0019", path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def _render(fn: str) -> tuple[str, list]:
    """The PostgreSQL SQL for upgrade/downgrade, and the Column objects add_column received."""
    buffer = io.StringIO()
    captured: list = []
    context = MigrationContext.configure(dialect_name="postgresql", opts={"as_sql": True, "output_buffer": buffer})
    with Operations.context(context) as operations:
        original = operations.add_column

        def spy(table, column, **kw):
            captured.append(column)
            return original(table, column, **kw)

        operations.add_column = spy
        getattr(_migration(), fn)()
    return buffer.getvalue(), captured


def test_single_head_and_0019_sits_between_0018_and_later_work():
    script = _script()
    heads = script.get_heads()
    assert len(heads) == 1  # one head, however many migrations are added after 0019
    assert script.get_revision("0019_mission_instruction_fields").down_revision == "0018_mission_video_requirements"
    assert script.get_revision("0018_mission_video_requirements").down_revision == "0016_child_video_daily_allowance"
    assert script.get_revision("0024_panda_chat_access").down_revision == "0023_parent_email_verification"
    ancestors = {r.revision for r in script.walk_revisions(base="base", head=heads[0])}
    assert "0019_mission_instruction_fields" in ancestors  # 0019 is on the path to the head


def test_every_revision_is_reachable_with_one_root_and_fits_version_num():
    script = _script()
    revisions = list(script.walk_revisions())
    ids = [r.revision for r in revisions]
    assert len(ids) == len(set(ids))
    assert "0019_mission_instruction_fields" in ids
    assert [r.revision for r in revisions if r.down_revision is None] == ["0001_seed_progression"]
    assert all(len(i) <= 64 for i in ids)  # alembic_version.version_num must be widened beyond 32 (see tests/schema)


def test_the_new_revision_id_fits_a_default_varchar_32_alembic_version_column():
    assert len("0019_mission_instruction_fields") <= 32
    assert len("0024_panda_chat_access") <= 32


def test_upgrade_adds_four_nullable_columns_and_nothing_else():
    sql, _ = _render("upgrade")
    statements = [line for line in sql.splitlines() if line.strip()]
    assert len(statements) == 4
    assert all(s.startswith("ALTER TABLE daily_mission_variations ADD COLUMN") for s in statements)
    assert "steps JSONB;" in sql and "learning_objective TEXT;" in sql
    for forbidden in ("NOT NULL", "DEFAULT", "DROP", "UPDATE", "INSERT", "DELETE", "CREATE"):
        assert forbidden not in sql.upper()


def test_downgrade_removes_only_the_four_new_columns():
    sql, _ = _render("downgrade")
    statements = [line for line in sql.splitlines() if line.strip()]
    assert [s.rsplit(" ", 1)[1].rstrip(";") for s in statements] == list(reversed(NEW_COLUMNS))
    assert all(s.startswith("ALTER TABLE daily_mission_variations DROP COLUMN") for s in statements)


@pytest.mark.parametrize("column", NEW_COLUMNS)
def test_each_new_column_is_nullable_without_a_default(column):
    _, captured = _render("upgrade")
    found = next(c for c in captured if c.name == column)
    assert found.nullable is True and found.server_default is None and found.default is None
    if column == "steps":
        assert isinstance(found.type, postgresql.JSONB)
    else:
        assert isinstance(found.type, sa.Text)
