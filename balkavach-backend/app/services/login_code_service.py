"""Passwordless sign-in with an emailed one-time code (existing, verified parent accounts only).

Separate from registration verification (``email_verification_service``): codes live in their own table
(``auth_otp_challenges``, migration 0025) with ``purpose = 'login'``, so neither kind of code can ever be
used as the other.

Rules
- Only an active parent whose email is already verified can receive or use a sign-in code. An unverified
  account must finish registration verification; otherwise someone who pre-registered another person's
  address could have it "verified" by its real owner and keep the password they chose.
- Codes are 6 digits, stored hashed, valid for ``CODE_EXPIRY_MINUTES``, single use, and burned after
  ``MAX_ATTEMPTS`` wrong guesses. A new request replaces the previous code (the old one stops working).
- Every failure (unknown address, ineligible account, no code, wrong, expired, used or burned code) is the
  same 400 ``invalid_login_code`` with the same hashing work, so responses do not reveal whether an
  account exists.
- The challenge row is locked (``FOR UPDATE``) and marked consumed in the same transaction that creates the
  session, so one code can start at most one session even under concurrent requests.
"""

import secrets
from datetime import datetime, timedelta, timezone

from sqlalchemy.orm import Session

from app.core.exceptions import APIError
from app.core.security import hash_password, verify_password
from app.db.base import get_model, has_model
from app.schemas.auth import TokenResponse
from app.services.session_service import start_session

PURPOSE = "login"
CODE_EXPIRY_MINUTES = 10
MAX_ATTEMPTS = 5
RESEND_COOLDOWN_SECONDS = 60
# Used or expired challenges are kept this long (for support questions), then removed.
RETENTION = timedelta(days=1)


def _now() -> datetime:
	return datetime.now(timezone.utc)


def available() -> bool:
	return has_model("AuthOtpChallenge")


def _invalid() -> APIError:
	return APIError(400, "invalid_login_code", "The sign-in code is invalid or has expired. Request a new code.")


def _eligible_parent(session: Session, email: str, *, lock: bool = False):
	User = get_model("User")
	query = session.query(User).filter(
		User.email == email.strip().lower(),
		User.role == "parent",
		User.is_active.is_(True),
		User.email_verified_at.is_not(None),
	)
	if lock:
		query = query.with_for_update()
	return query.one_or_none()


def _active_challenge(session: Session, user_id):
	Challenge = get_model("AuthOtpChallenge")
	return (
		session.query(Challenge)
		.filter(Challenge.user_id == user_id, Challenge.purpose == PURPOSE, Challenge.consumed_at.is_(None))
		.with_for_update()
		.one_or_none()
	)


def issue_login_code(session: Session, email: str) -> tuple[str, str] | None:
	"""Create (or replace) the sign-in code for an eligible account. Caller commits and sends the email.

	Returns ``None`` for an unknown or ineligible address, and while the previous code was sent less than
	``RESEND_COOLDOWN_SECONDS`` ago; the endpoint answers all of these exactly like a successful request.
	"""
	# Locking the account serialises concurrent requests for it (one live challenge per account).
	user = _eligible_parent(session, email, lock=True)
	if user is None:
		return None
	Challenge = get_model("AuthOtpChallenge")
	now = _now()
	session.query(Challenge).filter(
		Challenge.user_id == user.id,
		Challenge.purpose == PURPOSE,
		Challenge.consumed_at.is_not(None),
	).delete(synchronize_session=False)
	row = _active_challenge(session, user.id)
	if row is not None and (now - row.last_sent_at).total_seconds() < RESEND_COOLDOWN_SECONDS:
		return None
	otp = f"{secrets.randbelow(1_000_000):06d}"
	values = {
		"otp_hash": hash_password(otp),
		"expires_at": now + timedelta(minutes=CODE_EXPIRY_MINUTES),
		"attempts": 0,
		"last_sent_at": now,
	}
	if row is None:
		session.add(Challenge(user_id=user.id, purpose=PURPOSE, **values))
	else:
		for field, value in values.items():
			setattr(row, field, value)
	session.flush()
	return str(user.email), otp


def sign_in_with_code(session: Session, email: str, otp: str) -> TokenResponse:
	"""Check and consume a sign-in code and start the parent's session. Commits."""
	from app.services.auth_service import _dummy_password_hash

	user = _eligible_parent(session, email)
	row = _active_challenge(session, user.id) if user is not None else None
	now = _now()
	if row is None or row.expires_at <= now or row.attempts >= MAX_ATTEMPTS:
		verify_password(otp, _dummy_password_hash())
		raise _invalid()
	if not verify_password(otp, row.otp_hash):
		row.attempts += 1
		if row.attempts >= MAX_ATTEMPTS:
			row.consumed_at = now  # burned: a new code must be requested
		session.commit()
		raise _invalid()
	row.consumed_at = now
	session.flush()
	user.last_login_at = now.replace(tzinfo=None)
	response = start_session(session, user)
	session.commit()
	return response


def purge_stale_challenges(session: Session, *, now: datetime | None = None) -> int:
	"""Delete used, burned and expired sign-in codes older than ``RETENTION``. Caller commits.

	Safe to run at any time (for example from a periodic job): it never touches a live, unexpired code.
	"""
	Challenge = get_model("AuthOtpChallenge")
	cutoff = (now or _now()) - RETENTION
	return (
		session.query(Challenge)
		.filter((Challenge.expires_at < cutoff) | (Challenge.consumed_at < cutoff))
		.delete(synchronize_session=False)
	)
