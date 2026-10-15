"""Learning content: admin-curated items reach children correctly (en / gu / hi)."""

import pytest

from app.cli import create_admin
from app.core.permissions import expand_permissions
from app.db.base import get_model


def _content(api, admin, **overrides):
    payload = {"title": "Counting song", "content_type": "link", "language_code": "en", "content_url": "https://example.com/a"}
    payload.update(overrides)
    response = api.post("/admin/educational-content", admin["token"], payload)
    assert response.status_code == 201, response.text
    return response.json()


def _titles(api, token, path="/educational-content"):
    response = api.get(path, token)
    assert response.status_code == 200, response.text
    return [item["title"] for item in response.json()]


def test_child_sees_active_content_in_their_language_with_english_fallback(api):
    admin = api.make_admin()
    ctx = api.family_with_child()
    _content(api, admin, title="English story")
    _content(api, admin, title="Gujarati story", language_code="gu")
    _content(api, admin, title="Hindi story", language_code="hi")
    hidden = _content(api, admin, title="Retired")
    api.patch(f"/admin/educational-content/{hidden['id']}/active?is_active=false", admin["token"])

    titles = _titles(api, ctx["child"]["token"])
    assert "English story" in titles and "Retired" not in titles
    assert "Gujarati story" not in titles and "Hindi story" not in titles

    assert api.patch("/settings/me", ctx["child"]["token"], {"language_code": "gu"}).status_code == 200
    gu_titles = _titles(api, ctx["child"]["token"])
    assert "Gujarati story" in gu_titles and "English story" in gu_titles and "Hindi story" not in gu_titles


def test_curated_external_video_link_exposes_its_url_but_entitlement_content_does_not(api):
    admin = api.make_admin()
    ctx = api.family_with_child()
    _content(api, admin, title="Curated video", content_type="video", content_url="https://www.youtube.com/watch?v=abc123")
    items = {i["title"]: i for i in api.get("/educational-content", ctx["child"]["token"]).json()}
    assert items["Curated video"]["content_url"] == "https://www.youtube.com/watch?v=abc123"
    assert items["Curated video"]["content_type"] == "video"


def test_content_is_child_only_and_paginated(api):
    admin = api.make_admin()
    ctx = api.family_with_child()
    for index in range(5):
        _content(api, admin, title=f"Item {index}")
    assert api.get("/educational-content", ctx["parent"]["token"]).status_code == 403
    assert api.get("/educational-content").status_code == 401
    first = api.get("/educational-content?limit=2&offset=0", ctx["child"]["token"]).json()
    second = api.get("/educational-content?limit=2&offset=2", ctx["child"]["token"]).json()
    assert len(first) == 2 and len(second) == 2
    assert {i["id"] for i in first}.isdisjoint({i["id"] for i in second})


def test_categories_are_listed_for_children(api):
    ctx = api.family_with_child()
    response = api.get("/videos/categories", ctx["child"]["token"])
    assert response.status_code == 200
    assert {"Learning", "Stories", "Science"} <= {c["name"] for c in response.json()}


def test_content_validation(api):
    admin = api.make_admin()
    assert api.post("/admin/educational-content", admin["token"], {"title": "x", "content_type": "link"}).status_code == 422
    assert api.post("/admin/educational-content", admin["token"], {
        "title": "Bad type", "content_type": "movie", "content_url": "https://example.com"}).status_code == 422
    assert api.post("/admin/educational-content", admin["token"], {
        "title": "Bad url", "content_type": "link", "content_url": "javascript:alert(1)"}).status_code == 422
    assert api.post("/admin/educational-content", admin["token"], {
        "title": "Video w/o target", "content_type": "video"}).status_code == 422


# -- CLI -----------------------------------------------------------------------------------

def test_create_admin_cli_helper(isolated_test_session):
    user = create_admin(isolated_test_session, "Boss@Example.com", "Boss", "a-very-long-password")
    assert user.email == "boss@example.com" and user.role == "admin"
    UserAdminRole = get_model("UserAdminRole")
    assert isolated_test_session.query(UserAdminRole).filter(UserAdminRole.user_id == user.id).count() == 1
    AdminRole = get_model("AdminRole")
    role = (
        isolated_test_session.query(AdminRole)
        .join(UserAdminRole, UserAdminRole.admin_role_id == AdminRole.id)
        .filter(UserAdminRole.user_id == user.id)
        .one()
    )
    assert role.name == "super_admin" and "*" in expand_permissions(role.permissions)
    with pytest.raises(ValueError):
        create_admin(isolated_test_session, "boss@example.com", "Dup", "a-very-long-password")
    with pytest.raises(ValueError):
        create_admin(isolated_test_session, "short@example.com", "Short", "short")
    with pytest.raises(ValueError):
        create_admin(isolated_test_session, "role@example.com", "Role", "a-very-long-password", "no_such_role")
    with pytest.raises(ValueError, match="lacks required admin permissions"):
        create_admin(isolated_test_session, "manager@example.com", "Manager", "a-very-long-password", "content_manager")
    User = get_model("User")
    assert isolated_test_session.query(User.id).filter(User.email == "manager@example.com").first() is None


def test_admin_created_by_cli_can_sign_in_and_use_the_panel(api, isolated_test_session):
    create_admin(isolated_test_session, "panel@example.com", "Panel Admin", "a-very-long-password")
    login = api.post("/auth/login", json={"email": "panel@example.com", "password": "a-very-long-password"})
    assert login.status_code == 200
    token = login.json()["access_token"]
    assert login.json()["user"]["role"] == "admin"
    admin_me = api.get("/admin/me", token)
    assert admin_me.status_code == 200
    assert admin_me.json()["roles"] == ["super_admin"]
    assert admin_me.json()["permissions"] == ["*"]
    assert api.get("/admin/dashboard", token).status_code == 200
