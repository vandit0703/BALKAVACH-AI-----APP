from typing import Literal
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, Query, Request, status
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from app.core.dependencies import get_current_user, require_admin_permission, require_child, require_parent
from app.db.base import get_model
from app.db.session import get_db
from app.schemas.admin_manage import PresetTaskPublic
from app.schemas.task import (
	TaskCategoryCreate,
	TaskCategoryPublic,
	MySubmissionPublic,
	MissionVideoProgressPublic,
	MissionVideoWatchHeartbeatRequest,
	MissionVideoWatchPublic,
	MissionVideoWatchStartRequest,
	TaskCreate,
	TaskPublic,
	TaskSubmissionCreate,
	TaskSubmissionPublic,
	TaskUpdate,
)
from app.schemas.video import VideoFeedItem
from app.services.child_age import child_age_band_or_none, ineligible_daily_task_ids
from app.services.daily_mission_service import localized_task_fields
from app.services.mission_rewards import MISSION_STAR_REWARD, MISSION_XP_REWARD
from app.services.display_locale import resolve_display_locale
from app.services.ledger_service import awarded_by_submission
from app.services.mission_video_service import (
	get_mission_video_progress,
	interrupt_mission_video_watch,
	record_mission_video_heartbeat,
	start_mission_video_watch,
)
from app.services.notification_service import notify_task_assigned
from app.services.task_service import submit_completion
from app.utils import utc_naive

router = APIRouter(prefix="/tasks", tags=["tasks"])


def _require_family(session: Session, family_id: UUID, user_id: UUID) -> None:
	FamilyMember = get_model("FamilyMember")
	member = session.query(FamilyMember.id).filter(
		FamilyMember.family_id == family_id,
		FamilyMember.user_id == user_id,
		FamilyMember.is_active.is_(True),
	).first()
	if member is None:
		raise HTTPException(status_code=404, detail="Family not found")


@router.get("/categories", response_model=list[TaskCategoryPublic])
def list_categories(
	user=Depends(get_current_user),
	session: Session = Depends(get_db),
) -> list[TaskCategoryPublic]:
	TaskCategory = get_model("TaskCategory")
	categories = session.query(TaskCategory).filter(TaskCategory.is_active.is_(True)).order_by(TaskCategory.name).all()
	return [TaskCategoryPublic.model_validate(category) for category in categories]


@router.get("/presets", response_model=list[PresetTaskPublic])
def list_presets(
	request: Request,
	language: str | None = Query(default=None, min_length=2, max_length=10),
	category_id: UUID | None = None,
	limit: int = Query(default=100, ge=1, le=200),
	offset: int = Query(default=0, ge=0),
	parent=Depends(require_parent),
	session: Session = Depends(get_db),
) -> list[PresetTaskPublic]:
	"""Active preset missions in the selected/requested language first, then English."""
	PresetTask = get_model("PresetTask")
	TaskCategory = get_model("TaskCategory")
	chosen = language or resolve_display_locale(request, parent)
	languages = [chosen] if chosen == "en" else [chosen, "en"]
	query = (
		session.query(PresetTask, TaskCategory.name)
		.outerjoin(TaskCategory, TaskCategory.id == PresetTask.category_id)
		.filter(PresetTask.is_active.is_(True), PresetTask.language_code.in_(languages))
	)
	if category_id:
		query = query.filter(PresetTask.category_id == category_id)
	rows = query.order_by(PresetTask.title).all()
	rows.sort(key=lambda row: languages.index(row[0].language_code))
	presets = []
	for preset, category_name in rows[offset : offset + limit]:
		item = PresetTaskPublic.model_validate(preset)
		item.category_name = category_name
		presets.append(item)
	return presets


