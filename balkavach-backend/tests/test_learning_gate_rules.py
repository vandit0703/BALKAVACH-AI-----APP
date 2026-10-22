"""Learning-gate rules that can be checked without a database.

The queries in `learning_gate_service` need a reflected schema and are therefore
covered by the integration suite (which requires TEST_DATABASE_URL). The pure
decision logic below is what decides whether a child's missions are reachable,
so it is tested on its own.
"""

import pytest

from app.services.learning_gate_service import (
	DEFAULT_FIRST_SESSION_SECONDS,
	DEFAULT_SECOND_SESSION_SECONDS,
	MAX_SESSION_SECONDS,
	MIN_SESSION_SECONDS,
	PHASE_AWAITING_APPROVAL,
	PHASE_COMPLETE,
	PHASE_FIRST_SESSION,
	PHASE_MISSIONS,
	PHASE_SECOND_SESSION,
	PHASE_UNAVAILABLE,
	_clamped,
	_phase,
	_positive_int,
)


def phase(**overrides):
	defaults = {
		"gate_available": True,
		"first_done": False,
		"assigned": 2,
		"approved": 0,
		"pending": 0,
		"second_done": False,
	}
	return _phase(**{**defaults, **overrides})


class TestPhase:
	def test_unavailable_gate_wins_over_every_other_state(self):
		assert phase(gate_available=False, first_done=True, approved=2) == PHASE_UNAVAILABLE

	def test_first_session_is_the_starting_phase(self):
		assert phase() == PHASE_FIRST_SESSION

	def test_missions_follow_a_completed_first_session(self):
		assert phase(first_done=True) == PHASE_MISSIONS

	def test_partially_submitted_work_is_still_the_missions_phase(self):
		assert phase(first_done=True, assigned=3, pending=1) == PHASE_MISSIONS

	def test_fully_submitted_work_awaits_approval(self):
		assert phase(first_done=True, assigned=2, pending=2) == PHASE_AWAITING_APPROVAL

	def test_mixed_approved_and_pending_covering_all_work_awaits_approval(self):
		assert phase(first_done=True, assigned=2, approved=1, pending=1) == PHASE_AWAITING_APPROVAL

	def test_second_session_needs_every_mission_approved(self):
		assert phase(first_done=True, assigned=2, approved=2) == PHASE_SECOND_SESSION

	def test_approval_not_submission_opens_the_second_session(self):
		"""Submitting is not completing: parent review is mandatory."""
		assert phase(first_done=True, assigned=1, pending=1) != PHASE_SECOND_SESSION

	def test_no_missions_assigned_does_not_open_the_second_session(self):
		assert phase(first_done=True, assigned=0, approved=0) == PHASE_MISSIONS

	def test_complete_once_both_sessions_are_done(self):
		assert phase(first_done=True, assigned=1, approved=1, second_done=True) == PHASE_COMPLETE


class TestPositiveInt:
	@pytest.mark.parametrize("raw", [0, -5, None, "600", 12.5, True, False, [], {}])
	def test_rejects_anything_that_is_not_a_positive_whole_number(self, raw):
		assert _positive_int(raw) is None

	def test_accepts_a_positive_int(self):
		assert _positive_int(600) == 600


class TestClamped:
	def test_falls_back_to_the_default_when_unset(self):
		assert _clamped(None, DEFAULT_FIRST_SESSION_SECONDS) == DEFAULT_FIRST_SESSION_SECONDS

	def test_falls_back_to_the_default_for_a_junk_value(self):
		assert _clamped("ten minutes", DEFAULT_SECOND_SESSION_SECONDS) == DEFAULT_SECOND_SESSION_SECONDS

	def test_keeps_a_sensible_configured_value(self):
		assert _clamped(720, DEFAULT_FIRST_SESSION_SECONDS) == 720

	def test_a_parent_cannot_set_a_near_zero_session(self):
		assert _clamped(1, DEFAULT_FIRST_SESSION_SECONDS) == MIN_SESSION_SECONDS

	def test_a_parent_cannot_set_an_all_day_session(self):
		assert _clamped(99999, DEFAULT_FIRST_SESSION_SECONDS) == MAX_SESSION_SECONDS
