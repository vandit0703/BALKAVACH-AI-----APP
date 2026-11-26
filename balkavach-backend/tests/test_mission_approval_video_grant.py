"""Approval -> 900 s video entitlement -> child's allowance, through the REAL routes and services.

Regression for docs/VIDEO_ENTITLEMENT_APPROVAL_FIX_REPORT.md: commit 960926c removed the
``grant_mission_video_entitlement`` call from ``review_submission``, so approved missions paid stars and XP
but no video time and the child stayed locked (free daily allowance is 0).

Test type: in-memory SQLite (see approval_world). Row locks and PostgreSQL unique-constraint races are not
exercised here; tests/test_parent_approval_postgres.py covers those against PostgreSQL when
TEST_DATABASE_URL is set.
"""

import pytest

from tests import video_world
from tests.approval_world import approval_db, make_family, make_submission  # noqa: F401


@pytest.fixture
def world(approval_db, monkeypatch):
	from fastapi.testclient import TestClient

	from app.core.dependencies import require_child, require_parent
	from app.db.session import get_db
	from app.main import app
	from tests import approval_world

	# The allowance endpoint also reads today's free-watch usage row.
	monkeypatch.setitem(approval_world.MODELS, "ChildVideoDailyUsage", video_world.ChildVideoDailyUsage)
	video_world.ChildVideoDailyUsage.__table__.create(approval_db.get_bind())
	family = make_family(approval_db)
	app.dependency_overrides[require_parent] = lambda: family.parent
	app.dependency_overrides[require_child] = lambda: family.child
	app.dependency_overrides[get_db] = lambda: approval_db
	try:
		yield TestClient(app, raise_server_exceptions=False), family, approval_db
	finally:
		for dependency in (require_parent, require_child, get_db):
			app.dependency_overrides.pop(dependency, None)


def _review(http, submission, decision="approved"):
	return http.post(f"/api/v1/reviews/submissions/{submission.id}", json={"decision": decision})


def _granted(session):
	session.expire_all()
	return sorted(row.granted_seconds for row in session.query(video_world.VideoAccessEntitlement))


def _allowance(http):
	response = http.get("/api/v1/video-access/allowance")
	assert response.status_code == 200, response.text
	return response.json()


def test_child_is_locked_before_and_unlocked_with_900_seconds_after_approval(world):
	http, family, session = world
	item = make_submission(session, family)

	before = _allowance(http)
	assert before["remaining_seconds"] == 0
	assert before["is_exhausted"] is True
	assert before["free_allowance_seconds"] == 0

	assert _review(http, item.submission).status_code == 200

	after = _allowance(http)
	assert after["remaining_seconds"] == 900
	assert after["mission_remaining_seconds"] == 900
	assert after["is_exhausted"] is False
	assert after["free_allowance_seconds"] == 0
	assert after["child_id"] == str(family.child.id)


def test_entitlement_belongs_to_the_submitting_child_and_submission(world):
	http, family, session = world
	item = make_submission(session, family)
	assert _review(http, item.submission).status_code == 200
	row = session.query(video_world.VideoAccessEntitlement).one()
	assert row.child_id == family.child.id
	assert row.submission_id == item.submission.id
	assert row.task_id == item.task.id
	assert row.source_type == "mission_reward"
	assert row.status == "active"
	assert row.consumed_seconds == 0
	assert row.expires_at is None  # carries forward across days


def test_two_approved_missions_accumulate_to_1800_seconds(world):
	http, family, session = world
	first = make_submission(session, family, title="Mission one")
	second = make_submission(session, family, title="Mission two", daily=False)
	assert _review(http, first.submission).status_code == 200
	assert _review(http, second.submission).status_code == 200
	assert _granted(session) == [900, 900]
	assert _allowance(http)["remaining_seconds"] == 1800


def test_approving_the_same_submission_twice_grants_900_seconds_total(world):
	http, family, session = world
	item = make_submission(session, family)
	assert _review(http, item.submission).status_code == 200
	assert _review(http, item.submission).status_code == 200
	assert _granted(session) == [900]
	assert _allowance(http)["remaining_seconds"] == 900


@pytest.mark.parametrize("decision", ["rejected", "resubmission_requested"])
def test_declined_or_retry_decisions_grant_no_time(world, decision):
	http, family, session = world
	item = make_submission(session, family)
	assert _review(http, item.submission, decision).status_code == 200
	assert _granted(session) == []
	assert _allowance(http)["remaining_seconds"] == 0


def test_a_pending_submission_grants_no_time(world):
	http, family, session = world
	make_submission(session, family)
	assert _granted(session) == []
	assert _allowance(http)["remaining_seconds"] == 0


def test_a_rejected_then_conflicting_approval_grants_nothing(world):
	http, family, session = world
	item = make_submission(session, family)
	assert _review(http, item.submission, "rejected").status_code == 200
	assert _review(http, item.submission, "approved").status_code == 409
	assert _granted(session) == []


def test_unused_earned_time_carries_forward_to_later_days(world):
	from datetime import datetime, timedelta, timezone

	from app.services.video_entitlement_service import get_child_video_allowance_today

	http, family, session = world
	item = make_submission(session, family)
	assert _review(http, item.submission).status_code == 200
	later = datetime.now(timezone.utc) + timedelta(days=3)
	allowance = get_child_video_allowance_today(session, family.child.id, family.family_id, now_utc=later)
	assert allowance["total_earned_today_seconds"] == 0  # nothing earned that day...
	assert allowance["remaining_seconds"] == 900  # ...but the earlier grant is still there
	assert allowance["free_allowance_seconds"] == 0


def test_consumption_never_drives_the_balance_negative(world):
	from app.services.video_entitlement_service import consume_video_allowance

	http, family, session = world
	item = make_submission(session, family)
	assert _review(http, item.submission).status_code == 200
	consumed = consume_video_allowance(session, family.child.id, family.family_id, 5000)
	session.commit()
	assert consumed == 900
	assert consume_video_allowance(session, family.child.id, family.family_id, 60) == 0
	after = _allowance(http)
	assert after["remaining_seconds"] == 0
	assert after["is_exhausted"] is True