@router.post("/categories", response_model=TaskCategoryPublic, status_code=status.HTTP_201_CREATED)
def create_category(
	request: TaskCategoryCreate,
	admin=Depends(require_admin_permission("content:write")),
	session: Session = Depends(get_db),
) -> TaskCategoryPublic:
	TaskCategory = get_model("TaskCategory")
	category = TaskCategory(
		name=request.name.strip(),
		description=request.description,
		icon_name=request.icon_name,
		is_default=False,
		is_active=True,
	)
	session.add(category)
	try:
		session.commit()
		session.refresh(category)
	except IntegrityError as error:
		session.rollback()
		raise HTTPException(status_code=409, detail="A task category with that name already exists") from error
	return TaskCategoryPublic.model_validate(category)


@router.post("", response_model=TaskPublic, status_code=status.HTTP_201_CREATED)
def create_task(
	request: TaskCreate,
	parent=Depends(require_parent),
	session: Session = Depends(get_db),
) -> TaskPublic:
	_require_family(session, request.family_id, parent.id)
	if request.category_id is not None:
		TaskCategory = get_model("TaskCategory")
		category = session.query(TaskCategory.id).filter(
			TaskCategory.id == request.category_id,
			TaskCategory.is_active.is_(True),
		).first()
		if category is None:
			raise HTTPException(status_code=404, detail="Task category not found")
	ChildProfile = get_model("ChildProfile")
	if request.assigned_child_id and not session.query(ChildProfile.id).filter(
		ChildProfile.id == request.assigned_child_id,
		ChildProfile.family_id == request.family_id,
		ChildProfile.is_active.is_(True),
	).first():
		raise HTTPException(status_code=404, detail="Child profile not found")
	Task = get_model("Task")
	task = Task(
		family_id=request.family_id,
		category_id=request.category_id,
		created_by=parent.id,
		assigned_child_id=request.assigned_child_id,
		title=request.title.strip(),
		description=request.description,
		xp_reward=MISSION_XP_REWARD,
		star_reward=MISSION_STAR_REWARD,
		required_video_seconds=request.required_video_seconds,
		due_at=utc_naive(request.due_at) if request.due_at else None,
		repeat_rule=request.repeat_rule,
		is_custom=True,
		is_active=True,
	)
	session.add(task)
	session.flush()
	notify_task_assigned(session, task)
	session.commit()
	session.refresh(task)
	return TaskPublic.model_validate(task)


@router.get("", response_model=list[TaskPublic])
def list_tasks(
	request: Request,
	family_id: UUID | None = None,
	limit: int = Query(default=50, ge=1, le=100),
	offset: int = Query(default=0, ge=0),
	user=Depends(get_current_user),
	session: Session = Depends(get_db),
) -> list[TaskPublic]:
	Task = get_model("Task")
	query = session.query(Task).filter(Task.is_active.is_(True))
	child = None
	if user.role == "parent":
		FamilyMember = get_model("FamilyMember")
		family_ids = session.query(FamilyMember.family_id).filter(
			FamilyMember.user_id == user.id,
			FamilyMember.is_active.is_(True),
		)
		if family_id:
			_require_family(session, family_id, user.id)
			family_ids = [family_id]
		query = query.filter(Task.family_id.in_(family_ids))
	elif user.role == "child":
		ChildProfile = get_model("ChildProfile")
		child = session.query(ChildProfile).filter(
			ChildProfile.user_id == user.id,
			ChildProfile.is_active.is_(True),
		).one_or_none()
		if child is None or (family_id and family_id != child.family_id):
			raise HTTPException(status_code=404, detail="Tasks not found")
		query = query.filter(
			Task.family_id == child.family_id,
			(Task.assigned_child_id.is_(None)) | (Task.assigned_child_id == child.id),
			# Daily missions chosen for another age group are history, not current missions (child_age).
			Task.id.notin_(ineligible_daily_task_ids(session, child, child_age_band_or_none(session, child))),
		)
	else:
		raise HTTPException(status_code=403, detail="Task access denied")
	tasks = query.order_by(Task.created_at.desc(), Task.id).offset(offset).limit(limit).all()
	display_locale = resolve_display_locale(request, user)
	overrides = localized_task_fields(session, tasks, display_locale)
	result: list[TaskPublic] = []
	for task in tasks:
		item = TaskPublic.model_validate(task)
		override = overrides.get(task.id)
		if override:
			item = item.model_copy(update=override)
		result.append(item)
	return result


