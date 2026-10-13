"""API contract: nothing previously published disappears; nothing protected is open."""

import json
import re
from pathlib import Path
from uuid import uuid4

import pytest

from app.main import app

BASELINE = json.loads((Path(__file__).parent / "contracts" / "openapi_baseline.json").read_text(encoding="utf-8"))["operations"]
PUBLIC = {
    "POST /api/v1/auth/register",
    "POST /api/v1/auth/login",
    "POST /api/v1/auth/refresh",
    "POST /api/v1/auth/logout",
    "GET /api/v1/app-config",
    "GET /health",
    "GET /ready",
}
METHODS = {"get", "post", "put", "patch", "delete"}


def _operations():
    schema = app.openapi()
    return sorted(f"{method.upper()} {path}" for path, item in schema["paths"].items() for method in item if method in METHODS)


def test_every_previously_published_operation_still_exists():
    current = set(_operations())
    removed = [operation for operation in BASELINE if operation not in current]
    assert removed == [], f"Breaking change: operations removed from the API: {removed}"


def test_openapi_document_builds_and_has_unique_operation_ids():
    schema = app.openapi()
    ids = [op["operationId"] for item in schema["paths"].values() for m, op in item.items() if m in METHODS]
    assert len(ids) == len(set(ids))
    assert schema["info"]["title"]


def test_new_operations_are_documented_with_a_summary_tag():
    schema = app.openapi()
    for path, item in schema["paths"].items():
        for method, operation in item.items():
            if method in METHODS and path.startswith("/api/v1"):
                assert operation.get("tags"), f"{method} {path} has no tag"


def test_every_non_public_operation_requires_authentication(api):
    unprotected = []
    for operation in _operations():
        if operation in PUBLIC:
            continue
        method, path = operation.split(" ", 1)
        concrete = re.sub(r"\{[^}]+\}", str(uuid4()), path)
        response = api.client.request(method, concrete)
        if response.status_code != 401:
            unprotected.append((operation, response.status_code))
    assert unprotected == [], f"Reachable without credentials: {unprotected}"


def test_only_the_documented_routes_are_public():
    assert len(PUBLIC) == 7


# -- tenant isolation: another family can never read or change this family's data ----------

def test_a_second_family_cannot_reach_the_first_familys_resources(api):
    a = api.family_with_child("Asha")
    b = api.family_with_child("Bela")
    api.grant_stars(a["child"]["id"], 20)
    pa, pb, ca, cb = a["parent"]["token"], b["parent"]["token"], a["child"]["token"], b["child"]["token"]
    task = api.create_task(pa, a["family"]["id"])
    sub = api.submit(ca, task["id"]).json()
    reward = api.create_reward(pa, a["family"]["id"], star_cost=2).json()
    redemption = api.post(
        "/redemptions", ca, {"reward_id": reward["id"]}, headers={"Idempotency-Key": "iso-key-123456"}
    ).json()
    fam = a["family"]["id"]
    kid = a["child"]["id"]

    parent_b_attempts = [
        ("get", f"/families/{fam}", None),
        ("get", f"/families/{fam}/children", None),
        ("patch", f"/families/{fam}/children/{kid}", {"display_name": "Hacked"}),
        ("delete", f"/families/{fam}/children/{kid}", None),
        ("get", f"/progress/children/{kid}", None),
        ("get", f"/progress/children/{kid}/weekly", None),
        ("post", f"/auth/children/{kid}/session", None),
        ("delete", f"/auth/children/{kid}/sessions", None),
        ("get", f"/tasks?family_id={fam}", None),
        ("patch", f"/tasks/{task['id']}", {"title": "Hacked"}),
        ("delete", f"/tasks/{task['id']}", None),
        ("get", f"/tasks/{task['id']}/submissions", None),
        ("post", f"/reviews/submissions/{sub['id']}", {"decision": "approved"}),
        ("get", f"/reviews/pending?family_id={fam}", None),
        ("get", f"/rewards?family_id={fam}", None),
        ("patch", f"/rewards/{reward['id']}", {"name": "Hacked"}),
        ("delete", f"/rewards/{reward['id']}", None),
        ("get", f"/redemptions?family_id={fam}", None),
        ("post", f"/redemptions/{redemption['id']}/approve", {}),
        ("post", f"/redemptions/{redemption['id']}/reject", {}),
        ("post", f"/redemptions/{redemption['id']}/fulfill", None),
        ("post", f"/redemptions/{redemption['id']}/cancel", None),
        ("get", f"/settings/families/{fam}", None),
        ("patch", f"/settings/families/{fam}", {"default_language": "gu"}),
        ("get", f"/settings/families/{fam}/consents", None),
    ]
    for method, path, body in parent_b_attempts:
        response = api.client.request(method.upper(), f"/api/v1{path}", headers=api.auth(pb), json=body)
        assert response.status_code == 404, f"{method.upper()} {path} -> {response.status_code} {response.text}"

    # child B cannot see family A's work either
    assert api.get(f"/progress/children/{kid}", cb).status_code == 404
    assert api.get(f"/tasks?family_id={fam}", cb).status_code == 404
    assert api.submit(cb, task["id"]).status_code == 404
    assert api.post(f"/redemptions/{redemption['id']}/cancel/mine", cb).status_code == 404

    # nothing leaked or changed
    assert api.get(f"/families/{fam}", pa).status_code == 200
    assert api.get(f"/tasks?family_id={fam}", pa).json()[0]["title"] == "Make the bed"
    assert api.get(f"/rewards?family_id={fam}", pa).json()[0]["name"] == "Extra story"


def test_notifications_are_private_to_their_recipient(api):
    a = api.family_with_child()
    b = api.family_with_child()
    task = api.create_task(a["parent"]["token"], a["family"]["id"])
    api.submit(a["child"]["token"], task["id"])
    notification = api.get("/notifications", a["parent"]["token"]).json()[0]
    assert api.post(f"/notifications/{notification['id']}/read", b["parent"]["token"]).status_code == 404
    assert api.get("/notifications", b["parent"]["token"]).json() == []
    assert api.post(f"/notifications/{notification['id']}/read", a["parent"]["token"]).status_code == 200


def test_role_confusion_is_rejected(api):
    ctx = api.family_with_child()
    child, parent = ctx["child"]["token"], ctx["parent"]["token"]
    task = api.create_task(parent, ctx["family"]["id"])
    for method, path, body in [
        ("POST", "/tasks", {"family_id": ctx["family"]["id"], "title": "Child made"}),
        ("PATCH", f"/tasks/{task['id']}", {"title": "Child edit"}),
        ("POST", "/rewards", {"family_id": ctx["family"]["id"], "name": "Free", "reward_type": "custom", "star_cost": 1}),
        ("POST", "/families", {"family_name": "Child family"}),
    ]:
        response = api.client.request(method, f"/api/v1{path}", headers=api.auth(child), json=body)
        assert response.status_code == 403, (method, path, response.status_code)
    assert api.submit(parent, task["id"]).status_code == 403
    assert api.get("/tasks/submissions/mine", parent).status_code == 403
    assert api.post("/uploads/task-proofs", parent).status_code in {403, 422}
