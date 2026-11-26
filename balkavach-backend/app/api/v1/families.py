from datetime import datetime, timezone
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, Response, status
from sqlalchemy import func
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from app.core.dependencies import require_parent
from app.core.exceptions import APIError
from app.core.security import hash_password
from app.core.child_credentials import encrypt_child_password, decrypt_child_password
from app.db.base import get_model
from app.db.session import get_db
from app.schemas.user import (
	ChildCreate,
	ChildCredentialsPublic,
	ChildCredentialsUpdate,
	ChildPublic,
	ChildUpdate,
	FamilyCreate,
	FamilyPublic,
)

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
	if session.query(User.id).filter(func.lower(User.username) == request.username).first():
		raise APIError(409, "username_in_use", "That username is already taken")
	child_user = User(
		full_name=request.display_name.strip(),
		username=request.username,
		password_hash=hash_password(request.password),
		password_encrypted=encrypt_child_password(request.password),
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
	except IntegrityError as error:
		session.rollback()
		if "uq_users_username" in str(error.orig) or "users_username" in str(error.orig):
			raise APIError(409, "username_in_use", "That username is already taken") from error
		raise
	except Exception:
		session.rollback()
		raise
	return ChildPublic.model_validate(child)


@router.get("/{family_id}/children/{child_id}/credentials", response_model=ChildCredentialsPublic)
def get_child_credentials(
	family_id: UUID,
	child_id: UUID,
	user=Depends(require_parent),
	session: Session = Depends(get_db),
) -> ChildCredentialsPublic:
	_require_membership(session, family_id, user.id)
	ChildProfile = get_model("ChildProfile")
	child = session.query(ChildProfile).filter(
		ChildProfile.id == child_id,
		ChildProfile.family_id == family_id,
		ChildProfile.is_active.is_(True),
	).one_or_none()
	if child is None:
		raise HTTPException(status_code=404, detail="Child profile not found")
	User = get_model("User")
	child_user = session.query(User).filter(User.id == child.user_id, User.role == "child").one_or_none()
	if child_user is None or not child_user.username or not child_user.password_encrypted:
		raise APIError(404, "child_credentials_missing", "Child credentials are not available")
	return ChildCredentialsPublic(
		username=child_user.username,
		password=decrypt_child_password(child_user.password_encrypted),
	)


@router.put("/{family_id}/children/{child_id}/credentials", status_code=status.HTTP_204_NO_CONTENT)
def set_child_credentials(
	family_id: UUID,
	child_id: UUID,
	request: ChildCredentialsUpdate,
	user=Depends(require_parent),
	session: Session = Depends(get_db),
) -> Response:
	_require_membership(session, family_id, user.id)
	ChildProfile = get_model("ChildProfile")
	child = session.query(ChildProfile).filter(
		ChildProfile.id == child_id,
		ChildProfile.family_id == family_id,
		ChildProfile.is_active.is_(True),
	).one_or_none()
	if child is None:
		raise HTTPException(status_code=404, detail="Child profile not found")
	User = get_model("User")
	child_user = session.query(User).filter(User.id == child.user_id, User.role == "child").with_for_update().one_or_none()
	if child_user is None:
		raise HTTPException(status_code=404, detail="Child profile not found")
	if session.query(User.id).filter(
		func.lower(User.username) == request.username,
		User.id != child.user_id,
	).first():
		raise APIError(409, "username_in_use", "That username is already taken")
	child_user.username = request.username
	child_user.password_hash = hash_password(request.password)
	child_user.password_encrypted = encrypt_child_password(request.password)
	try:
		session.commit()
	except IntegrityError as error:
		session.rollback()
		if "uq_users_username" in str(error.orig) or "users_username" in str(error.orig):
			raise APIError(409, "username_in_use", "That username is already taken") from error
		raise
	return Response(status_code=status.HTTP_204_NO_CONTENT)


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


def _valid_interest_categories(session: Session) -> list[dict[str, str]]:
	VideoCategory = get_model("VideoCategory")
	rows = (
		session.query(VideoCategory.slug, VideoCategory.name)
		.filter(VideoCategory.is_active.is_(True))
		.order_by(VideoCategory.display_order, VideoCategory.name)
		.all()
	)
	return [{"slug": str(slug), "name": str(name)} for slug, name in rows if slug]


class _InterestsUpdateBody(ChildUpdate.__base__):
	interests: list[str]
	clear_pending: bool = True


@router.get("/{family_id}/children/{child_id}/interests")
def get_child_interests(
	family_id: UUID,
	child_id: UUID,
	user=Depends(require_parent),
	session: Session = Depends(get_db),
) -> dict:
	_require_membership(session, family_id, user.id)
	ChildProfile = get_model("ChildProfile")
	child = (
		session.query(ChildProfile)
		.filter(ChildProfile.id == child_id, ChildProfile.family_id == family_id, ChildProfile.is_active.is_(True))
		.one_or_none()
	)
	if child is None:
		raise HTTPException(status_code=404, detail="Child profile not found")
	return {
		"child_id": str(child.id),
		"interests": list(getattr(child, "interests", None) or []),
		"pending_requests": list(getattr(child, "pending_interest_requests", None) or []),
		"available_categories": _valid_interest_categories(session),
	}


@router.put("/{family_id}/children/{child_id}/interests")
def update_child_interests(
	family_id: UUID,
	child_id: UUID,
	body: _InterestsUpdateBody,
	user=Depends(require_parent),
	session: Session = Depends(get_db),
) -> dict:
	from datetime import datetime, timezone
	from app.services.admin_service import record_audit
	from app.utils import utc_naive

	_require_membership(session, family_id, user.id)
	ChildProfile = get_model("ChildProfile")
	child = (
		session.query(ChildProfile)
		.filter(ChildProfile.id == child_id, ChildProfile.family_id == family_id, ChildProfile.is_active.is_(True))
		.with_for_update()
		.one_or_none()
	)
	if child is None:
		raise HTTPException(status_code=404, detail="Child profile not found")
	if not hasattr(child, "interests"):
		# Schema without migration 0022: refuse rather than report a save that
		# was never stored.
		raise HTTPException(status_code=503, detail="Child interests are not available yet")
	categories = _valid_interest_categories(session)
	allowed = {c["slug"].lower() for c in categories}
	normalized = list(dict.fromkeys(s.strip().lower() for s in body.interests if s and s.strip().lower() in allowed))
	child.interests = normalized
	if body.clear_pending and hasattr(child, "pending_interest_requests"):
		child.pending_interest_requests = []
	now = utc_naive(datetime.now(timezone.utc))
	if hasattr(child, "interests_updated_at"):
		child.interests_updated_at = now
	if hasattr(child, "interests_updated_by"):
		child.interests_updated_by = user.id
	record_audit(session, user.id, "child.interests_updated", "child_profile", child.id, {"count": len(normalized)})
	session.commit()
	return {
		"child_id": str(child.id),
		"interests": normalized,
		"pending_requests": list(getattr(child, "pending_interest_requests", None) or []),
		"available_categories": categories,
	}


@router.post("/{family_id}/children/{child_id}/link-code", status_code=201)
def create_child_link_code(
	family_id: UUID,
	child_id: UUID,
	user=Depends(require_parent),
	session: Session = Depends(get_db),
) -> dict:
	import hashlib
	import secrets
	from datetime import datetime, timedelta, timezone
	from app.db.base import has_model
	from app.services.admin_service import record_audit
	from app.utils import utc_aware, utc_naive

	_require_membership(session, family_id, user.id)
	if not has_model("ChildLinkCode"):
		raise HTTPException(status_code=503, detail="Child linking is not configured")
	ChildProfile = get_model("ChildProfile")
	child = (
		session.query(ChildProfile)
		.filter(ChildProfile.id == child_id, ChildProfile.family_id == family_id, ChildProfile.is_active.is_(True))
		.one_or_none()
	)
	if child is None:
		raise HTTPException(status_code=404, detail="Child profile not found")

	ChildLinkCode = get_model("ChildLinkCode")
	now_utc = datetime.now(timezone.utc)
	expires_utc = now_utc + timedelta(minutes=10)
	session.query(ChildLinkCode).filter(
		ChildLinkCode.child_id == child.id,
		ChildLinkCode.used_at.is_(None),
		ChildLinkCode.is_revoked.is_(False),
	).update({"is_revoked": True}, synchronize_session=False)

	alphabet = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
	raw_code = "".join(secrets.choice(alphabet) for _ in range(8))
	code_hash = hashlib.sha256(raw_code.encode("utf-8")).hexdigest()
	row = ChildLinkCode(
		family_id=family_id,
		child_id=child.id,
		created_by=user.id,
		code_hash=code_hash,
		expires_at=utc_naive(expires_utc),
		is_revoked=False,
	)
	session.add(row)
	record_audit(session, user.id, "child_link.generated", "child_profile", child.id, {"expires_minutes": 10})
	session.commit()
	return {
		"code": raw_code,
		"qr_payload": f"balkavach://link?code={raw_code}",
		"expires_at": utc_aware(expires_utc).isoformat(),
		"child_id": str(child.id),
	}
