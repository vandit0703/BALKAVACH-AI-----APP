"""Admin API: authorisation, management endpoints, audit trail, app config."""

import pytest

from app.core.permissions import expand_permissions
from app.db.base import get_model


def _audit_actions(api, admin):
    return [row["action"] for row in api.get("/admin/audit-logs?limit=100", admin["token"]).json()]


# -- permissions -------------------------------------------------------------

def test_permission_aliases_cover_the_seeded_content_manager_role():
    granted = expand_permissions(
        ["videos.read", "videos.create", "videos.update", "videos.publish", "categories.manage", "collections.manage"]
    )
    assert {"video:read", "video:write", "content:read", "content:write"} <= granted
    assert "users:write" not in granted and "dashboard:read" not in granted
    assert expand_permissions({"users:read": True, "users:write": False}) == {"users:read"}
    assert expand_permissions(["users.read"]) == {"users:read"}
    assert expand_permissions(None) == set()


@pytest.mark.parametrize(
    "path",
    ["/admin/me", "/admin/dashboard", "/admin/users", "/admin/families", "/admin/tasks", "/admin/rewards",
     "/admin/redemptions", "/admin/task-categories", "/admin/preset-tasks", "/admin/analytics/overview",
     "/admin/settings", "/admin/audit-logs", "/admin/badges", "/admin/roles"],
)
def test_admin_endpoints_reject_parents_children_and_anonymous(api, path):
    ctx = api.family_with_child()
    assert api.get(path).status_code == 401
    assert api.get(path, ctx["parent"]["token"]).status_code == 403
    assert api.get(path, ctx["child"]["token"]).status_code == 403


def test_content_manager_can_manage_content_but_not_users(api):
    manager = api.make_admin("content_manager")
    assert api.get("/admin/educational-content", manager["token"]).status_code == 200
    assert api.get("/admin/task-categories", manager["token"]).status_code == 200
    assert api.get("/admin/users", manager["token"]).status_code == 403
    assert api.get("/admin/families", manager["token"]).status_code == 403
    assert api.get("/admin/dashboard", manager["token"]).status_code == 403


def test_a_user_with_an_admin_role_row_but_a_parent_account_is_still_refused(api, isolated_test_session):
    parent = api.register_parent()
    AdminRole = get_model("AdminRole")
    UserAdminRole = get_model("UserAdminRole")
    role = isolated_test_session.query(AdminRole).filter(AdminRole.name == "super_admin").one()
    isolated_test_session.add(UserAdminRole(user_id=parent["id"], admin_role_id=role.id))
    isolated_test_session.commit()
    assert api.get("/admin/dashboard", parent["token"]).status_code == 403


# -- users, families, children --------------------------------------------------

def test_user_listing_search_and_status(api):
    admin = api.make_admin()
    ctx = api.family_with_child("Findable Kid")
    users = api.get(f"/admin/users?q={ctx['parent']['email'][:12]}", admin["token"]).json()
    assert any(u["id"] == ctx["parent"]["id"] for u in users)
    assert {"is_active", "created_at"} <= set(users[0])

    off = api.patch(f"/admin/users/{ctx['parent']['id']}/status", admin["token"], {"is_active": False})
    assert off.status_code == 200 and off.json()["is_active"] is False
    assert api.get("/auth/me", ctx["parent"]["token"]).status_code == 401
    assert "user.deactivated" in _audit_actions(api, admin)
    assert api.patch(f"/admin/users/{admin['id']}/status", admin["token"], {"is_active": False}).status_code == 409


def test_family_list_and_detail(api):
    admin = api.make_admin()
    ctx = api.family_with_child("Asha")
    api.create_task(ctx["parent"]["token"], ctx["family"]["id"])
    families = api.get("/admin/families?q=Test%20Family", admin["token"]).json()
    row = next(f for f in families if f["id"] == ctx["family"]["id"])
    assert row["child_count"] == 1 and row["active_task_count"] == 1 and row["member_count"] >= 1

    detail = api.get(f"/admin/families/{ctx['family']['id']}", admin["token"])
    assert detail.status_code == 200
    body = detail.json()
    assert [c["display_name"] for c in body["children"]] == ["Asha"]
    assert body["parents"][0]["email"] == ctx["parent"]["email"]
    assert "date_of_birth" not in body["children"][0]
    assert api.get("/admin/families/00000000-0000-0000-0000-000000000000", admin["token"]).status_code == 404


def test_admin_can_deactivate_a_child_and_it_is_audited(api):
    admin = api.make_admin()
    ctx = api.family_with_child()
    response = api.patch(f"/admin/children/{ctx['child']['id']}/status", admin["token"], {"is_active": False})
    assert response.status_code == 200 and response.json()["is_active"] is False
    assert api.get("/auth/me", ctx["child"]["token"]).status_code == 401
    assert "child.deactivated" in _audit_actions(api, admin)
    back = api.patch(f"/admin/children/{ctx['child']['id']}/status", admin["token"], {"is_active": True})
    assert back.json()["is_active"] is True


# -- missions, rewards, redemptions ------------------------------------------------

