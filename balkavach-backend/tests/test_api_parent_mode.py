"""Parent-mode entry from a child device (SEC-01/02): email + password, bound to the child's family.

DB-backed: needs TEST_DATABASE_URL (baseline schema + migrations) and REDIS_URL, see
``scripts/testenv.py``. Every test runs inside the harness's rolled-back transaction.
"""

from uuid import uuid4

from fastapi.testclient import TestClient

from app.core.config import settings
from app.db.base import get_model
from app.main import app
from tests.harness import PASSWORD

ENTER = "/auth/parent-mode/enter"


def _enter(api, child_token, email, password, client=None):
	target = client or api.client
	return target.post(
		f"/api/v1{ENTER}",
		headers=api.auth(child_token),
		json={"email": email, "password": password},
	)


def _setup(api):
	data = api.family_with_child()
	return data, data["parent"]["email"], data["child"]["token"]


def test_correct_parent_credentials_issue_a_parent_session_for_the_family(api):
	data, email, child_token = _setup(api)
	response = _enter(api, child_token, email, PASSWORD)
	assert response.status_code == 200, response.text
	body = response.json()
	assert body["user"]["role"] == "parent"
	assert body["user"]["id"] == data["parent"]["id"]
	assert body["refresh_token"]
	# The new session reaches the parent's family data; the child's own token never could.
	assert api.get("/families", body["access_token"]).status_code == 200
	assert api.get("/families", child_token).status_code == 403


def test_parent_mode_session_is_labelled_short_lived_and_linked_to_the_child(api):
	data, email, child_token = _setup(api)
	body = _enter(api, child_token, email, PASSWORD).json()
	AuthSession = get_model("AuthSession")
	row = api.session.query(AuthSession).filter(AuthSession.user_id == data["parent"]["id"]).order_by(
		AuthSession.created_at.desc()
	).first()
	assert row.device_label == "parent_mode"
	assert str(row.issued_by) == data["child"]["user_id"]
	hours = (row.expires_at.replace(tzinfo=None) - row.created_at.replace(tzinfo=None)).total_seconds() / 3600
	assert hours <= settings.parent_mode_refresh_hours + 0.1
	# Rotation keeps the short lifetime and still works.
	refreshed = api.post("/auth/refresh", json={"refresh_token": body["refresh_token"]})
	assert refreshed.status_code == 200
	assert refreshed.json()["user"]["role"] == "parent"


def test_logout_revokes_the_parent_mode_session_immediately(api):
	_, email, child_token = _setup(api)
	body = _enter(api, child_token, email, PASSWORD).json()
	assert api.post("/auth/logout", json={"refresh_token": body["refresh_token"]}).status_code == 204
	assert api.get("/families", body["access_token"]).status_code == 401


def test_every_failure_looks_the_same_and_reveals_nothing_about_the_account(api):
	data, email, child_token = _setup(api)
	stranger = api.register_parent()  # a real parent, but of another family
	cases = {
		"wrong_password": (email, "not-the-password-0000"),
		"unknown_email": (f"nobody-{uuid4().hex}@example.com", PASSWORD),
		"other_family_correct_password": (stranger["email"], PASSWORD),
	}
	bodies = {}
	for name, (mail, password) in cases.items():
		response = _enter(api, child_token, mail, password)
		assert response.status_code == 403, (name, response.text)
		error = response.json()["error"]
		bodies[name] = (error["code"], error["message"])
	assert len(set(bodies.values())) == 1
	assert bodies["wrong_password"] == ("parent_authentication_failed", "Email or password is incorrect")


def test_parent_of_another_family_never_gets_a_session_here(api):
	_, _, child_token = _setup(api)
	stranger = api.register_parent()
	for _ in range(2):
		assert _enter(api, child_token, stranger["email"], PASSWORD).status_code in {403, 423}


def test_a_child_session_is_required_and_parent_or_anonymous_calls_are_refused(api):
	data, email, _ = _setup(api)
	assert api.client.post(f"/api/v1{ENTER}", json={"email": email, "password": PASSWORD}).status_code == 401
	assert _enter(api, data["parent"]["token"], email, PASSWORD).status_code == 403


def test_a_child_username_or_password_cannot_authenticate_as_a_parent(api):
	data, _, child_token = _setup(api)
	child = data["child"]
	# usernames are not e-mail addresses: rejected at validation, no session
	assert _enter(api, child_token, child["username"], child["password"]).status_code == 422
	assert _enter(api, child_token, f"{child['username']}@example.com", child["password"]).status_code == 403


def test_repeated_failures_lock_the_account_even_from_other_ip_addresses(api, monkeypatch):
	monkeypatch.setattr(settings, "parent_mode_max_failures", 3)
	data, email, child_token = _setup(api)
	codes = [_enter(api, child_token, email, "wrong-password-value").status_code for _ in range(3)]
	assert codes[:2] == [403, 403] and codes[2] == 423
	# A different client address, and the *correct* password: still refused while locked.
	other = TestClient(app, client=("203.0.113.77", 40000))
	locked = _enter(api, child_token, email, PASSWORD, client=other)
	assert locked.status_code == 423
	assert int(locked.headers["Retry-After"]) > 0
	assert locked.json()["error"]["code"] == "parent_mode_locked"


def test_lockout_is_per_family_so_guessing_many_emails_also_stops(api, monkeypatch):
	monkeypatch.setattr(settings, "parent_mode_max_failures", 3)
	data, email, child_token = _setup(api)
	statuses = [_enter(api, child_token, f"guess-{i}-{uuid4().hex}@example.com", "x" * 12).status_code for i in range(3)]
	assert statuses[-1] == 423
	assert _enter(api, child_token, email, PASSWORD).status_code == 423


