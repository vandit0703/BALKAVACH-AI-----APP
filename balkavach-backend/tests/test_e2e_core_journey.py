"""End-to-end: the agreed core journey, over HTTP, on an isolated database.

1 register/sign in as parent  2 create family  3 create + link child  4 create mission
5 enter child mode securely   6 child completes + submits (with a photo)
7 parent approves / rejects   8 child sees the result
9 stars, XP, badges, reports update   10 create + redeem a reward, approve / reject
11 notifications and resulting state
"""

import io

import pytest
from PIL import Image

from app.core.config import settings
from app.db.seed_data import seed_progression_defaults
from app.integrations import storage as storage_module
from app.services import push_service
from tests.harness import PASSWORD, in_days


class RecordingProvider:
    def __init__(self):
        self.sent = []

    def send(self, token, title, body, data):
        self.sent.append((token[:1], data["type"]))
        return "ok"


@pytest.fixture
def world(api, isolated_test_session, tmp_path, monkeypatch):
    monkeypatch.setattr(settings, "storage_provider", "local")
    monkeypatch.setattr(settings, "upload_dir", str(tmp_path))
    storage_module.reset_cache()
    seed_progression_defaults(isolated_test_session)
    isolated_test_session.commit()
    provider = RecordingProvider()
    monkeypatch.setattr(push_service, "get_push_notification_provider", lambda: provider)
    monkeypatch.setattr(push_service, "_runner", lambda fn: fn())

    class _Factory:
        def __enter__(self):
            return isolated_test_session

        def __exit__(self, *exc):
            return False

    monkeypatch.setattr(push_service, "_session_factory", lambda: _Factory())
    yield api, provider
    storage_module.reset_cache()


def _png():
    buffer = io.BytesIO()
    Image.new("RGB", (64, 48), (10, 120, 200)).save(buffer, format="PNG")
    return buffer.getvalue()


