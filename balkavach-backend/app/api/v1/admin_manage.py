"""Admin management endpoints (families, missions, rewards, presets, content, roles, settings, analytics).

Every route requires an assigned admin role holding the named permission; every
mutation writes an audit-log row in the same transaction.
"""

from datetime import datetime, timedelta, timezone
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, Query, Response, status
from sqlalchemy import func
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from app.core.dependencies import require_admin, require_admin_permission
from app.core.permissions import expand_permissions
from app.core.exceptions import APIError
from app.db.base import get_model
from app.db.session import get_db
from app.schemas.admin import AdminBadgePublic, EducationalContentAdminPublic
from app.schemas.admin_manage import (
	ActiveUpdate,
	AdminChildStatus,
	AdminFamilyChild,
	AdminFamilyDetail,
	AdminFamilyParent,
	AdminFamilyRow,
	AdminMePublic,
	AdminRedemptionPublic,
	AdminRewardPublic,
	AdminTaskCategoryPublic,
	AdminTaskPublic,
	AdminUserPublic,
	AnalyticsOverview,
	AnalyticsTotals,
	BadgeUpdate,
	DailyCount,
	EducationalContentUpdate,
	PresetTaskCreate,
	PresetTaskPublic,
	PresetTaskUpdate,
	RoleAssignment,
	SettingPublic,
	SettingValue,
	TaskCategoryUpdate,
)
from app.services.admin_service import record_audit
from app.services.app_settings_service import DEFAULTS, read_all, write_setting
from app.services.session_service import revoke_user_sessions
from app.services.timezone_service import family_timezone_name

router = APIRouter(prefix="/admin", tags=["admin"])


def _like(value: str) -> str:
	return "%" + value.replace("\\", "\\\\").replace("%", "\\%").replace("_", "\\_") + "%"


def _not_found(what: str) -> HTTPException:
	return HTTPException(status_code=404, detail=f"{what} not found")


@router.get("/me", response_model=AdminMePublic)
def admin_me(
	admin=Depends(require_admin),
	session: Session = Depends(get_db),
) -> AdminMePublic:
	"""Who am I and what may I do: lets the panel show only usable sections."""
	AdminRole = get_model("AdminRole")
	UserAdminRole = get_model("UserAdminRole")
	rows = (
		session.query(AdminRole.name, AdminRole.permissions)
		.join(UserAdminRole, UserAdminRole.admin_role_id == AdminRole.id)
		.filter(UserAdminRole.user_id == admin.id)
		.all()
	)
	granted: set[str] = set()
	for _, permissions in rows:
		granted |= expand_permissions(permissions)
	return AdminMePublic(
		user=AdminUserPublic.model_validate(admin),
		roles=sorted(name for name, _ in rows),
		permissions=sorted(granted),
	)


# -- users -------------------------------------------------------------------------

@router.get("/users", response_model=list[AdminUserPublic])
def list_users(
	q: str | None = Query(default=None, max_length=100),
	role: str | None = None,
	limit: int = Query(default=50, ge=1, le=100),
	offset: int = Query(default=0, ge=0),
	admin=Depends(require_admin_permission("users:read")),
	session: Session = Depends(get_db),
) -> list[AdminUserPublic]:
	User = get_model("User")
	query = session.query(User)
	if role:
		if role not in {"parent", "child", "admin", "staff"}:
			raise HTTPException(status_code=422, detail="Invalid user role filter")
		query = query.filter(User.role == role)
	if q:
		pattern = _like(q.strip())
		query = query.filter(User.full_name.ilike(pattern, escape="\\") | User.email.ilike(pattern, escape="\\"))
	rows = query.order_by(User.created_at.desc(), User.id).offset(offset).limit(limit).all()
	return [AdminUserPublic.model_validate(user) for user in rows]


# -- families and children ---------------------------------------------------------------

