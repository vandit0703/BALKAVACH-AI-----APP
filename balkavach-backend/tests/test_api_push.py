"""Device registration, push dispatch rules and the FCM provider (no network)."""

import json

import httpx
import pytest

from app.db.base import get_model
from app.integrations.fcm import FcmProvider
from app.services import push_service


class FakeProvider:
    def __init__(self, result="ok"):
        self.sent = []
        self.result = result

    def send(self, token, title, body, data):
        self.sent.append({"token": token, "title": title, "body": body, "data": data})
        return self.result


@pytest.fixture
def provider(monkeypatch, isolated_test_session):
    fake = FakeProvider()
    monkeypatch.setattr(push_service, "get_push_notification_provider", lambda: fake)
    monkeypatch.setattr(push_service, "_runner", lambda fn: fn())

    class _Factory:
        def __enter__(self):
            return isolated_test_session

        def __exit__(self, *exc):
            return False

    monkeypatch.setattr(push_service, "_session_factory", lambda: _Factory())
    return fake


def _register(api, token, device="a" * 40, platform="android"):
    return api.client.put(
        "/api/v1/notifications/devices",
        headers=api.auth(token),
        json={"token": device, "platform": platform, "app_version": "1.0.0"},
    )


def test_device_registration_requires_auth_and_validates(api):
    parent = api.register_parent()
    assert api.client.put("/api/v1/notifications/devices", json={"token": "a" * 40, "platform": "android"}).status_code == 401
    assert _register(api, parent["token"], platform="windows-phone").status_code == 422
    assert _register(api, parent["token"], device="short").status_code == 422
    assert _register(api, parent["token"]).status_code == 204


def test_tokens_are_never_returned_and_move_to_the_latest_user(api, isolated_test_session):
    a = api.register_parent()
    b = api.register_parent()
    assert _register(api, a["token"], device="t" * 50).status_code == 204
    assert _register(api, b["token"], device="t" * 50).status_code == 204
    DeviceToken = get_model("DeviceToken")
    rows = isolated_test_session.query(DeviceToken).filter(DeviceToken.token == "t" * 50).all()
    assert len(rows) == 1 and str(rows[0].user_id) == b["id"] and rows[0].is_active
    assert "t" * 50 not in json.dumps(api.get("/notifications", b["token"]).json())


def test_unregister_only_affects_the_callers_token(api, isolated_test_session):
    a = api.register_parent()
    b = api.register_parent()
    _register(api, a["token"], device="x" * 45)
    other = api.client.post("/api/v1/notifications/devices/unregister", headers=api.auth(b["token"]), json={"token": "x" * 45})
    assert other.status_code == 204
    DeviceToken = get_model("DeviceToken")
    assert isolated_test_session.query(DeviceToken).filter(DeviceToken.token == "x" * 45).count() == 1
    mine = api.client.post("/api/v1/notifications/devices/unregister", headers=api.auth(a["token"]), json={"token": "x" * 45})
    assert mine.status_code == 204
    assert isolated_test_session.query(DeviceToken).filter(DeviceToken.token == "x" * 45).count() == 0


def test_submission_pushes_a_generic_message_to_the_parent_device(api, provider):
    ctx = api.family_with_child("Secret Name")
    _register(api, ctx["parent"]["token"], device="p" * 40)
    task = api.create_task(ctx["parent"]["token"], ctx["family"]["id"], title="Private homework title")
    provider.sent.clear()
    api.submit(ctx["child"]["token"], task["id"])

    assert len(provider.sent) == 1
    sent = provider.sent[0]
    assert sent["token"] == "p" * 40
    blob = json.dumps(sent)
    assert "Secret Name" not in blob and "Private homework title" not in blob
    assert sent["data"]["type"] == "task_submitted"
    assert set(sent["data"]) == {"type", "notification_id"}


