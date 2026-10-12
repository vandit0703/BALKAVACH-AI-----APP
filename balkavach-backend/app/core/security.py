from datetime import datetime, timedelta, timezone
from typing import Any

import jwt
from fastapi import HTTPException
from jwt import InvalidTokenError
from pwdlib import PasswordHash

from app.core.config import settings

password_hash = PasswordHash.recommended()


def hash_password(password: str) -> str:
	return password_hash.hash(password)


def verify_password(password: str, encoded_hash: str) -> bool:
	return password_hash.verify(password, encoded_hash)


def _jwt_secret() -> str:
	secret = settings.jwt_secret_key
	if not secret or len(secret.encode("utf-8")) < 32:
		raise HTTPException(status_code=503, detail="Authentication is not configured")
	return secret


def create_access_token(subject: str) -> tuple[str, datetime]:
	expires_at = (datetime.now(timezone.utc) + timedelta(minutes=settings.access_token_expire_minutes)).replace(
		microsecond=0
	)
	token = jwt.encode(
		{"sub": subject, "iat": datetime.now(timezone.utc), "exp": expires_at},
		_jwt_secret(),
		algorithm=settings.jwt_algorithm,
	)
	return token, expires_at


def decode_access_token(token: str) -> dict[str, Any]:
	try:
		payload = jwt.decode(
			token,
			_jwt_secret(),
			algorithms=[settings.jwt_algorithm],
			options={"require": ["sub", "exp"]},
		)
	except InvalidTokenError as error:
		raise HTTPException(status_code=401, detail="Invalid or expired access token") from error
	return payload
