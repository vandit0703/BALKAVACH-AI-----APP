"""Streak writer anchored to the *activity* date, not the approval time (roadmap Phase 2, MIS-04/MIS-05).

``record_qualifying_activity(..., activity_date=D)`` is what ``review_submission`` calls with the family-local
date of the child's submission. Dates below are in Asia/Kolkata (UTC+5:30, no DST).
"""

from datetime import date, datetime, timezone

import pytest

from app.services.streak_service import record_qualifying_activity
from app.services.timezone_service import local_date_of
from tests.sqlite_world import ChildStreak, make_family, world_session  # noqa: F401  (fixture)

IST = "Asia/Kolkata"


def utc(*args) -> datetime:
	return datetime(*args, tzinfo=timezone.utc)


def ist_morning(day: int) -> datetime:
	"""08:00 IST on 2026-11-<day>, as the UTC instant the server sees."""
	return utc(2026, 11, day, 2, 30)


def _child_with_streak(session, *, last: date, current: int = 4, state: str = "active"):
	child = make_family(session, timezone_name=IST)
	session.add(
		ChildStreak(
			child_id=child.id,
			current_streak=current,
			longest_streak=current,
			last_activity_date=last,
			streak_state=state,
		)
	)
	session.flush()
	return child


def _streak(session, child) -> ChildStreak:
	session.flush()  # the service never commits and the session runs with autoflush off
	return session.query(ChildStreak).filter(ChildStreak.child_id == child.id).one()


def test_late_approval_counts_for_the_day_the_child_did_the_mission(world_session):
	child = _child_with_streak(world_session, last=date(2026, 11, 9))
	# done on the 10th, parent approves on the 11th at 08:00
	result = record_qualifying_activity(
		world_session, child.id, child.family_id, now_utc=ist_morning(11), activity_date=date(2026, 11, 10)
	)
	row = _streak(world_session, child)
	assert row.last_activity_date == date(2026, 11, 10)  # not the 11th
	assert (row.current_streak, result["current_streak"]) == (5, 5)
	assert result["streak_extended"] is True
	# the 11th has not been completed yet, so the day is still open, not "active"
	assert result["streak_state"] == "at_risk" and row.streak_state == "at_risk"
	assert row.grace_deadline is not None


def test_the_next_days_mission_then_extends_it_once_more(world_session):
	child = _child_with_streak(world_session, last=date(2026, 11, 9))
	record_qualifying_activity(world_session, child.id, child.family_id, now_utc=ist_morning(11), activity_date=date(2026, 11, 10))
	result = record_qualifying_activity(
		world_session, child.id, child.family_id, now_utc=ist_morning(11), activity_date=date(2026, 11, 11)
	)
	assert result["current_streak"] == 6 and result["streak_state"] == "active"
	assert _streak(world_session, child).grace_deadline is None


def test_a_second_approval_for_the_same_activity_day_adds_nothing(world_session):
	child = _child_with_streak(world_session, last=date(2026, 11, 9))
	record_qualifying_activity(world_session, child.id, child.family_id, now_utc=ist_morning(11), activity_date=date(2026, 11, 10))
	again = record_qualifying_activity(
		world_session, child.id, child.family_id, now_utc=ist_morning(12), activity_date=date(2026, 11, 10)
	)
	assert again["current_streak"] == 5 and again["streak_extended"] is False
	assert _streak(world_session, child).current_streak == 5


def test_a_late_approval_is_not_punished_when_the_activity_was_inside_the_grace_window(world_session):
	# last streak day: the 9th. grace ends at the start of the 12th. The 11th was done in time, approved on the 14th.
	child = _child_with_streak(world_session, last=date(2026, 11, 9))
	result = record_qualifying_activity(
		world_session, child.id, child.family_id, now_utc=ist_morning(14), activity_date=date(2026, 11, 11)
	)
	assert result["is_new_after_break"] is False
	assert result["current_streak"] == 5
	assert _streak(world_session, child).last_activity_date == date(2026, 11, 11)


