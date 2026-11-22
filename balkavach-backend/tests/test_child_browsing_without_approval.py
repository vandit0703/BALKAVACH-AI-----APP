"""A child browses Home and Shorts without any grown-up approval; playback and safety rules stay enforced.

Test type: in-memory SQLite (``tests/feed_world.py``, the REAL eligibility queries) behind the real FastAPI routes
with only the child sign-in and the database dependency overridden. No parent is signed in anywhere in this file,
which is the point: nothing in the browse path may need one. It is NOT PostgreSQL and says nothing about the
production data.
"""

from datetime import datetime, timezone

import pytest

from app.services.video_service import eligible_feed
from app.services.youtube_review_service import recheck
from app.utils import utc_naive
from tests.feed_world import (
	ChildVideoDailyUsage,
	ChildVideoWatchHistory,
	FakeYouTube,
	add_video,
	add_youtube,
	feed_db,  # noqa: F401  (fixture)
	good_item,
	make_child,
)


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


def use_up_allowance(session, child):
	from app.services.timezone_service import local_today

	session.add(
		ChildVideoDailyUsage(
			child_id=child.id,
			local_date=local_today(session, child.family_id),
			free_watched_seconds=900,
			last_heartbeat_at=utc_naive(datetime.now(timezone.utc)),
			is_playing=False,
		)
	)
	session.commit()


def titles_of(response) -> list[str]:
	assert response.status_code == 200, response.text
	return [item["title"] for item in response.json()]


# ---- 1-3: opening Home, browsing and Shorts need no parent -----------------------------------------------------


def test_a_child_opens_home_and_shorts_with_no_parent_signed_in(api):
	http, child, session = api
	add_youtube(session, title="Counting", duration_seconds=240)
	add_youtube(session, title="Quick", duration_seconds=30)
	assert titles_of(http.get("/api/v1/videos/feed")) == ["Counting"]
	assert titles_of(http.get("/api/v1/videos/shorts")) == ["Quick"]


def test_browsing_does_not_depend_on_any_parent_or_gate_dependency():
	from app.api.v1.videos import router
	from app.core.dependencies import require_child, require_parent

	feed_routes = [route for route in router.routes if route.path in {"/videos/feed", "/videos/shorts"}]
	assert len(feed_routes) == 2
	for route in feed_routes:
		called = {dependency.call for dependency in route.dependant.dependencies}
		assert require_child in called
		assert require_parent not in called


# ---- 8: an exhausted allowance keeps the catalogue, locks playback ---------------------------------------------


def test_an_exhausted_allowance_keeps_the_catalogue_visible_but_locks_playback(api):
	http, child, session = api
	add_youtube(session, title="Short", duration_seconds=30, youtube_id="sssssssssss")
	add_youtube(session, title="Long", duration_seconds=200, youtube_id="lllllllllll")
	use_up_allowance(session, child)

	feed = http.get("/api/v1/videos/feed").json()
	shorts = http.get("/api/v1/videos/shorts").json()

	assert [item["title"] for item in feed] == ["Long"]
	assert [item["title"] for item in shorts] == ["Short"]
	for item in feed + shorts:
		assert item["playback_locked"] is True
		assert item["youtube_video_id"] is None, "the lock must not be bypassable by reading the feed JSON"
		assert item["thumbnail_url"] is None or item["thumbnail_url"].startswith("https://")


def test_playable_ids_are_present_and_unlocked_while_time_remains(api):
	http, child, session = api
	add_youtube(session, title="Long", duration_seconds=200, youtube_id="lllllllllll")
	item = http.get("/api/v1/videos/feed").json()[0]
	assert item["playback_locked"] is False
	assert item["youtube_video_id"] == "lllllllllll"


def test_the_lock_is_not_a_way_around_the_other_safety_rules(api):
	http, child, session = api
	add_youtube(session, title="Fine", duration_seconds=200)
	add_youtube(session, title="Pending", duration_seconds=200, status="pending_review", is_published=True)
	add_youtube(session, title="Withdrawn", duration_seconds=200, status="unavailable", is_published=False)
	add_youtube(session, title="Quarantined", duration_seconds=200, status="quarantined", is_published=False)
	add_youtube(session, title="Teens", duration_seconds=200, age_min=13, age_max=15)
	add_youtube(session, title="Mature", duration_seconds=200, content_rating="mature")
	add_youtube(session, title="OldButApproved", duration_seconds=200, verified_hours_ago=300)
	use_up_allowance(session, child)
	assert set(titles_of(http.get("/api/v1/videos/feed"))) == {"Fine", "OldButApproved"}


def test_playback_stays_refused_at_zero_allowance(api):
	http, child, session = api
	video = add_youtube(session, title="Watch me", duration_seconds=200).video
	use_up_allowance(session, child)
	response = http.post(
		f"/api/v1/videos/watch-history/{video.id}/progress", json={"position_seconds": 5, "is_playing": True}
	)
	assert response.status_code == 403
	assert response.json()["error"]["code"] == "video_time_exhausted"


