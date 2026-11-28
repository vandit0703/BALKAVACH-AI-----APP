"""Talk to Panda microphone consent (existing ``consent_records``, no schema change).

In-memory SQLite (tests/sqlite_world.py) plus a ``consent_records`` model; route
functions are called directly. Not PostgreSQL. The route guards themselves
(``require_parent`` / ``require_child``) are covered by
tests/test_authorization_boundaries.py.
"""

from __future__ import annotations

from datetime import datetime
from types import SimpleNamespace
from uuid import UUID, uuid4

import pytest
from fastapi import HTTPException
from sqlalchemy import Boolean, DateTime, String, Uuid
from sqlalchemy.orm import Mapped, mapped_column

from app.core.exceptions import APIError
from app.schemas.companion import CompanionChatRequest, PandaVoiceConsentUpdate
from tests.sqlite_world import MODELS, FamilyMember, User, World, make_family, world_session  # noqa: F401


class ConsentRecord(World):
	__tablename__ = "consent_records"
	id: Mapped[UUID] = mapped_column(Uuid, primary_key=True, default=uuid4)
	family_id: Mapped[UUID] = mapped_column(Uuid)
	child_id: Mapped[UUID | None] = mapped_column(Uuid)
	parent_user_id: Mapped[UUID | None] = mapped_column(Uuid)
	consent_type: Mapped[str] = mapped_column(String)
	document_version: Mapped[str] = mapped_column(String)
	accepted: Mapped[bool] = mapped_column(Boolean)
	accepted_at: Mapped[datetime | None] = mapped_column(DateTime)
	revoked_at: Mapped[datetime | None] = mapped_column(DateTime)
	created_at: Mapped[datetime] = mapped_column(DateTime)


WORLD = {**MODELS, "ConsentRecord": ConsentRecord}


@pytest.fixture
def db(world_session, monkeypatch):
	import app.services.panda_voice_consent_service as service
	import app.services.panda_chat_access_service as chat_access
	import app.services.notification_service as notifications

	monkeypatch.setattr(service, "get_model", WORLD.__getitem__)
	monkeypatch.setattr(chat_access, "get_model", WORLD.__getitem__)
	monkeypatch.setattr(notifications, "get_model", WORLD.__getitem__)
	return world_session


def parent_of(db, family_id):
	parent = User(role="parent")
	db.add(parent)
	db.flush()
	db.add(FamilyMember(family_id=family_id, user_id=parent.id))
	db.commit()
	return parent


def grant_chat_access(db, child, parent=None):
	from app.services import panda_chat_access_service as access

	parent = parent or parent_of(db, child.family_id)
	access.request_access(db, child)
	return access.decide_access(db, child.family_id, child.id, parent.id, "approve")


def version():
	from app.services.panda_voice_consent_service import PANDA_VOICE_CONSENT_VERSION

	return PANDA_VOICE_CONSENT_VERSION


def get_consent(db, parent, child):
	from app.api.v1.settings import get_panda_voice_consent

	return get_panda_voice_consent(child.family_id, child.id, parent=parent, session=db)


def put_consent(db, parent, child, granted, document_version="__current__"):
	from app.api.v1.settings import set_panda_voice_consent

	if document_version == "__current__":
		document_version = version() if granted else None
	return set_panda_voice_consent(
		child.family_id,
		child.id,
		PandaVoiceConsentUpdate(granted=granted, document_version=document_version),
		parent=parent,
		session=db,
	)


def child_view(db, child):
	from app.api.v1.companion import companion_voice_consent

	return companion_voice_consent(child=child, session=db)


def test_no_consent_until_a_parent_agrees(db):
	child = make_family(db)
	parent = parent_of(db, child.family_id)

	assert get_consent(db, parent, child).granted is False
	assert child_view(db, child).granted is False


def test_a_parent_grants_for_this_child_only(db):
	child = make_family(db)
	sibling = make_family(db)
	parent = parent_of(db, child.family_id)

	result = put_consent(db, parent, child, True)

	assert result.granted is True
	assert result.granted_by == parent.id
	assert child_view(db, child).granted is True
	assert child_view(db, sibling).granted is False
	row = db.query(ConsentRecord).one()
	assert (row.family_id, row.child_id, row.consent_type) == (child.family_id, child.id, "panda_voice")
	assert row.accepted is True and row.revoked_at is None