def test_parent_child_mission_reward_journey(world):
    api, provider = world

    # 1-2: parent registers, signs in again, creates a family; consent version comes from the server
    email = "journey-parent@example.com"
    registered = api.post("/auth/register", json={"full_name": "Journey Parent", "email": email, "password": PASSWORD})
    assert registered.status_code == 201
    login = api.post("/auth/login", json={"email": email, "password": PASSWORD}).json()
    parent = login["access_token"]
    assert api.get("/app-config").json()["consent_versions"]["parent_guardian_terms"]
    family = api.post("/families", parent, {"family_name": "Journey Family"}).json()
    consent = api.post(f"/settings/families/{family['id']}/consents", parent, {
        "consent_type": "parent_guardian_terms", "document_version": "2026-10-draft", "accepted": True})
    assert consent.status_code == 201
    assert api.patch(f"/settings/families/{family['id']}", parent, {"mission_settings": {"timezone": "Asia/Kolkata"}}).status_code == 200
    assert api.client.put("/api/v1/notifications/devices", headers=api.auth(parent),
                          json={"token": "p" * 40, "platform": "android"}).status_code == 204

    # 3: child profile linked to the family; 5: parent starts child mode -> child-only credentials
    child = api.post(f"/families/{family['id']}/children", parent, {
        "display_name": "Asha", "date_of_birth": "2018-05-01",
        "username": "journey-asha", "password": PASSWORD,
    }).json()
    child_session = api.post(f"/auth/children/{child['id']}/session", parent).json()
    kid = child_session["access_token"]
    assert child_session["user"]["role"] == "child"
    assert email not in str(child_session) and login["refresh_token"] not in str(child_session)
    assert api.client.put("/api/v1/notifications/devices", headers=api.auth(kid),
                          json={"token": "c" * 40, "platform": "android"}).status_code == 204
    assert api.get("/families", kid).status_code == 403

    # 4: parent builds a mission from a preset-style payload with a due date
    categories = {c["name"]: c["id"] for c in api.get("/tasks/categories", parent).json()}
    task = api.post("/tasks", parent, {
        "family_id": family["id"], "assigned_child_id": child["id"], "category_id": categories["Learning"],
        "title": "Read for 20 minutes", "star_reward": 5, "xp_reward": 120, "due_at": in_days(1),
    }).json()
    assert ("c", "task_assigned") in provider.sent

    # child sees it, opens the list, uploads a photo and submits
    assert [t["title"] for t in api.get("/tasks", kid).json()] == ["Read for 20 minutes"]
    upload = api.client.post("/api/v1/uploads/task-proofs", headers=api.auth(kid),
                             files={"file": ("p.png", _png(), "image/png")}).json()
    submission = api.post(f"/tasks/{task['id']}/submissions", kid, {
        "proof_type": "image", "proof_upload_id": upload["upload_id"], "proof_note": "finished"}).json()
    assert submission["status"] == "pending"
    assert api.post(f"/tasks/{task['id']}/submissions", kid, {"proof_type": "note", "proof_note": "again"}).status_code == 409
    assert ("p", "task_submitted") in provider.sent

    # parent reviews: pending queue shows the photo, a rejection first (no rewards), then resubmission
    queue = api.get(f"/reviews/pending?family_id={family['id']}", parent).json()
    assert queue[0]["task_title"] == "Read for 20 minutes" and queue[0]["proof_type"] == "image"
    assert api.client.get(queue[0]["proof_url"], headers=api.auth(parent)).status_code == 200
    assert api.review(parent, submission["id"], "rejected", "Please show the book").status_code == 200
    assert api.get(f"/progress/children/{child['id']}", kid).json()["star_balance"] == 0
    mine = api.get("/tasks/submissions/mine", kid).json()
    assert [s["status"] for s in mine] == ["rejected"]
    second = api.post(f"/tasks/{task['id']}/submissions", kid, {"proof_type": "note", "proof_note": "with the book"}).json()
    assert second["submission_number"] == 2

    # 7-9: approval awards once; level, badge, streak, report all update
    assert api.review(parent, second["id"], "approved", "Great").status_code == 200
    assert api.review(parent, second["id"], "approved").status_code == 409
    progress = api.get(f"/progress/children/{child['id']}", kid).json()
    assert (progress["star_balance"], progress["total_xp"], progress["current_streak"]) == (5, 120, 1)
    assert progress["level_number"] == 2 and "First Mission" in [b["name"] for b in progress["badges"]]
    assert ("c", "task_approved") in provider.sent and ("c", "badge_unlocked") in provider.sent
    report = api.get(f"/progress/children/{child['id']}/weekly", parent).json()
    assert report["timezone"] == "Asia/Kolkata"
    assert report["totals"] == {"completed_tasks": 1, "stars_earned": 5, "xp_earned": 120}
    assert report["categories"][0]["name"] == "Learning" and report["pending_submissions"] == 0
    assert api.post(f"/tasks/{task['id']}/submissions", kid, {"proof_type": "none"}).status_code == 409

    # 10: parent creates rewards, child redeems one; reject keeps stars, approve debits once
    treat = api.create_reward(parent, family["id"], name="Ice cream", star_cost=3).json()
    toy = api.create_reward(parent, family["id"], name="Big toy", star_cost=9).json()
    catalog = {r["name"] for r in api.get("/rewards", kid).json()}
    assert catalog == {"Ice cream", "Big toy"}
    too_dear = api.post("/redemptions", kid, {"reward_id": toy["id"]}, headers={"Idempotency-Key": "journey-key-toy"})
    assert too_dear.status_code == 409 and too_dear.json()["error"]["code"] == "insufficient_stars"
    first = api.post("/redemptions", kid, {"reward_id": treat["id"]}, headers={"Idempotency-Key": "journey-key-1"}).json()
    assert ("p", "reward_requested") in provider.sent
    pending = api.get(f"/redemptions?family_id={family['id']}&status=pending", parent).json()
    assert [r["reward_name"] for r in pending] == ["Ice cream"]
    assert api.post(f"/redemptions/{first['id']}/reject", parent, {"review_note": "after dinner"}).status_code == 200
    assert api.get(f"/progress/children/{child['id']}", kid).json()["star_balance"] == 5
    again = api.post("/redemptions", kid, {"reward_id": treat["id"]}, headers={"Idempotency-Key": "journey-key-2"}).json()
    assert api.post(f"/redemptions/{again['id']}/approve", parent, {}).status_code == 200
    assert api.get(f"/progress/children/{child['id']}", kid).json()["star_balance"] == 2
    assert api.post(f"/redemptions/{again['id']}/fulfill", parent).json()["status"] == "fulfilled"
    history = [r["status"] for r in api.get("/redemptions/mine", kid).json()]
    assert history == ["fulfilled", "rejected"]

    # 11: notifications were stored for both roles and pushes never leaked content
    parent_types = {n["notification_type"] for n in api.get("/notifications", parent).json()}
    child_types = {n["notification_type"] for n in api.get("/notifications", kid).json()}
    assert {"task_submitted", "reward_requested"} <= parent_types
    assert {"task_assigned", "task_rejected", "task_approved", "badge_unlocked", "reward_rejected", "reward_approved",
            "reward_fulfilled"} <= child_types
    for expected in [("c", "reward_rejected"), ("c", "reward_approved"), ("c", "reward_fulfilled")]:
        assert expected in provider.sent, expected
    assert all("Asha" not in str(item) and "Ice cream" not in str(item) for item in provider.sent)

    # finally the parent ends this child's device and the child is signed out everywhere
    assert api.delete(f"/auth/children/{child['id']}/sessions", parent).status_code == 204
    assert api.get("/auth/me", kid).status_code == 401
    assert api.post("/auth/refresh", json={"refresh_token": child_session["refresh_token"]}).status_code == 401