def test_continue_watching_keeps_its_rows_but_withholds_ids_at_zero_allowance(api):
	http, child, session = api
	video = add_youtube(session, title="Half done", duration_seconds=200, youtube_id="hhhhhhhhhhh").video
	now = utc_naive(datetime.now(timezone.utc))
	session.add(
		ChildVideoWatchHistory(
			child_id=child.id, video_id=video.id, youtube_video_id="hhhhhhhhhhh", video_format="regular",
			started_at=now, last_watched_at=now, last_position_seconds=40, completion_percentage=20,
			is_completed=False,
		)
	)
	session.commit()
	use_up_allowance(session, child)
	rows = http.get("/api/v1/videos/watch-history/continue-watching").json()
	assert [row["title"] for row in rows] == ["Half done"]
	assert rows[0]["youtube_video_id"] is None


# ---- 4-6: moderation is untouched ------------------------------------------------------------------------------


@pytest.mark.parametrize("status", ["pending_review", "rejected", "unavailable", "quarantined", "revoked"])
def test_a_video_the_admin_has_not_approved_or_has_withdrawn_stays_hidden(api, status):
	http, child, session = api
	add_youtube(session, title="Hidden", status=status, is_published=status == "pending_review")
	assert titles_of(http.get("/api/v1/videos/feed")) == []
	assert titles_of(http.get("/api/v1/videos/shorts")) == []


def test_an_unpublished_hosted_video_stays_hidden(api):
	http, child, session = api
	add_video(session, title="Draft", duration_seconds=200, is_published=False)
	assert titles_of(http.get("/api/v1/videos/feed")) == []


def test_an_age_inappropriate_video_stays_hidden_for_a_young_child(api):
	http, child, session = api
	add_youtube(session, title="For teens", duration_seconds=200, age_min=13, age_max=15)
	assert titles_of(http.get("/api/v1/videos/feed")) == []


# ---- finished videos stay browsable (no parent replay approval) ------------------------------------------------


def test_finished_videos_stay_in_the_feed_after_the_unwatched_ones_without_a_parent_replay(api):
	http, child, session = api
	seen = add_youtube(session, title="Seen", display_order=0).video
	add_youtube(session, title="New", display_order=1)
	now = utc_naive(datetime.now(timezone.utc))
	session.add(
		ChildVideoWatchHistory(
			child_id=child.id, video_id=seen.id, video_format="regular", started_at=now, last_watched_at=now,
			is_completed=True, parent_replay_authorized=False,
		)
	)
	session.commit()
	assert titles_of(http.get("/api/v1/videos/feed")) == ["New", "Seen"]


def test_a_child_who_finished_everything_still_sees_the_catalogue(feed_db):
	child = make_child(feed_db)
	only = add_youtube(feed_db, title="Only one").video
	now = utc_naive(datetime.now(timezone.utc))
	feed_db.add(
		ChildVideoWatchHistory(
			child_id=child.id, video_id=only.id, video_format="regular", started_at=now, last_watched_at=now,
			is_completed=True,
		)
	)
	feed_db.commit()
	assert [v.title for v in eligible_feed(feed_db, child, None, 20, 0, video_format="regular")] == ["Only one"]


# ---- 7: verification age no longer hides approved videos -------------------------------------------------------


def test_old_verification_does_not_hide_the_video_and_recheck_refreshes_metadata(api, caplog):
	http, child, session = api
	stale = add_youtube(session, title="Stale", duration_seconds=200, verified_hours_ago=300, youtube_id="ttttttttttt")

	assert titles_of(http.get("/api/v1/videos/feed")) == ["Stale"]

	counts = recheck(session, FakeYouTube({"ttttttttttt": good_item("ttttttttttt", title="Stale")}), 200)

	assert counts["verified"] == 1
	session.refresh(stale.review)
	assert stale.review.status == "approved", "rechecking refreshes verification metadata; it does not re-approve"
	assert titles_of(http.get("/api/v1/videos/feed")) == ["Stale"]


# ---- 9: feed and playback agree --------------------------------------------------------------------------------


def test_every_video_in_the_feed_can_be_played_and_every_hidden_one_cannot(api):
	http, child, session = api
	shown = add_youtube(session, title="Shown", duration_seconds=200).video
	hidden = [
		add_youtube(session, title="Pending", status="pending_review", is_published=True).video,
		add_youtube(session, title="Quarantined", status="quarantined", is_published=True).video,
		add_youtube(session, title="Teens", age_min=13, age_max=15).video,
	]
	assert titles_of(http.get("/api/v1/videos/feed")) == ["Shown"]
	url = "/api/v1/videos/watch-history/{}/progress"
	assert http.post(url.format(shown.id), json={"position_seconds": 0, "is_playing": True}).status_code == 200
	for video in hidden:
		assert http.post(url.format(video.id), json={"position_seconds": 0, "is_playing": True}).status_code in (403, 404)


# ---- 10: a failing server is an error, never an empty feed -----------------------------------------------------


def test_a_server_failure_is_an_error_response_not_an_empty_list(api, monkeypatch):
	from fastapi.testclient import TestClient

	from app.api.v1 import videos as videos_api
	from app.main import app

	http, child, session = api

	def boom(*args, **kwargs):
		raise RuntimeError("database unavailable")

	monkeypatch.setattr(videos_api, "eligible_feed", boom)
	failing = TestClient(app, raise_server_exceptions=False)
	for path in ("/api/v1/videos/feed", "/api/v1/videos/shorts"):
		response = failing.get(path)
		assert response.status_code >= 500, f"{path} must fail loudly, got {response.status_code}"
		assert not isinstance(response.json(), list)
