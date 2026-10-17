from datetime import datetime, timezone

from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from app.core.exceptions import APIError
from app.core.security import hash_password, verify_password
from app.db.base import get_model
from app.schemas.auth import LoginRequest, RegistrationRequest, TokenResponse
from app.services.session_service import start_session


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
		response = start_session(session, user)
		session.commit()
	except IntegrityError as error:
		session.rollback()
		raise APIError(409, "account_conflict", "An account with these details already exists") from error
	return response


def authenticate_user(session: Session, request: LoginRequest) -> TokenResponse:
	User = get_model("User")
	child_profile = None
	if request.username is not None:
		ChildProfile = get_model("ChildProfile")
		FamilyMember = get_model("FamilyMember")
		user = (
			session.query(User)
			.join(ChildProfile, ChildProfile.user_id == User.id)
			.join(FamilyMember, FamilyMember.user_id == User.id)
			.filter(
				User.username == request.username,
				User.role == "child",
				User.is_active.is_(True),
				ChildProfile.is_active.is_(True),
				FamilyMember.family_id == ChildProfile.family_id,
				FamilyMember.relationship == "child",
				FamilyMember.is_active.is_(True),
			)
			.one_or_none()
		)
	else:
		email = str(request.email).strip().lower()
		user = session.query(User).filter(User.email == email, User.is_active.is_(True)).one_or_none()
	if user is None or not user.password_hash or not verify_password(request.password, user.password_hash):
		raise APIError(401, "invalid_credentials", "Username or password is incorrect")
	if request.username is not None:
		child_profile = session.query(ChildProfile).filter(
			ChildProfile.user_id == user.id,
			ChildProfile.is_active.is_(True),
		).one_or_none()
		if child_profile is None:
			raise APIError(401, "invalid_credentials", "Username or password is incorrect")

	user.last_login_at = datetime.now(timezone.utc).replace(tzinfo=None)
	response = start_session(session, user)
	if child_profile is not None:
		response.child_id = child_profile.id
	session.commit()
	return response
