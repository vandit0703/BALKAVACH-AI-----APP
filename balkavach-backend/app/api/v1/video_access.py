from uuid import UUID

from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session

from app.core.dependencies import require_child
from app.db.session import get_db
from app.schemas.video import PlaybackHeartbeatPublic, PlaybackHeartbeatRequest, PlaybackSessionPublic, PlaybackStartRequest
from app.services.video_access_service import interrupt_playback, record_heartbeat, start_playback

router = APIRouter(prefix="/video-access", tags=["video access"])


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
