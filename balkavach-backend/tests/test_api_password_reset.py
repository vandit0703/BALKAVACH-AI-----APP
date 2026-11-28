"""Forgot-password → email link → reset, end to end at the API level (DB-backed).

The emailed link is captured by replacing the SMTP sender; the landing page that consumes the
token is covered without a database in ``test_password_reset_page.py``.
"""

from uuid import uuid4
from datetime import datetime, timedelta, timezone

import pytest

from app.db.base import get_model
from app.core.config import settings
from tests.harness import PASSWORD

NEW_PASSWORD = "a-brand-new-long-password"


def _configure_mail(monkeypatch):
	monkeypatch.setattr(settings, "smtp_host", "smtp.test.invalid")
	monkeypatch.setattr(settings, "smtp_use_ssl", False)
	monkeypatch.setattr(settings, "smtp_use_tls", False)
	monkeypatch.setattr(settings, "smtp_username", None)
	monkeypatch.setattr(settings, "password_reset_from_email", "noreply@test.invalid")
	monkeypatch.setattr(settings, "password_reset_url", "https://api.test.invalid/reset-password")


@pytest.fixture
def mailbox(monkeypatch):
	_configure_mail(monkeypatch)
	sent: list[tuple[str, str]] = []
	monkeypatch.setattr("app.integrations.email.send_password_reset", lambda email, token: sent.append((email, token)))
	return sent


@pytest.fixture
def smtp_outbox(monkeypatch):
	"""The real reset email, captured where it would be handed to the SMTP server."""
	_configure_mail(monkeypatch)
	from app.integrations import email as mailer

	outbox = []

	class Recorder:
		def __init__(self, *args, **kwargs):
			pass

		def __enter__(self):
			return self

		def __exit__(self, *exc):
			return False

		def send_message(self, message):
			outbox.append(message)

	monkeypatch.setattr(mailer.smtplib, "SMTP", Recorder)
	return outbox


def _link_token(message) -> str:
	import re
	from urllib.parse import parse_qs, urlparse

	html = message.get_body(("html",)).get_content()
	href = re.search(r'<a href="([^"]+)"', html).group(1).replace("&amp;", "&")
	assert href.startswith("https://api.test.invalid/reset-password?")
	return parse_qs(urlparse(href).query)["token"][0]


def test_the_emailed_link_resets_the_password_end_to_end(api, smtp_outbox):
	parent = api.register_parent()
	assert api.post("/auth/password/forgot", json={"email": parent["email"]}).status_code == 202
	assert len(smtp_outbox) == 1 and smtp_outbox[0]["To"] == parent["email"]
	token = _link_token(smtp_outbox[0])

	assert api.post("/auth/password/reset", json={"token": token, "password": NEW_PASSWORD}).status_code == 204
	assert api.post("/auth/login", json={"email": parent["email"], "password": PASSWORD}).status_code == 401
	assert api.post("/auth/login", json={"email": parent["email"], "password": NEW_PASSWORD}).status_code == 200
	again = api.post("/auth/password/reset", json={"token": token, "password": "another-long-password-1"})
	assert again.status_code == 400 and again.json()["error"]["code"] == "invalid_reset_token"


def test_unconfigured_email_is_refused_the_same_way_for_every_address(api, monkeypatch):
	sent = []
	monkeypatch.setattr("app.integrations.email.send_password_reset", lambda email, token: sent.append(token))
	monkeypatch.setattr(settings, "password_reset_url", None)
	parent = api.register_parent()
	known = api.post("/auth/password/forgot", json={"email": parent["email"]})
	unknown = api.post("/auth/password/forgot", json={"email": f"nobody-{uuid4().hex}@example.com"})
	assert known.status_code == unknown.status_code == 503
	assert known.json()["error"]["code"] == unknown.json()["error"]["code"] == "password_reset_unavailable"
	assert sent == []
	ResetToken = get_model("PasswordResetToken")
	assert api.session.query(ResetToken).count() == 0  # no unusable token is created


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


def test_reset_token_expiry_and_request_rate_limit(api, mailbox, isolated_test_session, monkeypatch):
	monkeypatch.setattr(settings, "password_reset_rate_limit", 4)
	parent = api.register_parent()
	assert api.post("/auth/password/forgot", json={"email": parent["email"]}).status_code == 202
	ResetToken = get_model("PasswordResetToken")
	row = isolated_test_session.query(ResetToken).one()
	row.expires_at = datetime.now(timezone.utc) - timedelta(seconds=1)
	isolated_test_session.commit()
	expired = api.post("/auth/password/reset", json={"token": mailbox[0][1], "password": NEW_PASSWORD})
	assert expired.status_code == 400
	assert expired.json()["error"]["code"] == "invalid_reset_token"

	for _ in range(3):
		assert api.post("/auth/password/forgot", json={"email": f"unknown-{uuid4().hex}@example.com"}).status_code == 202
	limited = api.post("/auth/password/forgot", json={"email": f"unknown-{uuid4().hex}@example.com"})
	assert limited.status_code == 429
