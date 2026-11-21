"""Watch-time accounting rule used by the single deduction path (record_progress).

Pure-function tests: no database. They prove the rule only; the locking behaviour of
record_progress is a PostgreSQL concern and needs TEST_DATABASE_URL.
"""

import pytest

from app.services.video_watch_history_service import (
	MAX_PROGRESS_INTERVAL_SECONDS,
	accepted_progress_seconds,
)


def charge(**overrides):
	args = dict(elapsed_seconds=10, was_playing=True, is_playing=True, previous_position=0, position=10)
	args.update(overrides)
	return accepted_progress_seconds(**args)


def test_playing_interval_requires_position_progress():
	assert charge(elapsed_seconds=10) == 10
	assert charge(elapsed_seconds=10, previous_position=40, position=40) == 0


def test_interval_is_capped_so_an_idle_gap_cannot_overcharge():
	assert charge(elapsed_seconds=30, position=30) == MAX_PROGRESS_INTERVAL_SECONDS
	assert charge(elapsed_seconds=3600, previous_position=0, position=3600) == 0


def test_zero_or_negative_elapsed_charges_nothing_duplicate_request():
	assert charge(elapsed_seconds=0) == 0
	assert charge(elapsed_seconds=-5) == 0
	assert charge(elapsed_seconds=0.9) == 0


def test_honest_pause_is_free():
	assert charge(was_playing=False, is_playing=False, previous_position=40, position=40) == 0


def test_resume_report_does_not_charge_the_paused_interval():
	assert charge(was_playing=False, is_playing=True, previous_position=40, position=40) == 0


def test_claiming_paused_while_position_advances_is_charged():
	# A client that has already reported paused cannot charge by advancing position.
	assert charge(elapsed_seconds=10, was_playing=False, is_playing=False, previous_position=40, position=50) == 0


def test_paused_claim_with_slower_advance_is_charged_the_position_delta():
	assert charge(elapsed_seconds=10, was_playing=False, is_playing=False, previous_position=40, position=46) == 0


def test_seek_while_paused_is_not_charged():
	assert charge(elapsed_seconds=10, was_playing=False, is_playing=False, previous_position=40, position=400) == 0


def test_backwards_position_while_paused_is_not_charged():
	assert charge(was_playing=False, is_playing=False, previous_position=40, position=10) == 0


@pytest.mark.parametrize("elapsed", [1, 5, 30, 31, 10_000])
def test_never_charges_more_than_the_cap(elapsed):
	assert charge(elapsed_seconds=elapsed, was_playing=True) <= MAX_PROGRESS_INTERVAL_SECONDS
	assert (
		charge(elapsed_seconds=elapsed, was_playing=False, is_playing=False, previous_position=0, position=elapsed)
		<= MAX_PROGRESS_INTERVAL_SECONDS
	)
