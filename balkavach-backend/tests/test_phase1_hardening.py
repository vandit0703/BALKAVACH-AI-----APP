"""Regression tests for Phase 1 defects found while verifying parent-mode / password reset.

SQLite world (``tests/sqlite_world.py``) + fakeredis; no PostgreSQL baseline needed.
"""

import inspect
from datetime import datetime, timedelta, timezone
from uuid import uuid4

import fakeredis
import pytest
from fastapi import BackgroundTasks

from app.api.v1 import auth as auth_api
from app.core import dependencies as deps
from app.core.config import settings
from app.services import session_service
from app.services.attempt_lockout import AttemptLockout
from app.services.parent_mode_service import lockout_subjects
from tests.sqlite_world import AuthSession, world_session  # noqa: F401  (fixture)


def _now() -> datetime:
	return datetime.now(timezone.utc).replace(tzinfo=None)


def _session_row(session, **values) -> AuthSession:
	row = AuthSession(user_id=uuid4(), expires_at=values.pop("expires_at", _now() + timedelta(hours=12)), **values)
	session.add(row)
	session.flush()
	return row


# -- expired sessions ---------------------------------------------------------------------------

def test_a_session_past_its_expiry_is_treated_as_ended_even_with_a_valid_access_token(world_session):
	live = _session_row(world_session)
	expired = _session_row(world_session, expires_at=_now() - timedelta(seconds=1))
	assert session_service.is_session_revoked(world_session, str(live.id)) is False
	assert session_service.is_session_revoked(world_session, str(expired.id)) is True


def test_a_revoked_or_unknown_session_is_ended(world_session):
	revoked = _session_row(world_session, revoked_at=_now())
	assert session_service.is_session_revoked(world_session, str(revoked.id)) is True
	assert session_service.is_session_revoked(world_session, str(uuid4())) is True


# -- switching back to child mode ----------------------------------------------------------------

def test_starting_child_mode_ends_the_parent_mode_session_that_asked_for_it(world_session):
	parent_mode = _session_row(world_session, device_label=session_service.PARENT_MODE_LABEL)
	assert session_service.end_parent_mode_session(world_session, parent_mode.id) is True
	assert parent_mode.revoked_at is not None
	assert session_service.is_session_revoked(world_session, str(parent_mode.id)) is True


def test_an_ordinary_parent_login_session_is_not_ended_by_that_helper(world_session):
	ordinary = _session_row(world_session)
	assert session_service.end_parent_mode_session(world_session, ordinary.id) is False
	assert ordinary.revoked_at is None
	assert session_service.end_parent_mode_session(world_session, None) is False


def test_child_session_issue_route_knows_which_session_is_calling():
	params = inspect.signature(auth_api.issue_child_session).parameters
	assert "session_id" in params
	assert params["session_id"].default.dependency is deps.current_session_id


# -- lockout scope ------------------------------------------------------------------------------

def test_the_email_subject_is_scoped_to_the_family_being_attacked():
	mine, theirs = uuid4(), uuid4()
	a = lockout_subjects("Parent@Example.com", mine, "dev-1")
	b = lockout_subjects("parent@example.com", theirs, "dev-9")
	email_a = next(x for x in a if x.startswith("email:"))
	email_b = next(x for x in b if x.startswith("email:"))
	assert email_a != email_b
	assert email_a == next(x for x in lockout_subjects(" parent@EXAMPLE.com ", mine, "dev-2") if x.startswith("email:"))
	assert f"family:{mine}" in a and "dev-1" in " ".join(a)
	assert "parent@example.com" not in " ".join(a)  # nothing readable about the account in Redis keys


def test_a_stranger_family_cannot_lock_a_parent_out_of_their_own_family(monkeypatch):
	monkeypatch.setattr(settings, "parent_mode_max_failures", 3)
	lockout = AttemptLockout(client=fakeredis.FakeRedis(decode_responses=True))
	victim_email = "victim@example.com"
	attacker_family, victim_family = uuid4(), uuid4()
	for _ in range(3):  # the attacker hammers the victim's address from the attacker's own child device
		for subject in lockout_subjects(victim_email, attacker_family, "attacker-device"):
			lockout.record_failure(subject)
	assert all(lockout.locked_for(s) == 0 for s in lockout_subjects(victim_email, victim_family, "victim-device"))
	assert any(lockout.locked_for(s) > 0 for s in lockout_subjects(victim_email, attacker_family, "attacker-device"))


# -- forgot password never leaks existence through delivery work ---------------------------------

def test_forgot_password_hands_email_delivery_to_a_background_task():
	params = inspect.signature(auth_api.forgot_password).parameters
	assert any(p.annotation is BackgroundTasks for p in params.values())
	source = inspect.getsource(auth_api.forgot_password)
	assert "send_password_reset(" not in source.replace("background.add_task(send_password_reset", "")
