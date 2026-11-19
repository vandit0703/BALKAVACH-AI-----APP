"""Forgot-password → email link → reset, end to end at the API level (DB-backed).

The emailed link is captured by replacing the SMTP sender; the landing page that consumes the
token is covered without a database in ``test_password_reset_page.py``.
"""

from uuid import uuid4

import pytest

from tests.harness import PASSWORD

NEW_PASSWORD = "a-brand-new-long-password"


@pytest.fixture
def mailbox(monkeypatch):
	sent: list[tuple[str, str]] = []
	monkeypatch.setattr("app.integrations.email.send_password_reset", lambda email, token: sent.append((email, token)))
	return sent


def test_forgot_then_reset_changes_the_password_and_ends_every_session(api, mailbox):
	parent = api.register_parent()
	assert api.post("/auth/password/forgot", json={"email": parent["email"]}).status_code == 202
	assert len(mailbox) == 1 and mailbox[0][0] == parent["email"]
	token = mailbox[0][1]

	assert api.post("/auth/password/reset", json={"token": token, "password": NEW_PASSWORD}).status_code == 204
	assert api.get("/families", parent["token"]).status_code == 401  # old access token's session is revoked
	assert api.post("/auth/login", json={"email": parent["email"], "password": PASSWORD}).status_code == 401
	assert api.post("/auth/login", json={"email": parent["email"], "password": NEW_PASSWORD}).status_code == 200


def test_reset_token_is_single_use(api, mailbox):
	parent = api.register_parent()
	api.post("/auth/password/forgot", json={"email": parent["email"]})
	token = mailbox[0][1]
	assert api.post("/auth/password/reset", json={"token": token, "password": NEW_PASSWORD}).status_code == 204
	again = api.post("/auth/password/reset", json={"token": token, "password": "another-long-password-1"})
	assert again.status_code == 400
	assert again.json()["error"]["code"] == "invalid_reset_token"


def test_newer_request_invalidates_the_older_link(api, mailbox):
	parent = api.register_parent()
	api.post("/auth/password/forgot", json={"email": parent["email"]})
	api.post("/auth/password/forgot", json={"email": parent["email"]})
	first, second = mailbox[0][1], mailbox[1][1]
	assert api.post("/auth/password/reset", json={"token": first, "password": NEW_PASSWORD}).status_code == 400
	assert api.post("/auth/password/reset", json={"token": second, "password": NEW_PASSWORD}).status_code == 204


def test_unknown_email_gets_the_same_answer_and_sends_nothing(api, mailbox):
	response = api.post("/auth/password/forgot", json={"email": f"nobody-{uuid4().hex}@example.com"})
	assert response.status_code == 202
	assert mailbox == []


def test_child_accounts_cannot_use_password_reset(api, mailbox):
	data = api.family_with_child()
	api.post("/auth/password/forgot", json={"email": f"{data['child']['username']}@example.com"})
	assert mailbox == []


def test_garbage_and_short_passwords_are_rejected(api, mailbox):
	assert api.post("/auth/password/reset", json={"token": "x" * 40, "password": NEW_PASSWORD}).status_code == 400
	parent = api.register_parent()
	api.post("/auth/password/forgot", json={"email": parent["email"]})
	assert api.post("/auth/password/reset", json={"token": mailbox[0][1], "password": "short"}).status_code == 422