def test_admin_tasks_rewards_and_redemptions_views(api):
    admin = api.make_admin()
    ctx = api.family_with_child()
    api.grant_stars(ctx["child"]["id"], 10)
    task = api.create_task(ctx["parent"]["token"], ctx["family"]["id"], title="Admin visible")
    reward = api.create_reward(ctx["parent"]["token"], ctx["family"]["id"], star_cost=3).json()
    api.post("/redemptions", ctx["child"]["token"], {"reward_id": reward["id"]}, headers={"Idempotency-Key": "adm-key-12345"})

    tasks = api.get(f"/admin/tasks?family_id={ctx['family']['id']}", admin["token"]).json()
    assert [t["title"] for t in tasks] == ["Admin visible"]
    assert tasks[0]["family_name"] == "Test Family"
    rewards = api.get(f"/admin/rewards?family_id={ctx['family']['id']}", admin["token"]).json()
    assert [r["name"] for r in rewards] == ["Extra story"]
    redemptions = api.get("/admin/redemptions?status=pending", admin["token"]).json()
    assert any(r["reward_name"] == "Extra story" and r["child_name"] == "Kid" for r in redemptions)

    off = api.patch(f"/admin/tasks/{task['id']}/active", admin["token"], {"is_active": False})
    assert off.status_code == 200 and off.json()["is_active"] is False
    assert api.get("/tasks", ctx["child"]["token"]).json() == []
    assert api.patch(f"/admin/rewards/{reward['id']}/active", admin["token"], {"is_active": False}).json()["is_active"] is False
    actions = _audit_actions(api, admin)
    assert "task.deactivated" in actions and "reward.deactivated" in actions


# -- categories and presets ----------------------------------------------------------

def test_category_management_and_visibility(api):
    admin = api.make_admin()
    ctx = api.family_with_child()
    created = api.post("/tasks/categories", admin["token"], {"name": "Kindness", "icon_name": "heart"})
    assert created.status_code == 201
    category_id = created.json()["id"]
    assert any(c["name"] == "Kindness" for c in api.get("/tasks/categories", ctx["parent"]["token"]).json())

    edited = api.patch(f"/admin/task-categories/{category_id}", admin["token"], {"name": "Kindness Corner", "is_active": False})
    assert edited.status_code == 200
    assert not any(c["id"] == category_id for c in api.get("/tasks/categories", ctx["parent"]["token"]).json())
    listing = api.get("/admin/task-categories", admin["token"]).json()
    assert any(c["id"] == category_id and c["is_active"] is False for c in listing)
    dup = api.patch(f"/admin/task-categories/{category_id}", admin["token"], {"name": "Learning"})
    assert dup.status_code == 409
    assert api.patch(f"/admin/task-categories/{category_id}", ctx["parent"]["token"], {"name": "Hack"}).status_code == 403


def test_preset_tasks_admin_crud_and_parent_library(api):
    admin = api.make_admin()
    ctx = api.family_with_child()
    category = api.get("/tasks/categories", ctx["parent"]["token"]).json()[0]
    en = api.post("/admin/preset-tasks", admin["token"], {
        "title": "Brush teeth", "category_id": category["id"], "suggested_star_reward": 1, "suggested_xp_reward": 5,
    })
    assert en.status_code == 201, en.text
    hi = api.post("/admin/preset-tasks", admin["token"], {
        "title": "दाँत साफ़ करें", "language_code": "hi", "category_id": category["id"],
    })
    assert hi.status_code == 201
    hidden = api.post("/admin/preset-tasks", admin["token"], {"title": "Retired preset"}).json()
    api.patch(f"/admin/preset-tasks/{hidden['id']}", admin["token"], {"is_active": False})

    library = api.get("/tasks/presets", ctx["parent"]["token"]).json()
    assert "Brush teeth" in [p["title"] for p in library]
    assert "Retired preset" not in [p["title"] for p in library]
    assert "दाँत साफ़ करें" not in [p["title"] for p in library]
    hindi = api.get("/tasks/presets?language=hi", ctx["parent"]["token"]).json()
    assert [p["title"] for p in hindi][0] == "दाँत साफ़ करें"
    assert api.get("/tasks/presets", ctx["child"]["token"]).status_code == 403

    bad = api.post("/admin/preset-tasks", admin["token"], {"title": "Negative", "suggested_star_reward": -1})
    assert bad.status_code == 422
    assert api.patch(f"/admin/preset-tasks/{en.json()['id']}", admin["token"], {"title": "Brush teeth twice"}).json()["title"] == "Brush teeth twice"
    assert "preset_task.created" in _audit_actions(api, admin)


# -- badges, content, roles ------------------------------------------------------------

def test_badge_edit_and_educational_content_edit(api):
    admin = api.make_admin()
    badge = api.post("/admin/badges", admin["token"], {
        "name": "Helper", "criteria_type": "approved_tasks", "threshold": 3,
    }).json()
    edited = api.patch(f"/admin/badges/{badge['id']}", admin["token"], {"threshold": 5, "is_active": False})
    assert edited.status_code == 200
    assert edited.json()["criteria_value"] == {"threshold": 5} and edited.json()["is_active"] is False

    content = api.post("/admin/educational-content", admin["token"], {
        "title": "Counting song", "content_type": "link", "language_code": "en",
        "content_url": "https://example.com/counting",
    })
    assert content.status_code == 201, content.text
    updated = api.patch(f"/admin/educational-content/{content.json()['id']}", admin["token"], {"title": "Counting song 2", "language_code": "gu"})
    assert updated.status_code == 200
    assert (updated.json()["title"], updated.json()["language_code"]) == ("Counting song 2", "gu")


