from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session

from app.core.dependencies import require_child, require_parent
from app.db.base import get_model
from app.db.session import get_db
from app.schemas.video import (
	PlaybackHeartbeatPublic,
	PlaybackHeartbeatRequest,
	PlaybackSessionPublic,
	PlaybackStartRequest,
	VideoAllowancePublic,
)
from app.services.video_access_service import interrupt_playback, record_heartbeat, start_playback
from app.services.video_entitlement_service import get_child_video_allowance_today

router = APIRouter(prefix="/video-access", tags=["video access"])


@router.get("/allowance", response_model=VideoAllowancePublic)
def get_my_video_allowance(
	child=Depends(require_child),
	session: Session = Depends(get_db),
) -> VideoAllowancePublic:
	allowance = get_child_video_allowance_today(session, child.id, child.family_id)
	return VideoAllowancePublic(**allowance)


@router.get("/children/{child_id}/allowance", response_model=VideoAllowancePublic)
def get_child_video_allowance(
	child_id: UUID,
	parent=Depends(require_parent),
	session: Session = Depends(get_db),
) -> VideoAllowancePublic:
	ChildProfile = get_model("ChildProfile")
	FamilyMember = get_model("FamilyMember")
	child = (
		session.query(ChildProfile)
		.join(FamilyMember, FamilyMember.family_id == ChildProfile.family_id)
		.filter(
			ChildProfile.id == child_id,
			FamilyMember.user_id == parent.id,
			FamilyMember.is_active.is_(True),
		)
		.one_or_none()
	)
	if child is None:
		raise HTTPException(status_code=404, detail="Child not found")
	allowance = get_child_video_allowance_today(session, child.id, child.family_id)
	return VideoAllowancePublic(**allowance)


@router.post("/sessions", response_model=PlaybackSessionPublic, status_code=201)
def begin_playback(
	request: PlaybackStartRequest,
	child=Depends(require_child),
	session: Session = Depends(get_db),
) -> PlaybackSessionPublic:
	return start_playback(session, child, request)


@router.post("/heartbeats", response_model=PlaybackHeartbeatPublic)
def playback_heartbeat(
	request: PlaybackHeartbeatRequest,
	child=Depends(require_child),
	session: Session = Depends(get_db),
) -> PlaybackHeartbeatPublic:
	return record_heartbeat(session, child, request.session_id)


@router.post("/sessions/{session_id}/interrupt", response_model=PlaybackHeartbeatPublic)
def stop_playback(
	session_id: UUID,
	child=Depends(require_child),
	session: Session = Depends(get_db),
) -> PlaybackHeartbeatPublic:
	return interrupt_playback(session, child, session_id)