def _family_rows(session: Session, base_query):
	Family = get_model("Family")
	FamilyMember = get_model("FamilyMember")
	ChildProfile = get_model("ChildProfile")
	Task = get_model("Task")
	User = get_model("User")
	rows = base_query.all()
	result = []
	for family in rows:
		member_count = (
			session.query(func.count(FamilyMember.id))
			.filter(FamilyMember.family_id == family.id, FamilyMember.is_active.is_(True))
			.scalar()
		)
		parent_count = (
			session.query(func.count(FamilyMember.id))
			.join(User, User.id == FamilyMember.user_id)
			.filter(FamilyMember.family_id == family.id, FamilyMember.is_active.is_(True), User.role == "parent")
			.scalar()
		)
		child_count = (
			session.query(func.count(ChildProfile.id))
			.filter(ChildProfile.family_id == family.id, ChildProfile.is_active.is_(True))
			.scalar()
		)
		task_count = (
			session.query(func.count(Task.id)).filter(Task.family_id == family.id, Task.is_active.is_(True)).scalar()
		)
		result.append(
			{
				"id": family.id,
				"family_name": family.family_name,
				"created_at": family.created_at,
				"member_count": int(member_count or 0),
				"parent_count": int(parent_count or 0),
				"child_count": int(child_count or 0),
				"active_task_count": int(task_count or 0),
			}
		)
	return result


@router.get("/families", response_model=list[AdminFamilyRow])
def list_families(
	q: str | None = Query(default=None, max_length=100),
	limit: int = Query(default=50, ge=1, le=100),
	offset: int = Query(default=0, ge=0),
	admin=Depends(require_admin_permission("families:read")),
	session: Session = Depends(get_db),
) -> list[AdminFamilyRow]:
	Family = get_model("Family")
	query = session.query(Family)
	if q:
		query = query.filter(Family.family_name.ilike(_like(q.strip()), escape="\\"))
	query = query.order_by(Family.created_at.desc(), Family.id).offset(offset).limit(limit)
	return [AdminFamilyRow(**row) for row in _family_rows(session, query)]


@router.get("/families/{family_id}", response_model=AdminFamilyDetail)
def family_detail(
	family_id: UUID,
	admin=Depends(require_admin_permission("families:read")),
	session: Session = Depends(get_db),
) -> AdminFamilyDetail:
	Family = get_model("Family")
	FamilyMember = get_model("FamilyMember")
	ChildProfile = get_model("ChildProfile")
	User = get_model("User")
	family = session.query(Family).filter(Family.id == family_id).one_or_none()
	if family is None:
		raise _not_found("Family")
	summary = _family_rows(session, session.query(Family).filter(Family.id == family_id))[0]
	parents = (
		session.query(User)
		.join(FamilyMember, FamilyMember.user_id == User.id)
		.filter(FamilyMember.family_id == family_id, FamilyMember.is_active.is_(True), User.role == "parent")
		.order_by(User.full_name)
		.all()
	)
	children = session.query(ChildProfile).filter(ChildProfile.family_id == family_id).order_by(ChildProfile.created_at).all()
	return AdminFamilyDetail(
		**summary,
		timezone=family_timezone_name(session, family_id),
		parents=[
			AdminFamilyParent(user_id=p.id, full_name=p.full_name, email=p.email, is_active=p.is_active) for p in parents
		],
		children=[
			AdminFamilyChild(
				id=c.id, user_id=c.user_id, display_name=c.display_name, is_active=c.is_active, created_at=c.created_at
			)
			for c in children
		],
	)


@router.patch("/children/{child_id}/status", response_model=AdminChildStatus)
def set_child_status(
	child_id: UUID,
	request: ActiveUpdate,
	admin=Depends(require_admin_permission("families:write")),
	session: Session = Depends(get_db),
) -> AdminChildStatus:
	ChildProfile = get_model("ChildProfile")
	User = get_model("User")
	FamilyMember = get_model("FamilyMember")
	child = session.query(ChildProfile).filter(ChildProfile.id == child_id).with_for_update().one_or_none()
	if child is None:
		raise _not_found("Child profile")
	child.is_active = request.is_active
	session.query(User).filter(User.id == child.user_id).update({User.is_active: request.is_active})
	session.query(FamilyMember).filter(
		FamilyMember.family_id == child.family_id, FamilyMember.user_id == child.user_id
	).update({FamilyMember.is_active: request.is_active})
	record_audit(
		session, admin.id, "child.activated" if request.is_active else "child.deactivated", "child", child.id, {}
	)
	session.commit()
	if not request.is_active:
		revoke_user_sessions(session, child.user_id)
	return AdminChildStatus(
		id=child.id, family_id=child.family_id, display_name=child.display_name, is_active=child.is_active
	)


# -- missions, rewards, redemptions -----------------------------------------------------------