@router.patch("/{task_id}", response_model=TaskPublic)
def update_task(
	task_id: UUID,
	request: TaskUpdate,
	parent=Depends(require_parent),
	session: Session = Depends(get_db),
) -> TaskPublic:
	Task = get_model("Task")
	task = session.query(Task).filter(Task.id == task_id, Task.is_active.is_(True)).with_for_update().one_or_none()
	if task is None:
		raise HTTPException(status_code=404, detail="Task not found")
	_require_family(session, task.family_id, parent.id)
	updates = request.model_dump(exclude_unset=True)
	if updates.get("due_at") is not None:
		updates["due_at"] = utc_naive(updates["due_at"])
	if "assigned_child_id" in updates and updates["assigned_child_id"] is not None:
		ChildProfile = get_model("ChildProfile")
		if not session.query(ChildProfile.id).filter(
			ChildProfile.id == updates["assigned_child_id"],
			ChildProfile.family_id == task.family_id,
			ChildProfile.is_active.is_(True),
		).first():
			raise HTTPException(status_code=404, detail="Child profile not found")
	reassigned = updates.get("assigned_child_id") is not None and updates["assigned_child_id"] != task.assigned_child_id
	for field, value in updates.items():
		setattr(task, field, value)
	if reassigned:
		notify_task_assigned(session, task)
	session.commit()
	session.refresh(task)
	return TaskPublic.model_validate(task)


@router.get("/{task_id}/video-watch", response_model=MissionVideoProgressPublic)
def get_task_video_progress(
	task_id: UUID,
	child=Depends(require_child),
	session: Session = Depends(get_db),
) -> MissionVideoProgressPublic:
	return MissionVideoProgressPublic(**get_mission_video_progress(session, task_id, child))


@router.get("/{task_id}/video-catalogue", response_model=list[VideoFeedItem])
def get_task_video_catalogue(
	task_id: UUID,
	limit: int = Query(default=30, ge=1, le=50),
	child=Depends(require_child),
	session: Session = Depends(get_db),
) -> list[VideoFeedItem]:
	from app.api.v1.videos import _channel_names, _feed_item
	from app.services.video_service import eligible_feed

	task = get_model("Task")
	row = session.query(task).filter(task.id == task_id, task.is_active.is_(True)).one_or_none()
	if row is None or row.family_id != child.family_id or (
		row.assigned_child_id is not None and row.assigned_child_id != child.id
	):
		raise HTTPException(status_code=404, detail="Mission not found")
	if not row.required_video_seconds:
		raise HTTPException(status_code=409, detail="This mission has no video requirement")
	videos = eligible_feed(session, child, None, limit, 0, video_format="regular")
	channels = _channel_names(session, videos) if any(v.video_source == "youtube" for v in videos) else {}
	return [_feed_item(video, channels.get(video.id), playback_locked=False) for video in videos]


@router.post("/{task_id}/video-watch/sessions", response_model=MissionVideoWatchPublic, status_code=201)
def begin_task_video_watch(
	task_id: UUID,
	request: MissionVideoWatchStartRequest,
	child=Depends(require_child),
	session: Session = Depends(get_db),
) -> MissionVideoWatchPublic:
	return MissionVideoWatchPublic(**start_mission_video_watch(
		session, task_id, child, request.video_id, request.client_session_id
	))


@router.post("/video-watch/sessions/{session_id}/heartbeats", response_model=MissionVideoWatchPublic)
def task_video_watch_heartbeat(
	session_id: UUID,
	request: MissionVideoWatchHeartbeatRequest,
	child=Depends(require_child),
	session: Session = Depends(get_db),
) -> MissionVideoWatchPublic:
	return MissionVideoWatchPublic(**record_mission_video_heartbeat(
		session, session_id, child, request.sequence, request.position_seconds, request.is_playing
	))


