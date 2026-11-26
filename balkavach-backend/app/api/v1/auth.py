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
	verification_resend_limiter,
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
	RegistrationAccepted,
	RegistrationRequest,
	EmailVerificationRequest,
	EmailVerificationResendRequest,
	TokenResponse,
	UserPublic,
)
from app.services import account_security_service
from app.services.auth_service import authenticate_user, register_parent, set_parent_pin
from app.services.email_verification_service import resend_verification, verify_parent_email
from app.services.password_reset_service import consume_reset_token, create_reset_token
from app.core.exceptions import APIError
from app.services.attempt_lockout import parent_mode_lockout
from app.services.parent_mode_service import enter_parent_mode
from app.services.session_service import end_parent_mode_session, revoke, revoke_user_sessions, rotate, start_session

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/auth", tags=["authentication"])


@router.post("/register", response_model=RegistrationAccepted, status_code=status.HTTP_202_ACCEPTED)
def register(
	request: RegistrationRequest,
	http_request: Request,
	background: BackgroundTasks,
	session: Session = Depends(get_db),
) -> RegistrationAccepted:
	enforce(
		registration_limiter,
		f"{http_request.client.host if http_request.client else 'unknown'}:{request.email}",
		limit=settings.registration_rate_limit,
		window_seconds=settings.login_rate_window_seconds,
	)
	email, otp = register_parent(session, request)
	background.add_task(_deliver_verification, email, otp)
	return RegistrationAccepted(email=email)


def _deliver_verification(email: str, otp: str) -> None:
	try:
		from app.integrations import email as mailer

		mailer.send_parent_verification(email, otp)
	except Exception:
		logger.exception("Parent verification email delivery failed")


@router.post("/verify-email", status_code=status.HTTP_204_NO_CONTENT)
def verify_email(request: EmailVerificationRequest, session: Session = Depends(get_db)) -> Response:
	verify_parent_email(session, str(request.email), request.otp)
	return Response(status_code=status.HTTP_204_NO_CONTENT)


@router.post("/resend-verification", status_code=status.HTTP_202_ACCEPTED)
def resend_email_verification(
	request: EmailVerificationResendRequest,
	http_request: Request,
	background: BackgroundTasks,
	session: Session = Depends(get_db),
) -> Response:
	email = str(request.email).strip().lower()
	enforce(
		verification_resend_limiter,
		_client_ip(http_request),
		limit=settings.verification_resend_rate_limit,
		window_seconds=60,
	)
	result = resend_verification(session, email)
	if result is not None:
		delivery_email, otp = result
		session.commit()
		background.add_task(_deliver_verification, delivery_email, otp)
	return Response(status_code=status.HTTP_202_ACCEPTED)


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
		_client_ip(http_request),
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


class _AccountDeleteBody(LoginRequest.__base__):
	password: str = ""


