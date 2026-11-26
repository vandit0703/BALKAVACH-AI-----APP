import os

import pytest
from cryptography.fernet import Fernet
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

@pytest.fixture
def api(isolated_test_session, monkeypatch):
    """HTTP client wired to the rolled-back test transaction."""
    from fastapi.testclient import TestClient

    from app.core.config import settings
    from app.db.session import get_db
    from app.main import app
    from app.core.rate_limit import FixedWindowLimiter
    from tests.harness import ApiHarness

    monkeypatch.setattr(settings, "jwt_secret_key", "integration-test-secret-that-is-long-enough")
    monkeypatch.setattr(
        settings,
        "child_credentials_encryption_key",
        Fernet.generate_key().decode("ascii"),
    )
    import app.api.v1.auth as auth_api
    from app.integrations import email as email_module

    for limiter_name in (
        "registration_limiter",
        "login_limiter",
        "password_reset_limiter",
        "verification_resend_limiter",
    ):
        monkeypatch.setattr(auth_api, limiter_name, FixedWindowLimiter())
    verification_mailbox = []
    monkeypatch.setattr(
        email_module,
        "send_parent_verification",
        lambda email, otp: verification_mailbox.append((email, otp)),
    )
    from app.services.push_service import deliver_ready

    def _get_db():
        # Mirrors app.db.session.get_db: deliver pushes after success, and always discard
        # uncommitted work (production closes the session, which rolls back).
        try:
            yield isolated_test_session
            deliver_ready(isolated_test_session)
        finally:
            isolated_test_session.rollback()

    app.dependency_overrides[get_db] = _get_db
    try:
        with TestClient(app) as client:
            yield ApiHarness(client, isolated_test_session, verification_mailbox)
    finally:
        app.dependency_overrides.pop(get_db, None)


@pytest.fixture
def standin_submit(monkeypatch):
    """Test-only stand-in for the child-facing 'what to submit' text.

    The catalogue authors have not written ``submit`` yet, so the real catalogue is (correctly) not publishable. Tests
    that exercise rotation, eligibility or publishing need published missions, so they use the real catalogue plus the
    mission's last step as a stand-in submission. Never used by the audit or seeder-safety tests."""
    import app.services.mission_catalogue_service as catalogue

    original = catalogue.variation_payload

    def with_submit(mission, age_band, locale):
        payload = original(mission, age_band, locale)
        if not payload.get("submission_requirements"):
            payload["submission_requirements"] = payload["steps"][-1]
        return payload

    monkeypatch.setattr(catalogue, "variation_payload", with_submit)
