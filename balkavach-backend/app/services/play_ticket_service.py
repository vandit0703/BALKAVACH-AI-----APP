"""Play-ticket service (decision D6): issue, heartbeat, end, revoke.

Persistence is behind :class:`PlayTicketRepository`. The production
implementation (:class:`SqlPlayTicketRepository`) uses the deferred
``video_play_tickets`` table; until that table exists,
``charging_path.play_tickets_active()`` is false, :func:`require_play_tickets`
refuses every call with 503, and ``record_progress`` remains the charging
path. There is deliberately **no** in-memory production store.

Charging goes through ``apply_allowance_charge`` (the same ledger writer as
``record_progress``), so free time first, parent-approved grants, the daily
cap and family-local expiry are unchanged. Rules: ``play_ticket_rules``.
Design: ``docs/video-play-tickets.md``.
"""

from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
import logging
from typing import Any, Protocol
from uuid import UUID, uuid4

from fastapi import HTTPException
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from app.core.config import settings
from app.core.exceptions import APIError
from app.db.base import get_model
from app.services import play_ticket_rules as rules
from app.services.charging_path import TICKET_MODEL, play_tickets_active
from app.services.play_ticket_rules import TicketError, TicketSnapshot, TicketState
from app.services.timezone_service import family_timezone_name, local_day_bounds_utc_naive, local_today, parse_timezone
from app.services.video_entitlement_service import get_child_video_allowance_today
from app.services.video_watch_history_service import (
	_eligible_video,
	apply_allowance_charge,
	get_or_create_daily_usage,
	get_or_create_watch_history,
	update_watch_position,
)
from app.utils import utc_aware, utc_naive

logger = logging.getLogger(__name__)


class ActiveTicketConflict(Exception):
	"""Another active ticket for the child was stored concurrently (the partial
	unique index on ``child_id`` rejected this insert)."""


class PlayTicketRepository(Protocol):
	def active_for_child(self, child_id: UUID) -> Any | None: ...

	def get_for_child(self, ticket_id: UUID, child_id: UUID) -> Any | None:
		"""The ticket, locked for update, or None when missing or another child's."""

	def add(self, **fields: Any) -> Any:
		"""Insert a ticket; raises :class:`ActiveTicketConflict` on the one-active rule."""

	def flush(self) -> None: ...


class SqlPlayTicketRepository:
	"""Production repository over ``video_play_tickets``. Usable only once the
	table exists (``play_tickets_active()``)."""

	def __init__(self, session: Session) -> None:
		self._session = session
		self._model = get_model(TICKET_MODEL)

	def active_for_child(self, child_id: UUID):
		model = self._model
		return (
			self._session.query(model)
			.filter(model.child_id == child_id, model.state.in_([s.value for s in rules.ACTIVE_STATES]))
			.with_for_update()
			.one_or_none()
		)

	def get_for_child(self, ticket_id: UUID, child_id: UUID):
		model = self._model
		return (
			self._session.query(model)
			.filter(model.id == ticket_id, model.child_id == child_id)
			.with_for_update()
			.one_or_none()
		)

	def add(self, **fields: Any):
		ticket = self._model(**fields)
		try:
			with self._session.begin_nested():
				self._session.add(ticket)
				self._session.flush()
		except IntegrityError as error:
			raise ActiveTicketConflict from error
		return ticket

	def flush(self) -> None:
		self._session.flush()


def require_play_tickets(session: Session) -> PlayTicketRepository:
	"""The production repository, or 503 while tickets are not active."""
	if not play_tickets_active():
		raise APIError(503, "play_tickets_unavailable", "Play tickets are not enabled on this server")
	if not settings.jwt_secret_key:
		raise APIError(503, "play_tickets_unavailable", "Play tickets are not configured")
	return SqlPlayTicketRepository(session)