def test_role_assignment_cannot_remove_the_last_super_admin(api, isolated_test_session):
    admin = api.make_admin()
    roles = {r["name"]: r["id"] for r in api.get("/admin/roles", admin["token"]).json()}
    other = api.make_admin("content_manager")
    grant = api.post(f"/admin/users/{other['id']}/roles", admin["token"], {"role_id": roles["super_admin"]})
    assert grant.status_code == 204
    assert api.get("/admin/users", other["token"]).status_code == 200
    revoke = api.delete(f"/admin/users/{other['id']}/roles/{roles['super_admin']}", admin["token"])
    assert revoke.status_code == 204
    assert api.get("/admin/users", other["token"]).status_code == 403
    UserAdminRole = get_model("UserAdminRole")
    isolated_test_session.query(UserAdminRole).filter(UserAdminRole.admin_role_id == roles["super_admin"]).delete()
    isolated_test_session.add(UserAdminRole(user_id=admin["id"], admin_role_id=roles["super_admin"]))
    isolated_test_session.commit()
    last = api.delete(f"/admin/users/{admin['id']}/roles/{roles['super_admin']}", admin["token"])
    assert last.status_code == 409


# -- analytics -------------------------------------------------------------------------

def test_analytics_overview(api):
    admin = api.make_admin()
    ctx = api.family_with_child()
    task = api.create_task(ctx["parent"]["token"], ctx["family"]["id"])
    sub = api.submit(ctx["child"]["token"], task["id"]).json()
    api.review(ctx["parent"]["token"], sub["id"], "approved")
    overview = api.get("/admin/analytics/overview?days=7", admin["token"])
    assert overview.status_code == 200, overview.text
    body = overview.json()
    assert body["period_days"] == 7 and len(body["daily"]) == 7
    assert body["totals"]["submissions"] >= 1 and body["totals"]["approvals"] >= 1
    assert body["totals"]["new_users"] >= 2
    assert body["redemptions_by_status"].keys() >= {"pending"}
    assert api.get("/admin/analytics/overview?days=0", admin["token"]).status_code == 422
    assert api.get("/admin/analytics/overview?days=366", admin["token"]).status_code == 422


# -- application settings / public config -------------------------------------------------

def test_public_config_defaults_then_admin_override(api):
    default = api.get("/app-config")
    assert default.status_code == 200
    body = default.json()
    assert body["consent_versions"]["parent_guardian_terms"]
    assert body["consent_source"] == "default"
    assert body["maintenance"]["enabled"] is False

    admin = api.make_admin()
    put = api.client.put(
        "/api/v1/admin/settings/consent_versions",
        headers=api.auth(admin["token"]),
        json={"value": {"parent_guardian_terms": "2027-01", "privacy_notice": "2027-01"}},
    )
    assert put.status_code == 200, put.text
    after = api.get("/app-config").json()
    assert after["consent_versions"]["parent_guardian_terms"] == "2027-01"
    assert after["consent_source"] == "admin"
    assert "app_setting.updated" in _audit_actions(api, admin)


@pytest.mark.parametrize(
    "key, value",
    [
        ("consent_versions", {"parent_guardian_terms": ""}),
        ("consent_versions", {"x" * 100: "1"}),
        ("consent_versions", "not-an-object"),
        ("maintenance", {"enabled": "yes"}),
        ("maintenance", {"enabled": True, "message": "m" * 400}),
        ("min_app_version", "1.2.3"),
        ("secret_key", "value"),
    ],
)
def test_app_settings_reject_invalid_values_and_unknown_keys(api, key, value):
    admin = api.make_admin()
    response = api.client.put(
        f"/api/v1/admin/settings/{key}", headers=api.auth(admin["token"]), json={"value": value}
    )
    assert response.status_code in {404, 422}


def test_only_authorised_admins_can_write_settings(api):
    manager = api.make_admin("content_manager")
    denied = api.client.put(
        "/api/v1/admin/settings/maintenance", headers=api.auth(manager["token"]), json={"value": {"enabled": True}}
    )
    assert denied.status_code == 403
    assert api.get("/app-config").json()["maintenance"]["enabled"] is False


def test_admin_me_reports_roles_and_effective_permissions(api):
    manager = api.make_admin("content_manager")
    me = api.get("/admin/me", manager["token"])
    assert me.status_code == 200, me.text
    body = me.json()
    assert body["roles"] == ["content_manager"]
    assert {"content:write", "content:read", "video:write"} <= set(body["permissions"])
    assert "users:write" not in body["permissions"]
    root = api.get("/admin/me", api.make_admin()["token"]).json()
    assert root["permissions"] == ["*"] and root["roles"] == ["super_admin"]