@router.post("/video-watch/sessions/{session_id}/interrupt", response_model=MissionVideoWatchPublic)
def task_video_watch_interrupt(
	session_id: UUID,
	child=Depends(require_child),
	session: Session = Depends(get_db),
) -> MissionVideoWatchPublic:
	return MissionVideoWatchPublic(**interrupt_mission_video_watch(session, session_id, child))


@router.delete("/{task_id}", status_code=status.HTTP_204_NO_CONTENT)
def deactivate_task(
	task_id: UUID,
	parent=Depends(require_parent),
	session: Session = Depends(get_db),
) -> None:
	Task = get_model("Task")
	task = session.query(Task).filter(Task.id == task_id, Task.is_active.is_(True)).with_for_update().one_or_none()
	if task is None:
		raise HTTPException(status_code=404, detail="Task not found")
	_require_family(session, task.family_id, parent.id)
	task.is_active = False
	session.commit()


@router.post("/{task_id}/submissions", response_model=TaskSubmissionPublic, status_code=status.HTTP_201_CREATED)
def submit_task(
	task_id: UUID,
	request: TaskSubmissionCreate,
	child=Depends(require_child),
	session: Session = Depends(get_db),
) -> TaskSubmissionPublic:
	submission = submit_completion(session, task_id, child, request)
	return TaskSubmissionPublic.model_validate(submission)


@router.get("/submissions/mine", response_model=list[MySubmissionPublic])
def list_my_submissions(
	status_filter: Literal["pending", "approved", "rejected", "resubmission_requested", "cancelled"] | None = Query(
		default=None, alias="status"
	),
	limit: int = Query(default=50, ge=1, le=100),
	offset: int = Query(default=0, ge=0),
	child=Depends(require_child),
	session: Session = Depends(get_db),
) -> list[MySubmissionPublic]:
	TaskSubmission = get_model("TaskSubmission")
	Task = get_model("Task")
	TaskReview = get_model("TaskReview")
	query = (
		session.query(TaskSubmission, Task.title)
		.join(Task, Task.id == TaskSubmission.task_id)
		.filter(TaskSubmission.child_id == child.id)
	)
	if status_filter:
		query = query.filter(TaskSubmission.status == status_filter)
	rows = query.order_by(TaskSubmission.submitted_at.desc(), TaskSubmission.id).offset(offset).limit(limit).all()
	notes: dict = {}
	if rows:
		reviews = (
			session.query(TaskReview.submission_id, TaskReview.review_note, TaskReview.created_at)
			.filter(TaskReview.submission_id.in_([submission.id for submission, _ in rows]))
			.order_by(TaskReview.created_at.asc())
			.all()
		)
		notes = {submission_id: note for submission_id, note, _ in reviews}
		awarded = awarded_by_submission(session, [submission.id for submission, _ in rows])
	else:
		awarded = {}
	return [
		MySubmissionPublic(
			**TaskSubmissionPublic.model_validate(submission).model_dump(),
			task_title=title,
			review_note=notes.get(submission.id),
			stars_awarded=awarded.get(submission.id, (0, 0))[0],
			xp_awarded=awarded.get(submission.id, (0, 0))[1],
		)
		for submission, title in rows
	]


@router.get("/{task_id}/submissions", response_model=list[TaskSubmissionPublic])
def list_task_submissions(
	task_id: UUID,
	limit: int = Query(default=50, ge=1, le=100),
	offset: int = Query(default=0, ge=0),
	parent=Depends(require_parent),
	session: Session = Depends(get_db),
) -> list[TaskSubmissionPublic]:
	Task = get_model("Task")
	task = session.query(Task).filter(Task.id == task_id).one_or_none()
	if task is None:
		raise HTTPException(status_code=404, detail="Task not found")
	_require_family(session, task.family_id, parent.id)
	TaskSubmission = get_model("TaskSubmission")
	submissions = session.query(TaskSubmission).filter(TaskSubmission.task_id == task_id).order_by(
		TaskSubmission.submitted_at.desc()
	).offset(offset).limit(limit).all()
	return [TaskSubmissionPublic.model_validate(submission) for submission in submissions]
