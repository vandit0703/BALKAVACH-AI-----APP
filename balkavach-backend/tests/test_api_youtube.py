"""YouTube moderation end to end on the isolated test database.

Requires TEST_DATABASE_URL with migration 0008 applied. YouTube itself is
replaced by an in-memory fake; no real API call or key is involved.
"""

from datetime import date, datetime, timedelta, timezone

import pytest

from app.api.v1 import videos as video_routes
from app.db.base import get_model, has_model
from app.schemas.video import YouTubeDiscoverRequest
from app.services.youtube_review_service import discover, discover_trusted

VIDEO_ID = "dQw4w9WgXcQ"
OTHER_ID = "abcdefghijk"
TRUSTED_CHANNEL_ID = "UC1111111111111111111111"


def _item(video_id: str, duration: str = "PT45S", **status):
	return {
		"id": video_id,
		"snippet": {
			"title": f"Science {video_id}",
			"description": "Learning for children.",
			"channelId": TRUSTED_CHANNEL_ID,
			"channelTitle": "Kids Science",
			"liveBroadcastContent": "none",
			"thumbnails": {"high": {"url": f"https://i.ytimg.com/vi/{video_id}/hqdefault.jpg"}},
		},
		# 45 s: a Short under the 1-60 s rule. Tests needing a regular video
		# pass a longer duration.
		"contentDetails": {"duration": duration},
		"status": {"privacyStatus": "public", "embeddable": True, "uploadStatus": "processed", "madeForKids": True, **status},
	}


class FakeYouTube:
	def __init__(self):
		self.items = {VIDEO_ID: _item(VIDEO_ID), OTHER_ID: _item(OTHER_ID, madeForKids=False)}

	def search(self, topic, **kwargs):
		return {"video_ids": [VIDEO_ID, OTHER_ID, VIDEO_ID], "next_page_token": "NEXT"}

	def videos(self, ids, use_cache=True):
		return {video_id: self.items[video_id] for video_id in ids if video_id in self.items}


@pytest.fixture
def youtube(api, monkeypatch):
	if not has_model("YouTubeContentReview"):
		pytest.skip("Migration 0008 is not applied to the test database")
	fake = FakeYouTube()
	monkeypatch.setattr(video_routes, "get_youtube_client", lambda: fake)
	return fake


def _discover(api, admin):
	response = api.post("/admin/videos/youtube/discover", admin["token"], {"topic": "science"})
	assert response.status_code == 200, response.text
	return {row["youtube_video_id"]: row for row in response.json()["created"]}


def _approve(api, admin, review_id, **overrides):
	body = {"age_min": 6, "age_max": 8, "language_code": "en", "rights_status": "cleared", **overrides}
	return api.post(f"/admin/videos/youtube/reviews/{review_id}/approve", admin["token"], body)


def _feed_ids(api, token, path=None):
	"""Ids in one feed, or (path=None) everything the child can see in either."""
	if path is None:
		return _feed_ids(api, token, "/videos/feed") | _feed_ids(api, token, "/videos/shorts")
	response = api.get(path, token)
	assert response.status_code == 200, response.text
	return {item["youtube_video_id"] for item in response.json() if item["video_source"] == "youtube"}


def _feed_items(api, token, path):
	response = api.get(path, token)
	assert response.status_code == 200, response.text
	return {item["youtube_video_id"]: item for item in response.json()}


def _family_with_age(api, age=10):
	ctx = api.family_with_child()
	ChildProfile = get_model("ChildProfile")
	birth_date = date.today().replace(year=date.today().year - age)
	child = api.session.query(ChildProfile).filter(ChildProfile.id == ctx["child"]["id"]).one()
	child.date_of_birth = birth_date
	api.session.commit()
	return ctx


def test_discovery_deduplicates_and_screens(api, youtube):
	admin = api.make_admin()
	created = _discover(api, admin)
	assert set(created) == {VIDEO_ID, OTHER_ID}
	assert created[VIDEO_ID]["status"] == "pending_review"
	assert created[VIDEO_ID]["discovery_topic"] == "science"
	assert created[OTHER_ID]["status"] == "quarantined"
	assert "not_made_for_kids" in created[OTHER_ID]["screening_flags"]
	again = api.post("/admin/videos/youtube/discover", admin["token"], {"topic": "science"}).json()
	assert again["created"] == [] and again["skipped_existing"] == 2


