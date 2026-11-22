"""The child Home and Shorts feeds, tested against the REAL eligibility queries.

Test type: in-memory SQLite (``tests/feed_world.py``) plus the real FastAPI routes with the auth and database
dependencies overridden, and a fake YouTube client. It proves the filtering, freshness, recheck, allowance and
charging logic. It is NOT a PostgreSQL integration test (no row locks, no real schema) and it does not prove
what is in the production database.
"""

from datetime import datetime, timedelta, timezone
from uuid import uuid4

import pytest

from app.integrations.youtube import YouTubeQuotaError, YouTubeUnavailableError
from app.services import charging_path
from app.services.video_feed_diagnostics import diagnose, funnel
from app.services.video_service import eligible_feed, feed_languages
from app.services.youtube_review_service import recheck
from app.utils import utc_naive
from tests import video_world
from tests.feed_world import (
	AuditLog,
	ChildVideoDailyUsage,
	ChildVideoWatchHistory,
	FakeYouTube,
	VideoCategory,
	YouTubeContentReview,
	add_video,
	add_youtube,
	feed_db,  # noqa: F401  (fixture)
	good_item,
	make_child,
)


def titles(session, child, video_format=None, **kwargs):
	return {video.title for video in eligible_feed(session, child, kwargs.get("category_id"), 50, 0, video_format=video_format)}


# ---- approved, published, fresh --------------------------------------------------------------------------


def test_a_fresh_approved_published_youtube_video_is_in_the_home_feed(feed_db):
	child = make_child(feed_db)
	add_youtube(feed_db, title="Fresh", verified_hours_ago=1, duration_seconds=240)
	assert titles(feed_db, child, "regular") == {"Fresh"}


def test_a_fresh_approved_short_is_in_shorts_and_not_in_the_home_feed(feed_db):
	child = make_child(feed_db)
	add_youtube(feed_db, title="Quick", verified_hours_ago=1, duration_seconds=30)
	add_youtube(feed_db, title="Long", verified_hours_ago=1, duration_seconds=300)
	assert titles(feed_db, child, "short") == {"Quick"}
	assert titles(feed_db, child, "regular") == {"Long"}


def test_hosted_curated_videos_do_not_need_youtube_freshness(feed_db):
	child = make_child(feed_db)
	add_video(feed_db, title="Hosted", duration_seconds=200)
	assert titles(feed_db, child, "regular") == {"Hosted"}


# ---- stale approvals and the recheck workflow ------------------------------------------------------------


@pytest.mark.parametrize("hours", [73, 200, 24 * 17])
def test_an_approved_video_not_re_verified_within_the_window_still_appears(feed_db, hours):
	child = make_child(feed_db)
	add_youtube(feed_db, title="StaleOk", verified_hours_ago=hours)
	assert titles(feed_db, child, "regular") == {"StaleOk"}


def test_an_approved_video_that_was_never_verified_still_appears(feed_db):
	child = make_child(feed_db)
	add_youtube(feed_db, title="Never", verified_hours_ago=None)
	assert titles(feed_db, child, "regular") == {"Never"}


def test_a_video_just_inside_the_window_is_still_shown(feed_db):
	child = make_child(feed_db)
	add_youtube(feed_db, title="Edge", verified_hours_ago=71)
	assert titles(feed_db, child, "regular") == {"Edge"}


def test_recheck_refreshes_an_old_approved_video_without_re_approving_it(feed_db):
	child = make_child(feed_db)
	stale = add_youtube(feed_db, title="Stale", verified_hours_ago=200, youtube_id="aaaaaaaaaaa")
	assert titles(feed_db, child, "regular") == {"Stale"}

	counts = recheck(feed_db, FakeYouTube({"aaaaaaaaaaa": good_item("aaaaaaaaaaa", title="Stale")}), 200)

	assert counts == {"checked": 1, "verified": 1, "quarantined": 0, "unavailable": 0, "returned_to_review": 0}
	feed_db.refresh(stale.review)
	assert stale.review.status == "approved"  # unchanged: recheck never approves anything new
	assert titles(feed_db, child, "regular") == {"Stale"}


# ---- never shown --------------------------------------------------------------------------------------------


@pytest.mark.parametrize("status", ["pending_review", "quarantined", "rejected", "revoked", "unavailable"])
def test_a_video_that_is_not_approved_never_appears_even_if_published_and_fresh(feed_db, status):
	child = make_child(feed_db)
	add_youtube(feed_db, status=status, title="Nope", verified_hours_ago=1, is_published=True)
	assert titles(feed_db, child, "regular") == set()


