"""HTTP-level tests for rewards, redemptions and their notifications."""

from uuid import uuid4


def _types(api, token):
    return [item["notification_type"] for item in api.get("/notifications", token).json()]


def _redeem(api, child, reward_id, key=None):
    return api.post(
        "/redemptions",
        child["token"],
        {"reward_id": reward_id},
        headers={"Idempotency-Key": key or f"key-{uuid4()}"},
    )


def _ctx_with_stars(api, stars=10):
    ctx = api.family_with_child()
    api.grant_stars(ctx["child"]["id"], stars)
    return ctx


def test_child_sees_only_active_rewards_of_their_own_family(api):
    ctx = _ctx_with_stars(api)
    other = api.family_with_child()
    parent, family, child = ctx["parent"]["token"], ctx["family"], ctx["child"]
    api.create_reward(parent, family["id"], name="Movie night")
    hidden = api.create_reward(parent, family["id"], name="Hidden").json()
    api.delete(f"/rewards/{hidden['id']}", parent)
    api.create_reward(other["parent"]["token"], other["family"]["id"], name="Other family")

    catalog = api.get("/rewards", child["token"])
    assert catalog.status_code == 200, catalog.text
    assert [r["name"] for r in catalog.json()] == ["Movie night"]
    # parent contract is unchanged: family_id is still required
    assert api.get("/rewards", parent).status_code == 422
    assert api.get(f"/rewards?family_id={family['id']}", parent).status_code == 200


def test_parent_can_edit_and_deactivate_rewards_only_in_their_family(api):
    ctx = api.family_with_child()
    other = api.family_with_child()
    parent, family = ctx["parent"]["token"], ctx["family"]
    reward = api.create_reward(parent, family["id"]).json()

    edited = api.patch(f"/rewards/{reward['id']}", parent, {"name": "Bigger prize", "star_cost": 8})
    assert edited.status_code == 200, edited.text
    assert (edited.json()["name"], edited.json()["star_cost"]) == ("Bigger prize", 8)
    assert api.patch(f"/rewards/{reward['id']}", other["parent"]["token"], {"name": "x" * 5}).status_code == 404
    assert api.patch(f"/rewards/{reward['id']}", parent, {"star_cost": 0}).status_code == 422
    assert api.delete(f"/rewards/{reward['id']}", other["parent"]["token"]).status_code == 404
    assert api.delete(f"/rewards/{reward['id']}", parent).status_code == 204
    assert api.get(f"/rewards?family_id={family['id']}", parent).json() == []


def test_redemption_request_notifies_parent_and_approval_debits_once(api):
    ctx = _ctx_with_stars(api, 10)
    parent, family, child = ctx["parent"]["token"], ctx["family"], ctx["child"]
    reward = api.create_reward(parent, family["id"], star_cost=4).json()

    created = _redeem(api, child, reward["id"])
    assert created.status_code == 201, created.text
    assert "reward_requested" in _types(api, parent)

    queue = api.get(f"/redemptions?family_id={family['id']}&status=pending", parent)
    assert queue.status_code == 200, queue.text
    row = queue.json()[0]
    assert (row["reward_name"], row["child_name"], row["status"]) == ("Extra story", "Kid", "pending")

    approved = api.post(f"/redemptions/{row['id']}/approve", parent, {"review_note": "enjoy"})
    assert approved.status_code == 200, approved.text
    assert api.post(f"/redemptions/{row['id']}/approve", parent, {}).status_code == 409
    assert api.get(f"/progress/children/{child['id']}", child["token"]).json()["star_balance"] == 6
    assert "reward_approved" in _types(api, child["token"])


def test_rejected_redemption_keeps_stars_and_notifies_child(api):
    ctx = _ctx_with_stars(api, 10)
    parent, family, child = ctx["parent"]["token"], ctx["family"], ctx["child"]
    reward = api.create_reward(parent, family["id"], star_cost=4).json()
    redemption = _redeem(api, child, reward["id"]).json()
    assert api.post(f"/redemptions/{redemption['id']}/reject", parent, {"review_note": "not now"}).status_code == 200
    assert api.get(f"/progress/children/{child['id']}", child["token"]).json()["star_balance"] == 10
    assert "reward_rejected" in _types(api, child["token"])


def test_same_idempotency_key_returns_same_request_and_notifies_once(api):
    ctx = _ctx_with_stars(api, 10)
    parent, family, child = ctx["parent"]["token"], ctx["family"], ctx["child"]
    reward = api.create_reward(parent, family["id"], star_cost=4).json()
    first = _redeem(api, child, reward["id"], "same-key-12345")
    second = _redeem(api, child, reward["id"], "same-key-12345")
    assert first.json()["id"] == second.json()["id"]
    assert _types(api, parent).count("reward_requested") == 1


def test_second_pending_request_for_same_reward_is_rejected(api):
    ctx = _ctx_with_stars(api, 20)
    parent, family, child = ctx["parent"]["token"], ctx["family"], ctx["child"]
    reward = api.create_reward(parent, family["id"], star_cost=4).json()
    assert _redeem(api, child, reward["id"]).status_code == 201
    duplicate = _redeem(api, child, reward["id"])
    assert duplicate.status_code == 409
    assert duplicate.json()["error"]["code"] == "redemption_pending"


def test_pending_requests_reserve_stars(api):
    ctx = _ctx_with_stars(api, 5)
    parent, family, child = ctx["parent"]["token"], ctx["family"], ctx["child"]
    a = api.create_reward(parent, family["id"], name="Reward A", star_cost=3).json()
    b = api.create_reward(parent, family["id"], name="Reward B", star_cost=3).json()
    assert _redeem(api, child, a["id"]).status_code == 201
    blocked = _redeem(api, child, b["id"])
    assert blocked.status_code == 409
    assert blocked.json()["error"]["code"] == "insufficient_stars"


def test_not_enough_stars_is_refused(api):
    ctx = _ctx_with_stars(api, 1)
    parent, family, child = ctx["parent"]["token"], ctx["family"], ctx["child"]
    reward = api.create_reward(parent, family["id"], star_cost=4).json()
    refused = _redeem(api, child, reward["id"])
    assert refused.status_code == 409
    assert refused.json()["error"]["code"] == "insufficient_stars"


def test_redemption_listing_is_tenant_isolated(api):
    ctx = _ctx_with_stars(api, 10)
    other = api.family_with_child()
    reward = api.create_reward(ctx["parent"]["token"], ctx["family"]["id"], star_cost=2).json()
    _redeem(api, ctx["child"], reward["id"])
    denied = api.get(f"/redemptions?family_id={ctx['family']['id']}", other["parent"]["token"])
    assert denied.status_code == 404
    assert api.get(f"/redemptions?family_id={ctx['family']['id']}", ctx["child"]["token"]).status_code == 403
    mine = api.get("/redemptions/mine", ctx["child"]["token"])
    assert len(mine.json()) == 1


def test_child_can_cancel_own_pending_request(api):
    ctx = _ctx_with_stars(api, 10)
    parent, family, child = ctx["parent"]["token"], ctx["family"], ctx["child"]
    reward = api.create_reward(parent, family["id"], star_cost=4).json()
    redemption = _redeem(api, child, reward["id"]).json()
    cancelled = api.post(f"/redemptions/{redemption['id']}/cancel/mine", child["token"])
    assert cancelled.status_code == 200, cancelled.text
    assert cancelled.json()["status"] == "cancelled"
    # a cancelled request frees the reservation
    assert _redeem(api, child, reward["id"]).status_code == 201
