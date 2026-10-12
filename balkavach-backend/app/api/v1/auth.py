from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session

from app.core.dependencies import get_current_user, require_parent
from app.core.security import create_access_token
from app.db.base import get_model
from app.db.session import get_db
from app.schemas.auth import LoginRequest, RegistrationRequest, TokenResponse, UserPublic
from app.services.auth_service import authenticate_user, register_parent

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
	token, expires_at = create_access_token(str(child_user.id))
	return TokenResponse(access_token=token, expires_at=expires_at, user=UserPublic.model_validate(child_user))