def test_approved_but_not_made_for_kids_or_rights_not_cleared_never_appears(feed_db):
	child = make_child(feed_db)
	add_youtube(feed_db, title="NotKids", made_for_kids=False)
	add_youtube(feed_db, title="Unknown", made_for_kids=None)
	add_youtube(feed_db, title="NoRights", rights="not_cleared")
	add_youtube(feed_db, title="Unreviewed", rights="unreviewed")
	assert titles(feed_db, child, "regular") == set()


def test_an_unpublished_video_never_appears(feed_db):
	child = make_child(feed_db)
	add_youtube(feed_db, title="Hidden", is_published=False)
	add_video(feed_db, title="HiddenHosted", is_published=False)
	assert titles(feed_db, child, "regular") == set()


@pytest.mark.parametrize(
	"child_age, age_min, age_max",
	[(8, 13, 15), (14, 3, 5), (5, 6, 8), (8, 9, 12)],
)
def test_a_video_outside_the_childs_age_band_never_appears(feed_db, child_age, age_min, age_max):
	child = make_child(feed_db, age=child_age)
	add_youtube(feed_db, title="Other age", age_min=age_min, age_max=age_max)
	assert titles(feed_db, child, "regular") == set()


@pytest.mark.parametrize("age", [None, 2, 16, 30])
def test_a_child_without_a_valid_age_gets_nothing(feed_db, age):
	child = make_child(feed_db, age=age)
	add_youtube(feed_db, title="Any")
	assert titles(feed_db, child, "regular") == set()


def test_language_and_rating_are_enforced(feed_db):
	child = make_child(feed_db, language="en")
	add_youtube(feed_db, title="Gujarati only", language_code="gu")
	add_youtube(feed_db, title="Review required", content_rating="parent_review_required")
	add_video(feed_db, title="Adult", content_rating="mature")
	add_youtube(feed_db, title="English")
	assert titles(feed_db, child, "regular") == {"English"}


def test_a_gujarati_child_sees_gujarati_and_english_but_not_hindi(feed_db):
	child = make_child(feed_db, language="gu")
	add_youtube(feed_db, title="gu", language_code="gu")
	add_youtube(feed_db, title="en", language_code="en")
	add_youtube(feed_db, title="hi", language_code="hi")
	assert titles(feed_db, child, "regular") == {"gu", "en"}
	assert feed_languages("gu") == ["gu", "en"] and feed_languages("en") == ["en"]


def test_a_video_in_an_inactive_category_never_appears(feed_db):
	child = make_child(feed_db)
	category = VideoCategory(is_active=False)
	feed_db.add(category)
	feed_db.commit()
	add_youtube(feed_db, title="In retired", category_id=category.id)
	assert titles(feed_db, child, "regular") == set()


def test_a_duplicate_youtube_video_appears_once(feed_db):
	child = make_child(feed_db)
	first = add_youtube(feed_db, title="Dup one", youtube_id="hhhhhhhhhhh")
	second = add_youtube(feed_db, title="Dup two", youtube_id="hhhhhhhhhhh")
	assert len(eligible_feed(feed_db, child, None, 50, 0, video_format="regular")) == 1
	assert first.video.id != second.video.id


def test_completed_videos_stay_in_the_feed_after_unwatched_ones_without_any_parent_replay(feed_db):
	child = make_child(feed_db)
	seen = add_youtube(feed_db, title="Seen", display_order=0)
	replay = add_youtube(feed_db, title="Replay", display_order=1)
	add_youtube(feed_db, title="New", display_order=2)
	now = utc_naive(datetime.now(timezone.utc))
	for video, authorised in ((seen.video, False), (replay.video, True)):
		feed_db.add(
			ChildVideoWatchHistory(
				child_id=child.id, video_id=video.id, video_format="regular", started_at=now, last_watched_at=now,
				is_completed=True, parent_replay_authorized=authorised,
			)
		)
	feed_db.commit()
	ordered = [v.title for v in eligible_feed(feed_db, child, None, 50, 0, video_format="regular")]
	assert ordered[0] == "New" and set(ordered) == {"Seen", "Replay", "New"}


def test_pagination_returns_every_eligible_video_exactly_once(feed_db):
	child = make_child(feed_db)
	for index in range(7):
		add_youtube(feed_db, title=f"V{index}", display_order=index)
	seen = []
	for offset in (0, 3, 6, 9):
		seen += [v.title for v in eligible_feed(feed_db, child, None, 3, offset, video_format="regular")]
	assert seen == [f"V{i}" for i in range(7)]


# ---- diagnostics explain the same rules ------------------------------------------------------------------------