def test_scheduled_discovery_automatically_publishes_clean_non_trusted_video(api, youtube):
	admin = api.make_admin()
	ctx = _family_with_age(api)
	User = get_model("User")
	actor = api.session.query(User).filter(User.id == admin["id"]).one()
	result = discover(
		api.session,
		actor,
		youtube,
		YouTubeDiscoverRequest(topic="science", shorts=True),
		auto_publish=True,
	)

	assert result["automatically_published"] == 1
	assert result["created"][0]["publication_source"] == "automatic"
	assert _feed_ids(api, ctx["child"]["token"], "/videos/shorts") == {VIDEO_ID}


def test_existing_pending_candidate_is_reprocessed_by_auto_discovery(api, youtube):
	admin = api.make_admin()
	ctx = _family_with_age(api)
	actor = api.session.query(get_model("User")).filter(get_model("User").id == admin["id"]).one()
	first = discover(
		api.session,
		actor,
		youtube,
		YouTubeDiscoverRequest(topic="science"),
	)
	assert first["automatically_published"] == 0
	second = discover(
		api.session,
		actor,
		youtube,
		YouTubeDiscoverRequest(topic="science"),
		auto_publish=True,
	)
	assert second["automatically_published"] == 1
	assert _feed_ids(api, ctx["child"]["token"], "/videos/shorts") == {VIDEO_ID}


def test_trusted_channel_rights_are_inherited_on_existing_pending_candidate(api, youtube):
	if not has_model("YouTubeTrustedChannel"):
		pytest.skip("Migration 0010 is not applied to the test database")
	admin = api.make_admin()
	actor = api.session.query(get_model("User")).filter(get_model("User").id == admin["id"]).one()
	discover(api.session, actor, youtube, YouTubeDiscoverRequest(topic="science"))
	trusted = get_model("YouTubeTrustedChannel")(
		channel_id=TRUSTED_CHANNEL_ID,
		channel_title="Kids Science",
		age_min=6,
		age_max=8,
		language_code="en",
		rights_status="cleared",
		is_active=True,
		created_by=actor.id,
	)
	api.session.add(trusted)
	api.session.commit()
	result = discover_trusted(api.session, actor, youtube, 10)
	Review = get_model("YouTubeContentReview")
	Video = get_model("Video")
	review = api.session.query(Review).filter(Review.youtube_video_id == VIDEO_ID).one()
	video = api.session.query(Video).filter(Video.id == review.video_id).one()
	assert result["automatically_published"] == 1
	assert review.status == "approved"
	assert review.rights_status == "cleared"
	assert review.publication_source == "automatic"
	assert video.is_published is True
	assert (video.age_min, video.age_max) == (6, 8)


def test_approved_unpublished_short_is_revalidated_and_published(api, youtube):
	admin = api.make_admin()
	ctx = _family_with_age(api, 7)
	review = _discover(api, admin)[VIDEO_ID]
	assert _approve(api, admin, review["id"]).status_code == 200
	Video = get_model("Video")
	video = api.session.query(Video).filter(Video.id == review["video_id"]).one()
	video.is_published = False
	api.session.commit()
	response = api.post(
		"/admin/videos/youtube/publish-approved",
		admin["token"],
		{"limit": 50},
	)
	assert response.status_code == 200, response.text
	assert response.json()["newly_published"] == 1
	assert _feed_ids(api, ctx["child"]["token"], "/videos/shorts") == {VIDEO_ID}


def test_bulk_publish_keeps_rights_uncleared_video_out_of_feed(api, youtube):
	admin = api.make_admin()
	ctx = _family_with_age(api, 7)
	review_data = _discover(api, admin)[VIDEO_ID]
	assert _approve(api, admin, review_data["id"]).status_code == 200
	Review = get_model("YouTubeContentReview")
	Video = get_model("Video")
	review = api.session.query(Review).filter(Review.id == review_data["id"]).one()
	video = api.session.query(Video).filter(Video.id == review_data["video_id"]).one()
	review.rights_status = "not_cleared"
	video.is_published = False
	api.session.commit()
	response = api.post(
		"/admin/videos/youtube/publish-approved",
		admin["token"],
		{"limit": 50},
	)
	assert response.status_code == 200, response.text
	assert response.json()["newly_published"] == 0
	assert response.json()["blocked_by_reason"]["rights_not_cleared"] == 1
	assert _feed_ids(api, ctx["child"]["token"], "/videos/shorts") == set()


