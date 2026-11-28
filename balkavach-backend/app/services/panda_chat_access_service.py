"""Per-child parental approval for text chat with Panda."""

from __future__ import annotations

from datetime import datetime, timezone
from typing import Literal
from uuid import UUID

from fastapi import HTTPException
from sqlalchemy.orm import Session

from app.core.exceptions import APIError
from app.db.base import get_model
from app.services import notification_service
from app.utils import utc_naive

CONSENT_TYPE = "panda_chat_access"
DOCUMENT_VERSION = "panda-chat-access-v1"
AccessStatus = Literal["not_requested", "pending", "approved", "rejected", "revoked"]
AccessAction = Literal["approve", "reject", "revoke"]


def _latest(session: Session, child_id: UUID, *, for_update: bool = False):
	ConsentRecord = get_model("ConsentRecord")
	query = session.query(ConsentRecord).filter(
		ConsentRecord.child_id == child_id,
		ConsentRecord.consent_type == CONSENT_TYPE,
	)
	if for_update:
		query = query.with_for_update()
	return query.order_by(ConsentRecord.created_at.desc(), ConsentRecord.id.desc()).first()


def _status(record) -> AccessStatus:
	if record is None:
		return "not_requested"
	if record.accepted and record.revoked_at is None:
		return "approved"
	if not record.accepted and record.revoked_at is None:
		return "pending"
	return "revoked" if record.accepted else "rejected"


def _public(child_id: UUID, record) -> dict:
	state = _status(record)
	decided_at = None
	if record is not None:
		decided_at = record.accepted_at if state == "approved" else record.revoked_at
	return {
		"child_id": child_id,
		"status": state,
		"requested_at": record.created_at if record is not None else None,
		"decided_at": decided_at,
		"decided_by": record.parent_user_id if record is not None else None,
	}


def _active_child_query(query, ChildProfile):
	if hasattr(ChildProfile, "is_active"):
		return query.filter(ChildProfile.is_active.is_(True))
	return query


def status(session: Session, child_id: UUID) -> dict:
	return _public(child_id, _latest(session, child_id))


def chat_allowed(session: Session, child_id: UUID) -> bool:
	return _status(_latest(session, child_id)) == "approved"


def request_access(session: Session, child) -> dict:
	"""Create a pending child request once and notify every active family parent."""
	ChildProfile = get_model("ChildProfile")
	locked_child = _active_child_query(
		session.query(ChildProfile).filter(ChildProfile.id == child.id), ChildProfile
	).with_for_update().one_or_none()
	if locked_child is None:
		raise HTTPException(status_code=404, detail="Child profile not found")
	record = _latest(session, child.id, for_update=True)
	if _status(record) in {"pending", "approved"}:
		return _public(child.id, record)

	now = utc_naive(datetime.now(timezone.utc))
	ConsentRecord = get_model("ConsentRecord")
	record = ConsentRecord(
		family_id=locked_child.family_id,
		child_id=locked_child.id,
		parent_user_id=None,
		consent_type=CONSENT_TYPE,
		document_version=DOCUMENT_VERSION,
		accepted=False,
		accepted_at=None,
		revoked_at=None,
		created_at=now,
	)
	session.add(record)
	for parent_id in notification_service.family_parent_ids(session, locked_child.family_id):
		notification_service.create_notification(
			session,
			parent_id,
			"panda_chat_access_requested",
			"Panda chat request",
			f"{locked_child.display_name} asked to chat with Panda.",
			now=now,
		)
	session.commit()
	return _public(child.id, record)


def _require_parent_child(session: Session, family_id: UUID, child_id: UUID, parent_id: UUID):
	FamilyMember = get_model("FamilyMember")
	ChildProfile = get_model("ChildProfile")
	member = session.query(FamilyMember.id).filter(
		FamilyMember.family_id == family_id,
		FamilyMember.user_id == parent_id,
		FamilyMember.is_active.is_(True),
	).first()
	child = _active_child_query(
		session.query(ChildProfile).filter(
			ChildProfile.id == child_id,
			ChildProfile.family_id == family_id,
		),
		ChildProfile,
	).one_or_none()
	if member is None or child is None:
		raise HTTPException(status_code=404, detail="Child profile not found")
	return child


def family_statuses(session: Session, family_id: UUID, parent_id: UUID) -> list[dict]:
	FamilyMember = get_model("FamilyMember")
	ChildProfile = get_model("ChildProfile")
	member = session.query(FamilyMember.id).filter(
		FamilyMember.family_id == family_id,
		FamilyMember.user_id == parent_id,
		FamilyMember.is_active.is_(True),
	).first()
	if member is None:
		raise HTTPException(status_code=404, detail="Family not found")
	children = _active_child_query(
		session.query(ChildProfile).filter(ChildProfile.family_id == family_id), ChildProfile
	).order_by(ChildProfile.display_name, ChildProfile.id).all()
	if not children:
		return []
	ConsentRecord = get_model("ConsentRecord")
	records = session.query(ConsentRecord).filter(
		ConsentRecord.child_id.in_([child.id for child in children]),
		ConsentRecord.consent_type == CONSENT_TYPE,
	).order_by(ConsentRecord.child_id, ConsentRecord.created_at.desc(), ConsentRecord.id.desc()).all()
	latest_by_child = {}
	for record in records:
		latest_by_child.setdefault(record.child_id, record)
	return [_public(child.id, latest_by_child.get(child.id)) for child in children]


def decide_access(
	session: Session,
	family_id: UUID,
	child_id: UUID,
	parent_id: UUID,
	action: AccessAction,
) -> dict:
	"""Apply a parent decision to the latest request, scoped to this child."""
	child = _require_parent_child(session, family_id, child_id, parent_id)
	record = _latest(session, child.id, for_update=True)
	current = _status(record)
	if action == "approve" and current == "approved":
		return _public(child.id, record)
	if action == "reject" and current == "rejected":
		return _public(child.id, record)
	if action == "revoke" and current == "revoked":
		return _public(child.id, record)
	if action in {"approve", "reject"} and current != "pending":
		raise APIError(409, "panda_chat_request_not_pending", "There is no pending Panda chat request.")
	if action == "revoke" and current != "approved":
		raise APIError(409, "panda_chat_access_not_approved", "Panda chat access is not approved.")

	now = utc_naive(datetime.now(timezone.utc))
	if action == "approve":
		record.accepted = True
		record.accepted_at = now
		record.revoked_at = None
	else:
		record.revoked_at = now
	record.parent_user_id = parent_id
	session.commit()
	return _public(child.id, record)
