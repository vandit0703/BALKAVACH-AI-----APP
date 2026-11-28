import secrets
from datetime import datetime, timedelta, timezone

from sqlalchemy.orm import Session

from app.core.exceptions import APIError
from app.core.security import hash_password, verify_password
from app.db.base import get_model
from app.schemas.auth import TokenResponse
from app.services.session_service import start_session

OTP_EXPIRY_MINUTES = 5
OTP_MAX_ATTEMPTS = 5
RESEND_COOLDOWN_SECONDS = 60


def _now() -> datetime:
	return datetime.now(timezone.utc)


def create_verification(session: Session, user) -> str:
	Verification = get_model("ParentEmailVerification")
	otp = f"{secrets.randbelow(1_000_000):06d}"
	now = _now()
	row = session.query(Verification).filter(Verification.user_id == user.id).with_for_update().one_or_none()
	values = {
		"otp_hash": hash_password(otp),
		"expires_at": now + timedelta(minutes=OTP_EXPIRY_MINUTES),
		"attempts": 0,
		"last_sent_at": now,
	}
	if row is None:
		session.add(Verification(user_id=user.id, **values))
	else:
		for field, value in values.items():
			setattr(row, field, value)
	session.flush()
	return otp


def resend_verification(session: Session, email: str) -> tuple[str, str] | None:
	User = get_model("User")
	user = session.query(User).filter(
		User.email == email.strip().lower(),
		User.role == "parent",
		User.is_active.is_(True),
		User.email_verified_at.is_(None),
	).one_or_none()
	if user is None:
		return None
	Verification = get_model("ParentEmailVerification")
	row = session.query(Verification).filter(Verification.user_id == user.id).with_for_update().one_or_none()
	now = _now()
	if row is not None and (now - row.last_sent_at).total_seconds() < RESEND_COOLDOWN_SECONDS:
		return None
	return user.email, create_verification(session, user)


def verify_parent_email(session: Session, email: str, otp: str) -> TokenResponse:
	"""Check and consume a *registration* code, mark the email verified and start the parent's session.

	Only a correct, unexpired, unconsumed registration code for this exact account reaches the session.
	An unknown or already-verified account is answered exactly like a wrong code (and costs the same
	hashing work): an already-verified account never gets a session from this endpoint, whatever code
	is sent. Sign-in for verified accounts is the password or the separate sign-in code.

	Consumption is the deletion of the locked verification row, in the same transaction that creates
	the session, so two concurrent requests with the same code cannot both succeed.
	"""
	User = get_model("User")
	user = session.query(User).filter(
		User.email == email.strip().lower(),
		User.role == "parent",
		User.is_active.is_(True),
	).one_or_none()
	if user is None or user.email_verified_at is not None:
		from app.services.auth_service import _dummy_password_hash

		verify_password(otp, _dummy_password_hash())
		raise APIError(400, "invalid_verification_code", "The verification code is invalid")
	Verification = get_model("ParentEmailVerification")
	row = session.query(Verification).filter(Verification.user_id == user.id).with_for_update().one_or_none()
	if row is None or row.expires_at <= _now():
		raise APIError(400, "expired_verification_code", "The verification code is invalid or expired")
	if row.attempts >= OTP_MAX_ATTEMPTS:
		raise APIError(429, "verification_attempts_exceeded", "Too many incorrect verification attempts")
	if not verify_password(otp, row.otp_hash):
		row.attempts += 1
		session.commit()
		if row.attempts >= OTP_MAX_ATTEMPTS:
			raise APIError(429, "verification_attempts_exceeded", "Too many incorrect verification attempts")
		raise APIError(400, "invalid_verification_code", "The verification code is invalid")
	now = _now()
	user.email_verified_at = now
	session.delete(row)
	session.flush()
	user.last_login_at = now.replace(tzinfo=None)
	response = start_session(session, user)
	session.commit()
	return response