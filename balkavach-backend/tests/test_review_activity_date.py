"""How ``review_submission`` anchors an approval to the day of the activity (roadmap Phase 2, MIS-04/05).

``review_submission`` itself needs PostgreSQL (row locks, ``ON CONFLICT``); its end-to-end behaviour is covered
by the DB-backed tests in ``tests/test_api_mission_flow.py``. What can be proven without it is tested here.
"""

import inspect
from datetime import date, datetime, timezone
from types import SimpleNamespace

from app.services import task_service
from tests.sqlite_world import make_family, world_session  # noqa: F401  (fixture)


def _utc(*args) -> datetime:
	return datetime(*args, tzinfo=timezone.utc)


def test_a_mission_done_at_2330_and_approved_next_morning_belongs_to_the_day_it_was_done(world_session):
	child = make_family(world_session, timezone_name="Asia/Kolkata")
	submission = SimpleNamespace(submitted_at=datetime(2026, 11, 10, 18, 0))  # 23:30 IST on the 10th, stored naive UTC
	approved_next_morning = datetime(2026, 11, 11, 2, 30)  # 08:00 IST on the 11th
	assert task_service.submission_activity_date(world_session, child.family_id, submission, approved_next_morning) == date(2026, 11, 10)


def test_a_mission_submitted_just_after_local_midnight_belongs_to_the_new_day(world_session):
	child = make_family(world_session, timezone_name="Asia/Kolkata")
	submission = SimpleNamespace(submitted_at=datetime(2026, 11, 10, 18, 31))  # 00:01 IST on the 11th
	assert task_service.submission_activity_date(world_session, child.family_id, submission, datetime(2026, 11, 20, 0, 0)) == date(2026, 11, 11)


def test_a_resubmission_after_a_rejection_is_dated_by_the_resubmission(world_session):
	child = make_family(world_session, timezone_name="UTC")
	first = SimpleNamespace(submitted_at=datetime(2026, 11, 10, 9, 0))  # rejected
	second = SimpleNamespace(submitted_at=datetime(2026, 11, 12, 9, 0))  # redone two days later
	args = (world_session, child.family_id)
	assert task_service.submission_activity_date(*args, first, datetime(2026, 11, 13)) == date(2026, 11, 10)
	assert task_service.submission_activity_date(*args, second, datetime(2026, 11, 13)) == date(2026, 11, 12)


def test_a_missing_submission_time_falls_back_to_the_approval_time(world_session):
	child = make_family(world_session, timezone_name="UTC")
	submission = SimpleNamespace(submitted_at=None)
	assert task_service.submission_activity_date(world_session, child.family_id, submission, datetime(2026, 11, 13, 1, 0)) == date(2026, 11, 13)


def test_review_submission_has_no_second_streak_calculation_and_dates_the_streak_by_activity():
	source = inspect.getsource(task_service.review_submission)
	assert "last_activity_date" not in source, "streak maths must live only in streak_service"
	assert "yesterday" not in source
	assert "activity_date=activity_date" in source
	assert source.count("record_qualifying_activity(") == 1


def test_review_submission_uses_one_approval_instant_and_keeps_the_original_submission_time():
	source = inspect.getsource(task_service.review_submission)
	assert "datetime.now(" in source and source.count("datetime.now(") == 1
	assert "submission.submitted_at =" not in source  # approval never rewrites when the child submitted
