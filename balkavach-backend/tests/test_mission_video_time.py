"""Each approved standard mission unlocks exactly MISSION_REWARD_ALLOWANCE_SECONDS (225 s) of video, whole or nothing,
on top of the free daily allowance, and that time is counted genuinely.

Test type: in-memory SQLite (``tests/feed_world.py``) with the real grant, allowance and charging code and the real
progress route; the server clock is controlled by moving the stored last-heartbeat time back. Not PostgreSQL.
"""

from datetime import datetime, timedelta, timezone
from types import SimpleNamespace
from uuid import uuid4

import pytest

from app.services.video_entitlement_service import (
	FREE_DAILY_ALLOWANCE_SECONDS,
	MISSION_REWARD_ALLOWANCE_SECONDS,
	get_child_video_allowance_today,
	grant_mission_video_entitlement,
)
from app.utils import utc_naive
from tests import video_world
from tests.feed_world import ChildVideoDailyUsage, add_youtube, feed_db, make_child  # noqa: F401  (fixture)


def approve_mission(session, child):
	task = SimpleNamespace(id=uuid4(), family_id=child.family_id)
	entitlement = grant_mission_video_entitlement(session, child, task, SimpleNamespace(id=uuid4()))
	session.commit()
	return entitlement


def set_cap(session, child, seconds):
	row = session.query(video_world.FamilySetting).filter_by(family_id=child.family_id).one()
	row.video_settings = {"daily_limit_seconds": seconds}
	session.commit()


def remaining(session, child):
	return get_child_video_allowance_today(session, child.id, child.family_id)["remaining_seconds"]


def test_one_approved_mission_unlocks_exactly_one_missions_time(feed_db):
	child = make_child(feed_db)
	before = remaining(feed_db, child)
	entitlement = approve_mission(feed_db, child)
	assert MISSION_REWARD_ALLOWANCE_SECONDS == 225
	assert FREE_DAILY_ALLOWANCE_SECONDS == 900
	assert before == FREE_DAILY_ALLOWANCE_SECONDS
	assert entitlement.granted_seconds == 225
	assert remaining(feed_db, child) - before == 225


def test_each_mission_adds_another_missions_time(feed_db):
	child = make_child(feed_db)
	for count in (1, 2, 3):
		approve_mission(feed_db, child)
		assert remaining(feed_db, child) == FREE_DAILY_ALLOWANCE_SECONDS + count * MISSION_REWARD_ALLOWANCE_SECONDS


def test_approving_the_same_submission_twice_pays_once(feed_db):
	child = make_child(feed_db)
	task = SimpleNamespace(id=uuid4(), family_id=child.family_id)
	submission = SimpleNamespace(id=uuid4())
	first = grant_mission_video_entitlement(feed_db, child, task, submission)
	second = grant_mission_video_entitlement(feed_db, child, task, submission)
	feed_db.commit()
	assert first.id == second.id
	assert remaining(feed_db, child) == FREE_DAILY_ALLOWANCE_SECONDS + MISSION_REWARD_ALLOWANCE_SECONDS


def test_a_mission_never_unlocks_a_partial_slice_when_the_cap_is_nearly_used(feed_db):
	child = make_child(feed_db)
	set_cap(feed_db, child, 1000)  # room for four whole missions (900 s), plus 100 s that is not a mission's worth
	for _ in range(4):
		assert approve_mission(feed_db, child).granted_seconds == MISSION_REWARD_ALLOWANCE_SECONDS
	assert approve_mission(feed_db, child) is None
	assert remaining(feed_db, child) == FREE_DAILY_ALLOWANCE_SECONDS + 4 * MISSION_REWARD_ALLOWANCE_SECONDS


# ---- counting one mission's time genuinely, through the real progress route ----------------------------------------


@pytest.fixture
def api(feed_db):
	from fastapi.testclient import TestClient

	from app.core.dependencies import require_child
	from app.db.session import get_db
	from app.main import app

	child = make_child(feed_db)
	app.dependency_overrides[require_child] = lambda: child
	app.dependency_overrides[get_db] = lambda: feed_db
	try:
		yield TestClient(app), child, feed_db
	finally:
		app.dependency_overrides.pop(require_child, None)
		app.dependency_overrides.pop(get_db, None)


def report(http, session, child, video, position, *, playing=True, seconds_since_last=30):
	"""One progress report, ``seconds_since_last`` seconds of server time after the previous one."""
	usage = session.query(ChildVideoDailyUsage).filter_by(child_id=child.id).one_or_none()
	if usage is not None:
		usage.last_heartbeat_at = utc_naive(datetime.now(timezone.utc)) - timedelta(seconds=seconds_since_last)
		session.commit()
	return http.post(
		f"/api/v1/videos/watch-history/{video.id}/progress",
		json={"position_seconds": position, "is_playing": playing},
	)


