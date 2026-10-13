from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy.orm import Session

from app.core.dependencies import get_current_user
from app.db.base import get_model
from app.db.session import get_db
from app.schemas.progress import ProgressPublic, WeeklyReportPublic
from app.services.progress_service import get_progress
from app.services.report_service import weekly_report

router = APIRouter(prefix="/progress", tags=["progress"])


def _authorized_child(session: Session, user, child_id: UUID):
	ChildProfile = get_model("ChildProfile")
	child = session.query(ChildProfile).filter(
		ChildProfile.id == child_id,
		ChildProfile.is_active.is_(True),
	).one_or_none()
	if child is None:
		raise HTTPException(status_code=404, detail="Child profile not found")
	if user.role == "child":
		if child.user_id != user.id:
			raise HTTPException(status_code=404, detail="Child profile not found")
	elif user.role == "parent":
		FamilyMember = get_model("FamilyMember")
		member = session.query(FamilyMember.id).filter(
			FamilyMember.family_id == child.family_id,
			FamilyMember.user_id == user.id,
			FamilyMember.is_active.is_(True),
		).first()
		if member is None:
			raise HTTPException(status_code=404, detail="Child profile not found")
	else:
		raise HTTPException(status_code=403, detail="Progress access denied")
	return child


@router.get("/children/{child_id}", response_model=ProgressPublic)
def child_progress(
	child_id: UUID,
	user=Depends(get_current_user),
	session: Session = Depends(get_db),
) -> ProgressPublic:
	_authorized_child(session, user, child_id)
	return ProgressPublic.model_validate(get_progress(session, child_id))


@router.get("/children/{child_id}/activity", response_model=list)
def child_activity(
	child_id: UUID,
	limit: int = Query(default=30, ge=1, le=90),
	user=Depends(get_current_user),
	session: Session = Depends(get_db),
) -> list[dict]:
	progress = child_progress(child_id, user, session)
	return progress.activity_days[:limit]


@router.get("/children/{child_id}/weekly", response_model=WeeklyReportPublic)
def child_weekly_report(
	child_id: UUID,
	weeks_back: int = Query(default=0, ge=0, le=52),
	user=Depends(get_current_user),
	session: Session = Depends(get_db),
) -> WeeklyReportPublic:
	child = _authorized_child(session, user, child_id)
	return WeeklyReportPublic.model_validate(weekly_report(session, child, weeks_back))