def test_quarantine_must_be_re_evaluated_before_explicit_approval(api, youtube):
	admin = api.make_admin()
	ctx = _family_with_age(api, 7)
	review_data = _discover(api, admin)[OTHER_ID]
	assert review_data["status"] == "quarantined"
	youtube.items[OTHER_ID]["status"]["madeForKids"] = True
	rechecked = api.post(
		f"/admin/videos/youtube/reviews/{review_data['id']}/reevaluate",
		admin["token"],
	)
	assert rechecked.status_code == 200, rechecked.text
	assert rechecked.json()["status"] == "pending_review"
	assert _feed_ids(api, ctx["child"]["token"]) == set()
	approved = _approve(api, admin, review_data["id"])
	assert approved.status_code == 200, approved.text
	assert _feed_ids(api, ctx["child"]["token"], "/videos/shorts") == {OTHER_ID}


@pytest.mark.parametrize(("age", "age_min", "age_max"), [(4, 3, 5), (7, 6, 8), (10, 9, 12), (14, 13, 15)])
def test_each_approved_age_band_is_visible_to_eligible_child(api, youtube, age, age_min, age_max):
	admin = api.make_admin()
	ctx = _family_with_age(api, age)
	review = _discover(api, admin)[VIDEO_ID]
	response = _approve(api, admin, review["id"], age_min=age_min, age_max=age_max)
	assert response.status_code == 200, response.text
	assert _feed_ids(api, ctx["child"]["token"]) == {VIDEO_ID}


def test_pending_and_quarantined_videos_never_reach_children(api, youtube):
	admin = api.make_admin()
	ctx = _family_with_age(api)
	_discover(api, admin)
	assert _feed_ids(api, ctx["child"]["token"]) == set()
	assert _feed_ids(api, ctx["child"]["token"], "/videos/shorts") == set()


def test_rejected_video_never_reaches_child_feed(api, youtube):
	admin = api.make_admin()
	ctx = _family_with_age(api)
	review = _discover(api, admin)[VIDEO_ID]
	response = api.post(
		f"/admin/videos/youtube/reviews/{review['id']}/reject",
		admin["token"],
		{"notes": "Not suitable for the intended audience."},
	)
	assert response.status_code == 200 and response.json()["status"] == "rejected"
	assert _feed_ids(api, ctx["child"]["token"]) == set()


def test_missing_child_age_excludes_approved_video(api, youtube):
	admin = api.make_admin()
	ctx = _family_with_age(api)
	review = _discover(api, admin)[VIDEO_ID]
	assert _approve(api, admin, review["id"]).status_code == 200
	assert _feed_ids(api, ctx["child"]["token"]) == set()


def test_approved_video_appears_then_revocation_removes_it_immediately(api, youtube):
	admin = api.make_admin()
	ctx = _family_with_age(api)
	review = _discover(api, admin)[VIDEO_ID]
	response = _approve(api, admin, review["id"])
	assert response.status_code == 200, response.text
	assert _feed_ids(api, ctx["child"]["token"]) == {VIDEO_ID}
	assert _feed_ids(api, ctx["child"]["token"], "/videos/shorts") == {VIDEO_ID}

	revoked = api.post(f"/admin/videos/youtube/reviews/{review['id']}/revoke", admin["token"], {"reason": "parent complaint"})
	assert revoked.status_code == 200 and revoked.json()["status"] == "revoked"
	assert _feed_ids(api, ctx["child"]["token"]) == set()
	assert _approve(api, admin, review["id"]).status_code == 409


def test_not_made_for_kids_cannot_be_approved(api, youtube):
	admin = api.make_admin()
	review = _discover(api, admin)[OTHER_ID]
	response = _approve(api, admin, review["id"], notes="looked fine")
	assert response.status_code == 409 and response.json()["error"]["code"] == "not_made_for_kids"


def test_unavailable_search_candidate_is_retained_for_review(api, youtube):
	admin = api.make_admin()
	youtube.items.pop(VIDEO_ID)
	created = _discover(api, admin)[VIDEO_ID]
	assert created["status"] == "unavailable"
	assert created["screening_flags"] == ["not_returned"]
	assert created["reviewed_at"] is None


def test_video_that_disappears_becomes_unavailable(api, youtube):
	admin = api.make_admin()
	ctx = _family_with_age(api)
	review = _discover(api, admin)[VIDEO_ID]
	assert _approve(api, admin, review["id"]).status_code == 200
	del youtube.items[VIDEO_ID]
	result = api.post("/admin/videos/youtube/recheck", admin["token"], {"limit": 10}).json()
	assert result["unavailable"] == 1
	assert _feed_ids(api, ctx["child"]["token"]) == set()


