"""Regression tests for the child video-interests endpoints and the zero free
video allowance (docs/QUIZ_AND_INTERESTS_FIX_REPORT.md).

These run without a database: the routes are exercised through FastAPI with
dependency overrides and a fake session, like
test_video_recommendations_and_integrity.py.
"""

from datetime import date
from types import SimpleNamespace
from uuid import uuid4

import pytest
from fastapi.testclient import TestClient

from app.core.dependencies import require_child, require_parent
from app.db.session import get_db
from app.main import app
from app.schemas.video import VideoAllowancePublic
from app.services.video_service import _child_interest_slugs

_FAKE_CATEGORY = SimpleNamespace(
	slug=1,
	name=1,
	display_order=1,
	id=1,
	family_id=1,
	is_active=SimpleNamespace(is_=lambda v: True),
)


class _FakeQuery:
	def __init__(self, rows, child=None):
		self._rows = rows
		self._child = child

	def filter(self, *args, **kwargs):
		return self

	def order_by(self, *args, **kwargs):
		return self

	def with_for_update(self, *args, **kwargs):
		return self

	def all(self):
		return list(self._rows)

	def one_or_none(self):
		return self._child


class _FakeSession:
	def __init__(self, rows, child=None):
		self._rows = rows
		self._child = child
		self.commits = 0

	def query(self, *args, **kwargs):
		return _FakeQuery(self._rows, self._child)

	def commit(self):
		self.commits += 1


@pytest.fixture
def client():
	try:
		yield TestClient(app)
	finally:
		app.dependency_overrides.clear()


def _as_child(monkeypatch, child, rows):
	import app.api.v1.videos as video_routes

	monkeypatch.setattr(video_routes, "get_model", lambda name: _FAKE_CATEGORY)
	session = _FakeSession(rows)
	app.dependency_overrides[require_child] = lambda: child
	app.dependency_overrides[get_db] = lambda: session
	return session


def test_child_interests_returns_catalogue_approved_and_pending_separately(monkeypatch, client):
	child = SimpleNamespace(id=uuid4(), interests=["science"], pending_interest_requests=["stories"])
	_as_child(monkeypatch, child, [("science", "Science"), ("stories", "Stories")])

	res = client.get("/api/v1/videos/interests")

	assert res.status_code == 200
	assert res.json() == {
		"interests": ["science"],
		"pending_requests": ["stories"],
		"available_categories": [
			{"slug": "science", "name": "Science"},
			{"slug": "stories", "name": "Stories"},
		],
	}


def test_child_interests_empty_catalogue_is_success_not_error(monkeypatch, client):
	child = SimpleNamespace(id=uuid4(), interests=[], pending_interest_requests=[])
	_as_child(monkeypatch, child, [])

	res = client.get("/api/v1/videos/interests")

	assert res.status_code == 200
	assert res.json() == {"interests": [], "pending_requests": [], "available_categories": []}


def test_child_interests_requires_authentication(client):
	# No database here: only the bearer-token check is under test.
	app.dependency_overrides[get_db] = lambda: _FakeSession([])
	assert client.get("/api/v1/videos/interests").status_code == 401
	assert client.post("/api/v1/videos/interests/request", json={"interests": []}).status_code == 401


def test_interest_request_without_schema_column_is_refused_not_faked(monkeypatch, client):
	# A database without migration 0022 has no pending_interest_requests column.
	child = SimpleNamespace(id=uuid4())
	session = _as_child(monkeypatch, child, [("stories", "Stories")])

	res = client.post("/api/v1/videos/interests/request", json={"interests": ["stories"]})

	assert res.status_code == 503
	assert session.commits == 0


def test_parent_approval_updates_active_interests_and_clears_pending(monkeypatch, client):
	import app.api.v1.families as family_routes
	import app.services.admin_service as admin_service

	family_id, child_id = uuid4(), uuid4()
	child = SimpleNamespace(
		id=child_id,
		family_id=family_id,
		is_active=True,
		interests=["science"],
		pending_interest_requests=["stories"],
		interests_updated_at=None,
		interests_updated_by=None,
	)
	parent = SimpleNamespace(id=uuid4())
	monkeypatch.setattr(family_routes, "get_model", lambda name: _FAKE_CATEGORY)
	monkeypatch.setattr(family_routes, "_require_membership", lambda *a, **k: None)
	audits = []
	monkeypatch.setattr(admin_service, "record_audit", lambda *a, **k: audits.append(a))
	session = _FakeSession([("science", "Science"), ("stories", "Stories")], child=child)
	app.dependency_overrides[require_parent] = lambda: parent
	app.dependency_overrides[get_db] = lambda: session

	res = client.put(
		f"/api/v1/families/{family_id}/children/{child_id}/interests",
		json={"interests": ["science", "stories", "not-a-category"]},
	)

	assert res.status_code == 200
	body = res.json()
	assert body["interests"] == ["science", "stories"]
	assert body["pending_requests"] == []
	assert child.interests == ["science", "stories"]
	assert child.pending_interest_requests == []
	assert child.interests_updated_by == parent.id
	assert session.commits == 1
	assert len(audits) == 1


def test_parent_update_without_schema_column_is_refused_not_faked(monkeypatch, client):
	import app.api.v1.families as family_routes

	family_id, child_id = uuid4(), uuid4()
	child = SimpleNamespace(id=child_id, family_id=family_id, is_active=True)
	monkeypatch.setattr(family_routes, "get_model", lambda name: _FAKE_CATEGORY)
	monkeypatch.setattr(family_routes, "_require_membership", lambda *a, **k: None)
	session = _FakeSession([("science", "Science")], child=child)
	app.dependency_overrides[require_parent] = lambda: SimpleNamespace(id=uuid4())
	app.dependency_overrides[get_db] = lambda: session

	res = client.put(
		f"/api/v1/families/{family_id}/children/{child_id}/interests",
		json={"interests": ["science"]},
	)

	assert res.status_code == 503
	assert session.commits == 0


def test_pending_requests_never_influence_recommendations():
	child = SimpleNamespace(interests=[], pending_interest_requests=["stories", "science"])
	assert _child_interest_slugs(child) == set()
	child = SimpleNamespace(interests=["science"], pending_interest_requests=["stories"])
	assert _child_interest_slugs(child) == {"science"}


def test_allowance_schema_never_defaults_to_a_free_allowance():
	allowance = VideoAllowancePublic(
		child_id=uuid4(),
		local_date=date(2026, 11, 26),
		timezone="Asia/Kolkata",
		total_earned_today_seconds=0,
		consumed_today_seconds=0,
		remaining_seconds=0,
		daily_cap_seconds=3600,
		is_exhausted=True,
		active_entitlements_count=0,
	)
	assert allowance.free_allowance_seconds == 0
	assert allowance.free_remaining_seconds == 0
