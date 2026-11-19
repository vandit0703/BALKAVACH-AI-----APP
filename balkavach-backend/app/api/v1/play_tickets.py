"""D6 play-ticket endpoints. Child only. Refused with 503
``play_tickets_unavailable`` until tickets are active (setting on **and** the
deferred ``video_play_tickets`` table present); see ``charging_path``."""

from dataclasses import asdict
from uuid import UUID

from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session

from app.core.dependencies import require_child
from app.core.rate_limit import FixedWindowLimiter, enforce
from app.db.session import get_db
from app.schemas.play_ticket import (
	PlayTicketCreate,
	PlayTicketEnd,
	PlayTicketHeartbeat,
	PlayTicketPublic,
	PlayTicketStatus,
)
from app.services.play_ticket_service import end_ticket, issue_ticket, require_play_tickets, ticket_heartbeat

router = APIRouter(prefix="/video-access/tickets", tags=["video access"])

start_limiter = FixedWindowLimiter()
heartbeat_limiter = FixedWindowLimiter()
START_LIMIT = 6
HEARTBEAT_LIMIT = 20
WINDOW_SECONDS = 60


@router.post("", response_model=PlayTicketPublic, status_code=201)
def create_ticket(request: PlayTicketCreate, child=Depends(require_child), session: Session = Depends(get_db)):
	repo = require_play_tickets(session)
	enforce(start_limiter, f"ticket-start:{child.id}", limit=START_LIMIT, window_seconds=WINDOW_SECONDS)
	issued = issue_ticket(session, repo, child, video_id=request.video_id, device_session_id=request.device_session_id)
	return PlayTicketPublic(**asdict(issued))


@router.post("/{ticket_id}/heartbeat", response_model=PlayTicketStatus)
def heartbeat(
	ticket_id: UUID,
	request: PlayTicketHeartbeat,
	child=Depends(require_child),
	session: Session = Depends(get_db),
):
	repo = require_play_tickets(session)
	enforce(heartbeat_limiter, f"ticket-beat:{child.id}", limit=HEARTBEAT_LIMIT, window_seconds=WINDOW_SECONDS)
	outcome = ticket_heartbeat(
		session,
		repo,
		child,
		ticket_id=ticket_id,
		token=request.ticket_token,
		sequence=request.sequence,
		is_playing=request.is_playing,
		position_seconds=request.position_seconds,
	)
	return PlayTicketStatus(**asdict(outcome))


@router.post("/{ticket_id}/end", response_model=PlayTicketStatus)
def end(ticket_id: UUID, request: PlayTicketEnd, child=Depends(require_child), session: Session = Depends(get_db)):
	repo = require_play_tickets(session)
	outcome = end_ticket(
		session,
		repo,
		child,
		ticket_id=ticket_id,
		token=request.ticket_token,
		sequence=request.sequence,
		position_seconds=request.position_seconds,
	)
	return PlayTicketStatus(**asdict(outcome))
