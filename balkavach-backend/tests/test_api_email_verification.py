from datetime import datetime, timedelta, timezone

from app.db.base import get_model
from tests.harness import PASSWORD


def _register(api, email="parent-otp@example.com"):
	response = api.post(
		"/auth/register",
		json={"full_name": "OTP Parent", "email": email, "password": PASSWORD},
	)
	assert response.status_code == 202, response.text
	return email, api.verification_mailbox[-1][1]


def test_registration_sends_hashed_otp_and_blocks_login_until_verified(api, isolated_test_session):
	email, otp = _register(api)
	assert len(otp) == 6 and otp.isdigit()
	assert api.post("/auth/login", json={"email": email, "password": PASSWORD}).status_code == 403

	User = get_model("User")
	Verification = get_model("ParentEmailVerification")
	user = isolated_test_session.query(User).filter(User.email == email).one()
	verification = isolated_test_session.query(Verification).filter(Verification.user_id == user.id).one()
	assert user.email_verified_at is None
	assert verification.otp_hash != otp
	assert api.post("/auth/verify-email", json={"email": email, "otp": otp}).status_code == 204
	assert api.post("/auth/login", json={"email": email, "password": PASSWORD}).status_code == 200


def test_wrong_otp_is_limited_and_expired_otp_is_rejected(api, isolated_test_session):
	email, otp = _register(api, "wrong-otp@example.com")
	wrong_otp = f"{(int(otp) + 1) % 1_000_000:06d}"
	for attempt in range(5):
		response = api.post("/auth/verify-email", json={"email": email, "otp": wrong_otp})
		assert response.status_code == (429 if attempt == 4 else 400)
	blocked = api.post("/auth/verify-email", json={"email": email, "otp": otp})
	assert blocked.status_code == 429

	email, _ = _register(api, "expired-otp@example.com")
	User = get_model("User")
	Verification = get_model("ParentEmailVerification")
	user = isolated_test_session.query(User).filter(User.email == email).one()
	row = isolated_test_session.query(Verification).filter(Verification.user_id == user.id).one()
	row.expires_at = datetime.now(timezone.utc) - timedelta(seconds=1)
	isolated_test_session.commit()
	expired = api.post("/auth/verify-email", json={"email": email, "otp": api.verification_mailbox[-1][1]})
	assert expired.status_code == 400
	assert expired.json()["error"]["code"] == "expired_verification_code"


def test_resend_invalidates_previous_code_and_is_rate_limited(api, isolated_test_session):
	email, old_otp = _register(api, "resend-otp@example.com")
	Verification = get_model("ParentEmailVerification")
	User = get_model("User")
	user = isolated_test_session.query(User).filter(User.email == email).one()
	row = isolated_test_session.query(Verification).filter(Verification.user_id == user.id).one()
	row.last_sent_at = datetime.now(timezone.utc) - timedelta(seconds=61)
	isolated_test_session.commit()

	assert api.post("/auth/resend-verification", json={"email": email}).status_code == 202
	new_otp = api.verification_mailbox[-1][1]
	assert new_otp != old_otp
	assert api.post("/auth/resend-verification", json={"email": email}).status_code == 429
	assert api.post("/auth/verify-email", json={"email": email, "otp": old_otp}).status_code == 400
	assert api.post("/auth/verify-email", json={"email": email, "otp": new_otp}).status_code == 204