"""Phase 3: one-time codes that start real sessions.

Registration: the correct registration code verifies the email and returns a genuine session.
Passwordless sign-in: an existing, verified parent can sign in with an emailed code.

Every test checks the server side (``auth_sessions`` rows), not only the HTTP status: a failure must
create no session at all. Concurrency is covered on real PostgreSQL in ``test_otp_concurrency_postgres``.
"""

import logging
from datetime import datetime, timedelta, timezone
from uuid import uuid4

import pytest

from app.core.config import settings
from app.core.security import hash_password
from app.db.base import get_model
from app.services import login_code_service
from tests.harness import PASSWORD


# -- helpers -------------------------------------------------------------------------------------------


def _sessions_of(api, email: str) -> int:
	User, AuthSession = get_model("User"), get_model("AuthSession")
	user = api.session.query(User).filter(User.email == email).one()
	return api.session.query(AuthSession).filter(AuthSession.user_id == user.id).count()


def _register(api, email: str | None = None) -> tuple[str, str]:
	email = email or f"otp-{uuid4().hex}@example.com"
	response = api.post("/auth/register", json={"full_name": "OTP Parent", "email": email, "password": PASSWORD})
	assert response.status_code == 202, response.text
	return email, api.verification_mailbox[-1][1]


def _verified_parent(api) -> str:
	email, code = _register(api)
	assert api.post("/auth/verify-email", json={"email": email, "otp": code}).status_code == 200
	return email


def _other(code: str) -> str:
	return f"{(int(code) + 1) % 1_000_000:06d}"


def _request_login_code(api, email: str) -> str | None:
	before = len(api.login_code_mailbox)
	response = api.post("/auth/login-code/request", json={"email": email})
	assert response.status_code == 202, response.text
	return api.login_code_mailbox[-1][1] if len(api.login_code_mailbox) > before else None


def _challenge(api, email: str):
	User, Challenge = get_model("User"), get_model("AuthOtpChallenge")
	user = api.session.query(User).filter(User.email == email).one()
	return (
		api.session.query(Challenge)
		.filter(Challenge.user_id == user.id, Challenge.purpose == "login")
		.order_by(Challenge.created_at.desc())
		.first()
	)


def _assert_usable_session(api, body: dict, email: str) -> None:
	"""The tokens are genuine: they reach a protected API and the refresh token rotates."""
	assert body["token_type"] == "bearer" and body["access_token"] and body["refresh_token"]
	assert body["user"]["email"] == email and body["user"]["role"] == "parent"
	me = api.get("/auth/me", body["access_token"])
	assert me.status_code == 200 and me.json()["email"] == email
	assert api.get("/families", body["access_token"]).status_code == 200  # a parent-only protected API
	rotated = api.post("/auth/refresh", json={"refresh_token": body["refresh_token"]})
	assert rotated.status_code == 200, rotated.text
	assert rotated.json()["refresh_token"] != body["refresh_token"]
	assert api.get("/auth/me", rotated.json()["access_token"]).status_code == 200


def _invalid_login(response) -> None:
	assert response.status_code == 400, response.text
	assert response.json()["error"]["code"] == "invalid_login_code"


# -- A. registration verification establishes a session ---------------------------------------------


def test_1_correct_registration_code_starts_a_real_session(api):
	email, code = _register(api)
	assert _sessions_of(api, email) == 0
	response = api.post("/auth/verify-email", json={"email": email, "otp": code})
	assert response.status_code == 200, response.text
	assert _sessions_of(api, email) == 1
	_assert_usable_session(api, response.json(), email)
	User = get_model("User")
	assert api.session.query(User).filter(User.email == email).one().email_verified_at is not None


def test_2_wrong_registration_code_starts_no_session(api):
	email, code = _register(api)
	response = api.post("/auth/verify-email", json={"email": email, "otp": _other(code)})
	assert response.status_code == 400 and "access_token" not in response.text
	assert _sessions_of(api, email) == 0
	User = get_model("User")
	assert api.session.query(User).filter(User.email == email).one().email_verified_at is None


