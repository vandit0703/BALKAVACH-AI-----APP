from uuid import UUID

from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session

from app.core.dependencies import require_parent
from app.db.session import get_db
from app.schemas.task import TaskReviewCreate, TaskSubmissionPublic
from app.services.task_service import review_submission

router = APIRouter(prefix="/reviews", tags=["task reviews"])


@router.post("/submissions/{submission_id}", response_model=TaskSubmissionPublic)
def review_task_submission(
	submission_id: UUID,
	request: TaskReviewCreate,
	parent=Depends(require_parent),
	session: Session = Depends(get_db),
) -> TaskSubmissionPublic:
	submission = review_submission(session, submission_id, parent, request)
	return TaskSubmissionPublic.model_validate(submission)