def test_every_agreed_flow_pushes_exactly_once(api, provider):
    ctx = api.family_with_child()
    parent, child = ctx["parent"], ctx["child"]
    _register(api, parent["token"], device="p" * 40)
    _register(api, child["token"], device="c" * 40)
    api.grant_stars(child["id"], 10)

    task = api.create_task(parent["token"], ctx["family"]["id"])
    sub = api.submit(child["token"], task["id"]).json()
    api.review(parent["token"], sub["id"], "approved")
    reward = api.create_reward(parent["token"], ctx["family"]["id"], star_cost=2).json()
    red = api.post(
        "/redemptions", child["token"], {"reward_id": reward["id"]}, headers={"Idempotency-Key": "key-123456789"}
    ).json()
    api.post(f"/redemptions/{red['id']}/approve", parent["token"], {})

    kinds = [(m["token"][0], m["data"]["type"]) for m in provider.sent]
    assert ("c", "task_assigned") in kinds
    assert ("p", "task_submitted") in kinds
    assert ("c", "task_approved") in kinds
    assert ("p", "reward_requested") in kinds
    assert ("c", "reward_approved") in kinds
    for expected in [("c", "task_assigned"), ("p", "task_submitted"), ("c", "task_approved"), ("p", "reward_requested"), ("c", "reward_approved")]:
        assert kinds.count(expected) == 1, expected


def test_rejection_and_reward_rejection_push_to_the_child(api, provider):
    ctx = api.family_with_child()
    parent, child = ctx["parent"], ctx["child"]
    _register(api, child["token"], device="c" * 40)
    api.grant_stars(child["id"], 10)
    task = api.create_task(parent["token"], ctx["family"]["id"])
    sub = api.submit(child["token"], task["id"]).json()
    api.review(parent["token"], sub["id"], "rejected", "Try again")
    reward = api.create_reward(parent["token"], ctx["family"]["id"], star_cost=2).json()
    red = api.post(
        "/redemptions", child["token"], {"reward_id": reward["id"]}, headers={"Idempotency-Key": "key-987654321"}
    ).json()
    api.post(f"/redemptions/{red['id']}/reject", parent["token"], {})
    types = [m["data"]["type"] for m in provider.sent]
    assert "task_rejected" in types and "reward_rejected" in types
    assert all("Try again" not in json.dumps(m) for m in provider.sent)


def test_push_disabled_in_settings_sends_nothing(api, provider):
    ctx = api.family_with_child()
    _register(api, ctx["parent"]["token"], device="p" * 40)
    assert api.patch("/settings/me", ctx["parent"]["token"], {"push_enabled": False}).status_code == 200
    task = api.create_task(ctx["parent"]["token"], ctx["family"]["id"])
    provider.sent.clear()
    api.submit(ctx["child"]["token"], task["id"])
    assert provider.sent == []
    # the in-app notification is still stored
    assert any(n["notification_type"] == "task_submitted" for n in api.get("/notifications", ctx["parent"]["token"]).json())


def test_failed_request_sends_no_push(api, provider):
    ctx = api.family_with_child()
    _register(api, ctx["parent"]["token"], device="p" * 40)
    task = api.create_task(ctx["parent"]["token"], ctx["family"]["id"])
    api.submit(ctx["child"]["token"], task["id"])
    provider.sent.clear()
    duplicate = api.submit(ctx["child"]["token"], task["id"])
    assert duplicate.status_code == 409
    assert provider.sent == []


def test_invalid_token_result_deactivates_the_device(api, provider, isolated_test_session):
    ctx = api.family_with_child()
    _register(api, ctx["parent"]["token"], device="p" * 40)
    task = api.create_task(ctx["parent"]["token"], ctx["family"]["id"])
    provider.result = "invalid_token"
    api.submit(ctx["child"]["token"], task["id"])
    DeviceToken = get_model("DeviceToken")
    assert isolated_test_session.query(DeviceToken).filter(DeviceToken.token == "p" * 40).one().is_active is False