def test_3_expired_registration_code_starts_no_session(api):
	email, code = _register(api)
	User, Verification = get_model("User"), get_model("ParentEmailVerification")
	user = api.session.query(User).filter(User.email == email).one()
	row = api.session.query(Verification).filter(Verification.user_id == user.id).one()
	row.expires_at = datetime.now(timezone.utc) - timedelta(seconds=1)
	api.session.commit()
	response = api.post("/auth/verify-email", json={"email": email, "otp": code})
	assert response.status_code == 400 and response.json()["error"]["code"] == "expired_verification_code"
	assert _sessions_of(api, email) == 0


def test_4_reused_registration_code_starts_no_second_session(api):
	email, code = _register(api)
	assert api.post("/auth/verify-email", json={"email": email, "otp": code}).status_code == 200
	again = api.post("/auth/verify-email", json={"email": email, "otp": code})
	assert again.status_code == 400 and again.json()["error"]["code"] == "invalid_verification_code"
	assert _sessions_of(api, email) == 1


def test_5_already_verified_account_with_any_code_gets_no_session(api):
	"""The previous implementation returned success here without looking at the code."""
	email = _verified_parent(api)
	before = _sessions_of(api, email)
	for code in ("000000", "123456", "999999"):
		response = api.post("/auth/verify-email", json={"email": email, "otp": code})
		assert response.status_code == 400, response.text
		assert response.json()["error"]["code"] == "invalid_verification_code"
	assert _sessions_of(api, email) == before


def test_already_verified_answer_matches_unknown_address(api):
	email = _verified_parent(api)
	verified = api.post("/auth/verify-email", json={"email": email, "otp": "123456"})
	unknown = api.post("/auth/verify-email", json={"email": f"nobody-{uuid4().hex}@example.com", "otp": "123456"})
	assert verified.status_code == unknown.status_code == 400
	assert verified.json()["error"] == unknown.json()["error"]


# -- B. passwordless sign-in for existing accounts ---------------------------------------------------


def test_6_correct_login_code_starts_a_real_session(api):
	email = _verified_parent(api)
	before = _sessions_of(api, email)
	code = _request_login_code(api, email)
	assert code is not None and len(code) == 6 and code.isdigit()
	assert _challenge(api, email).otp_hash != code  # stored hashed
	response = api.post("/auth/login-code/verify", json={"email": email, "otp": code})
	assert response.status_code == 200, response.text
	assert _sessions_of(api, email) == before + 1
	_assert_usable_session(api, response.json(), email)
	assert _challenge(api, email).consumed_at is not None


def test_7_wrong_login_code_starts_no_session_and_five_wrong_burn_the_code(api):
	email = _verified_parent(api)
	before = _sessions_of(api, email)
	code = _request_login_code(api, email)
	for _ in range(login_code_service.MAX_ATTEMPTS):
		_invalid_login(api.post("/auth/login-code/verify", json={"email": email, "otp": _other(code)}))
	# The real code no longer works either: it was burned by the wrong guesses.
	_invalid_login(api.post("/auth/login-code/verify", json={"email": email, "otp": code}))
	assert _sessions_of(api, email) == before


def test_8_expired_login_code_starts_no_session(api):
	email = _verified_parent(api)
	before = _sessions_of(api, email)
	code = _request_login_code(api, email)
	row = _challenge(api, email)
	row.expires_at = datetime.now(timezone.utc) - timedelta(seconds=1)
	api.session.commit()
	_invalid_login(api.post("/auth/login-code/verify", json={"email": email, "otp": code}))
	assert _sessions_of(api, email) == before