def test_lock_notifies_the_parent_without_revealing_credentials(api, monkeypatch):
	monkeypatch.setattr(settings, "parent_mode_max_failures", 3)
	data, email, child_token = _setup(api)
	for _ in range(3):
		_enter(api, child_token, email, "wrong-password-value")
	inbox = api.get("/notifications", data["parent"]["token"]).json()
	assert any(item["notification_type"] == "parent_mode_locked" for item in inbox)


def test_success_clears_earlier_failures(api, monkeypatch):
	monkeypatch.setattr(settings, "parent_mode_max_failures", 3)
	_, email, child_token = _setup(api)
	for _ in range(2):
		assert _enter(api, child_token, email, "wrong-password-value").status_code == 403
	assert _enter(api, child_token, email, PASSWORD).status_code == 200
	assert _enter(api, child_token, email, "wrong-password-value").status_code == 403  # counter restarted


def test_the_old_unauthenticated_email_plus_pin_route_issues_nothing(api):
	_, email, _ = _setup(api)
	response = api.post("/auth/parent-pin/verify", json={"email": email, "pin": "123456"})
	assert response.status_code == 410
	assert "access_token" not in response.text


def test_pin_change_requires_the_current_pin_or_password(api):
	parent = api.register_parent()
	token = parent["token"]
	assert api.get("/auth/parent-pin", token).json() == {"is_set": False}
	assert api.post("/auth/parent-pin", token, {"pin": "482913"}).status_code == 204
	assert api.get("/auth/parent-pin", token).json() == {"is_set": True}
	assert api.post("/auth/parent-pin", token, {"pin": "135792"}).status_code == 403
	assert api.post("/auth/parent-pin", token, {"pin": "135792", "current_pin": "000000"}).status_code == 403
	assert api.post("/auth/parent-pin", token, {"pin": "135792", "current_password": "wrong-password-0"}).status_code == 403
	assert api.post("/auth/parent-pin", token, {"pin": "135792", "current_pin": "482913"}).status_code == 204
	assert api.post("/auth/parent-pin", token, {"pin": "246810", "current_password": PASSWORD}).status_code == 204


def test_new_pins_must_be_at_least_six_digits(api):
	token = api.register_parent()["token"]
	assert api.post("/auth/parent-pin", token, {"pin": "1234"}).status_code == 422
	assert api.post("/auth/parent-pin", token, {"pin": "12ab56"}).status_code == 422


def test_child_cannot_set_or_read_a_pin(api):
	_, _, child_token = _setup(api)
	assert api.post("/auth/parent-pin", child_token, {"pin": "482913"}).status_code == 403
	assert api.get("/auth/parent-pin", child_token).status_code == 403


def test_normal_login_refresh_and_logout_still_work(api):
	parent = api.register_parent()
	login = api.post("/auth/login", json={"email": parent["email"], "password": PASSWORD})
	assert login.status_code == 200
	refreshed = api.post("/auth/refresh", json={"refresh_token": login.json()["refresh_token"]})
	assert refreshed.status_code == 200
	assert api.post("/auth/logout", json={"refresh_token": refreshed.json()["refresh_token"]}).status_code == 204
	assert api.post("/auth/login", json={"email": parent["email"], "password": "wrong-password-0"}).status_code == 401


# -- added during Phase 1 verification (written; not yet run: needs the baseline schema) --------------


def test_handing_the_device_back_to_a_child_revokes_the_parent_mode_session_on_the_server(api):
	data, email, child_token = _setup(api)
	body = _enter(api, child_token, email, PASSWORD).json()
	switched = api.post(f"/auth/children/{data['child']['id']}/session", body["access_token"])
	assert switched.status_code == 200, switched.text
	assert api.get("/families", body["access_token"]).status_code == 401
	assert api.post("/auth/refresh", json={"refresh_token": body["refresh_token"]}).status_code == 401
	assert api.get("/families", data["parent"]["token"]).status_code == 200  # the normal parent login is untouched


def test_an_expired_parent_mode_session_is_refused_even_with_an_unexpired_access_token(api):
	data, email, child_token = _setup(api)
	body = _enter(api, child_token, email, PASSWORD).json()
	AuthSession = get_model("AuthSession")
	row = api.session.query(AuthSession).filter(AuthSession.device_label == "parent_mode").order_by(
		AuthSession.created_at.desc()
	).first()
	from datetime import datetime, timedelta, timezone

	row.expires_at = datetime.now(timezone.utc) - timedelta(minutes=1)
	api.session.commit()
	assert api.get("/families", body["access_token"]).status_code == 401
	assert api.post("/auth/refresh", json={"refresh_token": body["refresh_token"]}).status_code == 401


def test_a_parent_mode_session_cannot_read_another_familys_data(api):
	data, email, child_token = _setup(api)
	body = _enter(api, child_token, email, PASSWORD).json()
	stranger = api.register_parent()
	other_family = api.create_family(stranger["token"])
	assert api.get(f"/families/{other_family['id']}", body["access_token"]).status_code in {403, 404}


def test_a_stranger_cannot_lock_a_parent_out_of_their_own_family(api, monkeypatch):
	monkeypatch.setattr(settings, "parent_mode_max_failures", 3)
	data, email, child_token = _setup(api)
	attacker = api.family_with_child()
	for _ in range(3):  # hammering the victim's address from the attacker's own child device
		_enter(api, attacker["child"]["token"], email, "wrong-password-value")
	assert _enter(api, child_token, email, PASSWORD).status_code == 200
