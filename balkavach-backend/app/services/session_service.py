"""Refresh-token sessions.

Refresh tokens are random 48-byte values; only their SHA-256 digest is stored.
Every refresh rotates the token. Presenting a token that was already rotated away
is treated as theft and revokes the whole session.

If the ``auth_sessions`` table has not been migrated yet, issuing degrades to
"access token only" (the pre-existing behaviour) so a deploy that precedes the
migration cannot break sign-in.
"""

import hashlib
import logging
import secrets
from datetime import datetime, timedelta, timezone
from uuid import UUID

from sqlalchemy.orm import Session

from app.core.config import settings
from app.core.exceptions import APIError
from app.core.security import create_access_token
from app.db.base import get_model
from app.schemas.auth import TokenResponse, UserPublic

logger = logging.getLogger(__name__)


def _auth_session_model():
	try:
		return get_model("AuthSession")
	except (KeyError, AttributeError):
		return None


def _digest(token: str) -> str:
	return hashlib.sha256(token.encode("utf-8")).hexdigest()


def _now() -> datetime:
	return datetime.now(timezone.utc)


def _ttl(kind: str) -> timedelta:
	days = settings.child_refresh_token_expire_days if kind == "child" else settings.refresh_token_expire_days
	return timedelta(days=days)


def kind_for_role(role: str) -> str:
	if role == "child":
		return "child"
	return "admin" if role in {"admin", "staff"} else "parent"


def start_session(session: Session, user, *, issued_by: UUID | None = None) -> TokenResponse:
	"""Create a session row (when available) and return the token pair. Caller commits."""
	AuthSession = _auth_session_model()
	kind = kind_for_role(user.role)
	if AuthSession is None:
		logger.warning("auth_sessions table is missing; issuing an access token without a refresh token")
		access, expires_at = create_access_token(str(user.id))
		return TokenResponse(access_token=access, expires_at=expires_at, user=UserPublic.model_validate(user))
	refresh = secrets.token_urlsafe(48)
	refresh_expires = _now() + _ttl(kind)
	row = AuthSession(
		user_id=user.id,
		issued_by=issued_by,
		kind=kind,
		refresh_token_hash=_digest(refresh),
		expires_at=refresh_expires,
		last_used_at=_now(),
	)
	session.add(row)
	session.flush()
	access, expires_at = create_access_token(str(user.id), session_id=str(row.id))
	return TokenResponse(
		access_token=access,
		expires_at=expires_at,
		refresh_token=refresh,
		refresh_expires_at=refresh_expires,
		user=UserPublic.model_validate(user),
	)


def rotate(session: Session, refresh_token: str) -> TokenResponse:
	AuthSession = _auth_session_model()
	if AuthSession is None:
		raise APIError(501, "refresh_unavailable", "Session refresh is not available on this server")
	digest = _digest(refresh_token)
	row = session.query(AuthSession).filter(AuthSession.refresh_token_hash == digest).with_for_update().one_or_none()
	if row is None:
		reused = (
			session.query(AuthSession).filter(AuthSession.previous_token_hash == digest).with_for_update().one_or_none()
		)
		if reused is not None and reused.revoked_at is None:
			reused.revoked_at = _now()
			session.commit()
			logger.warning("Refresh token reuse detected; session %s revoked", reused.id)
			raise APIError(401, "refresh_token_reused", "This session was ended for your safety. Please sign in again.")
		raise APIError(401, "invalid_refresh_token", "Please sign in again")
	if row.revoked_at is not None or row.expires_at <= _now():
		raise APIError(401, "invalid_refresh_token", "Please sign in again")
	User = get_model("User")
	user = session.query(User).filter(User.id == row.user_id, User.is_active.is_(True)).one_or_none()
	if user is None:
		row.revoked_at = _now()
		session.commit()
		raise APIError(401, "invalid_refresh_token", "Please sign in again")
	new_refresh = secrets.token_urlsafe(48)
	row.previous_token_hash = row.refresh_token_hash
	row.refresh_token_hash = _digest(new_refresh)
	row.last_used_at = _now()
	row.expires_at = _now() + _ttl(row.kind)
	access, expires_at = create_access_token(str(user.id), session_id=str(row.id))
	response = TokenResponse(
		access_token=access,
		expires_at=expires_at,
		refresh_token=new_refresh,
		refresh_expires_at=row.expires_at,
		user=UserPublic.model_validate(user),
	)
	session.commit()
	return response


def revoke(session: Session, refresh_token: str) -> None:
	"""Idempotent: an unknown or already revoked token is not an error."""
	AuthSession = _auth_session_model()
	if AuthSession is None:
		return
	digest = _digest(refresh_token)
	row = session.query(AuthSession).filter(
		(AuthSession.refresh_token_hash == digest) | (AuthSession.previous_token_hash == digest)
	).with_for_update().first()
	if row is not None and row.revoked_at is None:
		row.revoked_at = _now()
		session.commit()


def revoke_user_sessions(session: Session, user_id: UUID) -> int:
	AuthSession = _auth_session_model()
	if AuthSession is None:
		return 0
	count = (
		session.query(AuthSession)
		.filter(AuthSession.user_id == user_id, AuthSession.revoked_at.is_(None))
		.update({AuthSession.revoked_at: _now()}, synchronize_session=False)
	)
	session.commit()
	return int(count or 0)


def is_session_revoked(session: Session, session_id: str) -> bool:
	AuthSession = _auth_session_model()
	if AuthSession is None:
		return False
	try:
		sid = UUID(session_id)
	except (TypeError, ValueError):
		return True
	row = session.query(AuthSession.revoked_at, AuthSession.expires_at).filter(AuthSession.id == sid).first()
	return row is None or row[0] is not None