@dataclass(frozen=True)
class IssuedTicket:
	ticket_id: UUID
	ticket_token: str
	video_id: UUID
	youtube_video_id: str | None
	expires_at: datetime
	heartbeat_interval_seconds: int
	remaining_seconds: int


@dataclass(frozen=True)
class HeartbeatOutcome:
	ticket_id: UUID
	state: str
	accepted_seconds: int
	remaining_seconds: int
	is_exhausted: bool
	duplicate: bool


_REFUSALS = {
	TicketState.SUPERSEDED: (409, "ticket_superseded", "Playback moved to another device"),
	TicketState.EXPIRED: (409, "ticket_expired", "This play ticket has expired"),
	TicketState.REVOKED: (403, "ticket_revoked", "This play ticket was revoked"),
	TicketState.EXHAUSTED: (403, "ticket_exhausted", "Video time is used up"),
	TicketState.ENDED: (409, "ticket_ended", "This play ticket has ended"),
}


def _secret() -> str:
	secret = settings.jwt_secret_key
	if not secret:
		raise APIError(503, "play_tickets_unavailable", "Play tickets are not configured")
	return secret


def _lock_child(session: Session, child_id: UUID):
	ChildProfile = get_model("ChildProfile")
	child = (
		session.query(ChildProfile)
		.filter(ChildProfile.id == child_id, ChildProfile.is_active.is_(True))
		.with_for_update()
		.one_or_none()
	)
	if child is None:
		raise HTTPException(status_code=404, detail="Child profile not found")
	return child


def _day_end(session: Session, family_id: UUID, local_date) -> datetime:
	zone = parse_timezone(family_timezone_name(session, family_id))
	return local_day_bounds_utc_naive(zone, local_date, 1)[1]


def _naive(value: datetime | None) -> datetime | None:
	if value is None or value.tzinfo is None:
		return value
	return utc_naive(value)


def _close(ticket, state: TicketState, now: datetime, reason: str) -> None:
	ticket.state = state.value
	ticket.ended_at = now
	ticket.end_reason = reason


def issue_ticket(
	session: Session,
	repo: PlayTicketRepository,
	child,
	*,
	video_id: UUID,
	device_session_id: str,
	now_aware: datetime | None = None,
) -> IssuedTicket:
	"""Authorise playback of one video. Supersedes the child's active ticket."""
	now_aware = now_aware or datetime.now(timezone.utc)
	now = utc_naive(now_aware)
	child = _lock_child(session, child.id)
	video = _eligible_video(session, child, video_id)
	allowance = get_child_video_allowance_today(session, child.id, child.family_id, now_utc=now_aware)
	if allowance["remaining_seconds"] <= 0:
		raise APIError(403, "video_time_exhausted", "Video access time has been exhausted.")

	token = rules.new_ticket_token()
	ticket_id = uuid4()
	local_date = allowance["local_date"]
	expires_at = rules.ticket_expires_at(now, _day_end(session, child.family_id, local_date))
	for attempt in range(2):
		previous = repo.active_for_child(child.id)
		if previous is not None:
			_close(previous, TicketState.SUPERSEDED, now, "superseded")
			previous.superseded_by = ticket_id
			repo.flush()
		try:
			repo.add(
				id=ticket_id,
				child_id=child.id,
				video_id=video.id,
				device_session_id=device_session_id,
				token_hash=rules.token_hash(token, _secret()),
				state=TicketState.ISSUED.value,
				issued_at=now,
				expires_at=expires_at,
				started_at=None,
				last_heartbeat_at=None,
				ended_at=None,
				last_sequence=-1,
				charged_seconds=0,
				free_charged_seconds=0,
				local_date=local_date,
				superseded_by=None,
				end_reason=None,
				created_at=now,
			)
			break
		except ActiveTicketConflict:
			# A start on another device won the race between our check and insert:
			# supersede it too, once. The child row lock makes this rare.
			if attempt:
				raise APIError(409, "playback_start_conflict", "Please try again") from None
	session.commit()
	logger.info("Play ticket %s issued for child %s", ticket_id, child.id)  # never the token
	return IssuedTicket(
		ticket_id=ticket_id,
		ticket_token=token,
		video_id=video.id,
		youtube_video_id=video.external_video_id if video.video_source == "youtube" else None,
		expires_at=utc_aware(expires_at),
		heartbeat_interval_seconds=rules.HEARTBEAT_INTERVAL_SECONDS,
		remaining_seconds=int(allowance["remaining_seconds"]),
	)


