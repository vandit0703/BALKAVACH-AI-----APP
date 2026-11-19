"""Entering parent mode from a child device: the same email + password check as parent login.

This reuses the existing primitives (``verify_password``, ``start_session``) and adds what
the plain login endpoint cannot know: the request is made from an **authenticated child
session**, so the parent must be an active member of **that child's family**.

Guarantees
* Only an authenticated child session may call it (route dependency ``require_child``).
* One generic failure for every reason: unknown email, wrong password, a parent of a
  different family, a child/admin account. Exactly one password hash is always computed so
  timing does not distinguish them either.
* Failures are tracked per target email *within the child's family*, per family and per child device
  session (never per IP). A locked subject is refused *before* any credential is evaluated.
* The issued parent session is a normal revocable session with a shortened refresh lifetime
  (``parent_mode_refresh_hours``), labelled ``parent_mode`` and linked to the child that
  requested it (``issued_by``).
"""

from __future__ import annotations

import hashlib
import logging
from datetime import timedelta
from uuid import UUID

from sqlalchemy.orm import Session

from app.core.config import settings
from app.core.exceptions import APIError
from app.core.security import hash_password, verify_password
from app.db.base import get_model
from app.schemas.auth import TokenResponse
from app.services.admin_service import record_audit
from app.services.attempt_lockout import AttemptLockout, parent_mode_lockout
from app.services.notification_service import create_notification, family_parent_ids
from app.services.session_service import PARENT_MODE_LABEL, start_session

logger = logging.getLogger(__name__)

GENERIC_FAILURE = "Email or password is incorrect"
_dummy_hash: str | None = None


def _dummy_password_hash() -> str:
	global _dummy_hash
	if _dummy_hash is None:
		_dummy_hash = hash_password("balkavach-timing-equalisation-value")
	return _dummy_hash


def email_subject(email: str, family_id: UUID) -> str:
	"""Failures against one address *within one family*.

	Scoped to the family on purpose: guessing a parent's password is only possible from a child session of
	that parent's own family (anyone else always fails the membership check), so a global per-address lock
	would only let a stranger with a child account of their own lock a parent out of theirs."""
	digest = hashlib.sha256(f"{family_id}:{email.strip().lower()}".encode("utf-8")).hexdigest()[:32]
	return f"email:{digest}"


def lockout_subjects(email: str, family_id: UUID, device: object) -> list[str]:
	return [email_subject(email, family_id), f"family:{family_id}", f"device:{device}"]


def _locked_error(seconds: int) -> APIError:
	return APIError(
		423,
		"parent_mode_locked",
		"Too many incorrect attempts. Please try again later.",
		headers={"Retry-After": str(max(1, seconds))},
		details={"retry_after_seconds": max(1, seconds)},
	)


def _notify_lock(session: Session, child, family_id: UUID) -> None:
	"""Tell the family's parents. Never allowed to break the response."""
	try:
		with session.begin_nested():
			for parent_id in family_parent_ids(session, family_id):
				create_notification(
					session,
					parent_id,
					"parent_mode_locked",
					"Parent sign-in locked",
					f"Several incorrect parent sign-in attempts were made on {child.display_name}'s device.",
				)
	except Exception:
		logger.exception("Could not create parent-mode lock notification")


def enter_parent_mode(
	session: Session,
	*,
	child,
	child_user,
	session_id: UUID | None,
	email: str,
	password: str,
	lockout: AttemptLockout | None = None,
) -> TokenResponse:
	lockout = lockout or parent_mode_lockout
	subjects = lockout_subjects(email, child.family_id, session_id or child_user.id)

	locked = max(lockout.locked_for(subject) for subject in subjects)
	if locked:
		raise _locked_error(locked)

	User = get_model("User")
	FamilyMember = get_model("FamilyMember")
	normalized = email.strip().lower()
	parent = (
		session.query(User)
		.filter(User.email == normalized, User.role == "parent", User.is_active.is_(True))
		.one_or_none()
	)
	is_member = False
	if parent is not None:
		is_member = (
			session.query(FamilyMember.id)
			.filter(
				FamilyMember.family_id == child.family_id,
				FamilyMember.user_id == parent.id,
				FamilyMember.is_active.is_(True),
			)
			.first()
			is not None
		)
	# Exactly one hash verification on every path, so timing reveals nothing.
	stored_hash = parent.password_hash if parent is not None and parent.password_hash else _dummy_password_hash()
	password_ok = verify_password(password, stored_hash)

	if not (parent is not None and is_member and password_ok):
		results = [lockout.record_failure(subject) for subject in subjects]
		record_audit(session, child_user.id, "parent_mode.failed", "child_profile", child.id, {})
		if any(result.newly_locked for result in results):
			record_audit(session, child_user.id, "parent_mode.locked", "child_profile", child.id, {})
			_notify_lock(session, child, child.family_id)
		session.commit()
		locked_now = max(result.locked_for for result in results)
		if locked_now:
			raise _locked_error(locked_now)
		remaining = min(result.attempts_remaining for result in results)
		raise APIError(
			403,
			"parent_authentication_failed",
			GENERIC_FAILURE,
			details={"attempts_remaining": remaining},
		)

	for subject in subjects:
		lockout.record_success(subject)
	response = start_session(
		session,
		parent,
		issued_by=child_user.id,
		refresh_ttl=timedelta(hours=settings.parent_mode_refresh_hours),
		device_label=PARENT_MODE_LABEL,
	)
	record_audit(session, parent.id, "parent_mode.entered", "child_profile", child.id, {})
	session.commit()
	return response
