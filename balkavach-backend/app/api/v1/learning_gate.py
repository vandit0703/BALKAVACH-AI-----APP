from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session

from app.core.dependencies import require_child
from app.db.session import get_db
from app.schemas.learning_gate import LearningGatePublic
from app.services.learning_gate_service import today_state

router = APIRouter(prefix="/learning-gate", tags=["learning gate"])


@router.get("/today", response_model=LearningGatePublic)
def learning_gate_today(
	child=Depends(require_child),
	session: Session = Depends(get_db),
) -> LearningGatePublic:
	"""Read-only daily state for the authenticated child.

	The child is taken from the validated session, never from the request, so a
	client cannot ask for another child's day.
	"""
	return LearningGatePublic.model_validate(today_state(session, child))
