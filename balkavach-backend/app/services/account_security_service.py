"""Parent account security: change password and sign out everywhere.

Uses the existing ``users.password_hash`` and ``auth_sessions`` rows only (no
schema change).

* Parent accounts only. Child accounts are separate users whose credentials a
  parent manages; nothing here touches a child's sessions.
* Refused from a **parent-mode session** (a parent session opened on a child's
  device, ``device_label = "parent_mode"``): account-wide actions must come from
  the parent's own sign-in.
* Revocation is immediate for every token that carries a session id (``sid``),
  because ``get_current_user`` checks it on each request. A legacy access token
  without ``sid`` cannot be revoked and lapses at its normal expiry (SEC-06).
"""

from __future__ import annotations

from uuid import UUID

from sqlalchemy.orm import Session

from app.core.exceptions import APIError
from app.core.security import hash_password, verify_password
from app.db.base import get_model
from app.schemas.auth import TokenResponse
from app.services import session_service


def _require_own_device(session: Session, session_id: UUID | None) -> None:
	if session_id is None:
		return
	AuthSession = session_service._auth_session_model()
	if AuthSession is None:
		return
	row = session.query(AuthSession).filter(AuthSession.id == session_id).one_or_none()
	if row is not None and getattr(row, "device_label", None) == session_service.PARENT_MODE_LABEL:
		raise APIError(
			403,
			"parent_mode_not_allowed",
			"Sign in on your own device to change account security settings.",
		)


def change_password(
	session: Session,
	parent,
	session_id: UUID | None,
	*,
	current_password: str,
	new_password: str,
) -> TokenResponse:
	"""Verify the current password, store the new one, end every session of this
	parent (other phones and parent-mode sessions on children's devices
	included) and return a fresh session for this device."""
	_require_own_device(session, session_id)
	User = get_model("User")
	user = (
		session.query(User)
		.filter(User.id == parent.id, User.is_active.is_(True))
		.with_for_update()
		.one_or_none()
	)
	if user is None or not user.password_hash or not verify_password(current_password, user.password_hash):
		raise APIError(400, "invalid_current_password", "The current password is not correct.")
	if verify_password(new_password, user.password_hash):
		raise APIError(422, "password_unchanged", "Choose a password you have not been using.")
	user.password_hash = hash_password(new_password)
	session.flush()
	# Commits the new hash together with the revocation of every session.
	session_service.revoke_user_sessions(session, user.id)
	tokens = session_service.start_session(session, user)
	session.commit()
	return tokens


def sign_out_everywhere(session: Session, parent, session_id: UUID | None) -> int:
	"""End every session of this parent, this one included. Returns how many."""
	_require_own_device(session, session_id)
	return session_service.revoke_user_sessions(session, parent.id)
