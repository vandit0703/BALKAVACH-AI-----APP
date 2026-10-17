from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, Response, status
from sqlalchemy.orm import Session

from app.core.dependencies import get_current_user, require_parent
from app.db.base import get_model
from app.db.session import get_db
from app.schemas.auth import LoginRequest, RefreshRequest, RegistrationRequest, TokenResponse, UserPublic
from app.services.auth_service import authenticate_user, register_parent
from app.services.session_service import revoke, revoke_user_sessions, rotate, start_session

router = APIRouter(prefix="/auth", tags=["authentication"])


@router.post("/register", response_model=TokenResponse, status_code=201)
def register(request: RegistrationRequest, session: Session = Depends(get_db)) -> TokenResponse:
	return register_parent(session, request)


@router.post("/login", response_model=TokenResponse)
def login(request: LoginRequest, session: Session = Depends(get_db)) -> TokenResponse:
	return authenticate_user(session, request)


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