def _load(repo: PlayTicketRepository, child, ticket_id: UUID, token: str):
	ticket = repo.get_for_child(ticket_id, child.id)
	if ticket is None:
		raise HTTPException(status_code=404, detail="Play ticket not found")
	if not rules.token_matches(token, ticket.token_hash, _secret()):
		raise APIError(403, "ticket_invalid", "This play ticket is not valid")
	return ticket


def _refuse(ticket) -> None:
	status, code, message = _REFUSALS[TicketState(ticket.state)]
	raise APIError(status, code, message)


def _charge(session, child, ticket, video, seconds: int, allowance: dict, now: datetime, now_aware: datetime):
	"""Charge through the shared ledger and record it on the ticket and history."""
	if seconds <= 0:
		return int(allowance["remaining_seconds"]), allowance["remaining_seconds"] <= 0
	usage, _ = get_or_create_daily_usage(session, child, allowance["local_date"], now, False)
	remaining, exhausted, free = apply_allowance_charge(session, child, usage, seconds, allowance, now_aware)
	ticket.charged_seconds = int(ticket.charged_seconds or 0) + seconds
	ticket.free_charged_seconds = int(ticket.free_charged_seconds or 0) + free
	history, _, _ = get_or_create_watch_history(session, child, video, now)
	history.watch_duration_seconds += seconds
	return remaining, exhausted