def test_the_funnel_names_the_rule_that_empties_the_feed_for_unapproved_content(feed_db):
	child = make_child(feed_db)
	add_youtube(feed_db, title="A", status="pending_review", is_published=True)
	add_youtube(feed_db, title="B", status="quarantined", is_published=True)
	result = funnel(feed_db, age=8, languages=["en"], child_id=child.id, video_format="regular")
	assert result["limiting_stage"] == "youtube_approved"
	assert result["eligible"] == 0
	assert result["diagnostic_counts"] == {
		"candidate_total": 2,
		"after_publication": 2,
		"after_moderation": 0,
		"after_age_language": 0,
		"eligible_before_paging": 0,
		"publication_status_counts": {"published": 2},
		"moderation_status_counts": {"pending_review": 1, "quarantined": 1},
		"youtube_id_counts": {"valid": 2, "missing": 0, "invalid": 0},
		"youtube_verification_counts": {"approved": 0, "recently_verified": 0, "not_recently_verified": 0},
	}
	stage = {row["stage"]: row for row in result["stages"]}
	assert stage["published"]["remaining"] == 2 and stage["youtube_approved"]["removed"] == 2


def test_the_funnel_agrees_with_the_feed(feed_db):
	child = make_child(feed_db)
	add_youtube(feed_db, title="Ok", duration_seconds=200)
	add_youtube(feed_db, title="Stale", verified_hours_ago=300)
	add_youtube(feed_db, title="Other lang", language_code="gu")
	add_video(feed_db, title="Hosted", duration_seconds=100)
	for fmt in ("regular", "short"):
		listed = eligible_feed(feed_db, child, None, 50, 0, video_format=fmt)
		assert funnel(feed_db, age=8, languages=["en"], child_id=child.id, video_format=fmt)["eligible"] == len(listed)


def test_diagnose_explains_old_verification_but_feed_remains_eligible(feed_db):
	child = make_child(feed_db)
	add_youtube(feed_db, title="A", verified_hours_ago=500, youtube_id="iiiiiiiiiii")
	report = diagnose(feed_db, child_id=child.id)
	assert report["youtube"]["not_recently_verified"] == 1 and report["youtube"]["recently_verified"] == 0
	assert any("not been re-verified recently" in line and "remain eligible" in line for line in report["findings"])

	recheck(feed_db, FakeYouTube({"iiiiiiiiiii": good_item("iiiiiiiiiii")}), 200)
	after = diagnose(feed_db, child_id=child.id)
	assert after["feeds"]["regular"]["eligible"] == 1
	assert all("youtube-recheck repairs" not in f for f in after.get("findings", []))


def test_diagnose_reports_a_missing_birth_date_and_an_exhausted_allowance(feed_db):
	no_birthday = make_child(feed_db, age=None)
	assert any("no birth date" in line for line in diagnose(feed_db, child_id=no_birthday.id)["findings"])

	child = make_child(feed_db)
	add_youtube(feed_db, title="Fine")
	_use_up_allowance(feed_db, child)
	report = diagnose(feed_db, child_id=child.id)
	assert report["allowance_exhausted"] is True
	assert any("allowance" in line for line in report["findings"])


def test_an_empty_first_page_logs_which_rule_removed_everything(feed_db, caplog):
	child = make_child(feed_db)
	add_youtube(feed_db, title="Not approved", status="pending_review", is_published=True)
	with caplog.at_level("INFO", logger="app.services.video_service"):
		assert eligible_feed(feed_db, child, None, 20, 0, video_format="regular") == []
	record = next(r for r in caplog.records if getattr(r, "event", "") == "videos.feed.empty")
	assert record.limiting_stage == "youtube_approved"
	assert record.stage_published == 1 and record.stage_youtube_approved == 0
	assert record.candidate_total == 1
	assert record.after_publication == 1
	assert record.after_moderation == 0
	assert record.after_age_language == 0
	assert record.final_returned_count == 0
	assert not hasattr(record, "age")
	assert "candidate_total=1" in record.message
	assert "publication_status_counts=published:1" in record.message
	assert "moderation_status_counts=pending_review:1" in record.message
	assert "youtube_id_counts=invalid:0,missing:0,valid:1" in record.message
	assert "youtube_verification_counts=approved:0,not_recently_verified:0,recently_verified:0" in record.message
	assert "youtube_approved:0/1" in record.message
	assert child.id.hex not in record.message


# ---- allowance ---------------------------------------------------------------------------------------------------


def _use_up_allowance(session, child):
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


# ---- the real routes ---------------------------------------------------------------------------------------------


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


