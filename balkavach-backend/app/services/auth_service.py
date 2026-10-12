from datetime import datetime, timezone

from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from app.core.exceptions import APIError
from app.core.security import create_access_token, hash_password, verify_password
from app.db.base import get_model
from app.schemas.auth import LoginRequest, RegistrationRequest, TokenResponse, UserPublic


def register_parent(session: Session, request: RegistrationRequest) -> TokenResponse:
	User = get_model("User")
	email = str(request.email).strip().lower()
	if session.query(User.id).filter(User.email == email).first():
		raise APIError(409, "email_in_use", "An account with this email already exists")

	user = User(
		full_name=request.full_name.strip(),
		email=email,
		password_hash=hash_password(request.password),
		role="parent",
		preferred_language="en",
		is_active=True,
	)
	session.add(user)
	try:
		session.flush()
		token, expires_at = create_access_token(str(user.id))
		session.commit()
	except IntegrityError as error:
		session.rollback()
		raise APIError(409, "account_conflict", "An account with these details already exists") from error
	return TokenResponse(access_token=token, expires_at=expires_at, user=UserPublic.model_validate(user))


def authenticate_user(session: Session, request: LoginRequest) -> TokenResponse:
	User = get_model("User")
	email = str(request.email).strip().lower()
	user = session.query(User).filter(User.email == email, User.is_active.is_(True)).one_or_none()
	if user is None or not user.password_hash or not verify_password(request.password, user.password_hash):
		raise APIError(401, "invalid_credentials", "Email or password is incorrect")

	token, expires_at = create_access_token(str(user.id))
	user.last_login_at = datetime.now(timezone.utc).replace(tzinfo=None)
	session.commit()
	return TokenResponse(access_token=token, expires_at=expires_at, user=UserPublic.model_validate(user))
