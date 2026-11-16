import logging
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, Request, Response, status
from sqlalchemy.orm import Session

from app.core.config import settings
from app.core.dependencies import get_current_user, require_parent
from app.core.rate_limit import (
	enforce,
	login_limiter,
	password_reset_limiter,
	parent_pin_limiter,
	registration_limiter,
)
from app.core.security import hash_password, verify_password
from app.db.base import get_model
from app.db.session import get_db
from app.schemas.auth import (
	LoginRequest,
	ParentPinSetRequest,
	ParentPinVerifyRequest,
	PasswordResetConfirm,
	PasswordResetRequest,
	RefreshRequest,
	RegistrationRequest,
	TokenResponse,
	UserPublic,
)
from app.services.auth_service import authenticate_user, register_parent, set_parent_pin
from app.services.password_reset_service import consume_reset_token, create_reset_token
from app.services.session_service import revoke, revoke_user_sessions, rotate, start_session

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/auth", tags=["authentication"])


@router.post("/register", response_model=TokenResponse, status_code=201)
def register(request: RegistrationRequest, http_request: Request, session: Session = Depends(get_db)) -> TokenResponse:
	enforce(
		registration_limiter,
		f"{http_request.client.host if http_request.client else 'unknown'}:{request.email}",
		limit=settings.registration_rate_limit,
		window_seconds=settings.login_rate_window_seconds,
	)
	return register_parent(session, request)


@router.post("/login", response_model=TokenResponse)
def login(request: LoginRequest, http_request: Request, session: Session = Depends(get_db)) -> TokenResponse:
	identifier = request.email or request.username or "unknown"
	enforce(
		login_limiter,
		f"{http_request.client.host if http_request.client else 'unknown'}:{identifier}",
		limit=settings.login_rate_limit,
		window_seconds=settings.login_rate_window_seconds,
	)
	return authenticate_user(session, request)


@router.post("/password/forgot", status_code=status.HTTP_202_ACCEPTED)
def forgot_password(
	request: PasswordResetRequest,
	http_request: Request,
	session: Session = Depends(get_db),
) -> Response:
	enforce(
		password_reset_limiter,
		f"{http_request.client.host if http_request.client else 'unknown'}:{request.email}",
		limit=settings.password_reset_rate_limit,
		window_seconds=settings.password_reset_window_seconds,
	)
	User = get_model("User")
	user = session.query(User).filter(User.email == str(request.email).lower(), User.is_active.is_(True)).one_or_none()
	if user is not None and user.role == "parent":
		token = create_reset_token(session, user)
		session.commit()
		try:
			from app.integrations.email import send_password_reset

			send_password_reset(str(user.email), token)
		except Exception:
			logger.exception("Password reset delivery failed")
	return Response(status_code=status.HTTP_202_ACCEPTED)


@router.post("/password/reset", status_code=status.HTTP_204_NO_CONTENT)
def reset_password(request: PasswordResetConfirm, session: Session = Depends(get_db)) -> Response:
	consume_reset_token(session, request.token, request.password)
	session.commit()
	return Response(status_code=status.HTTP_204_NO_CONTENT)


@router.post("/parent-pin", status_code=status.HTTP_204_NO_CONTENT)
def update_parent_pin(
	request: ParentPinSetRequest,
	parent=Depends(require_parent),
	session: Session = Depends(get_db),
) -> Response:
	set_parent_pin(session, parent, request.pin)
	return Response(status_code=status.HTTP_204_NO_CONTENT)


@router.post("/parent-pin/verify", response_model=TokenResponse)
def verify_parent_pin(
	request: ParentPinVerifyRequest,
	http_request: Request,
	session: Session = Depends(get_db),
) -> TokenResponse:
	enforce(
		parent_pin_limiter,
		f"{http_request.client.host if http_request.client else 'unknown'}:{request.email}",
		limit=settings.parent_pin_rate_limit,
		window_seconds=settings.parent_pin_window_seconds,
	)
	User = get_model("User")
	parent = session.query(User).filter(
		User.email == str(request.email).lower(),
		User.role == "parent",
		User.is_active.is_(True),
	).one_or_none()
	if parent is None or not getattr(parent, "parent_pin_hash", None) or not verify_password(request.pin, parent.parent_pin_hash):
		raise HTTPException(status_code=401, detail="Invalid parent PIN")
	return start_session(session, parent)


@router.get("/me", response_model=UserPublic)
def me(user=Depends(get_current_user)) -> UserPublic:
	return UserPublic.model_validate(user)


@router.post("/children/{child_id}/session", response_model=TokenResponse)
def issue_child_session(
	child_id: UUID,
	parent=Depends(require_parent),
	session: Session = Depends(get_db),
) -> TokenResponse:
	ChildProfile = get_model("ChildProfile")
	child = session.query(ChildProfile).filter(
		ChildProfile.id == child_id,
		ChildProfile.is_active.is_(True),
	).one_or_none()
	if child is None:
		raise HTTPException(status_code=404, detail="Child profile not found")
	FamilyMember = get_model("FamilyMember")
	membership = session.query(FamilyMember.id).filter(
		FamilyMember.family_id == child.family_id,
		FamilyMember.user_id == parent.id,
		FamilyMember.is_active.is_(True),
	).first()
	if membership is None:
		raise HTTPException(status_code=404, detail="Child profile not found")
	User = get_model("User")
	child_user = session.query(User).filter(
		User.id == child.user_id,
		User.role == "child",
		User.is_active.is_(True),
	).one_or_none()
	if child_user is None:
		raise HTTPException(status_code=404, detail="Child profile not found")
	response = start_session(session, child_user, issued_by=parent.id)
	response.child_id = child.id
	session.commit()
	return response


def _owned_child_user(session: Session, parent, child_id: UUID):
	ChildProfile = get_model("ChildProfile")
	child = session.query(ChildProfile).filter(ChildProfile.id == child_id).one_or_none()
	if child is None:
		raise HTTPException(status_code=404, detail="Child profile not found")
	FamilyMember = get_model("FamilyMember")
	if not session.query(FamilyMember.id).filter(
		FamilyMember.family_id == child.family_id,
		FamilyMember.user_id == parent.id,
		FamilyMember.is_active.is_(True),
	).first():
		raise HTTPException(status_code=404, detail="Child profile not found")
	return child


@router.delete("/children/{child_id}/sessions", status_code=status.HTTP_204_NO_CONTENT)
def revoke_child_sessions(
	child_id: UUID,
	parent=Depends(require_parent),
	session: Session = Depends(get_db),
) -> Response:
	"""End every signed-in device of one child (e.g. a lost tablet)."""
	child = _owned_child_user(session, parent, child_id)
	revoke_user_sessions(session, child.user_id)
	return Response(status_code=status.HTTP_204_NO_CONTENT)


@router.post("/refresh", response_model=TokenResponse)
def refresh(request: RefreshRequest, session: Session = Depends(get_db)) -> TokenResponse:
	return rotate(session, request.refresh_token)


@router.post("/logout", status_code=status.HTTP_204_NO_CONTENT)
def logout(request: RefreshRequest, session: Session = Depends(get_db)) -> Response:
	revoke(session, request.refresh_token)
	return Response(status_code=status.HTTP_204_NO_CONTENT)
