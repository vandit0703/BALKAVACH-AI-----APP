from typing import Literal
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy.orm import Session

from app.core.dependencies import require_parent
from app.db.base import get_model
from app.db.session import get_db
from app.schemas.task import PendingSubmissionPublic, TaskReviewCreate, TaskSubmissionPublic
from app.services.task_service import review_submission

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
	return [
		PendingSubmissionPublic(
			**TaskSubmissionPublic.model_validate(submission).model_dump(),
			family_id=task.family_id,
			task_title=task.title,
			category_name=category_name,
			child_name=child.display_name,
			star_reward=task.star_reward,
			xp_reward=task.xp_reward,
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


@router.post("/submissions/{submission_id}", response_model=TaskSubmissionPublic)
def review_task_submission(
	submission_id: UUID,
	request: TaskReviewCreate,
	parent=Depends(require_parent),
	session: Session = Depends(get_db),
) -> TaskSubmissionPublic:
	submission = review_submission(session, submission_id, parent, request)
	return TaskSubmissionPublic.model_validate(submission)