@router.get("/tasks", response_model=list[AdminTaskPublic])
def list_tasks(
	family_id: UUID | None = None,
	q: str | None = Query(default=None, max_length=100),
	is_active: bool | None = None,
	limit: int = Query(default=50, ge=1, le=100),
	offset: int = Query(default=0, ge=0),
	admin=Depends(require_admin_permission("tasks:read")),
	session: Session = Depends(get_db),
) -> list[AdminTaskPublic]:
	Task = get_model("Task")
	Family = get_model("Family")
	TaskCategory = get_model("TaskCategory")
	ChildProfile = get_model("ChildProfile")
	query = (
		session.query(Task, Family.family_name, TaskCategory.name, ChildProfile.display_name)
		.join(Family, Family.id == Task.family_id)
		.outerjoin(TaskCategory, TaskCategory.id == Task.category_id)
		.outerjoin(ChildProfile, ChildProfile.id == Task.assigned_child_id)
	)
	if family_id:
		query = query.filter(Task.family_id == family_id)
	if is_active is not None:
		query = query.filter(Task.is_active.is_(is_active))
	if q:
		query = query.filter(Task.title.ilike(_like(q.strip()), escape="\\"))
	rows = query.order_by(Task.created_at.desc(), Task.id).offset(offset).limit(limit).all()
	return [
		AdminTaskPublic(
			id=task.id,
			family_id=task.family_id,
			family_name=family_name,
			title=task.title,
			category_name=category_name,
			assigned_child_name=child_name,
			star_reward=task.star_reward,
			xp_reward=task.xp_reward,
			due_at=task.due_at,
			is_active=task.is_active,
			created_at=task.created_at,
		)
		for task, family_name, category_name, child_name in rows
	]


@router.patch("/tasks/{task_id}/active", response_model=AdminTaskPublic)
def set_task_active(
	task_id: UUID,
	request: ActiveUpdate,
	admin=Depends(require_admin_permission("tasks:write")),
	session: Session = Depends(get_db),
) -> AdminTaskPublic:
	Task = get_model("Task")
	task = session.query(Task).filter(Task.id == task_id).with_for_update().one_or_none()
	if task is None:
		raise _not_found("Task")
	task.is_active = request.is_active
	record_audit(session, admin.id, "task.activated" if request.is_active else "task.deactivated", "task", task.id, {})
	session.commit()
	return _task_row(session, task_id)


def _task_row(session: Session, task_id: UUID) -> AdminTaskPublic:
	Task = get_model("Task")
	Family = get_model("Family")
	TaskCategory = get_model("TaskCategory")
	ChildProfile = get_model("ChildProfile")
	task, family_name, category_name, child_name = (
		session.query(Task, Family.family_name, TaskCategory.name, ChildProfile.display_name)
		.join(Family, Family.id == Task.family_id)
		.outerjoin(TaskCategory, TaskCategory.id == Task.category_id)
		.outerjoin(ChildProfile, ChildProfile.id == Task.assigned_child_id)
		.filter(Task.id == task_id)
		.one()
	)
	return AdminTaskPublic(
		id=task.id,
		family_id=task.family_id,
		family_name=family_name,
		title=task.title,
		category_name=category_name,
		assigned_child_name=child_name,
		star_reward=task.star_reward,
		xp_reward=task.xp_reward,
		due_at=task.due_at,
		is_active=task.is_active,
		created_at=task.created_at,
	)


@router.get("/rewards", response_model=list[AdminRewardPublic])
def list_rewards(
	family_id: UUID | None = None,
	limit: int = Query(default=50, ge=1, le=100),
	offset: int = Query(default=0, ge=0),
	admin=Depends(require_admin_permission("rewards:read")),
	session: Session = Depends(get_db),
) -> list[AdminRewardPublic]:
	Reward = get_model("Reward")
	Family = get_model("Family")
	query = session.query(Reward, Family.family_name).join(Family, Family.id == Reward.family_id)
	if family_id:
		query = query.filter(Reward.family_id == family_id)
	rows = query.order_by(Reward.created_at.desc(), Reward.id).offset(offset).limit(limit).all()
	return [
		AdminRewardPublic(
			id=r.id,
			family_id=r.family_id,
			family_name=name,
			name=r.name,
			reward_type=r.reward_type,
			star_cost=r.star_cost,
			is_active=r.is_active,
			created_at=r.created_at,
		)
		for r, name in rows
	]


