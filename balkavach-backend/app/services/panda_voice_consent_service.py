"""Parental consent for Talk to Panda's microphone (speech recognition).

Stored in the existing ``consent_records`` table (no schema change): one row per
grant, ``consent_type = "panda_voice"``, scoped to the family and the child.
Consent is in force while the newest grant is accepted and not revoked.

* Only a parent who is an active member of the child's family can read, grant
  or revoke it. Revoking is allowed for **any** such parent (stopping is the
  safe direction), unlike the generic consent revoke, which is limited to the
  parent who recorded the row.
* A grant must name the consent-text version the parent was shown
  (``PANDA_VOICE_CONSENT_VERSION``). A newer text version makes older grants
  stale: the parent must agree again.
* Nothing here stores audio or what the child said; the app keeps no audio
  either. The text version below is a product draft and still needs owner and
  legal approval (see docs/panda-talking-companion.md).
"""

from __future__ import annotations

from datetime import datetime, timezone
from uuid import UUID

from fastapi import HTTPException
from sqlalchemy.orm import Session

from app.core.exceptions import APIError
from app.db.base import get_model
from app.utils import utc_naive

CONSENT_TYPE = "panda_voice"
# Version of the consent explanation shown in the parent app. Bump it (and the
# app strings) when the wording changes; older grants then stop counting.
PANDA_VOICE_CONSENT_VERSION = "panda-voice-2026-11-20"


def require_family_child(session: Session, family_id: UUID, child_id: UUID, parent_id: UUID):
	"""The child, if ``parent_id`` is an active member of the child's family; 404 otherwise."""
	FamilyMember = get_model("FamilyMember")
	ChildProfile = get_model("ChildProfile")
	member = session.query(FamilyMember.id).filter(
		FamilyMember.family_id == family_id,
		FamilyMember.user_id == parent_id,
		FamilyMember.is_active.is_(True),
	).first()
	child = (
		session.query(ChildProfile)
		.filter(ChildProfile.id == child_id, ChildProfile.family_id == family_id)
		.one_or_none()
	)
	if member is None or child is None:
		# One answer for "not your family" and "no such child": no existence oracle.
		raise HTTPException(status_code=404, detail="Child profile not found")
	return child


def _active_grants(session: Session, child_id: UUID, *, for_update: bool = False):
	ConsentRecord = get_model("ConsentRecord")
	query = session.query(ConsentRecord).filter(
		ConsentRecord.child_id == child_id,
		ConsentRecord.consent_type == CONSENT_TYPE,
		ConsentRecord.accepted.is_(True),
		ConsentRecord.revoked_at.is_(None),
	)
	if for_update:
		query = query.with_for_update()
	return query.order_by(ConsentRecord.created_at.desc()).all()


def current_grant(session: Session, child_id: UUID):
	"""The grant in force for the current consent text, or None."""
	for grant in _active_grants(session, child_id):
		if grant.document_version == PANDA_VOICE_CONSENT_VERSION:
			return grant
	return None


def is_granted(session: Session, child_id: UUID) -> bool:
	return current_grant(session, child_id) is not None


def is_refused(session: Session, child_id: UUID) -> bool:
	"""A parent explicitly turned voice off: no grant in force and the newest record was withdrawn.

	"No record yet" and "a grant for an older consent text" are not refusals. A refusal stops even
	on-device recognition, so the parent's switch keeps controlling the microphone.
	"""
	if is_granted(session, child_id):
		return False
	ConsentRecord = get_model("ConsentRecord")
	newest = (
		session.query(ConsentRecord)
		.filter(ConsentRecord.child_id == child_id, ConsentRecord.consent_type == CONSENT_TYPE)
		.order_by(ConsentRecord.created_at.desc())
		.first()
	)
	return newest is not None and newest.revoked_at is not None


def voice_turn_allowed(session: Session, child_id: UUID, speech: str) -> bool:
	"""On-device recognition: allowed unless a parent turned voice off. Cloud: needs consent."""
	if speech == "on_device":
		return not is_refused(session, child_id)
	return is_granted(session, child_id)


def describe(session: Session, child_id: UUID) -> dict:
	grant = current_grant(session, child_id)
	return {
		"child_id": child_id,
		"granted": grant is not None,
		"granted_at": grant.accepted_at if grant is not None else None,
		"granted_by": grant.parent_user_id if grant is not None else None,
		"document_version": PANDA_VOICE_CONSENT_VERSION,
	}


def grant(session: Session, child, parent_id: UUID, document_version: str) -> dict:
	"""Record the parent's agreement to the current text (idempotent)."""
	if document_version != PANDA_VOICE_CONSENT_VERSION:
		raise APIError(
			409,
			"consent_version_outdated",
			"The consent text has changed. Show the current text and ask again.",
		)
	if current_grant(session, child.id) is None:
		ConsentRecord = get_model("ConsentRecord")
		now = utc_naive(datetime.now(timezone.utc))
		session.add(
			ConsentRecord(
				family_id=child.family_id,
				child_id=child.id,
				parent_user_id=parent_id,
				consent_type=CONSENT_TYPE,
				document_version=PANDA_VOICE_CONSENT_VERSION,
				accepted=True,
				accepted_at=now,
				revoked_at=None,
				created_at=now,
			)
		)
		session.commit()
	return describe(session, child.id)


def revoke(session: Session, child) -> dict:
	"""Withdraw consent: every active panda_voice grant for this child (idempotent)."""
	now = utc_naive(datetime.now(timezone.utc))
	changed = False
	for record in _active_grants(session, child.id, for_update=True):
		record.revoked_at = now
		changed = True
	if changed:
		session.commit()
	return describe(session, child.id)
