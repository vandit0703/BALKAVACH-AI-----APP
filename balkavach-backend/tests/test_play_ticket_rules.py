"""Unit tests for the D6 play-ticket rules (pure functions, no database).

What these do NOT cover, by design: one-active-ticket-per-child under concurrent
requests and supersession races. Those need the deferred table and row locks,
i.e. the PostgreSQL suite (see docs/video-play-tickets.md, test plan).
"""

from datetime import datetime, timedelta

import pytest

from app.services import play_ticket_rules as rules
from app.services.play_ticket_rules import TicketError, TicketSnapshot, TicketState as S

T0 = datetime(2026, 11, 19, 12, 0, 0)


def snap(state=S.PLAYING, last=T0, seq=0, issued=T0 - timedelta(seconds=5)):
	return TicketSnapshot(state=state, issued_at=issued, last_heartbeat_at=last, last_sequence=seq)


def beat(ticket, seconds, *, seq=None, playing=True, remaining=900):
	return rules.heartbeat(
		ticket,
		now=(ticket.last_heartbeat_at or ticket.issued_at) + timedelta(seconds=seconds),
		sequence=ticket.last_sequence + 1 if seq is None else seq,
		reports_playing=playing,
		remaining_seconds=remaining,
	)


def test_terminal_states_never_revive():
	for terminal in rules.TERMINAL_STATES:
		assert rules.TRANSITIONS[terminal] == frozenset()
		for target in rules.ACTIVE_STATES:
			assert not rules.can_transition(terminal, target)
	assert rules.can_transition(S.ISSUED, S.PLAYING)
	assert rules.can_transition(S.PLAYING, S.SUPERSEDED)


def test_an_issued_ticket_that_never_plays_costs_nothing():
	issued = snap(state=S.ISSUED, last=None, seq=-1)
	first = beat(issued, 3, playing=False)
	assert first.charge_seconds == 0
	assert first.state == S.PAUSED
	paused = snap(state=S.PAUSED, seq=0)
	assert beat(paused, 10, playing=False).charge_seconds == 0


def test_first_heartbeat_starts_the_clock_without_charging():
	issued = snap(state=S.ISSUED, last=None, seq=-1)
	result = beat(issued, 2)
	assert result.charge_seconds == 0
	assert result.state == S.PLAYING


def test_an_unused_ticket_expires_after_its_ttl():
	issued = snap(state=S.ISSUED, last=None, seq=-1, issued=T0)
	late = rules.heartbeat(issued, now=T0 + timedelta(seconds=61), sequence=0, reports_playing=True, remaining_seconds=900)
	assert late.state == S.EXPIRED
	assert late.charge_seconds == 0


def test_playing_intervals_are_charged_in_full_up_to_the_gap():
	assert beat(snap(), 10).charge_seconds == 10
	assert beat(snap(), 44).charge_seconds == 44  # no free excess for sparse heartbeats


def test_resuming_charges_nothing_for_the_paused_interval():
	result = beat(snap(state=S.PAUSED), 30, playing=True)
	assert result.charge_seconds == 0
	assert result.state == S.PLAYING


def test_missing_heartbeats_lapse_the_ticket_with_a_small_grace():
	result = beat(snap(), 600)  # app killed, device asleep, network gone
	assert result.state == S.EXPIRED
	assert result.charge_seconds == rules.LAPSE_GRACE_SECONDS
	assert beat(snap(state=S.PAUSED), 600).charge_seconds == 0


def test_duplicates_are_idempotent_and_old_replays_are_refused():
	ticket = snap(seq=7)
	for seq in (7, 6, 5):
		result = beat(ticket, 10, seq=seq)
		assert result.duplicate and result.charge_seconds == 0 and result.state == S.PLAYING
	with pytest.raises(TicketError) as replay:
		beat(ticket, 10, seq=1)
	assert replay.value.code == "ticket_sequence_invalid"


def test_client_clock_is_irrelevant_and_server_clock_going_back_is_refused():
	# The client sends no time at all; only a server clock that went backwards matters.
	with pytest.raises(TicketError) as backwards:
		rules.heartbeat(snap(), now=T0 - timedelta(seconds=5), sequence=1, reports_playing=True, remaining_seconds=900)
	assert backwards.value.code == "invalid_heartbeat"


def test_charge_never_exceeds_the_allowance_and_zero_exhausts():
	result = beat(snap(), 20, remaining=12)
	assert result.charge_seconds == 12
	assert result.state == S.EXHAUSTED
	assert beat(snap(), 5, remaining=0).state == S.EXHAUSTED


@pytest.mark.parametrize("state", sorted(rules.TERMINAL_STATES, key=lambda s: s.value))
def test_dead_tickets_cannot_consume_more(state):
	with pytest.raises(TicketError) as refused:
		beat(snap(state=state), 10)
	assert refused.value.code == f"ticket_{state.value}"


def test_a_parent_grant_during_a_session_just_raises_remaining():
	# The ticket is not bound to an allowance snapshot: each heartbeat reads the live figure.
	near_zero = beat(snap(), 10, remaining=900 + 5)
	assert near_zero.state == S.PLAYING and near_zero.charge_seconds == 10


def test_midnight_split():
	midnight = datetime(2026, 11, 19, 18, 30)  # 00:00 Asia/Kolkata in UTC
	assert rules.split_at_local_midnight(midnight - timedelta(seconds=20), midnight - timedelta(seconds=5), midnight) == (15, 0)
	assert rules.split_at_local_midnight(midnight - timedelta(seconds=10), midnight + timedelta(seconds=15), midnight) == (10, 15)
	assert rules.ticket_expires_at(midnight - timedelta(seconds=20), midnight) == midnight


def test_tokens_are_unguessable_hashed_and_compared_safely():
	a, b = rules.new_ticket_token(), rules.new_ticket_token()
	assert a != b and len(a) >= 40
	stored = rules.token_hash(a, "server-secret")
	assert stored != a
	assert rules.token_matches(a, stored, "server-secret")
	assert not rules.token_matches(b, stored, "server-secret")
	assert not rules.token_matches(a, stored, "other-secret")


def test_only_the_two_gated_paths_write_the_allowance_ledger():
	"""Single writer: the ledger is charged only through apply_allowance_charge
	(record_progress or the ticket heartbeat, never both: charging_path decides),
	and consume_video_allowance is called nowhere else."""
	import pathlib

	app = pathlib.Path(__file__).resolve().parents[1] / "app"
	charge_users = sorted(
		p.name for p in app.rglob("*.py") if "apply_allowance_charge(" in p.read_text(encoding="utf-8")
	)
	assert charge_users == ["play_ticket_service.py", "video_watch_history_service.py"]
	consume_users = sorted(
		p.name for p in app.rglob("*.py") if "consume_video_allowance(" in p.read_text(encoding="utf-8")
	)
	assert consume_users == ["video_entitlement_service.py", "video_watch_history_service.py"]
	gate_users = sorted(p.name for p in app.rglob("*.py") if "play_tickets_active()" in p.read_text(encoding="utf-8"))
	assert {"play_ticket_service.py", "video_watch_history_service.py"} <= set(gate_users)
