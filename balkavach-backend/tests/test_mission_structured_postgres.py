"""Migration 0019 on REAL PostgreSQL, in a throwaway schema inside a disposable test database.

Skips unless ``TEST_DATABASE_URL`` names a disposable database (its name must contain "test" and it must not be the
application database; see ``conftest.isolated_test_engine``). It never touches the real ``daily_mission_variations``:
it creates a scratch schema, builds a copy of that table as migration 0015 defines it, runs 0019's upgrade and
downgrade there, and rolls everything back (PostgreSQL DDL is transactional).

Run it only against a disposable database. SQLite and mock tests elsewhere do not prove any of this.
"""

import importlib.util
from pathlib import Path
from uuid import uuid4

from alembic.migration import MigrationContext
from alembic.operations import Operations
from sqlalchemy import text

BACKEND = Path(__file__).resolve().parent.parent
NEW = {"learning_objective", "steps", "observation_guidance", "submission_requirements"}
LEGACY = {
    "id", "template_id", "age_band", "locale", "title", "description", "instructions", "required_materials",
    "duration_minutes", "safety_instructions", "completion_criteria", "variation_key",
}
_SELECT = "SELECT id, title, instructions, required_materials FROM daily_mission_variations ORDER BY locale"


def _migration():
    path = BACKEND / "alembic" / "versions" / "0019_mission_instruction_fields.py"
    spec = importlib.util.spec_from_file_location("m0019", path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def _columns(connection, schema):
    rows = connection.execute(
        text(
            "SELECT column_name, data_type, is_nullable, column_default FROM information_schema.columns "
            "WHERE table_schema = :s AND table_name = 'daily_mission_variations'"
        ),
        {"s": schema},
    ).all()
    return {r[0]: r for r in rows}


def test_0019_upgrade_and_downgrade_on_postgresql(isolated_test_engine):
    schema = f"zz_probe_{uuid4().hex[:10]}"
    connection = isolated_test_engine.connect()
    transaction = connection.begin()
    try:
        connection.execute(text(f'CREATE SCHEMA "{schema}"'))
        connection.execute(text(f'SET LOCAL search_path TO "{schema}"'))
        connection.execute(
            text(
                "CREATE TABLE daily_mission_variations ("
                "id uuid PRIMARY KEY DEFAULT gen_random_uuid(), template_id uuid NOT NULL, age_band varchar(8) NOT NULL, "
                "locale varchar(10) NOT NULL, title varchar(180) NOT NULL, description text NOT NULL, instructions text NOT NULL, "
                "required_materials jsonb NOT NULL DEFAULT '[]', duration_minutes integer NOT NULL, "
                "safety_instructions text NOT NULL, completion_criteria text NOT NULL, variation_key varchar(40) NOT NULL DEFAULT 'v1')"
            )
        )
        template = uuid4()
        for index in range(2):
            connection.execute(
                text(
                    "INSERT INTO daily_mission_variations (template_id, age_band, locale, title, description, instructions, "
                    "required_materials, duration_minutes, safety_instructions, completion_criteria) VALUES "
                    "(:t, '7_10', :l, 'T', 'D', 'one', CAST('[\"x\"]' AS jsonb), 5, 'S', 'C')"
                ),
                {"t": template, "l": f"l{index}"},
            )
        before = connection.execute(text(_SELECT)).all()

        context = MigrationContext.configure(connection)
        module = _migration()
        with Operations.context(context):
            module.upgrade()

        columns = _columns(connection, schema)
        assert set(columns) == LEGACY | NEW
        for name in NEW:
            _, data_type, nullable, default = columns[name]
            assert nullable == "YES" and default is None
            assert data_type == ("jsonb" if name == "steps" else "text")
        assert connection.execute(text(_SELECT)).all() == before  # ids and legacy values intact
        assert connection.execute(text("SELECT count(*) FROM daily_mission_variations WHERE steps IS NULL AND learning_objective IS NULL")).scalar() == 2

        connection.execute(text("""UPDATE daily_mission_variations SET steps = CAST('["First", "Second"]' AS jsonb) WHERE locale = 'l0'"""))
        assert connection.execute(text("SELECT steps->>1 FROM daily_mission_variations WHERE locale = 'l0'")).scalar() == "Second"

        with Operations.context(context):
            module.downgrade()
        assert set(_columns(connection, schema)) == LEGACY
        assert connection.execute(text(_SELECT)).all() == before
    finally:
        transaction.rollback()  # discards the scratch schema and everything in it
        connection.close()
