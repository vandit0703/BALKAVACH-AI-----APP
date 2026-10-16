import jwt
from cryptography.fernet import Fernet

from app.core.config import settings
from app.core.child_credentials import decrypt_child_password, encrypt_child_password
from app.core.security import create_access_token, decode_access_token, hash_password, verify_password
from app.schemas.user import ChildCreate


def test_passwords_are_hashed_and_verified() -> None:
    encoded = hash_password("a-long-test-password")

    assert encoded != "a-long-test-password"
    assert verify_password("a-long-test-password", encoded)
    assert not verify_password("a-different-password", encoded)


def test_child_password_encryption_is_authenticated_and_round_trips(monkeypatch) -> None:
    monkeypatch.setattr(settings, "child_credentials_encryption_key", Fernet.generate_key().decode())

    encrypted = encrypt_child_password("a-secure-child-password")

    assert encrypted != "a-secure-child-password"
    assert decrypt_child_password(encrypted) == "a-secure-child-password"


def test_child_creation_normalizes_username_and_rejects_invalid_credentials() -> None:
    request = ChildCreate(
        display_name="Kid",
        username="  Aarav_7 ",
        password="a-secure-child-password",
    )
    assert request.username == "aarav_7"

    for values in (
        {"display_name": "Kid", "username": "bad user", "password": "a-secure-child-password"},
        {"display_name": "Kid", "username": "kid123", "password": "short"},
    ):
        try:
            ChildCreate(**values)
        except Exception:
            pass
        else:
            raise AssertionError("Invalid child credentials were accepted")


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