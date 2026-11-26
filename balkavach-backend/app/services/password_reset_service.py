import hashlib
import secrets
from datetime import datetime, timedelta, timezone

from sqlalchemy.orm import Session

from app.core.config import settings
from app.core.exceptions import APIError
from app.core.security import hash_password
from app.db.base import get_model


def _digest(token: str) -> str:
	return hashlib.sha256(token.encode("utf-8")).hexdigest()


def create_reset_token(session: Session, user) -> str:
	ResetToken = get_model("PasswordResetToken")
	now = datetime.now(timezone.utc)
	session.query(ResetToken).filter(
		ResetToken.user_id == user.id,
		ResetToken.used_at.is_(None),
	).update({ResetToken.used_at: now}, synchronize_session=False)
	token = secrets.token_urlsafe(48)
	session.add(
		ResetToken(
			user_id=user.id,
			token_hash=_digest(token),
			expires_at=now + timedelta(minutes=settings.password_reset_expire_minutes),
		)
	)
	session.flush()
	return token


def consume_reset_token(session: Session, token: str, password: str) -> None:
	ResetToken = get_model("PasswordResetToken")
	now = datetime.now(timezone.utc)
	row = (
		session.query(ResetToken)
		.filter(ResetToken.token_hash == _digest(token))
		.with_for_update()
		.one_or_none()
	)
	if row is None or row.used_at is not None or row.expires_at <= now:
		raise APIError(400, "invalid_reset_token", "This password reset link is invalid or expired")
	User = get_model("User")
	user = session.query(User).filter(User.id == row.user_id, User.is_active.is_(True)).one_or_none()
	if user is None or user.role != "parent":
		raise APIError(400, "invalid_reset_token", "This password reset link is invalid or expired")
	user.password_hash = hash_password(password)
	row.used_at = now
	from app.services.session_service import revoke_user_sessions

	session.flush()
	revoke_user_sessions(session, user.id)