@router.delete("/account", status_code=status.HTTP_204_NO_CONTENT)
def delete_account(
	request: _AccountDeleteBody,
	parent=Depends(require_parent),
	session: Session = Depends(get_db),
) -> Response:
	"""Soft-delete and anonymize parent + child PII while retaining anonymized ledgers and audit logs."""
	from datetime import datetime, timezone
	from app.core.security import verify_password
	from app.db.base import get_model, has_model
	from app.services.admin_service import record_audit
	from app.services.session_service import revoke_all_sessions
	from app.utils import utc_naive

	if not request.password or not verify_password(request.password, parent.password_hash):
		raise HTTPException(status_code=403, detail="Password verification failed")

	now = utc_naive(datetime.now(timezone.utc))
	User = get_model("User")
	FamilyMember = get_model("FamilyMember")
	ChildProfile = get_model("ChildProfile")
	DeviceToken = get_model("DeviceToken") if has_model("DeviceToken") else None

	family_ids = [
		row[0]
		for row in session.query(FamilyMember.family_id)
		.filter(FamilyMember.user_id == parent.id, FamilyMember.is_active.is_(True))
		.all()
	]
	session.query(FamilyMember).filter(FamilyMember.user_id == parent.id).update({"is_active": False})
	revoke_all_sessions(session, parent.id)
	if DeviceToken is not None:
		session.query(DeviceToken).filter(DeviceToken.user_id == parent.id).delete(synchronize_session=False)

	if family_ids:
		children = (
			session.query(ChildProfile)
			.filter(ChildProfile.family_id.in_(family_ids), ChildProfile.is_active.is_(True))
			.all()
		)
		for child in children:
			other_parents = (
				session.query(FamilyMember.id)
				.filter(
					FamilyMember.family_id == child.family_id,
					FamilyMember.user_id != parent.id,
					FamilyMember.is_active.is_(True),
				)
				.first()
			)
			if other_parents is not None:
				continue
			child.display_name = "Deleted Child"
			child.date_of_birth = None
			child.avatar_url = None
			child.is_active = False
			if hasattr(child, "interests"):
				child.interests = []
			if hasattr(child, "deleted_at"):
				child.deleted_at = now
			revoke_all_sessions(session, child.user_id)
			if DeviceToken is not None:
				session.query(DeviceToken).filter(DeviceToken.user_id == child.user_id).delete(synchronize_session=False)
			child_user = session.query(User).filter(User.id == child.user_id).one_or_none()
			if child_user is not None:
				child_user.email = f"deleted-{child_user.id}@deleted.local"
				child_user.full_name = "Deleted Child"
				child_user.phone_number = None
				child_user.password_hash = "!"
				child_user.is_active = False
				if hasattr(child_user, "deleted_at"):
					child_user.deleted_at = now

	parent.email = f"deleted-{parent.id}@deleted.local"
	parent.full_name = "Deleted User"
	parent.phone_number = None
	parent.password_hash = "!"
	parent.is_active = False
	if hasattr(parent, "deleted_at"):
		parent.deleted_at = now
	record_audit(session, parent.id, "account.deleted", "user", parent.id, {"anonymized": True})
	session.commit()
	return Response(status_code=status.HTTP_204_NO_CONTENT)


class _ChildLinkRedeemBody(LoginRequest.__base__):
	code: str


@router.post("/child-link/redeem", response_model=TokenResponse)
def redeem_child_link_code(
	request: _ChildLinkRedeemBody,
	http_request: Request,
	session: Session = Depends(get_db),
) -> TokenResponse:
	"""Redeem a single-use, short-lived child linking code/QR payload and issue a child session (DEC-05)."""
	import hashlib
	from datetime import datetime, timezone
	from app.core.exceptions import APIError
	from app.db.base import get_model, has_model
	from app.services.admin_service import record_audit
	from app.utils import utc_naive

	enforce(
		login_limiter,
		f"child_link:{_client_ip(http_request)}",
		limit=settings.login_rate_limit,
		window_seconds=settings.login_rate_window_seconds,
	)
	if not has_model("ChildLinkCode"):
		raise HTTPException(status_code=503, detail="Child linking is not configured")

	raw = request.code.strip()
	if raw.startswith("balkavach://"):
		from urllib.parse import parse_qs, urlparse

		raw = (parse_qs(urlparse(raw).query).get("code") or [""])[0].strip()
	normalized = raw.upper()
	if len(normalized) < 6 or len(normalized) > 32:
		raise APIError(400, "invalid_link_code", "Invalid linking code")

	code_hash = hashlib.sha256(normalized.encode("utf-8")).hexdigest()
	ChildLinkCode = get_model("ChildLinkCode")
	row = session.query(ChildLinkCode).filter(ChildLinkCode.code_hash == code_hash).with_for_update().one_or_none()
	now = utc_naive(datetime.now(timezone.utc))
	if row is None or row.is_revoked or row.used_at is not None or row.expires_at <= now:
		if row is not None:
			record_audit(session, row.created_by, "child_link.failed", "child_profile", row.child_id, {"reason": "expired_or_used"})
			session.commit()
		raise APIError(400, "invalid_or_expired_link_code", "This linking code is invalid or expired")

	ChildProfile = get_model("ChildProfile")
	User = get_model("User")
	child = (
		session.query(ChildProfile)
		.filter(ChildProfile.id == row.child_id, ChildProfile.family_id == row.family_id, ChildProfile.is_active.is_(True))
		.one_or_none()
	)
	child_user = (
		session.query(User)
		.filter(User.id == child.user_id, User.role == "child", User.is_active.is_(True))
		.one_or_none()
		if child is not None
		else None
	)
	if child is None or child_user is None:
		raise APIError(404, "child_not_found", "Child profile not found")

	row.used_at = now
	response = start_session(session, child_user, issued_by=row.created_by)
	response.child_id = child.id
	record_audit(session, row.created_by, "child_link.redeemed", "child_profile", child.id, {"link_id": str(row.id)})
	session.commit()
	return response