def test_home_route_returns_the_eligible_videos_with_a_playable_id(api):
	http, child, session = api
	add_youtube(session, title="Counting", duration_seconds=240, youtube_id="jjjjjjjjjjj")
	add_youtube(session, title="Stale", duration_seconds=240, verified_hours_ago=300)
	add_youtube(session, title="Quick", duration_seconds=30)

	body = http.get("/api/v1/videos/feed").json()

	assert {item["title"] for item in body} == {"Counting", "Stale"}
	counting = next(item for item in body if item["title"] == "Counting")
	assert counting["youtube_video_id"] == "jjjjjjjjjjj"
	assert all(item["video_format"] == "regular" and item["video_source"] == "youtube" for item in body)
	assert all(item["youtube_video_id"] for item in body)


def test_shorts_route_returns_only_eligible_shorts(api):
	http, child, session = api
	add_youtube(session, title="Quick", duration_seconds=30)
	add_youtube(session, title="Stale quick", duration_seconds=30, verified_hours_ago=300)
	add_youtube(session, title="Long", duration_seconds=300)
	add_youtube(session, title="Unapproved quick", duration_seconds=30, status="pending_review", is_published=True)

	body = http.get("/api/v1/videos/shorts").json()

	assert {item["title"] for item in body} == {"Quick", "Stale quick"}
	assert all(item["video_format"] == "short" for item in body)


def test_both_routes_are_empty_only_when_nothing_is_eligible(api):
	http, child, session = api
	assert http.get("/api/v1/videos/feed").json() == []
	assert http.get("/api/v1/videos/shorts").json() == []
	add_youtube(session, title="Now eligible", duration_seconds=30)
	add_youtube(session, title="Also eligible", duration_seconds=200)
	assert len(http.get("/api/v1/videos/shorts").json()) == 1
	assert len(http.get("/api/v1/videos/feed").json()) == 1


def test_an_exhausted_allowance_keeps_listing_both_feeds_with_playback_locked(api):
	http, child, session = api
	add_youtube(session, title="Short", duration_seconds=30)
	add_youtube(session, title="Long", duration_seconds=200)
	assert http.get("/api/v1/videos/shorts").json() and http.get("/api/v1/videos/feed").json()
	_use_up_allowance(session, child)
	for path in ("/api/v1/videos/shorts", "/api/v1/videos/feed"):
		items = http.get(path).json()
		assert len(items) == 1
		assert items[0]["playback_locked"] is True and items[0]["youtube_video_id"] is None


def test_playback_progress_charges_the_free_allowance_through_the_one_authoritative_path(api):
	http, child, session = api
	video = add_youtube(session, title="Watch me", duration_seconds=200, youtube_id="kkkkkkkkkkk").video
	url = f"/api/v1/videos/watch-history/{video.id}/progress"

	first = http.post(url, json={"position_seconds": 0, "is_playing": True})
	assert first.status_code == 200 and first.json()["accepted_seconds"] == 0

	usage = session.query(ChildVideoDailyUsage).filter_by(child_id=child.id).one()
	usage.last_heartbeat_at = utc_naive(datetime.now(timezone.utc)) - timedelta(seconds=30)
	session.commit()
	second = http.post(url, json={"position_seconds": 30, "is_playing": True})

	assert second.status_code == 200
	assert second.json()["accepted_seconds"] == 30
	assert second.json()["remaining_allowance_seconds"] == 900 - 30
	session.refresh(usage)
	assert usage.free_watched_seconds == 30
	assert charging_path.play_tickets_active() is False


def test_playback_is_refused_once_the_allowance_is_used_up(api):
	http, child, session = api
	video = add_youtube(session, title="Watch me", duration_seconds=200).video
	_use_up_allowance(session, child)
	response = http.post(
		f"/api/v1/videos/watch-history/{video.id}/progress", json={"position_seconds": 5, "is_playing": True}
	)
	assert response.status_code == 403
	assert response.json()["error"]["code"] == "video_time_exhausted"


def test_a_stale_or_unapproved_video_cannot_be_played_even_by_id(api):
	http, child, session = api
	stale = add_youtube(session, title="Stale", verified_hours_ago=300).video
	pending = add_youtube(session, status="pending_review", is_published=True).video

	stale_response = http.post(
		f"/api/v1/videos/watch-history/{stale.id}/progress", json={"position_seconds": 1, "is_playing": True}
	)
	assert stale_response.status_code == 200, stale_response.text

	pending_response = http.post(
		f"/api/v1/videos/watch-history/{pending.id}/progress", json={"position_seconds": 1, "is_playing": True}
	)
	assert pending_response.status_code == 404