def ticket_heartbeat(
	session: Session,
	repo: PlayTicketRepository,
	child,
	*,
	ticket_id: UUID,
	token: str,
	sequence: int,
	is_playing: bool,
	position_seconds: int,
	now_aware: datetime | None = None,
	_ending: bool = False,
) -> HeartbeatOutcome:
	now_aware = now_aware or datetime.now(timezone.utc)
	now = utc_naive(now_aware)
	ticket = _load(repo, child, ticket_id, token)
	child = _lock_child(session, child.id)
	if TicketState(ticket.state) in rules.TERMINAL_STATES:
		_refuse(ticket)

	Video = get_model("Video")
	video = session.query(Video).filter(Video.id == ticket.video_id).one_or_none()

	# Family-local midnight: charge only the part before it, then end the ticket.
	day_end = _day_end(session, child.family_id, ticket.local_date)
	last = _naive(ticket.last_heartbeat_at)
	if now >= day_end:
		if ticket.state == TicketState.PLAYING.value and last is not None and video is not None:
			before, _ = rules.split_at_local_midnight(last, now, day_end)
			before = min(before, rules.MAX_HEARTBEAT_GAP_SECONDS)
			old_moment = utc_aware(day_end - timedelta(seconds=1))
			old_allowance = get_child_video_allowance_today(session, child.id, child.family_id, now_utc=old_moment)
			_charge(session, child, ticket, video, min(before, int(old_allowance["remaining_seconds"])),
				old_allowance, day_end - timedelta(seconds=1), old_moment)
		_close(ticket, TicketState.EXPIRED, now, "midnight")
		session.commit()
		today = get_child_video_allowance_today(session, child.id, child.family_id, now_utc=now_aware)
		return HeartbeatOutcome(ticket.id, ticket.state, 0, int(today["remaining_seconds"]), today["is_exhausted"], False)

	# The video must still be allowed for this child (unpublished, age, category...).
	try:
		video = _eligible_video(session, child, ticket.video_id)
	except HTTPException:
		_close(ticket, TicketState.REVOKED, now, "video_unavailable")
		session.commit()
		raise APIError(403, "ticket_revoked", "This video is no longer available") from None

	allowance = get_child_video_allowance_today(session, child.id, child.family_id, now_utc=now_aware)
	snapshot = TicketSnapshot(
		state=TicketState(ticket.state),
		issued_at=_naive(ticket.issued_at),
		last_heartbeat_at=last,
		last_sequence=int(ticket.last_sequence),
	)
	try:
		result = rules.heartbeat(
			snapshot,
			now=now,
			sequence=sequence,
			reports_playing=is_playing and not _ending,
			remaining_seconds=int(allowance["remaining_seconds"]),
		)
	except TicketError as error:
		raise APIError(error.status, error.code, "This heartbeat cannot be accepted") from None
	if result.duplicate:
		return HeartbeatOutcome(
			ticket.id, ticket.state, 0, int(allowance["remaining_seconds"]), allowance["remaining_seconds"] <= 0, True
		)

	remaining, exhausted = _charge(session, child, ticket, video, result.charge_seconds, allowance, now, now_aware)
	ticket.last_sequence = sequence
	ticket.last_heartbeat_at = now
	if ticket.started_at is None and result.state == TicketState.PLAYING:
		ticket.started_at = now
	state = result.state
	if state in rules.ACTIVE_STATES and (exhausted or remaining <= 0):
		state = TicketState.EXHAUSTED
	if _ending and state in rules.ACTIVE_STATES:
		state = TicketState.ENDED
	if state in rules.TERMINAL_STATES:
		reason = {
			TicketState.EXPIRED: "missed_heartbeats" if last is not None else "not_started",
			TicketState.EXHAUSTED: "allowance_exhausted",
			TicketState.ENDED: "closed_by_child",
		}.get(state, state.value)
		_close(ticket, state, now, reason)
	else:
		ticket.state = state.value
	history, format_name, _ = get_or_create_watch_history(session, child, video, now)
	update_watch_position(history, video, format_name, position_seconds, now)
	session.commit()
	return HeartbeatOutcome(ticket.id, ticket.state, result.charge_seconds, remaining, exhausted or remaining <= 0, False)


def end_ticket(
	session: Session,
	repo: PlayTicketRepository,
	child,
	*,
	ticket_id: UUID,
	token: str,
	sequence: int,
	position_seconds: int,
	now_aware: datetime | None = None,
) -> HeartbeatOutcome:
	"""Charge the last interval if it was playing and close the ticket. Idempotent."""
	ticket = _load(repo, child, ticket_id, token)
	if TicketState(ticket.state) in rules.TERMINAL_STATES:
		now_aware = now_aware or datetime.now(timezone.utc)
		allowance = get_child_video_allowance_today(session, child.id, child.family_id, now_utc=now_aware)
		return HeartbeatOutcome(
			ticket.id, ticket.state, 0, int(allowance["remaining_seconds"]), allowance["remaining_seconds"] <= 0, True
		)
	return ticket_heartbeat(
		session, repo, child, ticket_id=ticket_id, token=token, sequence=sequence, is_playing=False,
		position_seconds=position_seconds, now_aware=now_aware, _ending=True,
	)


def revoke_child_tickets(session: Session, repo: PlayTicketRepository, child_id: UUID, reason: str) -> bool:
	"""Revoke the child's active ticket (parent or admin action). The caller commits.
	A modified client that ignores the refusal can keep a loaded YouTube player
	going; see docs/video-play-tickets.md §5."""
	ticket = repo.active_for_child(child_id)
	if ticket is None:
		return False
	_close(ticket, TicketState.REVOKED, utc_naive(datetime.now(timezone.utc)), reason)
	repo.flush()
	logger.info("Play ticket %s revoked (%s)", ticket.id, reason)
	return True
