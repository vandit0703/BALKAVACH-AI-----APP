"""One-time codes under real concurrency (PostgreSQL row locks).

The ``api`` tests share one rolled-back transaction and cannot race. These use separate committed
connections on the disposable test database and remove what they create.
"""

from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timedelta, timezone
from threading import Barrier
from uuid import uuid4

import pytest
from sqlalchemy.orm import sessionmaker

from app.core.config import settings
from app.core.exceptions import APIError
from app.core.security import hash_password
from app.db.base import get_model
from app.services import login_code_service
from app.services.email_verification_service import verify_parent_email

THREADS = 8
CODE = "246810"


@pytest.fixture
def factory(isolated_test_engine, monkeypatch):
	monkeypatch.setattr(settings, "jwt_secret_key", "integration-test-secret-that-is-long-enough")
	return sessionmaker(bind=isolated_test_engine, expire_on_commit=False, autoflush=False)


@pytest.fixture
def parent(factory):
	"""A committed parent account; its sessions, codes and the account are removed afterwards."""
	User = get_model("User")
	email = f"race-{uuid4().hex}@example.com"
	with factory() as session:
		user = User(
			full_name="Race Parent",
			email=email,
			password_hash=hash_password("a-long-integration-password"),
			role="parent",
			preferred_language="en",
			is_active=True,
		)
		session.add(user)
		session.commit()
		user_id = user.id
	try:
		yield user_id, email
	finally:
		with factory() as session:
			session.query(get_model("AuthSession")).filter_by(user_id=user_id).delete()
			session.query(get_model("AuthOtpChallenge")).filter_by(user_id=user_id).delete()
			session.query(get_model("ParentEmailVerification")).filter_by(user_id=user_id).delete()
			session.query(User).filter_by(id=user_id).delete()
			session.commit()


def _race(factory, attempt):
	"""Run ``attempt(session)`` in THREADS sessions released together; count successes and failures."""
	barrier = Barrier(THREADS)

	def one(_):
		with factory() as session:
			barrier.wait()
			try:
				return attempt(session)
			except APIError as error:
				session.rollback()
				return error

	with ThreadPoolExecutor(THREADS) as pool:
		results = list(pool.map(one, range(THREADS)))
	return [r for r in results if not isinstance(r, APIError)], [r for r in results if isinstance(r, APIError)]


def _session_count(factory, user_id) -> int:
	with factory() as session:
		return session.query(get_model("AuthSession")).filter_by(user_id=user_id).count()


def test_11_one_login_code_starts_exactly_one_session_under_concurrency(factory, parent):
	user_id, email = parent
	now = datetime.now(timezone.utc)
	with factory() as session:
		session.query(get_model("User")).filter_by(id=user_id).update({"email_verified_at": now})
		session.add(
			get_model("AuthOtpChallenge")(
				user_id=user_id,
				purpose="login",
				otp_hash=hash_password(CODE),
				expires_at=now + timedelta(minutes=5),
				attempts=0,
				last_sent_at=now,
			)
		)
		session.commit()

	wins, losses = _race(factory, lambda s: login_code_service.sign_in_with_code(s, email, CODE))
	assert len(wins) == 1, f"{len(wins)} sessions from one code"
	assert all(error.code == "invalid_login_code" for error in losses)
	assert _session_count(factory, user_id) == 1


def test_11_one_registration_code_starts_exactly_one_session_under_concurrency(factory, parent):
	user_id, email = parent
	now = datetime.now(timezone.utc)
	with factory() as session:
		session.add(
			get_model("ParentEmailVerification")(
				user_id=user_id,
				otp_hash=hash_password(CODE),
				expires_at=now + timedelta(minutes=5),
				attempts=0,
				last_sent_at=now,
			)
		)
		session.commit()

	wins, losses = _race(factory, lambda s: verify_parent_email(s, email, CODE))
	assert len(wins) == 1, f"{len(wins)} sessions from one code"
	assert {error.code for error in losses} <= {"expired_verification_code", "invalid_verification_code"}
	assert _session_count(factory, user_id) == 1
	with factory() as session:
		assert session.query(get_model("User")).filter_by(id=user_id).one().email_verified_at is not None


def test_concurrent_code_requests_leave_one_live_code(factory, parent):
	user_id, email = parent
	with factory() as session:
		session.query(get_model("User")).filter_by(id=user_id).update({"email_verified_at": datetime.now(timezone.utc)})
		session.commit()

	def request(session):
		issued = login_code_service.issue_login_code(session, email)
		session.commit()
		return issued

	wins, losses = _race(factory, request)
	assert losses == []  # no unique-index violation leaks out as an error
	sent = [issued for issued in wins if issued is not None]
	assert len(sent) == 1  # the others fell inside the resend cooldown
	Challenge = get_model("AuthOtpChallenge")
	with factory() as session:
		assert session.query(Challenge).filter_by(user_id=user_id, consumed_at=None).count() == 1
	with factory() as session:
		signed_in = login_code_service.sign_in_with_code(session, email, sent[0][1])
	assert signed_in.user.email == email
