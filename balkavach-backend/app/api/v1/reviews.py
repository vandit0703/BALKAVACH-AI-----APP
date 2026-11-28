from typing import Literal
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy import func
from sqlalchemy.orm import Session

from app.core.dependencies import require_parent
from app.db.base import get_model, has_model
from app.db.session import get_db
from app.schemas.task import PendingSubmissionPublic, TaskReviewCreate, TaskReviewResultPublic, TaskSubmissionPublic
from app.services.mission_rewards import effective_star_reward, effective_xp_reward
from app.services.task_service import review_submission
from app.services.video_entitlement_service import offered_reward_seconds

SubmissionStatus = Literal["pending", "approved", "rejected", "resubmission_requested", "cancelled"]

router = APIRouter(prefix="/reviews", tags=["task reviews"])


def _review_queue(
	session: Session,
	parent,
	family_id: UUID,
	statuses: list[str] | None,
	limit: int,
	offset: int,
	oldest_first: bool,
) -> list[PendingSubmissionPublic]:
	FamilyMember = get_model("FamilyMember")
	if not session.query(FamilyMember.id).filter(
		FamilyMember.family_id == family_id,
		FamilyMember.user_id == parent.id,
		FamilyMember.is_active.is_(True),
	).first():
		raise HTTPException(status_code=404, detail="Family not found")
	TaskSubmission = get_model("TaskSubmission")
	Task = get_model("Task")
	TaskCategory = get_model("TaskCategory")
	ChildProfile = get_model("ChildProfile")
	query = (
		session.query(TaskSubmission, Task, ChildProfile, TaskCategory.name)
		.join(Task, Task.id == TaskSubmission.task_id)
		.join(ChildProfile, ChildProfile.id == TaskSubmission.child_id)
		.outerjoin(TaskCategory, TaskCategory.id == Task.category_id)
		.filter(Task.family_id == family_id)
	)
	if statuses:
		query = query.filter(TaskSubmission.status.in_(statuses))
	order = TaskSubmission.submitted_at.asc() if oldest_first else TaskSubmission.submitted_at.desc()
	rows = query.order_by(order, TaskSubmission.id).offset(offset).limit(limit).all()
	verified_seconds: dict[tuple[UUID, UUID], int] = {}
	if rows and has_model("MissionVideoWatchSession"):
		Watch = get_model("MissionVideoWatchSession")
		for task_id, child_id, seconds in session.query(
			Watch.task_id,
			Watch.child_id,
			func.coalesce(func.sum(Watch.watched_seconds), 0),
		).filter(
			Watch.task_id.in_({task.id for _, task, _, _ in rows}),
			Watch.child_id.in_({submission.child_id for submission, _, _, _ in rows}),
		).group_by(Watch.task_id, Watch.child_id).all():
			verified_seconds[(task_id, child_id)] = int(seconds or 0)
	return [
		PendingSubmissionPublic(
			**TaskSubmissionPublic.model_validate(submission).model_dump(),
			family_id=task.family_id,
			task_title=task.title,
			category_name=category_name,
			child_name=child.display_name,
			star_reward=effective_star_reward(task.star_reward),
			xp_reward=effective_xp_reward(task.xp_reward),
			video_minutes_reward=offered_reward_seconds(task) // 60,
			video_seconds_reward=offered_reward_seconds(task),
			required_video_seconds=getattr(task, "required_video_seconds", None),
			verified_video_seconds=verified_seconds.get((task.id, submission.child_id), 0),
		)
		for submission, task, child, category_name in rows
	]


@router.get("/pending", response_model=list[PendingSubmissionPublic])
def list_pending_submissions(
	family_id: UUID,
	limit: int = Query(default=50, ge=1, le=100),
	offset: int = Query(default=0, ge=0),
	parent=Depends(require_parent),
	session: Session = Depends(get_db),
) -> list[PendingSubmissionPublic]:
	return _review_queue(session, parent, family_id, ["pending"], limit, offset, oldest_first=True)


@router.get("/submissions", response_model=list[PendingSubmissionPublic])
def list_family_submissions(
	family_id: UUID,
	status_filter: list[SubmissionStatus] | None = Query(default=None, alias="status"),
	limit: int = Query(default=50, ge=1, le=100),
	offset: int = Query(default=0, ge=0),
	parent=Depends(require_parent),
	session: Session = Depends(get_db),
) -> list[PendingSubmissionPublic]:
	"""Newest first; repeat ``status`` to combine statuses, omit it for all."""
	return _review_queue(
		session, parent, family_id, [str(item) for item in status_filter] if status_filter else None, limit, offset, False
	)


@router.post("/submissions/{submission_id}", response_model=TaskReviewResultPublic)
def review_task_submission(
	submission_id: UUID,
	request: TaskReviewCreate,
	parent=Depends(require_parent),
	session: Session = Depends(get_db),
) -> TaskReviewResultPublic:
	submission = review_submission(session, submission_id, parent, request)
	# What was actually granted comes from the entitlement ledger (also for a repeated, idempotent approval).
	Task = get_model("Task")
	task = session.get(Task, submission.task_id)
	granted = 0
	if submission.status == "approved" and has_model("VideoAccessEntitlement"):
		Entitlement = get_model("VideoAccessEntitlement")
		if hasattr(Entitlement, "submission_id"):
			granted = int(
				session.query(func.coalesce(func.sum(Entitlement.granted_seconds), 0))
				.filter(Entitlement.submission_id == submission.id)
				.scalar()
				or 0
			)
	return TaskReviewResultPublic(
		**TaskSubmissionPublic.model_validate(submission).model_dump(),
		video_seconds_reward=offered_reward_seconds(task) if task is not None else 0,
		video_seconds_granted=granted,
	)