def test_9_reused_login_code_starts_no_second_session(api):
	email = _verified_parent(api)
	before = _sessions_of(api, email)
	code = _request_login_code(api, email)
	assert api.post("/auth/login-code/verify", json={"email": email, "otp": code}).status_code == 200
	_invalid_login(api.post("/auth/login-code/verify", json={"email": email, "otp": code}))
	assert _sessions_of(api, email) == before + 1


def test_10_one_accounts_code_cannot_sign_in_another(api):
	alice, bob = _verified_parent(api), _verified_parent(api)
	_request_login_code(api, alice)
	_request_login_code(api, bob)
	# Known, different codes for each account.
	_challenge(api, alice).otp_hash = hash_password("111111")
	_challenge(api, bob).otp_hash = hash_password("222222")
	api.session.commit()
	before = _sessions_of(api, bob)
	_invalid_login(api.post("/auth/login-code/verify", json={"email": bob, "otp": "111111"}))
	assert _sessions_of(api, bob) == before
	response = api.post("/auth/login-code/verify", json={"email": alice, "otp": "111111"})
	assert response.status_code == 200 and response.json()["user"]["email"] == alice


def test_12_new_code_replaces_the_old_one_and_resend_has_a_cooldown(api):
	email = _verified_parent(api)
	old = _request_login_code(api, email)
	assert _request_login_code(api, email) is None  # inside the cooldown: same 202, nothing sent
	row = _challenge(api, email)
	row.last_sent_at = datetime.now(timezone.utc) - timedelta(seconds=login_code_service.RESEND_COOLDOWN_SECONDS + 1)
	api.session.commit()
	new = _request_login_code(api, email)
	assert new is not None
	Challenge = get_model("AuthOtpChallenge")
	live = api.session.query(Challenge).filter(Challenge.user_id == row.user_id, Challenge.consumed_at.is_(None))
	assert live.count() == 1  # one live code per account
	if new != old:
		_invalid_login(api.post("/auth/login-code/verify", json={"email": email, "otp": old}))
	assert api.post("/auth/login-code/verify", json={"email": email, "otp": new}).status_code == 200


def test_resend_after_sign_in_issues_a_fresh_code(api):
	email = _verified_parent(api)
	code = _request_login_code(api, email)
	assert api.post("/auth/login-code/verify", json={"email": email, "otp": code}).status_code == 200
	fresh = _request_login_code(api, email)  # the used code does not hold a cooldown
	assert fresh is not None
	assert api.post("/auth/login-code/verify", json={"email": email, "otp": fresh}).status_code == 200


# -- 13. rate limits ---------------------------------------------------------------------------------


def test_13_login_code_requests_are_rate_limited_per_address(api, monkeypatch):
	monkeypatch.setattr(settings, "login_code_request_rate_limit", 2)
	email = _verified_parent(api)
	for _ in range(2):
		assert api.post("/auth/login-code/request", json={"email": email}).status_code == 202
	assert api.post("/auth/login-code/request", json={"email": email}).status_code == 429
	# Unknown addresses hit the same limit the same way (no enumeration through 429).
	unknown = f"nobody-{uuid4().hex}@example.com"
	for _ in range(2):
		assert api.post("/auth/login-code/request", json={"email": unknown}).status_code == 202
	assert api.post("/auth/login-code/request", json={"email": unknown}).status_code == 429


def test_13_login_code_requests_are_rate_limited_per_client(api, monkeypatch):
	monkeypatch.setattr(settings, "login_code_request_ip_rate_limit", 3)
	for _ in range(3):
		email = f"nobody-{uuid4().hex}@example.com"
		assert api.post("/auth/login-code/request", json={"email": email}).status_code == 202
	assert api.post("/auth/login-code/request", json={"email": f"x-{uuid4().hex}@example.com"}).status_code == 429


