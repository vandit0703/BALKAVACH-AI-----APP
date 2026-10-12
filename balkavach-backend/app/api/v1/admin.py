from datetime import datetime, timezone
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy import func
from sqlalchemy.orm import Session

from app.core.dependencies import require_admin_permission
from app.db.base import get_model
from app.db.session import get_db
from app.schemas.admin import (
	AdminBadgePublic,
	AdminRolePublic,
	AdminSummary,
	AuditLogPublic,
	BadgeCreate,
	EducationalContentAdminPublic,
	EducationalContentCreate,
	EducationalContentPublic,
	UserStatusUpdate,
)
from app.schemas.auth import UserPublic
from app.services.admin_service import record_audit
from app.utils import utc_naive

router = APIRouter(prefix="/admin", tags=["admin"])


def _count(session: Session, model_name: str, *conditions) -> int:
	Model = get_model(model_name)
	query = session.query(func.count(Model.id))
	if conditions:
		query = query.filter(*conditions)
	return int(query.scalar() or 0)


@router.get("/dashboard", response_model=AdminSummary)
def dashboard(
	admin=Depends(require_admin_permission("dashboard:read")),
	session: Session = Depends(get_db),
) -> AdminSummary:
	Task = get_model("Task")
	Video = get_model("Video")
	RedemptionRequest = get_model("RedemptionRequest")
	return AdminSummary(
		users=_count(session, "User"),
		families=_count(session, "Family"),
		children=_count(session, "ChildProfile", get_model("ChildProfile").is_active.is_(True)),
		active_tasks=_count(session, "Task", Task.is_active.is_(True)),
		published_videos=_count(session, "Video", Video.is_published.is_(True)),
		pending_redemptions=_count(session, "RedemptionRequest", RedemptionRequest.status == "pending"),
	)


@router.get("/users", response_model=list[UserPublic])
def list_users(
	limit: int = Query(default=50, ge=1, le=100),
	offset: int = Query(default=0, ge=0),
	role: str | None = None,
	admin=Depends(require_admin_permission("users:read")),
	session: Session = Depends(get_db),
) -> list[UserPublic]:
	User = get_model("User")
	query = session.query(User)
	if role:
		if role not in {"parent", "child", "admin", "staff"}:
			raise HTTPException(status_code=422, detail="Invalid user role filter")
		query = query.filter(User.role == role)
	rows = query.order_by(User.created_at.desc(), User.id).offset(offset).limit(limit).all()
	return [UserPublic.model_validate(user) for user in rows]


@router.patch("/users/{user_id}/status", response_model=UserPublic)
def set_user_status(
	user_id: UUID,
	request: UserStatusUpdate,
	admin=Depends(require_admin_permission("users:write")),
	session: Session = Depends(get_db),
) -> UserPublic:
	if user_id == admin.id and not request.is_active:
		raise HTTPException(status_code=409, detail="Administrators cannot deactivate their own account")
	User = get_model("User")
	user = session.query(User).filter(User.id == user_id).with_for_update().one_or_none()
	if user is None:
		raise HTTPException(status_code=404, detail="User not found")
	user.is_active = request.is_active
	record_audit(
		session,
		admin.id,
		"user.activated" if request.is_active else "user.deactivated",
		"user",
		user.id,
		{},
	)
	session.commit()
	session.refresh(user)
	return UserPublic.model_validate(user)


@router.get("/roles", response_model=list[AdminRolePublic])
def list_admin_roles(
	admin=Depends(require_admin_permission("admin_roles:read")),
	session: Session = Depends(get_db),
) -> list[AdminRolePublic]:
	AdminRole = get_model("AdminRole")
	return [AdminRolePublic.model_validate(role) for role in session.query(AdminRole).order_by(AdminRole.name).all()]


@router.get("/badges", response_model=list[AdminBadgePublic])
def list_badges(
	admin=Depends(require_admin_permission("badges:read")),
	session: Session = Depends(get_db),
) -> list[AdminBadgePublic]:
	Badge = get_model("Badge")
	rows = session.query(Badge).order_by(Badge.name).all()
	return [AdminBadgePublic.model_validate(badge) for badge in rows]


