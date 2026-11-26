"""Parent interest management and child interest requests on real PostgreSQL.

Exercises the HTTP API end to end on the disposable test database (``TEST_DATABASE_URL``,
see ``tests/conftest.py``): JSONB persistence, parent-family authorization, child-only request
submission, approval / rejection through the parent save endpoint, and that only approved
interests reach the recommendation ranking. Every test runs in a rolled-back transaction.

Parent Mode (a parent session opened on the child's device via ``/auth/parent-mode/enter``) issues
an ordinary parent access token, so the parent-token cases here cover both entry points.
"""

from __future__ import annotations

from uuid import uuid4

import pytest

from app.db.base import get_model, has_model
from app.services.video_service import _child_interest_slugs

pytestmark = pytest.mark.usefixtures("api")


@pytest.fixture
def categories(api):
	if not has_model("VideoCategory"):
		pytest.skip("video_categories table not present in the test schema")
	VideoCategory = get_model("VideoCategory")
	suffix = uuid4().hex[:6]
	rows = [
		VideoCategory(name=f"Science {suffix}", slug=f"science-{suffix}", display_order=1, is_active=True),
		VideoCategory(name=f"Stories {suffix}", slug=f"stories-{suffix}", display_order=2, is_active=True),
		VideoCategory(name=f"Music {suffix}", slug=f"music-{suffix}", display_order=3, is_active=True),
		VideoCategory(name=f"Hidden {suffix}", slug=f"hidden-{suffix}", display_order=4, is_active=False),
	]
	api.session.add_all(rows)
	api.session.flush()
	return {"science": rows[0].slug, "stories": rows[1].slug, "music": rows[2].slug, "hidden": rows[3].slug}


@pytest.fixture
def world(api, categories):
	ChildProfile = get_model("ChildProfile")
	if not hasattr(ChildProfile, "interests") or not hasattr(ChildProfile, "pending_interest_requests"):
		pytest.skip("migration 0022_production_readiness not applied to the test database")
	data = api.family_with_child("Mia")
	data["cats"] = categories
	return data


def _url(world, family_id=None, child_id=None):
	return f"/families/{family_id or world['family']['id']}/children/{child_id or world['child']['id']}/interests"


def _put(api, token, path, body):
	return api.client.put(f"/api/v1{path}", headers=api.auth(token), json=body)


def _stored(api, child_id):
	"""Read the row back from PostgreSQL, bypassing the identity map."""
	api.session.expire_all()
	ChildProfile = get_model("ChildProfile")
	return api.session.query(ChildProfile).filter(ChildProfile.id == child_id).one()


# ---- parent account / parent mode -------------------------------------------------------------------------


def test_parent_loads_linked_child_interests_and_catalogue(api, world):
	res = api.get(_url(world), world["parent"]["token"])
	assert res.status_code == 200, res.text
	body = res.json()
	assert body["child_id"] == world["child"]["id"]
	assert body["interests"] == []
	assert body["pending_requests"] == []
	slugs = [c["slug"] for c in body["available_categories"]]
	cats = world["cats"]
	assert {cats["science"], cats["stories"], cats["music"]} <= set(slugs)
	assert cats["hidden"] not in slugs  # inactive categories are never offered


def test_parent_save_persists_to_postgres_and_reloads(api, world):
	cats = world["cats"]
	token = world["parent"]["token"]
	res = _put(api, token, _url(world), {"interests": [cats["science"], cats["music"].upper(), "not-a-topic"], "clear_pending": False})
	assert res.status_code == 200, res.text
	assert res.json()["interests"] == [cats["science"], cats["music"]]

	row = _stored(api, world["child"]["id"])
	assert row.interests == [cats["science"], cats["music"]]
	assert str(row.interests_updated_by) == world["parent"]["id"]
	assert row.interests_updated_at is not None

	# A fresh GET (what the app does after restart / re-login) shows the saved topics.
	again = api.get(_url(world), token).json()
	assert again["interests"] == [cats["science"], cats["music"]]


def test_parent_save_without_clear_pending_keeps_child_request(api, world):
	cats = world["cats"]
	assert api.post("/videos/interests/request", world["child"]["token"], {"interests": [cats["stories"]]}).status_code == 200
	res = _put(api, world["parent"]["token"], _url(world), {"interests": [cats["science"]], "clear_pending": False})
	assert res.status_code == 200, res.text
	assert res.json()["pending_requests"] == [cats["stories"]]
	assert _stored(api, world["child"]["id"]).pending_interest_requests == [cats["stories"]]


def test_unrelated_parent_cannot_read_or_modify_another_familys_child(api, world):
	cats = world["cats"]
	intruder = api.register_parent("Intruder")
	own_family = api.create_family(intruder["token"], "Other Family")

	# Victim's family id: the intruder is not a member.
	assert api.get(_url(world), intruder["token"]).status_code == 404
	assert _put(api, intruder["token"], _url(world), {"interests": [cats["science"]]}).status_code == 404
	# Intruder's own family id with the victim's child id: the child is not in that family.
	assert api.get(_url(world, family_id=own_family["id"]), intruder["token"]).status_code == 404
	res = _put(api, intruder["token"], _url(world, family_id=own_family["id"]), {"interests": [cats["science"]]})
	assert res.status_code == 404
	assert _stored(api, world["child"]["id"]).interests == []


def test_parent_endpoints_require_authentication(api, world):
	assert api.get(_url(world)).status_code == 401
	assert api.client.put(f"/api/v1{_url(world)}", json={"interests": []}).status_code == 401


