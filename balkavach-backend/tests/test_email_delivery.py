"""Outgoing email: password reset and parent verification (no database).

SMTP is replaced by a recorder at the ``smtplib`` level, so the real message building and transport
choice (SSL, STARTTLS or plain) are exercised; nothing is sent.
"""

import ast
import inspect
from html.parser import HTMLParser
from urllib.parse import parse_qs, urlparse

import pytest

from app.core.config import settings
from app.integrations import email as mailer

TOKEN = "Tok_abc-123_XYZ"


class _Links(HTMLParser):
	def __init__(self):
		super().__init__()
		self.hrefs: list[str] = []

	def handle_starttag(self, tag, attrs):
		if tag == "a":
			self.hrefs.append(dict(attrs).get("href"))


@pytest.fixture
def smtp(monkeypatch):
	"""Records how a message would be sent, for both SMTP classes."""
	calls: list[dict] = []

	def factory(kind):
		class Recorder:
			def __init__(self, host, port, **kwargs):
				self.call = {"kind": kind, "host": host, "port": port, "starttls": False, "login": None, "messages": []}
				calls.append(self.call)

			def __enter__(self):
				return self

			def __exit__(self, *exc):
				return False

			def starttls(self, **kwargs):
				self.call["starttls"] = True

			def login(self, user, password):
				self.call["login"] = user

			def send_message(self, message):
				self.call["messages"].append(message)

		return Recorder

	monkeypatch.setattr(mailer.smtplib, "SMTP", factory("SMTP"))
	monkeypatch.setattr(mailer.smtplib, "SMTP_SSL", factory("SMTP_SSL"))
	return calls


@pytest.fixture
def configured(monkeypatch):
	monkeypatch.setattr(settings, "smtp_host", "smtp.test.invalid")
	monkeypatch.setattr(settings, "smtp_port", 465)
	monkeypatch.setattr(settings, "smtp_use_ssl", True)
	monkeypatch.setattr(settings, "smtp_use_tls", False)
	monkeypatch.setattr(settings, "smtp_username", "mailer")
	monkeypatch.setattr(settings, "password_reset_from_email", "noreply@test.invalid")
	monkeypatch.setattr(settings, "password_reset_url", "https://api.test.invalid/reset-password")


def _reset_message(smtp_calls):
	mailer.send_password_reset("parent@example.com", TOKEN)
	assert len(smtp_calls) == 1 and len(smtp_calls[0]["messages"]) == 1
	return smtp_calls[0]["messages"][0]


def _token_of(url: str) -> str:
	return parse_qs(urlparse(url).query)["token"][0]


def test_only_one_password_reset_sender_exists():
	tree = ast.parse(inspect.getsource(mailer))
	names = [node.name for node in tree.body if isinstance(node, ast.FunctionDef)]
	assert names.count("send_password_reset") == 1
	assert names.count("send_parent_verification") == 1


def test_reset_email_uses_ssl_when_configured(configured, smtp):
	_reset_message(smtp)
	assert smtp[0]["kind"] == "SMTP_SSL" and smtp[0]["port"] == 465
	assert smtp[0]["login"] == "mailer"


@pytest.mark.parametrize(("use_tls", "starttls"), [(True, True), (False, False)])
def test_reset_email_uses_plain_smtp_with_or_without_starttls(configured, smtp, monkeypatch, use_tls, starttls):
	monkeypatch.setattr(settings, "smtp_use_ssl", False)
	monkeypatch.setattr(settings, "smtp_use_tls", use_tls)
	monkeypatch.setattr(settings, "smtp_port", 587)
	_reset_message(smtp)
	assert smtp[0]["kind"] == "SMTP" and smtp[0]["starttls"] is starttls


def test_reset_email_links_are_well_formed_in_html_and_text(configured, smtp):
	message = _reset_message(smtp)
	assert message["To"] == "parent@example.com"
	assert message["From"] == "noreply@test.invalid"
	html = message.get_body(("html",)).get_content()
	text = message.get_body(("plain",)).get_content()

	parser = _Links()
	parser.feed(html)
	assert parser.hrefs == [f"https://api.test.invalid/reset-password?token={TOKEN}"]
	assert f"https://api.test.invalid/reset-password?token={TOKEN}" in text
	assert _token_of(parser.hrefs[0]) == TOKEN


@pytest.mark.parametrize(
	("configured_url", "expected_prefix"),
	[
		("https://api.test.invalid/reset-password/", "https://api.test.invalid/reset-password?"),
		("https://api.test.invalid/reset-password?lang=hi", "https://api.test.invalid/reset-password?lang=hi&"),
		("balkavach://app/reset-password", "balkavach://app/reset-password?"),
	],
)
def test_reset_link_respects_the_configured_url(configured, smtp, monkeypatch, configured_url, expected_prefix):
	monkeypatch.setattr(settings, "password_reset_url", configured_url)
	message = _reset_message(smtp)
	parser = _Links()
	parser.feed(message.get_body(("html",)).get_content())
	assert parser.hrefs[0].startswith(expected_prefix)
	assert _token_of(parser.hrefs[0]) == TOKEN


def test_tokens_that_need_escaping_survive_the_round_trip(configured, smtp):
	mailer.send_password_reset("parent@example.com", "a+b/c=d&e")
	parser = _Links()
	parser.feed(smtp[0]["messages"][0].get_body(("html",)).get_content())
	assert _token_of(parser.hrefs[0]) == "a+b/c=d&e"


@pytest.mark.parametrize("missing", ["smtp_host", "password_reset_from_email", "password_reset_url"])
def test_reset_email_is_not_reported_as_configured_when_a_setting_is_missing(configured, smtp, monkeypatch, missing):
	assert mailer.password_reset_configured() is True
	monkeypatch.setattr(settings, missing, None)
	assert mailer.password_reset_configured() is False
	with pytest.raises(RuntimeError):
		mailer.send_password_reset("parent@example.com", TOKEN)
	assert smtp == []


def test_verification_email_is_unchanged_and_uses_the_same_transport(configured, smtp):
	mailer.send_parent_verification("parent@example.com", "123456")
	assert smtp[0]["kind"] == "SMTP_SSL"
	message = smtp[0]["messages"][0]
	assert message["Subject"] == "Verify your BalKavach parent account"
	assert "123456" in message.get_body(("plain",)).get_content()
	assert "123456" in message.get_body(("html",)).get_content()


def test_verification_email_does_not_need_a_reset_url(configured, smtp, monkeypatch):
	monkeypatch.setattr(settings, "password_reset_url", None)
	mailer.send_parent_verification("parent@example.com", "654321")
	assert len(smtp[0]["messages"]) == 1
