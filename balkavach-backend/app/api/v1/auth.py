import logging
from uuid import UUID

from fastapi import APIRouter, BackgroundTasks, Depends, HTTPException, Request, Response, status
from sqlalchemy.orm import Session

from app.core.config import settings
from app.core.dependencies import current_session_id, get_current_user, require_child, require_parent
from app.core.rate_limit import (
	enforce,
	login_limiter,
	password_reset_limiter,
	parent_mode_limiter,
	password_change_limiter,
	registration_limiter,
)
from app.core.security import hash_password, verify_password
from app.db.base import get_model
from app.db.session import get_db
from app.schemas.auth import (
	LoginRequest,
	ParentModeEnterRequest,
	ParentPinSetRequest,
	ParentPinStatus,
	PasswordChangeRequest,
	PasswordResetConfirm,
	PasswordResetRequest,
	RefreshRequest,
	RegistrationRequest,
	TokenResponse,
	UserPublic,
)
from app.services import account_security_service
from app.services.auth_service import authenticate_user, register_parent, set_parent_pin
from app.services.password_reset_service import consume_reset_token, create_reset_token
from app.core.exceptions import APIError
from app.services.attempt_lockout import parent_mode_lockout
from app.services.parent_mode_service import enter_parent_mode
from app.services.session_service import end_parent_mode_session, revoke, revoke_user_sessions, rotate, start_session

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


def _deliver_password_reset(email: str, token: str) -> None:
	try:
		from app.integrations import email as mailer

		mailer.send_password_reset(email, token)
	except Exception:
		logger.exception("Password reset delivery failed")


@router.post("/password/forgot", status_code=status.HTTP_202_ACCEPTED)
def forgot_password(
	request: PasswordResetRequest,
	http_request: Request,
	background: BackgroundTasks,
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
		# Delivery (SMTP) runs after the response so a known and an unknown address answer in the same time.
		background.add_task(_deliver_password_reset, str(user.email), token)
	return Response(status_code=status.HTTP_202_ACCEPTED)


@router.post("/password/reset", status_code=status.HTTP_204_NO_CONTENT)
def reset_password(request: PasswordResetConfirm, session: Session = Depends(get_db)) -> Response:
	consume_reset_token(session, request.token, request.password)
	session.commit()
	return Response(status_code=status.HTTP_204_NO_CONTENT)


def _client_ip(http_request: Request) -> str:
	return http_request.client.host if http_request.client else "unknown"


@router.post("/parent-mode/enter", response_model=TokenResponse)
def parent_mode_enter(
	request: ParentModeEnterRequest,
	http_request: Request,
	child=Depends(require_child),
	child_user=Depends(get_current_user),
	session_id=Depends(current_session_id),
	session: Session = Depends(get_db),
) -> TokenResponse:
	"""Leave child mode: the *child device's* session proves where the request comes from and the
	parent proves who they are with the same email + password as the normal parent login. The
	parent must belong to this child's family."""
	enforce(
		parent_mode_limiter,
		f"{_client_ip(http_request)}:{session_id or child_user.id}",
		limit=settings.parent_mode_rate_limit,
		window_seconds=settings.parent_mode_rate_window_seconds,
	)
	return enter_parent_mode(
		session,
		child=child,
		child_user=child_user,
		session_id=session_id,
		email=str(request.email),
		password=request.password,
	)


@router.post("/parent-pin/verify", include_in_schema=False)
def verify_parent_pin_removed() -> None:
	"""Removed: an unauthenticated email + PIN exchange for a parent session was unsafe.

	Kept as a tombstone so old app builds fail clearly (and no credential is ever evaluated).
	Use ``POST /auth/parent-mode/enter`` from a child session instead."""
	raise APIError(410, "endpoint_removed", "Update the app to switch to parent mode.")


@router.get("/parent-pin", response_model=ParentPinStatus)
def parent_pin_status(parent=Depends(require_parent)) -> ParentPinStatus:
	return ParentPinStatus(is_set=bool(getattr(parent, "parent_pin_hash", None)))


@router.post("/parent-pin", status_code=status.HTTP_204_NO_CONTENT)
def update_parent_pin(
	request: ParentPinSetRequest,
	parent=Depends(require_parent),
	session: Session = Depends(get_db),
) -> Response:
	"""Set a parental-control PIN. It is **not** used to enter parent mode. Changing an existing
	PIN needs the current PIN or the account password, with account-level lockout."""
	existing = getattr(parent, "parent_pin_hash", None)
	if existing:
		subject = f"pin-change:{parent.id}"
		locked = parent_mode_lockout.locked_for(subject)
		if locked:
			raise APIError(
				423,
				"pin_change_locked",
				"Too many incorrect attempts. Please try again later.",
				headers={"Retry-After": str(locked)},
			)
		if request.current_pin is not None:
			proven = verify_password(request.current_pin, existing)
		elif request.current_password is not None:
			proven = bool(parent.password_hash) and verify_password(request.current_password, parent.password_hash)
		else:
			raise APIError(403, "current_credential_required", "Enter your current PIN or password to change the PIN.")
		if not proven:
			parent_mode_lockout.record_failure(subject)
			raise APIError(403, "current_credential_invalid", "The current PIN or password is incorrect.")
		parent_mode_lockout.record_success(subject)
	set_parent_pin(session, parent, request.pin)
	return Response(status_code=status.HTTP_204_NO_CONTENT)


@router.get("/me", response_model=UserPublic)
def me(user=Depends(get_current_user)) -> UserPublic:
	return UserPublic.model_validate(user)


@router.post("/children/{child_id}/session", response_model=TokenResponse)
def issue_child_session(
	child_id: UUID,
	parent=Depends(require_parent),
	session_id=Depends(current_session_id),
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
	# Handing the device back to the child ends a parent-mode session on the server, atomically with the
	# new child session (the app also logs out, best effort).
	end_parent_mode_session(session, session_id)
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


# Wrong current passwords per parent account (not per IP) before a pause.
PASSWORD_CHANGE_LIMIT = 5
PASSWORD_CHANGE_WINDOW_SECONDS = 900


@router.post("/password/change", response_model=TokenResponse)
def change_password(
	request: PasswordChangeRequest,
	parent=Depends(require_parent),
	session_id=Depends(current_session_id),
	session: Session = Depends(get_db),
) -> TokenResponse:
	"""Parent only, from their own sign-in (not a parent-mode session on a child's
	device). Ends every session of this parent and returns a new one for this device."""
	enforce(
		password_change_limiter,
		f"user:{parent.id}",
		limit=PASSWORD_CHANGE_LIMIT,
		window_seconds=PASSWORD_CHANGE_WINDOW_SECONDS,
	)
	return account_security_service.change_password(
		session,
		parent,
		session_id,
		current_password=request.current_password,
		new_password=request.new_password,
	)


@router.post("/logout-all", status_code=status.HTTP_204_NO_CONTENT)
def logout_all(
	parent=Depends(require_parent),
	session_id=Depends(current_session_id),
	session: Session = Depends(get_db),
) -> Response:
	"""Parent only: sign out of every device, this one included. Children's own
	sessions are not affected (a parent ends those per child)."""
	account_security_service.sign_out_everywhere(session, parent, session_id)
	return Response(status_code=status.HTTP_204_NO_CONTENT)