@router.patch("/rewards/{reward_id}/active", response_model=AdminRewardPublic)
def set_reward_active(
	reward_id: UUID,
	request: ActiveUpdate,
	admin=Depends(require_admin_permission("rewards:write")),
	session: Session = Depends(get_db),
) -> AdminRewardPublic:
	Reward = get_model("Reward")
	Family = get_model("Family")
	reward = session.query(Reward).filter(Reward.id == reward_id).with_for_update().one_or_none()
	if reward is None:
		raise _not_found("Reward")
	reward.is_active = request.is_active
	record_audit(
		session, admin.id, "reward.activated" if request.is_active else "reward.deactivated", "reward", reward.id, {}
	)
	session.commit()
	family_name = session.query(Family.family_name).filter(Family.id == reward.family_id).scalar()
	return AdminRewardPublic(
		id=reward.id,
		family_id=reward.family_id,
		family_name=family_name,
		name=reward.name,
		reward_type=reward.reward_type,
		star_cost=reward.star_cost,
		is_active=reward.is_active,
		created_at=reward.created_at,
	)


@router.get("/redemptions", response_model=list[AdminRedemptionPublic])
def list_redemptions(
	status_filter: str | None = Query(default=None, alias="status", pattern="^(pending|approved|rejected|fulfilled|cancelled)$"),
	family_id: UUID | None = None,
	limit: int = Query(default=50, ge=1, le=100),
	offset: int = Query(default=0, ge=0),
	admin=Depends(require_admin_permission("redemptions:read")),
	session: Session = Depends(get_db),
) -> list[AdminRedemptionPublic]:
	RedemptionRequest = get_model("RedemptionRequest")
	Reward = get_model("Reward")
	ChildProfile = get_model("ChildProfile")
	Family = get_model("Family")
	query = (
		session.query(RedemptionRequest, Reward.name, ChildProfile.display_name, Family.id, Family.family_name)
		.join(Reward, Reward.id == RedemptionRequest.reward_id)
		.join(ChildProfile, ChildProfile.id == RedemptionRequest.child_id)
		.join(Family, Family.id == ChildProfile.family_id)
	)
	if status_filter:
		query = query.filter(RedemptionRequest.status == status_filter)
	if family_id:
		query = query.filter(Family.id == family_id)
	rows = query.order_by(RedemptionRequest.requested_at.desc(), RedemptionRequest.id).offset(offset).limit(limit).all()
	return [
		AdminRedemptionPublic(
			id=r.id,
			family_id=fid,
			family_name=fname,
			reward_name=reward_name,
			child_name=child_name,
			status=r.status,
			star_cost_at_request=r.star_cost_at_request,
			requested_at=r.requested_at,
			reviewed_at=r.reviewed_at,
		)
		for r, reward_name, child_name, fid, fname in rows
	]


# -- categories and presets ----------------------------------------------------------------

@router.get("/task-categories", response_model=list[AdminTaskCategoryPublic])
def list_task_categories(
	admin=Depends(require_admin_permission("content:read")),
	session: Session = Depends(get_db),
) -> list[AdminTaskCategoryPublic]:
	TaskCategory = get_model("TaskCategory")
	return [AdminTaskCategoryPublic.model_validate(c) for c in session.query(TaskCategory).order_by(TaskCategory.name).all()]


@router.patch("/task-categories/{category_id}", response_model=AdminTaskCategoryPublic)
def update_task_category(
	category_id: UUID,
	request: TaskCategoryUpdate,
	admin=Depends(require_admin_permission("content:write")),
	session: Session = Depends(get_db),
) -> AdminTaskCategoryPublic:
	TaskCategory = get_model("TaskCategory")
	category = session.query(TaskCategory).filter(TaskCategory.id == category_id).with_for_update().one_or_none()
	if category is None:
		raise _not_found("Category")
	updates = request.model_dump(exclude_unset=True)
	if updates.get("name") is None and "name" in updates or updates.get("is_active") is None and "is_active" in updates:
		raise HTTPException(status_code=422, detail="name and is_active cannot be cleared")
	if "name" in updates:
		updates["name"] = updates["name"].strip()
	for field, value in updates.items():
		setattr(category, field, value)
	record_audit(session, admin.id, "task_category.updated", "task_category", category.id, {"fields": sorted(updates)})
	try:
		session.commit()
	except IntegrityError as error:
		session.rollback()
		raise HTTPException(status_code=409, detail="A task category with that name already exists") from error
	session.refresh(category)
	return AdminTaskCategoryPublic.model_validate(category)


