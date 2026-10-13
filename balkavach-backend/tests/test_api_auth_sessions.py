"""Registration, login, refresh rotation, logout and role separation over HTTP."""

from datetime import datetime, timedelta, timezone

from app.db.base import get_model
from tests.harness import PASSWORD


def _login(api, email):
    response = api.post("/auth/login", json={"email": email, "password": PASSWORD})
    assert response.status_code == 200, response.text
    return response.json()


def test_login_and_register_return_a_refresh_token(api):
    parent = api.register_parent()
    body = _login(api, parent["email"])
    assert body["refresh_token"] and len(body["refresh_token"]) >= 40
    assert body["refresh_expires_at"] > body["expires_at"]
    assert api.get("/auth/me", body["access_token"]).json()["email"] == parent["email"]


def test_refresh_rotates_and_old_token_reuse_revokes_the_session(api):
    parent = api.register_parent()
    first = _login(api, parent["email"])
    second = api.post("/auth/refresh", json={"refresh_token": first["refresh_token"]})
    assert second.status_code == 200, second.text
    assert second.json()["refresh_token"] != first["refresh_token"]
    assert api.get("/auth/me", second.json()["access_token"]).status_code == 200

    replay = api.post("/auth/refresh", json={"refresh_token": first["refresh_token"]})
    assert replay.status_code == 401
    assert replay.json()["error"]["code"] == "refresh_token_reused"
    # the thief's replay also ended the legitimate session
    assert api.post("/auth/refresh", json={"refresh_token": second.json()["refresh_token"]}).status_code == 401
    assert api.get("/auth/me", second.json()["access_token"]).status_code == 401


def test_unknown_or_malformed_refresh_token_is_rejected(api):
    assert api.post("/auth/refresh", json={"refresh_token": "x" * 48}).status_code == 401
    assert api.post("/auth/refresh", json={"refresh_token": "short"}).status_code == 422


def test_expired_refresh_token_is_rejected(api, isolated_test_session):
    parent = api.register_parent()
    body = _login(api, parent["email"])
    AuthSession = get_model("AuthSession")
    isolated_test_session.query(AuthSession).update(
        {AuthSession.expires_at: datetime.now(timezone.utc) - timedelta(minutes=1)}
    )
    isolated_test_session.commit()
    denied = api.post("/auth/refresh", json={"refresh_token": body["refresh_token"]})
    assert denied.status_code == 401
    assert denied.json()["error"]["code"] == "invalid_refresh_token"


def test_logout_revokes_the_session_and_its_access_token(api):
    parent = api.register_parent()
    body = _login(api, parent["email"])
    assert api.post("/auth/logout", json={"refresh_token": body["refresh_token"]}).status_code == 204
    assert api.post("/auth/logout", json={"refresh_token": body["refresh_token"]}).status_code == 204
    assert api.post("/auth/refresh", json={"refresh_token": body["refresh_token"]}).status_code == 401
    assert api.get("/auth/me", body["access_token"]).status_code == 401


def test_child_session_refreshes_as_a_child_and_never_gains_parent_rights(api):
    ctx = api.family_with_child()
    child, family = ctx["child"], ctx["family"]
    response = api.post(f"/auth/children/{child['id']}/session", ctx["parent"]["token"])
    body = response.json()
    assert body["user"]["role"] == "child" and body["refresh_token"]

    refreshed = api.post("/auth/refresh", json={"refresh_token": body["refresh_token"]}).json()
    assert refreshed["user"]["role"] == "child"
    assert refreshed["user"]["id"] == body["user"]["id"]
    token = refreshed["access_token"]
    assert api.get("/auth/me", token).json()["role"] == "child"
    assert api.get("/families", token).status_code == 403
    assert api.post("/families", token, {"family_name": "Nope"}).status_code == 403
    assert api.get(f"/settings/families/{family['id']}", token).status_code == 403
    assert api.post(f"/auth/children/{child['id']}/session", token).status_code == 403
    # the child response never carries anything of the parent's
    assert ctx["parent"]["email"] not in str(refreshed)


def test_parent_can_end_a_childs_sessions_but_not_another_familys(api):
    ctx = api.family_with_child()
    other = api.family_with_child()
    child = ctx["child"]
    session = api.post(f"/auth/children/{child['id']}/session", ctx["parent"]["token"]).json()

    assert api.delete(f"/auth/children/{child['id']}/sessions", other["parent"]["token"]).status_code == 404
    assert api.get("/auth/me", session["access_token"]).status_code == 200

    assert api.delete(f"/auth/children/{child['id']}/sessions", ctx["parent"]["token"]).status_code == 204
    assert api.get("/auth/me", session["access_token"]).status_code == 401
    assert api.post("/auth/refresh", json={"refresh_token": session["refresh_token"]}).status_code == 401


def test_deactivated_child_cannot_refresh(api):
    ctx = api.family_with_child()
    session = api.post(f"/auth/children/{ctx['child']['id']}/session", ctx["parent"]["token"]).json()
    assert api.delete(f"/families/{ctx['family']['id']}/children/{ctx['child']['id']}", ctx["parent"]["token"]).status_code == 204
    assert api.post("/auth/refresh", json={"refresh_token": session["refresh_token"]}).status_code == 401
    assert api.get("/auth/me", session["access_token"]).status_code == 401
    assert api.post(f"/auth/children/{ctx['child']['id']}/session", ctx["parent"]["token"]).status_code == 404


def test_wrong_password_and_duplicate_email(api):
    parent = api.register_parent()
    bad = api.post("/auth/login", json={"email": parent["email"], "password": "definitely-wrong-password"})
    assert bad.status_code == 401 and bad.json()["error"]["code"] == "invalid_credentials"
    dup = api.post("/auth/register", json={"full_name": "Dup Parent", "email": parent["email"].upper(), "password": PASSWORD})
    assert dup.status_code == 409 and dup.json()["error"]["code"] == "email_in_use"
    weak = api.post("/auth/register", json={"full_name": "Weak", "email": "weak@example.com", "password": "short"})
    assert weak.status_code == 422


def test_sign_in_still_works_when_the_sessions_table_is_not_migrated(api, monkeypatch):
    monkeypatch.setattr("app.services.session_service._auth_session_model", lambda: None)
    parent = api.register_parent()
    body = _login(api, parent["email"])
    assert body["refresh_token"] is None
    assert api.get("/auth/me", body["access_token"]).status_code == 200
    assert api.post("/auth/refresh", json={"refresh_token": "x" * 48}).status_code == 501