def test_parent_token_cannot_use_child_request_endpoint(api, world):
	res = api.post("/videos/interests/request", world["parent"]["token"], {"interests": [world["cats"]["science"]]})
	assert res.status_code == 403


# ---- child account ----------------------------------------------------------------------------------------


def test_child_loads_catalogue_and_submits_pending_request(api, world):
	cats = world["cats"]
	child_token = world["child"]["token"]
	assert _put(api, world["parent"]["token"], _url(world), {"interests": [cats["science"]]}).status_code == 200

	mine = api.get("/videos/interests", child_token)
	assert mine.status_code == 200, mine.text
	assert mine.json()["interests"] == [cats["science"]]
	assert cats["stories"] in [c["slug"] for c in mine.json()["available_categories"]]

	res = api.post("/videos/interests/request", child_token, {"interests": [cats["science"], cats["stories"]]})
	assert res.status_code == 200, res.text
	assert res.json()["interests"] == [cats["science"]]  # never approved by the request itself
	assert res.json()["pending_requests"] == [cats["science"], cats["stories"]]

	row = _stored(api, world["child"]["id"])
	assert row.interests == [cats["science"]]
	assert row.pending_interest_requests == [cats["science"], cats["stories"]]
	# The parent sees the request on the linked child's profile.
	parent_view = api.get(_url(world), world["parent"]["token"]).json()
	assert parent_view["pending_requests"] == [cats["science"], cats["stories"]]
	assert parent_view["interests"] == [cats["science"]]


@pytest.mark.parametrize("requested", [[], ["not-a-topic"], ["hidden"]])
def test_child_request_with_no_valid_topics_is_refused_not_faked(api, world, requested):
	cats = world["cats"]
	child_token = world["child"]["token"]
	assert api.post("/videos/interests/request", child_token, {"interests": [cats["music"]]}).status_code == 200
	payload = [cats.get(item, item) for item in requested]
	res = api.post("/videos/interests/request", child_token, {"interests": payload})
	assert res.status_code == 422, res.text
	# The earlier request is still waiting for the parent.
	assert _stored(api, world["child"]["id"]).pending_interest_requests == [cats["music"]]


def test_child_request_rejects_malformed_body(api, world):
	res = api.post("/videos/interests/request", world["child"]["token"], {"interests": "science"})
	assert res.status_code == 422


def test_child_cannot_approve_own_request(api, world):
	cats = world["cats"]
	child_token = world["child"]["token"]
	assert api.post("/videos/interests/request", child_token, {"interests": [cats["stories"]]}).status_code == 200
	res = _put(api, child_token, _url(world), {"interests": [cats["stories"]], "clear_pending": True})
	assert res.status_code == 403
	assert api.get(_url(world), child_token).status_code == 403
	row = _stored(api, world["child"]["id"])
	assert row.interests == []
	assert row.pending_interest_requests == [cats["stories"]]


# ---- approval / rejection ---------------------------------------------------------------------------------


def test_parent_approves_request_replacing_active_interests(api, world):
	cats = world["cats"]
	token = world["parent"]["token"]
	assert _put(api, token, _url(world), {"interests": [cats["science"], cats["music"]]}).status_code == 200
	# The child asks to drop music and add stories (the request is the full wanted set).
	assert api.post("/videos/interests/request", world["child"]["token"], {"interests": [cats["science"], cats["stories"]]}).status_code == 200

	pending = api.get(_url(world), token).json()["pending_requests"]
	res = _put(api, token, _url(world), {"interests": pending, "clear_pending": True})
	assert res.status_code == 200, res.text
	assert res.json()["interests"] == [cats["science"], cats["stories"]]
	assert res.json()["pending_requests"] == []
	row = _stored(api, world["child"]["id"])
	assert row.interests == [cats["science"], cats["stories"]]
	assert row.pending_interest_requests == []
	assert api.get("/videos/interests", world["child"]["token"]).json()["interests"] == [cats["science"], cats["stories"]]


def test_parent_rejects_request_keeping_active_interests(api, world):
	cats = world["cats"]
	token = world["parent"]["token"]
	assert _put(api, token, _url(world), {"interests": [cats["science"]]}).status_code == 200
	assert api.post("/videos/interests/request", world["child"]["token"], {"interests": [cats["stories"]]}).status_code == 200

	current = api.get(_url(world), token).json()["interests"]
	res = _put(api, token, _url(world), {"interests": current, "clear_pending": True})
	assert res.status_code == 200, res.text
	row = _stored(api, world["child"]["id"])
	assert row.interests == [cats["science"]]
	assert row.pending_interest_requests == []


# ---- recommendation integrity -----------------------------------------------------------------------------


def test_only_approved_interests_reach_recommendation_ranking(api, world):
	cats = world["cats"]
	token = world["parent"]["token"]
	assert _put(api, token, _url(world), {"interests": [cats["science"]]}).status_code == 200
	assert api.post("/videos/interests/request", world["child"]["token"], {"interests": [cats["stories"]]}).status_code == 200

	# eligible_feed ranks by _child_interest_slugs(child) on the persisted row.
	assert _child_interest_slugs(_stored(api, world["child"]["id"])) == {cats["science"]}

	assert _put(api, token, _url(world), {"interests": [cats["stories"]], "clear_pending": True}).status_code == 200
	assert _child_interest_slugs(_stored(api, world["child"]["id"])) == {cats["stories"]}