def _preset_public(preset, category_name: str | None) -> PresetTaskPublic:
	data = PresetTaskPublic.model_validate(preset)
	data.category_name = category_name
	return data


def _category_name(session: Session, category_id: UUID | None) -> str | None:
	if category_id is None:
		return None
	TaskCategory = get_model("TaskCategory")
	name = session.query(TaskCategory.name).filter(TaskCategory.id == category_id).scalar()
	if name is None:
		raise HTTPException(status_code=404, detail="Task category not found")
	return name


@router.get("/preset-tasks", response_model=list[PresetTaskPublic])
def list_preset_tasks(
	limit: int = Query(default=100, ge=1, le=200),
	offset: int = Query(default=0, ge=0),
	admin=Depends(require_admin_permission("content:read")),
	session: Session = Depends(get_db),
) -> list[PresetTaskPublic]:
	PresetTask = get_model("PresetTask")
	TaskCategory = get_model("TaskCategory")
	rows = (
		session.query(PresetTask, TaskCategory.name)
		.outerjoin(TaskCategory, TaskCategory.id == PresetTask.category_id)
		.order_by(PresetTask.created_at.desc(), PresetTask.id)
		.offset(offset)
		.limit(limit)
		.all()
	)
	return [_preset_public(preset, name) for preset, name in rows]


@router.post("/preset-tasks", response_model=PresetTaskPublic, status_code=status.HTTP_201_CREATED)
def create_preset_task(
	request: PresetTaskCreate,
	admin=Depends(require_admin_permission("content:write")),
	session: Session = Depends(get_db),
) -> PresetTaskPublic:
	PresetTask = get_model("PresetTask")
	category_name = _category_name(session, request.category_id)
	now = datetime.now(timezone.utc)
	preset = PresetTask(
		**request.model_dump(exclude={"title"}),
		title=request.title.strip(),
		is_active=True,
		created_by=admin.id,
		created_at=now,
		updated_at=now,
	)
	session.add(preset)
	session.flush()
	record_audit(session, admin.id, "preset_task.created", "preset_task", preset.id, {})
	session.commit()
	session.refresh(preset)
	return _preset_public(preset, category_name)


@router.patch("/preset-tasks/{preset_id}", response_model=PresetTaskPublic)
def update_preset_task(
	preset_id: UUID,
	request: PresetTaskUpdate,
	admin=Depends(require_admin_permission("content:write")),
	session: Session = Depends(get_db),
) -> PresetTaskPublic:
	PresetTask = get_model("PresetTask")
	preset = session.query(PresetTask).filter(PresetTask.id == preset_id).with_for_update().one_or_none()
	if preset is None:
		raise _not_found("Preset task")
	updates = request.model_dump(exclude_unset=True)
	for required in ("title", "language_code", "suggested_star_reward", "suggested_xp_reward", "age_min", "age_max", "is_active"):
		if required in updates and updates[required] is None:
			raise HTTPException(status_code=422, detail=f"{required} cannot be cleared")
	if "category_id" in updates:
		_category_name(session, updates["category_id"])
	for field, value in updates.items():
		setattr(preset, field, value.strip() if field == "title" else value)
	if preset.age_max < preset.age_min:
		raise HTTPException(status_code=422, detail="age_max must not be below age_min")
	preset.updated_at = datetime.now(timezone.utc)
	record_audit(session, admin.id, "preset_task.updated", "preset_task", preset.id, {"fields": sorted(updates)})
	session.commit()
	session.refresh(preset)
	return _preset_public(preset, _category_name(session, preset.category_id))


# -- badges and educational content ----------------------------------------------------------

@router.patch("/badges/{badge_id}", response_model=AdminBadgePublic)
def update_badge(
	badge_id: UUID,
	request: BadgeUpdate,
	admin=Depends(require_admin_permission("badges:write")),
	session: Session = Depends(get_db),
) -> AdminBadgePublic:
	Badge = get_model("Badge")
	badge = session.query(Badge).filter(Badge.id == badge_id).with_for_update().one_or_none()
	if badge is None:
		raise _not_found("Badge")
	updates = request.model_dump(exclude_unset=True)
	threshold = updates.pop("threshold", None)
	if "icon_url" in updates:
		updates["icon_url"] = str(updates["icon_url"]) if updates["icon_url"] else None
	for required in ("name", "criteria_type", "is_active"):
		if required in updates and updates[required] is None:
			raise HTTPException(status_code=422, detail=f"{required} cannot be cleared")
	for field, value in updates.items():
		setattr(badge, field, value.strip() if field == "name" else value)
	if threshold is not None:
		badge.criteria_value = {"threshold": threshold}
	record_audit(session, admin.id, "badge.updated", "badge", badge.id, {"fields": sorted(updates)})
	try:
		session.commit()
	except IntegrityError as error:
		session.rollback()
		raise HTTPException(status_code=409, detail="A badge with that name already exists") from error
	session.refresh(badge)
	return AdminBadgePublic.model_validate(badge)