def test_13_login_code_guesses_are_rate_limited(api, monkeypatch):
	monkeypatch.setattr(settings, "otp_verify_rate_limit", 3)
	email = _verified_parent(api)
	code = _request_login_code(api, email)
	for _ in range(3):
		_invalid_login(api.post("/auth/login-code/verify", json={"email": email, "otp": _other(code)}))
	blocked = api.post("/auth/login-code/verify", json={"email": email, "otp": code})
	assert blocked.status_code == 429


def test_13_registration_code_guesses_are_rate_limited(api, monkeypatch):
	monkeypatch.setattr(settings, "otp_verify_rate_limit", 3)
	email, code = _register(api)
	for _ in range(3):
		assert api.post("/auth/verify-email", json={"email": email, "otp": _other(code)}).status_code == 400
	assert api.post("/auth/verify-email", json={"email": email, "otp": code}).status_code == 429
	assert _sessions_of(api, email) == 0


def test_13_code_guesses_are_rate_limited_per_client_across_addresses(api, monkeypatch):
	monkeypatch.setattr(settings, "otp_verify_ip_rate_limit", 3)
	for _ in range(3):
		_invalid_login(
			api.post("/auth/login-code/verify", json={"email": f"n-{uuid4().hex}@example.com", "otp": "123456"})
		)
	assert (
		api.post("/auth/login-code/verify", json={"email": f"n-{uuid4().hex}@example.com", "otp": "123456"}).status_code
		== 429
	)


# -- 16-18. password login, unverified accounts, enumeration ----------------------------------------


def test_16_password_login_still_works_alongside_codes(api):
	email = _verified_parent(api)
	code = _request_login_code(api, email)
	assert api.post("/auth/login-code/verify", json={"email": email, "otp": code}).status_code == 200
	login = api.post("/auth/login", json={"email": email, "password": PASSWORD})
	assert login.status_code == 200 and login.json()["refresh_token"]
	assert api.post("/auth/login", json={"email": email, "password": "wrong-password-123"}).status_code == 401


def test_17_unverified_account_cannot_use_sign_in_codes(api):
	email, registration_code = _register(api)
	assert _request_login_code(api, email) is None  # same 202, nothing sent, no challenge
	assert _challenge(api, email) is None
	# Neither its registration code nor any other code signs it in through the sign-in endpoint.
	_invalid_login(api.post("/auth/login-code/verify", json={"email": email, "otp": registration_code}))
	assert api.post("/auth/login", json={"email": email, "password": PASSWORD}).status_code == 403
	assert _sessions_of(api, email) == 0


def test_codes_are_bound_to_their_purpose(api):
	"""A sign-in code is not a registration code, and the reverse."""
	email = _verified_parent(api)
	code = _request_login_code(api, email)
	before = _sessions_of(api, email)
	response = api.post("/auth/verify-email", json={"email": email, "otp": code})
	assert response.status_code == 400
	assert _sessions_of(api, email) == before
	assert _challenge(api, email).consumed_at is None  # still usable for sign-in
	assert api.post("/auth/login-code/verify", json={"email": email, "otp": code}).status_code == 200


def test_child_and_inactive_accounts_cannot_use_sign_in_codes(api, isolated_test_session):
	User = get_model("User")
	child = User(
		full_name="Child",
		email=f"child-{uuid4().hex}@example.com",
		password_hash=hash_password(PASSWORD),
		role="child",
		preferred_language="en",
		is_active=True,
		email_verified_at=datetime.now(timezone.utc),
	)
	isolated_test_session.add(child)
	isolated_test_session.commit()
	assert _request_login_code(api, child.email) is None

	email = _verified_parent(api)
	parent = isolated_test_session.query(User).filter(User.email == email).one()
	parent.is_active = False
	isolated_test_session.commit()
	assert _request_login_code(api, email) is None


