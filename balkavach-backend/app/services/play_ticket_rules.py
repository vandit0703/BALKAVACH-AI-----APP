"""Play-ticket rules (decision D6, 2026-11-19): pure logic, no database, not wired.

The ticket service itself needs the deferred ``video_play_tickets`` table
(``docs/deferred-database-integration.md``). Everything here is the part that
does not: the state machine, the heartbeat charging rule, the local-midnight
split and the opaque ticket token. When the table exists, the service calls
these functions under a row lock; until then nothing imports this module, and
``record_progress`` stays the only deduction path.

Design: ``docs/video-play-tickets.md``.
"""

from __future__ import annotations

import base64
from dataclasses import dataclass
from datetime import datetime, timedelta
from enum import Enum
import hashlib
import hmac
import secrets


class TicketState(str, Enum):
	ISSUED = "issued"  # authorised, playback not started: nothing is charged
	PLAYING = "playing"
	PAUSED = "paused"
	SUPERSEDED = "superseded"  # a newer ticket for the same child replaced it
	EXPIRED = "expired"  # missed heartbeats, local midnight, or past expires_at
	REVOKED = "revoked"  # a parent or admin action, or the video was unpublished
	EXHAUSTED = "exhausted"  # the allowance reached zero
	ENDED = "ended"  # the child closed the player


ACTIVE_STATES = frozenset({TicketState.ISSUED, TicketState.PLAYING, TicketState.PAUSED})
TERMINAL_STATES = frozenset(set(TicketState) - ACTIVE_STATES)

TRANSITIONS: dict[TicketState, frozenset[TicketState]] = {
	TicketState.ISSUED: frozenset({TicketState.PLAYING, TicketState.PAUSED} | TERMINAL_STATES),
	TicketState.PLAYING: frozenset({TicketState.PAUSED} | TERMINAL_STATES),
	TicketState.PAUSED: frozenset({TicketState.PLAYING} | TERMINAL_STATES),
	**{state: frozenset() for state in TERMINAL_STATES},  # terminal: never revived
}

# Heartbeat timing (server clock only).
HEARTBEAT_INTERVAL_SECONDS = 10  # what the client aims for
MAX_HEARTBEAT_GAP_SECONDS = 45  # longer silence lapses the ticket
LAPSE_GRACE_SECONDS = 10  # charged once for a lapsed, playing ticket
TICKET_TTL_SECONDS = 60  # an unused ticket must start within this
MAX_REPLAY_WINDOW = 3  # sequence numbers within this many of the last are duplicates


class TicketError(Exception):
	"""A heartbeat that must be refused. ``code`` is the API error code."""

	def __init__(self, code: str, status: int = 409) -> None:
		super().__init__(code)
		self.code = code
		self.status = status


def can_transition(current: TicketState, target: TicketState) -> bool:
	return current == target or target in TRANSITIONS[current]


@dataclass(frozen=True)
class TicketSnapshot:
	"""What the server stored after the last accepted heartbeat."""

	state: TicketState
	issued_at: datetime
	last_heartbeat_at: datetime | None  # server time; None before the first heartbeat
	last_sequence: int  # -1 before the first heartbeat


@dataclass(frozen=True)
class HeartbeatResult:
	charge_seconds: int
	state: TicketState
	duplicate: bool = False


def heartbeat(
	ticket: TicketSnapshot,
	*,
	now: datetime,
	sequence: int,
	reports_playing: bool,
	remaining_seconds: int,
) -> HeartbeatResult:
	"""Charge one heartbeat. ``now`` is the server's clock; the client sends only
	a sequence number and whether it is playing, so changing the device clock
	changes nothing.

	* Time is charged only for an interval that **began playing**: a ticket that
	  was issued but never played, or a paused one, costs nothing.
	* An interval up to :data:`MAX_HEARTBEAT_GAP_SECONDS` is charged in full
	  (no free excess for sparse heartbeats). A longer silence lapses the ticket:
	  :data:`LAPSE_GRACE_SECONDS` at most, then a new ticket is needed.
	* A repeated or older sequence number is a duplicate: charged 0, no change.
	* The charge never exceeds ``remaining_seconds``. Reaching 0 exhausts it.
	"""
	if ticket.state in TERMINAL_STATES:
		raise TicketError(f"ticket_{ticket.state.value}")
	if sequence <= ticket.last_sequence:
		if ticket.last_sequence - sequence > MAX_REPLAY_WINDOW:
			raise TicketError("ticket_sequence_invalid")
		return HeartbeatResult(0, ticket.state, duplicate=True)

	previous = ticket.last_heartbeat_at
	if previous is None:
		# First heartbeat: the ticket must be used promptly; nothing to charge yet.
		if (now - ticket.issued_at).total_seconds() > TICKET_TTL_SECONDS:
			return HeartbeatResult(0, TicketState.EXPIRED)
		return HeartbeatResult(0, _next_state(reports_playing, remaining_seconds))

	elapsed = (now - previous).total_seconds()
	if elapsed < 0:
		raise TicketError("invalid_heartbeat")  # server clock went backwards; refuse, charge nothing
	was_playing = ticket.state == TicketState.PLAYING
	if elapsed > MAX_HEARTBEAT_GAP_SECONDS:
		charge = min(LAPSE_GRACE_SECONDS, max(0, remaining_seconds)) if was_playing else 0
		return HeartbeatResult(charge, TicketState.EXPIRED)
	charge = min(int(elapsed), max(0, remaining_seconds)) if was_playing else 0
	if remaining_seconds - charge <= 0:
		return HeartbeatResult(charge, TicketState.EXHAUSTED)
	return HeartbeatResult(charge, _next_state(reports_playing, remaining_seconds - charge))


def _next_state(reports_playing: bool, remaining: int) -> TicketState:
	if remaining <= 0:
		return TicketState.EXHAUSTED
	return TicketState.PLAYING if reports_playing else TicketState.PAUSED


def split_at_local_midnight(start: datetime, end: datetime, next_midnight: datetime) -> tuple[int, int]:
	"""Seconds of [start, end) before and after the family-local midnight
	(all naive UTC). The ticket service charges only the part before midnight
	to that day and ends the ticket, so the new day starts with a fresh check."""
	if end <= next_midnight:
		return int((end - start).total_seconds()), 0
	before = max(0, int((next_midnight - start).total_seconds()))
	return before, int((end - max(start, next_midnight)).total_seconds())


# --------------------------------------------------------------------------- tokens


def new_ticket_token() -> str:
	"""An unguessable opaque token for the client. Only its hash is stored."""
	return base64.urlsafe_b64encode(secrets.token_bytes(32)).rstrip(b"=").decode("ascii")


def token_hash(token: str, secret: str) -> str:
	"""Keyed hash stored in the ticket row; a leaked table cannot be replayed."""
	return hmac.new(secret.encode("utf-8"), token.encode("utf-8"), hashlib.sha256).hexdigest()


def token_matches(token: str, stored_hash: str, secret: str) -> bool:
	return hmac.compare_digest(token_hash(token, secret), stored_hash)


def ticket_expires_at(issued_at: datetime, next_midnight: datetime) -> datetime:
	"""An unused ticket must start within the TTL, and never outlives local midnight."""
	return min(issued_at + timedelta(seconds=TICKET_TTL_SECONDS), next_midnight)