def test_localised_push_text(api, provider):
    ctx = api.family_with_child()
    assert api.patch("/settings/me", ctx["parent"]["token"], {"language_code": "hi"}).status_code == 200
    _register(api, ctx["parent"]["token"], device="p" * 40)
    task = api.create_task(ctx["parent"]["token"], ctx["family"]["id"])
    provider.sent.clear()
    api.submit(ctx["child"]["token"], task["id"])
    assert provider.sent[0]["title"] != "Mission submitted"
    assert any("ऀ" <= ch <= "ॿ" for ch in provider.sent[0]["title"])


def test_provider_exception_never_breaks_the_request(api, provider):
    ctx = api.family_with_child()
    _register(api, ctx["parent"]["token"], device="p" * 40)
    task = api.create_task(ctx["parent"]["token"], ctx["family"]["id"])

    def boom(*args, **kwargs):
        raise RuntimeError("fcm down")

    provider.send = boom
    assert api.submit(ctx["child"]["token"], task["id"]).status_code == 201


# -- FCM provider ---------------------------------------------------------

def _service_account():
    from cryptography.hazmat.primitives import serialization
    from cryptography.hazmat.primitives.asymmetric import rsa

    key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
    pem = key.private_bytes(
        serialization.Encoding.PEM, serialization.PrivateFormat.PKCS8, serialization.NoEncryption()
    ).decode()
    return {
        "type": "service_account",
        "project_id": "demo-project",
        "client_email": "svc@demo-project.iam.gserviceaccount.com",
        "private_key": pem,
        "token_uri": "https://oauth2.example.test/token",
    }


def _fcm(handler):
    client = httpx.Client(transport=httpx.MockTransport(handler))
    return FcmProvider(_service_account(), http_client=client)


def test_fcm_sends_v1_payload_and_caches_the_access_token():
    calls = {"oauth": 0, "send": []}

    def handler(request: httpx.Request):
        if request.url.host == "oauth2.example.test":
            calls["oauth"] += 1
            assert b"grant_type=urn" in request.content
            return httpx.Response(200, json={"access_token": "ya29.test", "expires_in": 3600})
        assert request.headers["authorization"] == "Bearer ya29.test"
        assert str(request.url) == "https://fcm.googleapis.com/v1/projects/demo-project/messages:send"
        calls["send"].append(json.loads(request.content))
        return httpx.Response(200, json={"name": "projects/demo-project/messages/1"})

    provider = _fcm(handler)
    assert provider.send("tok" * 20, "Title", "Body", {"type": "x"}) == "ok"
    assert provider.send("tok" * 20, "Title", "Body", {"type": "x"}) == "ok"
    assert calls["oauth"] == 1
    message = calls["send"][0]["message"]
    assert message["token"] == "tok" * 20
    assert message["notification"] == {"title": "Title", "body": "Body"}
    assert message["data"] == {"type": "x"}
    assert message["android"]["priority"] == "HIGH"


@pytest.mark.parametrize(
    "status, body, expected",
    [
        (404, {"error": {"status": "NOT_FOUND", "details": [{"errorCode": "UNREGISTERED"}]}}, "invalid_token"),
        (400, {"error": {"status": "INVALID_ARGUMENT", "details": [{"errorCode": "INVALID_ARGUMENT"}]}}, "invalid_token"),
        (429, {"error": {"status": "RESOURCE_EXHAUSTED"}}, "retry"),
        (503, {"error": {"status": "UNAVAILABLE"}}, "retry"),
        (403, {"error": {"status": "PERMISSION_DENIED"}}, "error"),
    ],
)
def test_fcm_error_mapping(status, body, expected):
    def handler(request):
        if request.url.host == "oauth2.example.test":
            return httpx.Response(200, json={"access_token": "t", "expires_in": 3600})
        return httpx.Response(status, json=body)

    assert _fcm(handler).send("tok" * 20, "T", "B", {}) == expected


def test_fcm_oauth_failure_is_an_error_not_an_exception():
    def handler(request):
        return httpx.Response(401, json={"error": "invalid_grant"})

    assert _fcm(handler).send("tok" * 20, "T", "B", {}) == "error"


def test_fcm_requires_a_complete_service_account():
    with pytest.raises(ValueError):
        FcmProvider({"project_id": "x"})
