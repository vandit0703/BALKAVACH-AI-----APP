import secrets
from datetime import datetime, timedelta, timezone

from sqlalchemy.orm import Session

from app.core.exceptions import APIError
from app.core.security import hash_password, verify_password
from app.db.base import get_model

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


def verify_parent_email(session: Session, email: str, otp: str) -> None:
	User = get_model("User")
	user = session.query(User).filter(
		User.email == email.strip().lower(),
		User.role == "parent",
		User.is_active.is_(True),
	).one_or_none()
	if user is None:
		raise APIError(400, "invalid_verification_code", "The verification code is invalid")
	if user.email_verified_at is not None:
		return
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
	user.email_verified_at = _now()
	session.delete(row)
	session.commit()