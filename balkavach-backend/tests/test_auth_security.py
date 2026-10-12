import jwt

from app.core.config import settings
from app.core.security import create_access_token, decode_access_token, hash_password, verify_password


def test_passwords_are_hashed_and_verified() -> None:
    encoded = hash_password("a-long-test-password")

    assert encoded != "a-long-test-password"
    assert verify_password("a-long-test-password", encoded)
    assert not verify_password("a-different-password", encoded)


def test_access_tokens_are_signed_and_expiring(monkeypatch) -> None:
    monkeypatch.setattr(settings, "jwt_secret_key", "test-secret-that-is-at-least-32-bytes-long")

    token, expires_at = create_access_token("user-id")
    payload = decode_access_token(token)

    assert payload["sub"] == "user-id"
    assert expires_at.timestamp() == payload["exp"]


def test_access_tokens_reject_tampering(monkeypatch) -> None:
    monkeypatch.setattr(settings, "jwt_secret_key", "test-secret-that-is-at-least-32-bytes-long")
    token, _ = create_access_token("user-id")
    parts = token.split(".")
    tampered = ".".join([parts[0], parts[1], jwt.utils.base64url_encode(b"wrong-signature").decode()])

    try:
        decode_access_token(tampered)
    except Exception as error:
        assert getattr(error, "status_code", None) == 401
    else:
        raise AssertionError("Tampered token was accepted")