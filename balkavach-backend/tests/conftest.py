import os

import pytest
from sqlalchemy import create_engine
from sqlalchemy.engine import make_url
from sqlalchemy.orm import sessionmaker

from app.core.config import get_database_url
from app.db.base import prepare_models


@pytest.fixture
def isolated_test_engine():
    test_url = os.environ.get("TEST_DATABASE_URL")
    if not test_url:
        pytest.skip("Set TEST_DATABASE_URL to a dedicated disposable test database")
    test_parts = make_url(test_url)
    app_url = get_database_url()
    if app_url:
        app_parts = make_url(app_url)
        if (test_parts.host, test_parts.port, test_parts.database) == (
            app_parts.host,
            app_parts.port,
            app_parts.database,
        ):
            pytest.fail("TEST_DATABASE_URL must not point to the configured application database")
    database_name = test_parts.database or ""
    if "test" not in database_name.casefold():
        pytest.fail("TEST_DATABASE_URL database name must contain 'test'")
    if test_parts.drivername in {"postgres", "postgresql"}:
        test_parts = test_parts.set(drivername="postgresql+psycopg")
    engine = create_engine(test_parts, pool_pre_ping=True)
    try:
        prepare_models(engine)
        yield engine
    finally:
        engine.dispose()


@pytest.fixture
def isolated_test_session(isolated_test_engine):
    connection = isolated_test_engine.connect()
    transaction = connection.begin()
    connection.exec_driver_sql("SET LOCAL TIME ZONE 'UTC'")
    test_session_factory = sessionmaker(
        bind=connection,
        autoflush=False,
        expire_on_commit=False,
        join_transaction_mode="create_savepoint",
    )
    session = test_session_factory()
    try:
        yield session
    finally:
        session.close()
        transaction.rollback()
        connection.close()