from datetime import datetime, timezone
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, Response, status
from sqlalchemy.orm import Session

from app.core.dependencies import require_parent
from app.db.base import get_model
from app.db.session import get_db
from app.schemas.user import ChildCreate, ChildPublic, ChildUpdate, FamilyCreate, FamilyPublic

router = APIRouter(prefix="/families", tags=["families"])


def _require_membership(session: Session, family_id: UUID, user_id: UUID):
	FamilyMember = get_model("FamilyMember")
	membership = (
		session.query(FamilyMember)
		.filter(
			FamilyMember.family_id == family_id,
			FamilyMember.user_id == user_id,
			FamilyMember.is_active.is_(True),
		)
		.one_or_none()
	)
	if membership is None:
		raise HTTPException(status_code=404, detail="Family not found")
	return membership


@router.post("", response_model=FamilyPublic, status_code=status.HTTP_201_CREATED)
def create_family(
	request: FamilyCreate,
	user=Depends(require_parent),
	session: Session = Depends(get_db),
) -> FamilyPublic:
	Family = get_model("Family")
	FamilyMember = get_model("FamilyMember")
	family = Family(family_name=request.family_name.strip(), created_by=user.id)
	try:
		session.add(family)
		session.flush()
		session.add(
			FamilyMember(
				family_id=family.id,
				user_id=user.id,
				relationship="parent",
				is_primary_parent=True,
				is_active=True,
			)
		)
		session.commit()
		session.refresh(family)
	except Exception:
		session.rollback()
		raise
	return FamilyPublic.model_validate(family)


@router.get("", response_model=list[FamilyPublic])
def list_families(user=Depends(require_parent), session: Session = Depends(get_db)) -> list[FamilyPublic]:
	Family = get_model("Family")
	FamilyMember = get_model("FamilyMember")
	families = (
		session.query(Family)
		.join(FamilyMember, FamilyMember.family_id == Family.id)
		.filter(FamilyMember.user_id == user.id, FamilyMember.is_active.is_(True))
		.order_by(Family.created_at.desc())
		.all()
	)
	return [FamilyPublic.model_validate(family) for family in families]


@router.get("/{family_id}", response_model=FamilyPublic)
def get_family(
	family_id: UUID,
	user=Depends(require_parent),
	session: Session = Depends(get_db),
) -> FamilyPublic:
	_require_membership(session, family_id, user.id)
	Family = get_model("Family")
	family = session.query(Family).filter(Family.id == family_id).one_or_none()
	if family is None:
		raise HTTPException(status_code=404, detail="Family not found")
	return FamilyPublic.model_validate(family)


@router.post("/{family_id}/children", response_model=ChildPublic, status_code=status.HTTP_201_CREATED)
def create_child(
	family_id: UUID,
	request: ChildCreate,
	user=Depends(require_parent),
	session: Session = Depends(get_db),
) -> ChildPublic:
	_require_membership(session, family_id, user.id)
	User = get_model("User")
	ChildProfile = get_model("ChildProfile")
	FamilyMember = get_model("FamilyMember")
	child_user = User(
		full_name=request.display_name.strip(),
		role="child",
		preferred_language=request.preferred_language,
		is_active=True,
	)
	try:
		session.add(child_user)
		session.flush()
		child = ChildProfile(
			user_id=child_user.id,
			family_id=family_id,
			display_name=request.display_name.strip(),
			date_of_birth=request.date_of_birth,
			avatar_url=str(request.avatar_url) if request.avatar_url else None,
			is_active=True,
		)
		session.add(child)
		session.flush()
		session.add(
			FamilyMember(
				family_id=family_id,
				user_id=child_user.id,
				relationship="child",
				is_primary_parent=False,
				is_active=True,
			)
		)
		session.commit()
		session.refresh(child)
	except Exception:
		session.rollback()
		raise
	return ChildPublic.model_validate(child)


@router.get("/{family_id}/children", response_model=list[ChildPublic])
def list_children(
	family_id: UUID,
	user=Depends(require_parent),
	session: Session = Depends(get_db),
) -> list[ChildPublic]:
	_require_membership(session, family_id, user.id)
	ChildProfile = get_model("ChildProfile")
	children = (
		session.query(ChildProfile)
		.filter(ChildProfile.family_id == family_id, ChildProfile.is_active.is_(True))
		.order_by(ChildProfile.created_at)
		.all()
	)
	return [ChildPublic.model_validate(child) for child in children]


@router.patch("/{family_id}/children/{child_id}", response_model=ChildPublic)
def update_child(
	family_id: UUID,
	child_id: UUID,
	request: ChildUpdate,
	user=Depends(require_parent),
	session: Session = Depends(get_db),
) -> ChildPublic:
	_require_membership(session, family_id, user.id)
	ChildProfile = get_model("ChildProfile")
	child = (
		session.query(ChildProfile)
		.filter(ChildProfile.id == child_id, ChildProfile.family_id == family_id)
		.with_for_update()
		.one_or_none()
	)
	if child is None:
		raise HTTPException(status_code=404, detail="Child profile not found")
	updates = request.model_dump(exclude_unset=True)
	for field in ("display_name", "date_of_birth", "is_active"):
		if field in updates:
			setattr(child, field, updates[field])
	if "avatar_url" in updates:
		child.avatar_url = str(updates["avatar_url"]) if updates["avatar_url"] else None
	if "is_active" in updates:
		User = get_model("User")
		session.query(User).filter(User.id == child.user_id).update({User.is_active: updates["is_active"]})
		FamilyMember = get_model("FamilyMember")
		session.query(FamilyMember).filter(FamilyMember.family_id == family_id, FamilyMember.user_id == child.user_id).update(
			{FamilyMember.is_active: updates["is_active"]}
		)
	session.commit()
	session.refresh(child)
	return ChildPublic.model_validate(child)


@router.delete("/{family_id}/children/{child_id}", status_code=status.HTTP_204_NO_CONTENT)
def deactivate_child(
	family_id: UUID,
	child_id: UUID,
	user=Depends(require_parent),
	session: Session = Depends(get_db),
) -> Response:
	return update_child(
		family_id,
		child_id,
		ChildUpdate(is_active=False),
		user=user,
		session=session,
	) and Response(status_code=status.HTTP_204_NO_CONTENT)
