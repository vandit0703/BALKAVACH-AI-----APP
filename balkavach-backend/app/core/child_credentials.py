import re

from cryptography.fernet import Fernet, InvalidToken

from app.core.config import settings
from app.core.exceptions import APIError


def normalize_username(value: str) -> str:
	username = value.strip().lower()
	if not re.fullmatch(r"[a-z][a-z0-9._-]{2,31}", username):
		raise ValueError("Invalid child username")
	return username


def _cipher() -> Fernet:
	key = settings.child_credentials_encryption_key
	if not key:
		raise APIError(
			503,
			"credential_encryption_unavailable",
			"CHILD_CREDENTIALS_ENCRYPTION_KEY is not configured",
		)
	try:
		return Fernet(key.encode("ascii"))
	except (ValueError, UnicodeEncodeError):
		raise APIError(
			503,
			"credential_encryption_unavailable",
			"CHILD_CREDENTIALS_ENCRYPTION_KEY is invalid",
		) from None


def encrypt_child_password(password: str) -> str:
	return _cipher().encrypt(password.encode("utf-8")).decode("ascii")


def decrypt_child_password(ciphertext: str) -> str:
	try:
		return _cipher().decrypt(ciphertext.encode("ascii")).decode("utf-8")
	except (InvalidToken, UnicodeError):
		raise APIError(500, "credential_decryption_failed", "Saved child credentials are unavailable") from None