@router.patch("/educational-content/{content_id}", response_model=EducationalContentAdminPublic)
def update_educational_content(
	content_id: UUID,
	request: EducationalContentUpdate,
	admin=Depends(require_admin_permission("content:write")),
	session: Session = Depends(get_db),
) -> EducationalContentAdminPublic:
	Content = get_model("EducationalContent")
	item = session.query(Content).filter(Content.id == content_id).with_for_update().one_or_none()
	if item is None:
		raise _not_found("Educational content")
	updates = request.model_dump(exclude_unset=True)
	for required in ("title", "content_type", "language_code", "requires_entitlement", "is_active"):
		if required in updates and updates[required] is None:
			raise HTTPException(status_code=422, detail=f"{required} cannot be cleared")
	for url_field in ("content_url", "thumbnail_url"):
		if url_field in updates:
			updates[url_field] = str(updates[url_field]) if updates[url_field] else None
	for field, value in updates.items():
		setattr(item, field, value.strip() if field == "title" else value)
	if item.requires_entitlement and not (item.video_id or item.collection_id):
		raise HTTPException(status_code=422, detail="Entitlement-required content must reference a video or collection")
	if item.content_type == "video" and not (item.video_id or item.collection_id or item.content_url):
		raise HTTPException(status_code=422, detail="Video content requires a video, collection, or URL")
	item.updated_at = datetime.now(timezone.utc)
	record_audit(session, admin.id, "educational_content.updated", "educational_content", item.id, {"fields": sorted(updates)})
	session.commit()
	session.refresh(item)
	return EducationalContentAdminPublic.model_validate(item)


# -- roles ---------------------------------------------------------------------------------------

@router.post("/users/{user_id}/roles", status_code=status.HTTP_204_NO_CONTENT)
def assign_role(
	user_id: UUID,
	request: RoleAssignment,
	admin=Depends(require_admin_permission("admin_roles:write")),
	session: Session = Depends(get_db),
) -> Response:
	User = get_model("User")
	AdminRole = get_model("AdminRole")
	UserAdminRole = get_model("UserAdminRole")
	user = session.query(User).filter(User.id == user_id).one_or_none()
	if user is None:
		raise _not_found("User")
	if user.role not in {"admin", "staff"}:
		raise HTTPException(status_code=422, detail="Only admin or staff accounts can hold administrator roles")
	if session.query(AdminRole.id).filter(AdminRole.id == request.role_id).first() is None:
		raise _not_found("Role")
	exists = session.query(UserAdminRole).filter(
		UserAdminRole.user_id == user_id, UserAdminRole.admin_role_id == request.role_id
	).first()
	if exists is None:
		session.add(UserAdminRole(user_id=user_id, admin_role_id=request.role_id, assigned_by=admin.id))
		record_audit(session, admin.id, "admin_role.assigned", "user", user_id, {"role_id": str(request.role_id)})
		session.commit()
	return Response(status_code=status.HTTP_204_NO_CONTENT)


@router.delete("/users/{user_id}/roles/{role_id}", status_code=status.HTTP_204_NO_CONTENT)
def remove_role(
	user_id: UUID,
	role_id: UUID,
	admin=Depends(require_admin_permission("admin_roles:write")),
	session: Session = Depends(get_db),
) -> Response:
	AdminRole = get_model("AdminRole")
	UserAdminRole = get_model("UserAdminRole")
	assignment = (
		session.query(UserAdminRole)
		.filter(UserAdminRole.user_id == user_id, UserAdminRole.admin_role_id == role_id)
		.with_for_update()
		.one_or_none()
	)
	if assignment is None:
		return Response(status_code=status.HTTP_204_NO_CONTENT)
	role = session.query(AdminRole).filter(AdminRole.id == role_id).one()
	if "*" in (role.permissions or []):
		holders = session.query(func.count(UserAdminRole.user_id)).filter(UserAdminRole.admin_role_id == role_id).scalar()
		if int(holders or 0) <= 1:
			raise APIError(409, "last_super_admin", "At least one super administrator must remain")
	session.delete(assignment)
	record_audit(session, admin.id, "admin_role.removed", "user", user_id, {"role_id": str(role_id)})
	session.commit()
	return Response(status_code=status.HTTP_204_NO_CONTENT)