def test_an_age_ineligible_video_cannot_be_played_by_id(api):
	http, child, session = api
	video = add_youtube(session, title="Teens", age_min=13, age_max=15).video
	response = http.post(
		f"/api/v1/videos/watch-history/{video.id}/progress", json={"position_seconds": 1, "is_playing": True}
	)
	assert response.status_code == 403


def test_the_feed_never_exposes_a_media_url_for_hosted_videos(api):
	http, child, session = api
	add_video(session, title="Hosted", duration_seconds=200, thumbnail_url="https://cdn.example/t.jpg")
	item = http.get("/api/v1/videos/feed").json()[0]
	assert item["youtube_video_id"] is None
	assert not any(key in item for key in ("media_url", "video_url", "content_url", "url"))


# ---- the contract the Flutter app is tested against ---------------------------------------------------------------

import json  # noqa: E402
import os  # noqa: E402
from pathlib import Path  # noqa: E402
from uuid import UUID  # noqa: E402

CONTRACT = Path(__file__).resolve().parents[2] / "balkavach-frontend" / "test" / "fixtures" / "video_feed_contract.json"


def test_feed_responses_match_the_fixture_the_flutter_tests_use(api):
	"""The Flutter app is tested against ``video_feed_contract.json``; this keeps it equal to what the real routes return.

	Regenerate deliberately with ``UPDATE_FEED_FIXTURE=1 pytest tests/test_video_feed_real_filters.py``."""
	http, child, session = api
	long_video = add_youtube(
		session, title="Counting to ten", duration_seconds=240, youtube_id="aaaaaaaaaaa", display_order=1,
		id=UUID("11111111-1111-4111-8111-111111111111"), description=None,
	)
	long_video.review.channel_title = "Little Learners"
	add_youtube(
		session, title="Clap along", duration_seconds=30, youtube_id="bbbbbbbbbbb", display_order=1,
		id=UUID("22222222-2222-4222-8222-222222222222"), description=None,
	)
	session.commit()
	payload = {
		"feed": http.get("/api/v1/videos/feed").json(),
		"shorts": http.get("/api/v1/videos/shorts").json(),
	}
	# The same catalogue as the real routes return it once today's allowance is used up.
	_use_up_allowance(session, child)
	payload["feed_locked"] = http.get("/api/v1/videos/feed").json()
	payload["shorts_locked"] = http.get("/api/v1/videos/shorts").json()
	if os.environ.get("UPDATE_FEED_FIXTURE"):
		CONTRACT.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")
	assert json.loads(CONTRACT.read_text(encoding="utf-8")) == payload


# ---- recheck queue order -------------------------------------------------------------------------------------------


def test_permanently_unavailable_videos_never_starve_approved_ones_of_rechecks(feed_db):
	"""An unavailable video that is still unavailable keeps its old ``last_verified_at``, so it would sort first
	for ever. With ``limit`` or more of them, approved videos would never be re-verified and the feed would empty."""
	for index in range(3):
		add_youtube(feed_db, status="unavailable", verified_hours_ago=2000 + index, youtube_id=f"unavail{index:04d}")
	stale = add_youtube(feed_db, title="Needs it", verified_hours_ago=100, youtube_id="needsit0000")
	client = FakeYouTube({"needsit0000": good_item("needsit0000", title="Needs it")})

	counts = recheck(feed_db, client, 3)

	assert "needsit0000" in client.calls[0], "the approved video must be inside the checked batch"
	assert counts["verified"] == 1
	feed_db.refresh(stale.review)
	assert stale.review.last_verified_at > utc_naive(datetime.now(timezone.utc)) - timedelta(minutes=5)


def test_recheck_still_checks_unavailable_videos_when_there_is_room(feed_db):
	add_youtube(feed_db, title="Fine", verified_hours_ago=100, youtube_id="finefinefin")
	add_youtube(feed_db, status="unavailable", verified_hours_ago=2000, youtube_id="comesback00")
	client = FakeYouTube({y: good_item(y) for y in ("finefinefin", "comesback00")})
	counts = recheck(feed_db, client, 10)
	assert counts["checked"] == 2 and counts["returned_to_review"] == 1


def test_diagnose_counts_each_hidden_video_once_not_once_per_feed(feed_db):
	child = make_child(feed_db)
	add_youtube(feed_db, title="A", verified_hours_ago=400, duration_seconds=240)
	add_youtube(feed_db, title="B", verified_hours_ago=300, duration_seconds=30)
	report = diagnose(feed_db, child_id=child.id)
	assert report["feeds"]["regular"]["eligible"] == 1
	assert report["feeds"]["short"]["eligible"] == 1
	assert any("not been re-verified recently" in line and "remain eligible" in line for line in report["findings"])