def test_stale_verification_hides_the_video(api, youtube):
	admin = api.make_admin()
	ctx = _family_with_age(api)
	review = _discover(api, admin)[VIDEO_ID]
	assert _approve(api, admin, review["id"]).status_code == 200
	Review = get_model("YouTubeContentReview")
	row = api.session.query(Review).filter(Review.id == review["id"]).one()
	row.last_verified_at = datetime.now(timezone.utc) - timedelta(days=60)
	api.session.commit()
	assert _feed_ids(api, ctx["child"]["token"]) == set()


def test_generic_admin_routes_cannot_bypass_review(api, youtube):
	admin = api.make_admin()
	review = _discover(api, admin)[VIDEO_ID]
	assert api.post(f"/admin/videos/{review['video_id']}/publish", admin["token"]).status_code == 409
	body = {"title": "Sneaky", "video_source": "youtube", "video_url": f"https://youtu.be/{VIDEO_ID}", "duration_seconds": 60}
	assert api.post("/admin/videos", admin["token"], body).status_code == 409


def test_parent_report_quarantines_an_approved_video(api, youtube):
	admin = api.make_admin()
	ctx = _family_with_age(api)
	review = _discover(api, admin)[VIDEO_ID]
	assert _approve(api, admin, review["id"]).status_code == 200
	response = api.post("/videos/report", ctx["parent"]["token"], {"video_id": review["video_id"], "reason": "scary"})
	assert response.status_code == 201 and set(response.json()) == {"id", "status"}
	assert _feed_ids(api, ctx["child"]["token"]) == set()
	reports = api.get("/admin/videos/reports", admin["token"]).json()
	assert [r["video_id"] for r in reports] == [review["video_id"]]


def test_malformed_import_url_is_rejected(api, youtube):
	admin = api.make_admin()
	response = api.post("/admin/videos/youtube/import", admin["token"], {"url": "https://evil.example/watch?v=dQw4w9WgXcQ"})
	assert response.status_code == 422 and response.json()["error"]["code"] == "invalid_youtube_url"


def test_hosted_feed_is_unchanged_and_exposes_no_youtube_id(api, youtube):
	admin = api.make_admin()
	ctx = _family_with_age(api)
	body = {"title": "Hosted lesson", "video_url": "https://cdn.example.com/a.mp4", "duration_seconds": 90, "age_min": 0}
	video = api.post("/admin/videos", admin["token"], body).json()
	assert api.post(f"/admin/videos/{video['id']}/publish", admin["token"]).status_code == 200
	items = api.get("/videos/feed", ctx["child"]["token"]).json()
	hosted = [item for item in items if item["id"] == video["id"]]
	assert hosted and hosted[0]["video_source"] == "hosted" and hosted[0]["youtube_video_id"] is None


@pytest.mark.parametrize(
	("duration", "shorts", "regular", "expected_format", "expected_seconds"),
	[
		("PT1S", False, True, "unknown", None),  # stored sentinel for "unknown"
		("PT30S", True, False, "short", 30),
		("PT60S", True, False, "short", 60),
		("PT61S", False, True, "regular", 61),
		("PT2M", False, True, "regular", 120),
		("P0D", False, True, "unknown", None),  # live/unknown: stored as 1
	],
)
def test_short_and_regular_feeds_split_by_real_duration(
	api, youtube, duration, shorts, regular, expected_format, expected_seconds
):
	youtube.items[VIDEO_ID] = _item(VIDEO_ID, duration=duration)
	admin = api.make_admin()
	ctx = _family_with_age(api, 7)  # inside the default 6-8 approval band
	review = _discover(api, admin)[VIDEO_ID]
	assert _approve(api, admin, review["id"]).status_code == 200
	token = ctx["child"]["token"]

	short_items = _feed_items(api, token, "/videos/shorts")
	regular_items = _feed_items(api, token, "/videos/feed")
	assert (VIDEO_ID in short_items) is shorts
	assert (VIDEO_ID in regular_items) is regular
	item = short_items.get(VIDEO_ID) or regular_items[VIDEO_ID]
	assert item["video_format"] == expected_format
	assert item["duration_seconds"] == expected_seconds


def test_feeds_reject_non_child_callers(api, youtube):
	admin = api.make_admin()
	for path in ("/videos/shorts", "/videos/feed"):
		assert api.get(path).status_code in (401, 403)
		assert api.get(path, admin["token"]).status_code == 403