def test_granting_twice_keeps_one_record(db):
	child = make_family(db)
	parent = parent_of(db, child.family_id)

	put_consent(db, parent, child, True)
	put_consent(db, parent, child, True)

	assert db.query(ConsentRecord).count() == 1


def test_a_grant_must_name_the_current_consent_text(db):
	child = make_family(db)
	parent = parent_of(db, child.family_id)

	with pytest.raises(APIError) as outdated:
		put_consent(db, parent, child, True, document_version="panda-voice-old")
	assert outdated.value.status_code == 409
	with pytest.raises(HTTPException) as missing:
		put_consent(db, parent, child, True, document_version=None)
	assert missing.value.status_code == 422
	assert db.query(ConsentRecord).count() == 0


def test_a_new_consent_text_makes_older_grants_stale(db, monkeypatch):
	import app.services.panda_voice_consent_service as service

	child = make_family(db)
	parent = parent_of(db, child.family_id)
	put_consent(db, parent, child, True)

	monkeypatch.setattr(service, "PANDA_VOICE_CONSENT_VERSION", "panda-voice-next")

	assert child_view(db, child).granted is False


def test_another_familys_parent_cannot_read_grant_or_revoke(db):
	child = make_family(db)
	outsider = parent_of(db, uuid4())

	for call in (
		lambda: get_consent(db, outsider, child),
		lambda: put_consent(db, outsider, child, True),
		lambda: put_consent(db, outsider, child, False),
	):
		with pytest.raises(HTTPException) as refused:
			call()
		assert refused.value.status_code == 404
	assert db.query(ConsentRecord).count() == 0


def test_a_child_outside_the_family_is_not_found(db):
	child = make_family(db)
	other_child = make_family(db)
	parent = parent_of(db, child.family_id)
	from app.api.v1.settings import get_panda_voice_consent

	with pytest.raises(HTTPException) as refused:
		get_panda_voice_consent(child.family_id, other_child.id, parent=parent, session=db)
	assert refused.value.status_code == 404


def test_any_parent_in_the_family_can_withdraw(db):
	child = make_family(db)
	first = parent_of(db, child.family_id)
	second = parent_of(db, child.family_id)
	put_consent(db, first, child, True)

	result = put_consent(db, second, child, False)

	assert result.granted is False
	assert child_view(db, child).granted is False
	assert db.query(ConsentRecord).one().revoked_at is not None
	# Withdrawing again changes nothing.
	assert put_consent(db, second, child, False).granted is False


def test_an_inactive_parent_cannot_change_it(db):
	child = make_family(db)
	parent = parent_of(db, child.family_id)
	db.query(FamilyMember).filter_by(user_id=parent.id).update({"is_active": False})
	db.commit()

	with pytest.raises(HTTPException):
		put_consent(db, parent, child, True)


def _chat(db, child, monkeypatch, *, input_mode, speech=None):
	import app.api.v1.companion as companion

	monkeypatch.setattr(companion, "load_child_context", lambda session, child: (None, "en"))
	monkeypatch.setattr(
		companion,
		"compose_reply",
		lambda text, locale, ctx, context_intent=None: SimpleNamespace(
			text="Hello!", mood="happy", intent="greeting", follow_up=None, safety="ok", suggestions=[]
		),
	)
	extra = {} if speech is None else {"speech": speech}
	request = CompanionChatRequest(text="hello panda", turn_id=uuid4(), input=input_mode, **extra)
	return companion.companion_chat(request, child=child, session=db)


def test_voice_turns_need_consent_typed_turns_do_not(db, monkeypatch):
	child = make_family(db)
	grant_chat_access(db, child)

	with pytest.raises(APIError) as refused:
		_chat(db, child, monkeypatch, input_mode="voice")
	assert refused.value.status_code == 403
	assert refused.value.code == "panda_voice_consent_required"

	assert _chat(db, child, monkeypatch, input_mode="text").reply == "Hello!"


def test_withdrawal_stops_the_next_voice_turn(db, monkeypatch):
	child = make_family(db)
	parent = parent_of(db, child.family_id)
	grant_chat_access(db, child, parent)
	put_consent(db, parent, child, True)
	assert _chat(db, child, monkeypatch, input_mode="voice").reply == "Hello!"

	put_consent(db, parent, child, False)

	with pytest.raises(APIError):
		_chat(db, child, monkeypatch, input_mode="voice")