@router.post("/badges", response_model=AdminBadgePublic, status_code=201)
def create_badge(
	request: BadgeCreate,
	admin=Depends(require_admin_permission("badges:write")),
	session: Session = Depends(get_db),
) -> AdminBadgePublic:
	Badge = get_model("Badge")
	badge = Badge(
		name=request.name.strip(),
		description=request.description,
		icon_url=str(request.icon_url) if request.icon_url else None,
		criteria_type=request.criteria_type,
		criteria_value={"threshold": request.threshold},
		is_active=True,
	)
	session.add(badge)
	session.flush()
	record_audit(session, admin.id, "badge.created", "badge", badge.id, {"criteria_type": request.criteria_type})
	session.commit()
	session.refresh(badge)
	return AdminBadgePublic.model_validate(badge)


@router.get("/audit-logs", response_model=list[AuditLogPublic])
def list_audit_logs(
	entity_type: str | None = None,
	limit: int = Query(default=50, ge=1, le=100),
	offset: int = Query(default=0, ge=0),
	admin=Depends(require_admin_permission("audit:read")),
	session: Session = Depends(get_db),
) -> list[AuditLogPublic]:
	AuditLog = get_model("AuditLog")
	query = session.query(AuditLog)
	if entity_type:
		query = query.filter(AuditLog.entity_type == entity_type)
	logs = query.order_by(AuditLog.created_at.desc(), AuditLog.id).offset(offset).limit(limit).all()
	return [AuditLogPublic.model_validate(entry) for entry in logs]


@router.get("/educational-content", response_model=list[EducationalContentAdminPublic])
def admin_list_educational_content(
	limit: int = Query(default=50, ge=1, le=100),
	offset: int = Query(default=0, ge=0),
	admin=Depends(require_admin_permission("content:read")),
	session: Session = Depends(get_db),
) -> list[EducationalContentAdminPublic]:
	Content = get_model("EducationalContent")
	rows = session.query(Content).order_by(Content.created_at.desc(), Content.id).offset(offset).limit(limit).all()
	return [EducationalContentAdminPublic.model_validate(item) for item in rows]


@router.post("/educational-content", response_model=EducationalContentAdminPublic, status_code=201)
def admin_create_educational_content(
	request: EducationalContentCreate,
	admin=Depends(require_admin_permission("content:write")),
	session: Session = Depends(get_db),
) -> EducationalContentAdminPublic:
	Content = get_model("EducationalContent")
	item = Content(
		title=request.title.strip(),
		description=request.description,
		content_type=request.content_type,
		category_id=request.category_id,
		language_code=request.language_code,
		content_url=str(request.content_url) if request.content_url else None,
		thumbnail_url=str(request.thumbnail_url) if request.thumbnail_url else None,
		video_id=request.video_id,
		collection_id=request.collection_id,
		requires_entitlement=request.requires_entitlement,
		is_active=True,
		created_by=admin.id,
	)
	session.add(item)
	session.flush()
	record_audit(session, admin.id, "educational_content.created", "educational_content", item.id, {})
	session.commit()
	session.refresh(item)
	return EducationalContentAdminPublic.model_validate(item)


@router.patch("/educational-content/{content_id}/active", response_model=EducationalContentAdminPublic)
def admin_set_content_active(
	content_id: UUID,
	is_active: bool,
	admin=Depends(require_admin_permission("content:write")),
	session: Session = Depends(get_db),
) -> EducationalContentAdminPublic:
	Content = get_model("EducationalContent")
	item = session.query(Content).filter(Content.id == content_id).with_for_update().one_or_none()
	if item is None:
		raise HTTPException(status_code=404, detail="Educational content not found")
	item.is_active = is_active
	record_audit(
		session,
		admin.id,
		"educational_content.activated" if is_active else "educational_content.deactivated",
		"educational_content",
		item.id,
		{},
	)
	session.commit()
	session.refresh(item)
	return EducationalContentAdminPublic.model_validate(item)
