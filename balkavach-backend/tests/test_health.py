from fastapi.testclient import TestClient
import pytest
from sqlalchemy import inspect

from app.db.base import Base, prepare_models
from app.db.session import get_db
from app.db.session import engine
from app.main import app

client = TestClient(app)


def test_health_is_available_without_database() -> None:
	response = client.get("/health")

	assert response.status_code == 200
	assert response.json() == {"status": "ok"}


def test_readiness_executes_database_probe() -> None:
	class ProbeSession:
		def __init__(self) -> None:
			self.statement = None

		def execute(self, statement):
			self.statement = str(statement)

	session = ProbeSession()

	def override_get_db():
		yield session

	app.dependency_overrides[get_db] = override_get_db
	try:
		response = client.get("/ready")
	finally:
		app.dependency_overrides.pop(get_db, None)

	assert response.status_code == 200
	assert response.json() == {"status": "ready"}
	assert session.statement == "SELECT 1"


def test_readiness_returns_unavailable_when_database_probe_fails() -> None:
	from sqlalchemy.exc import OperationalError

	class BrokenSession:
		def execute(self, statement):
			raise OperationalError("SELECT 1", {}, Exception("connection unavailable"))

	def override_get_db():
		yield BrokenSession()

	app.dependency_overrides[get_db] = override_get_db
	try:
		response = client.get("/ready")
	finally:
		app.dependency_overrides.pop(get_db, None)

	assert response.status_code == 503
	assert response.json()["error"]["message"] == "Database is unavailable"


def test_reflected_model_metadata_matches_database() -> None:
	if engine is None:
		pytest.skip("DATABASE_URL is not configured")

	prepare_models(engine)
	inspector = inspect(engine)
	database_tables = set(inspector.get_table_names(schema="public"))
	reflected_tables = {table.name: table for table in Base.metadata.tables.values()}

	assert set(reflected_tables) == database_tables
	unique_columns = {
		item["name"]: {tuple(item["column_names"])}
		for item in (
			inspector.get_unique_constraints("star_transactions", schema="public")
			+ inspector.get_unique_constraints("xp_transactions", schema="public")
			+ inspector.get_unique_constraints("redemption_requests", schema="public")
			+ inspector.get_unique_constraints("video_access_entitlements", schema="public")
		)
	}
	assert any(columns == {("idempotency_key",)} for columns in unique_columns.values())
	assert any(columns == {("redemption_id",)} for columns in unique_columns.values())
	for table_name in database_tables:
		table = reflected_tables[table_name]
		assert {column.name for column in table.columns} == {
			column["name"] for column in inspector.get_columns(table_name, schema="public")
		}
		assert [column.name for column in table.primary_key.columns] == inspector.get_pk_constraint(
			table_name, schema="public"
		)["constrained_columns"]
		assert {
			(foreign_key.parent.name, foreign_key.column.table.name, foreign_key.column.name)
			for foreign_key in table.foreign_keys
		} == {
			(local, target_table, target)
			for foreign_key in inspector.get_foreign_keys(table_name, schema="public")
			for local, target in zip(foreign_key["constrained_columns"], foreign_key["referred_columns"])
			for target_table in [foreign_key["referred_table"]]
		}