def use_free_time(session, child):
	from app.services.timezone_service import local_today

	session.add(
		ChildVideoDailyUsage(
			child_id=child.id,
			local_date=local_today(session, child.family_id),
			free_watched_seconds=FREE_DAILY_ALLOWANCE_SECONDS,
			last_heartbeat_at=utc_naive(datetime.now(timezone.utc)),
			is_playing=False,
		)
	)
	session.commit()


def test_one_missions_worth_of_real_playback_uses_exactly_one_missions_time(api):
	http, child, session = api
	video = add_youtube(session, title="Long", duration_seconds=3600).video
	use_free_time(session, child)
	approve_mission(session, child)
	assert remaining(session, child) == MISSION_REWARD_ALLOWANCE_SECONDS

	position = 0
	assert report(http, session, child, video, position, playing=True, seconds_since_last=0).status_code == 200
	charged = 0
	for _ in range(MISSION_REWARD_ALLOWANCE_SECONDS // 15):  # 15 reports x 15 s of server time = 225 s
		position += 15
		response = report(http, session, child, video, position, seconds_since_last=15)
		assert response.status_code == 200, response.text
		charged += response.json()["accepted_seconds"]

	assert charged == MISSION_REWARD_ALLOWANCE_SECONDS
	assert remaining(session, child) == 0
	assert report(http, session, child, video, position + 30).status_code == 403  # time is up


def test_paused_time_and_long_gaps_are_not_counted(api):
	http, child, session = api
	video = add_youtube(session, title="Long", duration_seconds=3600).video
	use_free_time(session, child)
	approve_mission(session, child)

	report(http, session, child, video, 0, playing=True, seconds_since_last=0)
	paused = report(http, session, child, video, 10, playing=False, seconds_since_last=10)
	assert paused.json()["accepted_seconds"] == 10  # the 10 s before the pause was real playback
	idle = report(http, session, child, video, 10, playing=False, seconds_since_last=600)
	assert idle.json()["accepted_seconds"] == 0  # ten paused minutes cost nothing
	resumed = report(http, session, child, video, 10, playing=True, seconds_since_last=5)
	assert resumed.json()["accepted_seconds"] == 0
	gap = report(http, session, child, video, 40, playing=True, seconds_since_last=3600)
	assert gap.json()["accepted_seconds"] == 0, "a disconnected interval is not verified playback"
	assert remaining(session, child) == MISSION_REWARD_ALLOWANCE_SECONDS - 10


def test_the_client_cannot_inflate_or_deflate_the_count_by_its_position(api):
	http, child, session = api
	video = add_youtube(session, title="Long", duration_seconds=3600).video
	use_free_time(session, child)
	approve_mission(session, child)

	report(http, session, child, video, 0, playing=True, seconds_since_last=0)
	seek = report(http, session, child, video, 1500, playing=True, seconds_since_last=30)
	assert seek.json()["accepted_seconds"] == 0, "a seek is not verified playback"
	sneaky = report(http, session, child, video, 1525, playing=False, seconds_since_last=25)
	assert sneaky.json()["accepted_seconds"] == 25, "the interval before pause remains verified"
	paused_position = report(http, session, child, video, 1550, playing=False, seconds_since_last=25)
	assert paused_position.json()["accepted_seconds"] == 0, "paused playback is not verified"
	assert remaining(session, child) == MISSION_REWARD_ALLOWANCE_SECONDS - 25


def test_two_devices_share_one_daily_cap(api):
	http, child, session = api
	first_video = add_youtube(session, title="Device one", duration_seconds=3600).video
	second_video = add_youtube(session, title="Device two", duration_seconds=3600).video
	from tests.feed_world import ChildVideoDailyUsage
	from app.services.timezone_service import local_today

	session.add(
		ChildVideoDailyUsage(
			child_id=child.id,
			local_date=local_today(session, child.family_id),
			free_watched_seconds=880,
			last_heartbeat_at=utc_naive(datetime.now(timezone.utc)),
			is_playing=False,
		)
	)
	session.commit()

	assert report(http, session, child, first_video, 0, seconds_since_last=0).status_code == 200
	charged = report(http, session, child, first_video, 20, seconds_since_last=20)
	assert charged.json()["accepted_seconds"] == 20
	assert remaining(session, child) == 0
	refused = http.post(
		f"/api/v1/videos/watch-history/{second_video.id}/progress",
		json={"position_seconds": 20, "is_playing": True},
	)
	assert refused.status_code == 403