# -- application settings -----------------------------------------------------------------------------

@router.get("/settings", response_model=list[SettingPublic])
def list_settings(
	admin=Depends(require_admin_permission("settings:read")),
	session: Session = Depends(get_db),
) -> list[SettingPublic]:
	values, overridden = read_all(session)
	return [SettingPublic(key=key, value=values[key], overridden=key in overridden) for key in DEFAULTS]


@router.put("/settings/{key}", response_model=SettingPublic)
def put_setting(
	key: str,
	request: SettingValue,
	admin=Depends(require_admin_permission("settings:write")),
	session: Session = Depends(get_db),
) -> SettingPublic:
	row = write_setting(session, admin.id, key, request.value)
	record_audit(session, admin.id, "app_setting.updated", "app_setting", None, {"key": key})
	session.commit()
	return SettingPublic(key=key, value=row.value, overridden=True)


# -- analytics ----------------------------------------------------------------------------------------

@router.get("/analytics/overview", response_model=AnalyticsOverview)
def analytics_overview(
	days: int = Query(default=30, ge=1, le=365),
	admin=Depends(require_admin_permission("reports:read")),
	session: Session = Depends(get_db),
) -> AnalyticsOverview:
	User = get_model("User")
	TaskSubmission = get_model("TaskSubmission")
	RedemptionRequest = get_model("RedemptionRequest")
	Task = get_model("Task")
	TaskCategory = get_model("TaskCategory")
	today = datetime.now(timezone.utc).date()
	first_day = today - timedelta(days=days - 1)
	start = datetime.combine(first_day, datetime.min.time(), tzinfo=timezone.utc)

	def bucket(column, *conditions) -> dict[str, int]:
		day = func.date(func.timezone("UTC", column))
		rows = session.query(day, func.count()).filter(column >= start, *conditions).group_by(day).all()
		return {str(d): int(c) for d, c in rows}

	new_users = bucket(User.created_at)
	submissions = bucket(TaskSubmission.submitted_at)
	approvals = bucket(TaskSubmission.reviewed_at, TaskSubmission.status == "approved")
	daily = []
	for index in range(days):
		key = str(first_day + timedelta(days=index))
		daily.append(
			DailyCount(
				date=key,
				new_users=new_users.get(key, 0),
				submissions=submissions.get(key, 0),
				approvals=approvals.get(key, 0),
			)
		)
	rejections = (
		session.query(func.count(TaskSubmission.id))
		.filter(TaskSubmission.reviewed_at >= start, TaskSubmission.status.in_(["rejected", "resubmission_requested"]))
		.scalar()
	)
	redemption_counts = dict(
		session.query(RedemptionRequest.status, func.count(RedemptionRequest.id)).group_by(RedemptionRequest.status).all()
	)
	statuses = {name: int(redemption_counts.get(name, 0)) for name in ["pending", "approved", "rejected", "fulfilled", "cancelled"]}
	redemptions_in_period = (
		session.query(func.count(RedemptionRequest.id)).filter(RedemptionRequest.requested_at >= start).scalar()
	)
	top = (
		session.query(TaskCategory.name, func.count(TaskSubmission.id))
		.join(Task, Task.category_id == TaskCategory.id)
		.join(TaskSubmission, TaskSubmission.task_id == Task.id)
		.filter(TaskSubmission.reviewed_at >= start, TaskSubmission.status == "approved")
		.group_by(TaskCategory.name)
		.order_by(func.count(TaskSubmission.id).desc(), TaskCategory.name)
		.limit(5)
		.all()
	)
	return AnalyticsOverview(
		period_days=days,
		totals=AnalyticsTotals(
			new_users=sum(new_users.values()),
			submissions=sum(submissions.values()),
			approvals=sum(approvals.values()),
			rejections=int(rejections or 0),
			redemptions=int(redemptions_in_period or 0),
		),
		daily=daily,
		redemptions_by_status=statuses,
		top_categories=[{"name": name, "approved_tasks": int(count)} for name, count in top],
	)