def test_activity_after_the_grace_window_starts_a_new_streak_even_if_approved_at_once(world_session):
	child = _child_with_streak(world_session, last=date(2026, 11, 9))
	result = record_qualifying_activity(
		world_session, child.id, child.family_id, now_utc=ist_morning(12), activity_date=date(2026, 11, 12)
	)
	assert result["is_new_after_break"] is True and result["current_streak"] == 1
	assert _streak(world_session, child).longest_streak == 4


def test_a_row_the_scheduler_already_marked_broken_is_recovered_by_an_in_window_late_approval(world_session):
	child = _child_with_streak(world_session, last=date(2026, 11, 9), state="broken")
	result = record_qualifying_activity(
		world_session, child.id, child.family_id, now_utc=ist_morning(14), activity_date=date(2026, 11, 10)
	)
	assert result["current_streak"] == 5 and result["is_new_after_break"] is False


def test_an_older_activity_approved_after_a_newer_one_never_moves_the_streak_back(world_session):
	child = _child_with_streak(world_session, last=date(2026, 11, 11), current=6)
	result = record_qualifying_activity(
		world_session, child.id, child.family_id, now_utc=ist_morning(12), activity_date=date(2026, 11, 10)
	)
	row = _streak(world_session, child)
	assert (row.current_streak, row.last_activity_date) == (6, date(2026, 11, 11))
	assert result["streak_extended"] is False and result["current_streak"] == 6


def test_an_activity_date_in_the_future_is_clamped_to_the_family_local_today(world_session):
	child = _child_with_streak(world_session, last=date(2026, 11, 9))
	record_qualifying_activity(
		world_session, child.id, child.family_id, now_utc=ist_morning(10), activity_date=date(2026, 12, 25)
	)
	assert _streak(world_session, child).last_activity_date == date(2026, 11, 10)


def test_the_first_ever_activity_is_dated_by_when_it_happened(world_session):
	child = make_family(world_session, timezone_name=IST)
	result = record_qualifying_activity(
		world_session, child.id, child.family_id, now_utc=ist_morning(12), activity_date=date(2026, 11, 11)
	)
	assert result["current_streak"] == 1
	assert _streak(world_session, child).last_activity_date == date(2026, 11, 11)


def test_without_an_activity_date_the_existing_behaviour_is_unchanged(world_session):
	child = _child_with_streak(world_session, last=date(2026, 11, 9))
	result = record_qualifying_activity(world_session, child.id, child.family_id, now_utc=ist_morning(10))
	assert result["current_streak"] == 5 and _streak(world_session, child).last_activity_date == date(2026, 11, 10)


@pytest.mark.parametrize(
	"submitted_at_utc, expected_local_day",
	[
		(utc(2026, 11, 10, 18, 29, 59), date(2026, 11, 10)),  # 23:59:59 IST
		(utc(2026, 11, 10, 18, 30, 0), date(2026, 11, 11)),  # 00:00:00 IST next day
		(utc(2026, 11, 10, 0, 0, 0), date(2026, 11, 10)),
	],
)
def test_the_activity_day_follows_the_family_timezone_boundary(world_session, submitted_at_utc, expected_local_day):
	child = make_family(world_session, timezone_name=IST)
	assert local_date_of(world_session, child.family_id, submitted_at_utc) == expected_local_day


def test_a_naive_stored_timestamp_is_read_as_utc(world_session):
	child = make_family(world_session, timezone_name=IST)
	assert local_date_of(world_session, child.family_id, datetime(2026, 11, 10, 18, 30)) == date(2026, 11, 11)


def test_dst_zone_boundary_uses_the_offset_in_force_on_that_date(world_session):
	child = make_family(world_session, timezone_name="America/New_York")
	# 2026-11-01 is the end of DST: 04:30Z is 00:30 EDT on the 1st; 2026-11-02 04:30Z is 23:30 EST on the 1st.
	assert local_date_of(world_session, child.family_id, utc(2026, 11, 1, 4, 30)) == date(2026, 11, 1)
	assert local_date_of(world_session, child.family_id, utc(2026, 11, 2, 4, 30)) == date(2026, 11, 1)
	assert local_date_of(world_session, child.family_id, utc(2026, 11, 2, 5, 0)) == date(2026, 11, 2)