def test_older_apps_without_the_input_field_count_as_typed():
	request = CompanionChatRequest(text="hi", turn_id=uuid4())
	assert request.input == "text"


# ---- option B (2026-11-26): on-device recognition needs no grown-up step ------------------------------------
#
# Audio from the on-device recogniser never leaves the phone, so voice turns recognised on the device are
# allowed without a consent record. A parent who explicitly turned voice off still stops them. The cloud
# recogniser (the only option on phones without on-device recognition) still needs the parent's consent.


def test_on_device_voice_turns_need_no_consent_record(db, monkeypatch):
	child = make_family(db)
	grant_chat_access(db, child)
	assert _chat(db, child, monkeypatch, input_mode="voice", speech="on_device").reply == "Hello!"


def test_cloud_voice_turns_still_need_consent(db, monkeypatch):
	child = make_family(db)
	grant_chat_access(db, child)
	with pytest.raises(APIError) as refused:
		_chat(db, child, monkeypatch, input_mode="voice", speech="cloud")
	assert refused.value.code == "panda_voice_consent_required"


def test_voice_turns_from_older_apps_count_as_cloud():
	request = CompanionChatRequest(text="hi", turn_id=uuid4(), input="voice")
	assert request.speech == "cloud"


def test_a_parent_who_turned_voice_off_stops_on_device_voice_too(db, monkeypatch):
	child = make_family(db)
	parent = parent_of(db, child.family_id)
	grant_chat_access(db, child, parent)
	put_consent(db, parent, child, True)
	put_consent(db, parent, child, False)

	assert child_view(db, child).refused is True
	with pytest.raises(APIError) as refused:
		_chat(db, child, monkeypatch, input_mode="voice", speech="on_device")
	assert refused.value.status_code == 403
	assert refused.value.code == "panda_voice_consent_required"
	# Typing still works.
	assert _chat(db, child, monkeypatch, input_mode="text").reply == "Hello!"


def test_no_record_is_not_a_refusal_and_a_new_grant_clears_one(db):
	child = make_family(db)
	parent = parent_of(db, child.family_id)
	assert child_view(db, child).refused is False
	put_consent(db, parent, child, True)
	put_consent(db, parent, child, False)
	assert child_view(db, child).refused is True
	put_consent(db, parent, child, True)
	view = child_view(db, child)
	assert (view.granted, view.refused) == (True, False)


def test_a_stale_grant_is_not_a_refusal(db, monkeypatch):
	import app.services.panda_voice_consent_service as service

	child = make_family(db)
	parent = parent_of(db, child.family_id)
	put_consent(db, parent, child, True)
	monkeypatch.setattr(service, "PANDA_VOICE_CONSENT_VERSION", "panda-voice-next")
	assert child_view(db, child).refused is False


def test_chat_access_request_is_child_scoped_and_notifies_each_parent(db, monkeypatch):
	from app.services import notification_service
	from app.services import panda_chat_access_service as access

	child = make_family(db)
	first = parent_of(db, child.family_id)
	second = parent_of(db, child.family_id)
	notifications = []
	monkeypatch.setattr(
		notification_service,
		"create_notification",
		lambda session, recipient, kind, title, message, **kwargs: notifications.append(
			(recipient, kind, title, message)
		),
	)

	requested = access.request_access(db, child)
	assert requested["status"] == "pending"
	assert access.request_access(db, child)["status"] == "pending"
	assert [notice[0] for notice in notifications] == [first.id, second.id]
	assert all(notice[1] == "panda_chat_access_requested" for notice in notifications)
	assert all("hello panda" not in notice[3] for notice in notifications)
	request = db.query(ConsentRecord).one()
	assert request.parent_user_id is None and request.accepted is False and request.revoked_at is None

	approved = access.decide_access(db, child.family_id, child.id, first.id, "approve")
	assert approved["status"] == "approved"
	assert access.chat_allowed(db, child.id) is True

	sibling = make_family(db)
	assert access.chat_allowed(db, sibling.id) is False

	revoked = access.decide_access(db, child.family_id, child.id, second.id, "revoke")
	assert revoked["status"] == "revoked"
	assert access.chat_allowed(db, child.id) is False

	new_request = access.request_access(db, child)
	assert new_request["status"] == "pending"
	rejected = access.decide_access(db, child.family_id, child.id, second.id, "reject")
	assert rejected["status"] == "rejected"
	assert access.chat_allowed(db, child.id) is False
