from datetime import datetime, timezone
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session

from app.core.dependencies import get_current_user, require_parent
from app.db.base import get_model
from app.db.session import get_db
from app.schemas.settings import (
	ConsentCreate,
	ConsentPublic,
	FamilySettingsPublic,
	FamilySettingsUpdate,
	UserSettingsPublic,
	UserSettingsUpdate,
)
from app.utils import utc_naive

router = APIRouter(prefix="/settings", tags=["settings"])


@router.get("/me", response_model=UserSettingsPublic)
def get_user_settings(user=Depends(get_current_user), session: Session = Depends(get_db)) -> UserSettingsPublic:
	UserSetting = get_model("UserSetting")
	setting = session.query(UserSetting).filter(UserSetting.user_id == user.id).one_or_none()
	if setting:
		return UserSettingsPublic.model_validate(setting)
	return UserSettingsPublic(
		user_id=user.id,
		language_code=user.preferred_language,
		push_enabled=True,
		email_notifications_enabled=True,
		updated_at=None,
	)


@router.patch("/me", response_model=UserSettingsPublic)
def update_user_settings(
	request: UserSettingsUpdate,
	user=Depends(get_current_user),
	session: Session = Depends(get_db),
) -> UserSettingsPublic:
	UserSetting = get_model("UserSetting")
	values = request.model_dump(exclude_unset=True)
	if any(value is None for value in values.values()):
		raise HTTPException(status_code=422, detail="Settings values cannot be null")
	current = session.query(UserSetting).filter(UserSetting.user_id == user.id).one_or_none()
	if current is None:
		current = UserSetting(
			user_id=user.id,
			language_code=values.get("language_code", user.preferred_language),
			push_enabled=values.get("push_enabled", True),
			email_notifications_enabled=values.get("email_notifications_enabled", True),
			updated_at=utc_naive(datetime.now(timezone.utc)),
		)
		session.add(current)
	else:
		for field, value in values.items():
			setattr(current, field, value)
		current.updated_at = utc_naive(datetime.now(timezone.utc))
	if "language_code" in values:
		user.preferred_language = values["language_code"]
	session.commit()
	session.refresh(current)
	return UserSettingsPublic.model_validate(current)


def _require_family(session: Session, family_id: UUID, parent_id: UUID) -> None:
	FamilyMember = get_model("FamilyMember")
	if not session.query(FamilyMember.id).filter(
		FamilyMember.family_id == family_id,
		FamilyMember.user_id == parent_id,
		FamilyMember.is_active.is_(True),
	).first():
		raise HTTPException(status_code=404, detail="Family not found")


@router.get("/families/{family_id}", response_model=FamilySettingsPublic)
def get_family_settings(
	family_id: UUID,
	parent=Depends(require_parent),
	session: Session = Depends(get_db),
) -> FamilySettingsPublic:
	_require_family(session, family_id, parent.id)
	FamilySetting = get_model("FamilySetting")
	setting = session.query(FamilySetting).filter(FamilySetting.family_id == family_id).one_or_none()
	if setting:
		return FamilySettingsPublic.model_validate(setting)
	return FamilySettingsPublic(
		family_id=family_id,
		default_language="en",
		mission_settings={},
		reward_settings={},
		video_settings={"enabled": True, "default_daily_limit_seconds": 0},
		updated_at=None,
	)


@router.patch("/families/{family_id}", response_model=FamilySettingsPublic)
def update_family_settings(
	family_id: UUID,
	request: FamilySettingsUpdate,
	parent=Depends(require_parent),
	session: Session = Depends(get_db),
) -> FamilySettingsPublic:
	_require_family(session, family_id, parent.id)
	FamilySetting = get_model("FamilySetting")
	values = request.model_dump(exclude_unset=True)
	if any(value is None for value in values.values()):
		raise HTTPException(status_code=422, detail="Settings values cannot be null")
	Family = get_model("Family")
	if not session.query(Family.id).filter(Family.id == family_id).with_for_update().first():
		raise HTTPException(status_code=404, detail="Family not found")
	setting = session.query(FamilySetting).filter(FamilySetting.family_id == family_id).with_for_update().one_or_none()
	if setting is None:
		setting = FamilySetting(
			family_id=family_id,
			default_language=values.get("default_language", "en"),
			mission_settings=values.get("mission_settings", {}),
			reward_settings=values.get("reward_settings", {}),
			video_settings=values.get("video_settings", {"enabled": True, "default_daily_limit_seconds": 0}),
			updated_at=utc_naive(datetime.now(timezone.utc)),
		)
		session.add(setting)
	else:
		for field, value in values.items():
			setattr(setting, field, value)
		setting.updated_at = utc_naive(datetime.now(timezone.utc))
	session.commit()
	session.refresh(setting)
	return FamilySettingsPublic.model_validate(setting)


@router.post("/families/{family_id}/consents", response_model=ConsentPublic, status_code=201)
def create_consent(
	family_id: UUID,
	request: ConsentCreate,
	parent=Depends(require_parent),
	session: Session = Depends(get_db),
) -> ConsentPublic:
	_require_family(session, family_id, parent.id)
	if request.child_id:
		ChildProfile = get_model("ChildProfile")
		if not session.query(ChildProfile.id).filter(
			ChildProfile.id == request.child_id,
			ChildProfile.family_id == family_id,
		).first():
			raise HTTPException(status_code=404, detail="Child profile not found")
	ConsentRecord = get_model("ConsentRecord")
	now = utc_naive(datetime.now(timezone.utc))
	consent = ConsentRecord(
		family_id=family_id,
		child_id=request.child_id,
		parent_user_id=parent.id,
		consent_type=request.consent_type,
		document_version=request.document_version,
		accepted=request.accepted,
		accepted_at=now if request.accepted else None,
		revoked_at=None,
		created_at=now,
	)
	session.add(consent)
	session.commit()
	session.refresh(consent)
	return ConsentPublic.model_validate(consent)


@router.get("/families/{family_id}/consents", response_model=list[ConsentPublic])
def list_consents(
	family_id: UUID,
	parent=Depends(require_parent),
	session: Session = Depends(get_db),
) -> list[ConsentPublic]:
	_require_family(session, family_id, parent.id)
	ConsentRecord = get_model("ConsentRecord")
	rows = session.query(ConsentRecord).filter(ConsentRecord.family_id == family_id).order_by(
		ConsentRecord.created_at.desc()
	).all()
	return [ConsentPublic.model_validate(item) for item in rows]


@router.post("/consents/{consent_id}/revoke", response_model=ConsentPublic)
def revoke_consent(
	consent_id: UUID,
	parent=Depends(require_parent),
	session: Session = Depends(get_db),
) -> ConsentPublic:
	ConsentRecord = get_model("ConsentRecord")
	consent = session.query(ConsentRecord).filter(
		ConsentRecord.id == consent_id,
		ConsentRecord.parent_user_id == parent.id,
	).with_for_update().one_or_none()
	if consent is None:
		raise HTTPException(status_code=404, detail="Consent record not found")
	if consent.accepted and consent.revoked_at is None:
		consent.revoked_at = utc_naive(datetime.now(timezone.utc))
		session.commit()
		session.refresh(consent)
	return ConsentPublic.model_validate(consent)