def test_18_unknown_address_is_answered_like_a_real_one(api):
	email = _verified_parent(api)
	unknown = f"nobody-{uuid4().hex}@example.com"
	real = api.post("/auth/login-code/request", json={"email": email})
	fake = api.post("/auth/login-code/request", json={"email": unknown})
	assert real.status_code == fake.status_code == 202
	assert real.content == fake.content
	wrong_real = api.post("/auth/login-code/verify", json={"email": email, "otp": "000000"})
	wrong_fake = api.post("/auth/login-code/verify", json={"email": unknown, "otp": "000000"})
	assert wrong_real.status_code == wrong_fake.status_code == 400
	assert wrong_real.json()["error"] == wrong_fake.json()["error"]


# -- 19. email delivery ------------------------------------------------------------------------------


@pytest.mark.parametrize("missing", ["smtp_host", "password_reset_from_email"])
def test_19_unconfigured_email_refuses_every_code_request_the_same_way(api, monkeypatch, missing):
	email = _verified_parent(api)
	pending, _ = _register(api)
	monkeypatch.setattr(settings, missing, None)
	unknown = f"nobody-{uuid4().hex}@example.com"
	sent = len(api.login_code_mailbox), len(api.verification_mailbox)
	answers = [
		api.post("/auth/login-code/request", json={"email": email}),
		api.post("/auth/login-code/request", json={"email": unknown}),
		api.post("/auth/register", json={"full_name": "New Parent", "email": unknown, "password": PASSWORD}),
	]
	for response in answers:
		assert response.status_code == 503, response.text
		assert response.json()["error"]["code"] == "email_unavailable"
	assert _challenge(api, email) is None
	User = get_model("User")
	assert api.session.query(User).filter(User.email == unknown).count() == 0  # no undeliverable account
	assert (len(api.login_code_mailbox), len(api.verification_mailbox)) == sent
	# Resend is refused the same way (its own rate limit allows one call per minute).
	resend = api.post("/auth/resend-verification", json={"email": pending})
	assert resend.status_code == 503 and resend.json()["error"]["code"] == "email_unavailable"


def test_19_smtp_failure_is_logged_without_the_code(monkeypatch, caplog):
	from app.api.v1 import auth as auth_api
	from app.integrations import email as mailer

	def broken(*args, **kwargs):
		raise OSError("connection refused")

	monkeypatch.setattr(mailer, "send_login_code", broken)
	with caplog.at_level(logging.ERROR):
		auth_api._deliver_login_code("parent@example.com", "424242")  # must not raise
	assert "Sign-in code email delivery failed" in caplog.text
	assert "424242" not in caplog.text


def test_sign_in_codes_report_unavailable_before_the_migration(api, monkeypatch):
	monkeypatch.setattr(login_code_service, "available", lambda: False)
	email = _verified_parent(api)
	for path, body in (
		("/auth/login-code/request", {"email": email}),
		("/auth/login-code/verify", {"email": email, "otp": "123456"}),
	):
		response = api.post(path, json=body)
		assert response.status_code == 503 and response.json()["error"]["code"] == "login_code_unavailable"


def test_codes_never_reach_the_logs(api, caplog):
	with caplog.at_level(logging.DEBUG):
		email, registration_code = _register(api)
		api.post("/auth/verify-email", json={"email": email, "otp": registration_code})
		code = _request_login_code(api, email)
		response = api.post("/auth/login-code/verify", json={"email": email, "otp": code})
	assert response.status_code == 200
	for secret in (registration_code, code, response.json()["access_token"], response.json()["refresh_token"]):
		assert secret not in caplog.text


# -- cleanup -----------------------------------------------------------------------------------------


def test_purge_removes_only_stale_challenges(api):
	email = _verified_parent(api)
	_request_login_code(api, email)
	live = _challenge(api, email)
	now = datetime.now(timezone.utc)
	assert login_code_service.purge_stale_challenges(api.session, now=now) == 0
	assert login_code_service.purge_stale_challenges(api.session, now=now + timedelta(days=2)) == 1
	api.session.commit()
	Challenge = get_model("AuthOtpChallenge")
	assert api.session.query(Challenge).filter(Challenge.id == live.id).count() == 0
