"""Change password and sign out everywhere (existing users/auth_sessions only).

In-memory SQLite (tests/sqlite_world.py); route functions are called directly.
Not PostgreSQL. The ``require_parent`` guard on both routes is covered by
tests/test_authorization_boundaries.py (child and admin tokens are refused).
"""

from __future__ import annotations

from datetime import datetime, timedelta, timezone
from uuid import UUID

import pytest
from pydantic import ValidationError

from app.core.exceptions import APIError
from app.core.rate_limit import FixedWindowLimiter
from app.core.security import hash_password, verify_password
from app.schemas.auth import PasswordChangeRequest
from tests.sqlite_world import AuthSession, User, world_session  # noqa: F401

OLD = "old-password-123"
NEW = "brand-new-password-456"


@pytest.fixture
def db(world_session, monkeypatch):
	import app.api.v1.auth as auth_api
	import app.services.account_security_service as service
	from app.core.config import settings
	from tests.sqlite_world import _get_model

	monkeypatch.setattr(service, "get_model", _get_model)
	monkeypatch.setattr(settings, "jwt_secret_key", "account-security-test-secret-long-enough-0123")
	monkeypatch.setattr(auth_api, "password_change_limiter", FixedWindowLimiter())
	# The SQLite user row has no full_name; the real start_session still runs
	# (session row, refresh token, access token), only the profile echo is faked.
	import app.services.session_service as sessions
	from app.schemas.auth import UserPublic

	monkeypatch.setattr(
		sessions,
		"UserPublic",
		type(
			"UserPublicForTests",
			(),
			{
				"model_validate": staticmethod(
					lambda user: UserPublic(
						id=user.id, full_name="Test Parent", email=user.email, role=user.role, preferred_language="en"
					)
				)
			},
		),
	)
	return world_session


def make_user(db, role="parent"):
	user = User(role=role, email=f"{role}@example.com", password_hash=hash_password(OLD))
	db.add(user)
	db.commit()
	return user


def open_session(db, user, *, label=None, issued_by=None) -> UUID:
	row = AuthSession(
		user_id=user.id,
		kind="child" if user.role == "child" else "parent",
		device_label=label,
		issued_by=issued_by,
		expires_at=datetime.now(timezone.utc).replace(tzinfo=None) + timedelta(days=30),
	)
	db.add(row)
	db.commit()
	return row.id


def active(db, session_id) -> bool:
	from app.services.session_service import is_session_revoked

	return not is_session_revoked(db, str(session_id))


def change(db, parent, session_id, current=OLD, new=NEW):
	from app.api.v1.auth import change_password

	return change_password(
		PasswordChangeRequest(current_password=current, new_password=new),
		parent=parent,
		session_id=session_id,
		session=db,
	)


def logout_all(db, parent, session_id):
	from app.api.v1.auth import logout_all as route

	return route(parent=parent, session_id=session_id, session=db)


def test_changing_the_password_ends_every_parent_session_but_this_device_gets_a_new_one(db):
	parent = make_user(db)
	child = make_user(db, role="child")
	here = open_session(db, parent)
	other_phone = open_session(db, parent)
	parent_mode_on_tablet = open_session(db, parent, label="parent_mode", issued_by=child.id)
	child_device = open_session(db, child)

	tokens = change(db, parent, here)

	assert verify_password(NEW, db.get(User, parent.id).password_hash)
	for old in (here, other_phone, parent_mode_on_tablet):
		assert not active(db, old)
	assert active(db, child_device), "a child's own session is not touched"
	assert tokens.refresh_token
	new_rows = db.query(AuthSession).filter_by(user_id=parent.id, revoked_at=None).all()
	assert len(new_rows) == 1


def test_a_wrong_current_password_changes_nothing(db):
	parent = make_user(db)
	here = open_session(db, parent)

	with pytest.raises(APIError) as refused:
		change(db, parent, here, current="not-the-password")

	assert refused.value.status_code == 400
	assert refused.value.code == "invalid_current_password"
	assert verify_password(OLD, db.get(User, parent.id).password_hash)
	assert active(db, here)


def test_the_same_password_is_refused(db):
	parent = make_user(db)
	here = open_session(db, parent)

	with pytest.raises(APIError) as refused:
		change(db, parent, here, new=OLD)

	assert refused.value.status_code == 422
	assert active(db, here)


def test_a_parent_mode_session_on_a_childs_device_cannot_change_it(db):
	parent = make_user(db)
	child = make_user(db, role="child")
	tablet = open_session(db, parent, label="parent_mode", issued_by=child.id)
	phone = open_session(db, parent)

	with pytest.raises(APIError) as refused:
		change(db, parent, tablet)

	assert refused.value.status_code == 403
	assert refused.value.code == "parent_mode_not_allowed"
	assert verify_password(OLD, db.get(User, parent.id).password_hash)
	assert active(db, phone)


def test_wrong_passwords_are_limited_per_account(db):
	parent = make_user(db)
	here = open_session(db, parent)
	from fastapi import HTTPException

	for _ in range(5):
		with pytest.raises(APIError):
			change(db, parent, here, current="guess-guess-guess")
	with pytest.raises(HTTPException) as limited:
		change(db, parent, here)

	assert limited.value.status_code == 429
	assert verify_password(OLD, db.get(User, parent.id).password_hash)


def test_new_passwords_follow_the_registration_rule():
	with pytest.raises(ValidationError):
		PasswordChangeRequest(current_password=OLD, new_password="short")


def test_logout_all_ends_every_parent_session_and_no_child_session(db):
	parent = make_user(db)
	child = make_user(db, role="child")
	here = open_session(db, parent)
	other_phone = open_session(db, parent)
	child_device = open_session(db, child)

	response = logout_all(db, parent, here)

	assert response.status_code == 204
	assert not active(db, here), "this device is signed out too"
	assert not active(db, other_phone)
	assert active(db, child_device)


def test_logout_all_is_refused_from_a_parent_mode_session(db):
	parent = make_user(db)
	child = make_user(db, role="child")
	tablet = open_session(db, parent, label="parent_mode", issued_by=child.id)
	phone = open_session(db, parent)

	with pytest.raises(APIError) as refused:
		logout_all(db, parent, tablet)

	assert refused.value.status_code == 403
	assert active(db, phone)
	assert active(db, tablet)


def test_another_parent_is_never_affected(db):
	parent = make_user(db)
	other = User(role="parent", email="other@example.com", password_hash=hash_password(OLD))
	db.add(other)
	db.commit()
	here = open_session(db, parent)
	theirs = open_session(db, other)

	logout_all(db, parent, here)

	assert active(db, theirs)
