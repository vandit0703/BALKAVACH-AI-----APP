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
REGULAR_ID = "lmnopqrstuv"
TRUSTED_CHANNEL_ID = "UC1111111111111111111111"


def _item(video_id: str, duration: str = "PT45S", **status):
	return {
		"id": video_id,
		"snippet": {
			"title": f"Science {video_id}",
			"description": "Learning for children.",
			"channelId": TRUSTED_CHANNEL_ID,
			"channelTitle": "Kids Science",
			"defaultAudioLanguage": "en",
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
		self.items = {
			VIDEO_ID: _item(VIDEO_ID),
			OTHER_ID: _item(OTHER_ID, madeForKids=False),
			REGULAR_ID: _item(REGULAR_ID, "PT5M"),
		}
		self.search_calls = []
		self.upload_calls = []
		self.upload_ids = list(self.items)

	def search(self, topic, **kwargs):
		self.search_calls.append(kwargs)
		if kwargs.get("channel_id") and kwargs.get("short") is False:
			return {"video_ids": [REGULAR_ID, VIDEO_ID], "next_page_token": None}
		return {"video_ids": [VIDEO_ID, OTHER_ID, VIDEO_ID], "next_page_token": "NEXT"}

	def videos(self, ids, use_cache=True):
		return {video_id: self.items[video_id] for video_id in ids if video_id in self.items}

	def uploads_playlist(self, channel_id):
		self.upload_calls.append(channel_id)
		return f"UU{channel_id[2:]}"

	def playlist_items(self, playlist_id, *, page_token=None, max_results=50):
		start = int(page_token or 0)
		end = start + max_results
		return {
			"video_ids": self.upload_ids[start:end],
			"next_page_token": str(end) if end < len(self.upload_ids) else None,
		}

	def search_channels(self, query, *, max_results=10):
		return [{
			"channel_id": TRUSTED_CHANNEL_ID,
			"channel_title": "Kids Science",
			"thumbnail_url": "https://yt3.ggpht.com/channel.png",
		}]


@pytest.fixture
def youtube(api, monkeypatch):
	if not has_model("YouTubeContentReview"):
		pytest.skip("Migration 0008 is not applied to the test database")
	from app.core.config import settings

	monkeypatch.setattr(settings, "youtube_auto_publish_age_band", "9-12")
	fake = FakeYouTube()
	monkeypatch.setattr(video_routes, "get_youtube_client", lambda: fake)
	return fake


def _discover(api, admin, auto=False):
	"""Admin discovery. ``auto=False`` runs it in manual-review mode so the tests of
	the human approval flow keep their candidates pending."""
	from app.core.config import settings

	previous = settings.youtube_auto_publish_non_trusted
	settings.youtube_auto_publish_non_trusted = auto
	try:
		response = api.post("/admin/videos/youtube/discover", admin["token"], {"topic": "science"})
	finally:
		settings.youtube_auto_publish_non_trusted = previous
	assert response.status_code == 200, response.text
	return {row["youtube_video_id"]: row for row in response.json()["created"]}


def _approve(api, admin, review_id, **overrides):
	body = {"age_min": 6, "age_max": 8, "language_code": "en", "rights_status": "cleared", **overrides}
	return api.post(f"/admin/videos/youtube/reviews/{review_id}/approve", admin["token"], body)


def test_admin_can_discover_channels_and_see_trust_status(api, youtube):
	if not has_model("YouTubeTrustedChannel"):
		pytest.skip("Migration 0010 is not applied to the test database")
	admin = api.make_admin()
	response = api.get(
		"/admin/videos/youtube/channels/discover?query=science",
		admin["token"],
	)
	assert response.status_code == 200, response.text
	assert response.json() == [{
		"channel_id": TRUSTED_CHANNEL_ID,
		"channel_title": "Kids Science",
		"thumbnail_url": "https://yt3.ggpht.com/channel.png",
		"is_trusted": False,
	}]


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


def _science_category(api):
	VideoCategory = get_model("VideoCategory")
	category = VideoCategory(
		name="Science",
		slug="science",
		description="Science learning",
		display_order=0,
		is_active=True,
	)
	api.session.add(category)
	api.session.flush()
	return category.id


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
		category_id=_science_category(api),
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
	assert result["automatically_published"] == 2
	assert review.status == "approved"
	assert review.rights_status == "cleared"
	assert review.publication_source == "automatic"
	assert video.is_published is True
	assert (video.age_min, video.age_max) == (6, 8)
	assert youtube.upload_calls == [TRUSTED_CHANNEL_ID]
	regular_review = api.session.query(Review).filter(Review.youtube_video_id == REGULAR_ID).one()
	regular_video = api.session.query(Video).filter(Video.id == regular_review.video_id).one()
	assert regular_review.status == "approved"
	assert regular_video.is_published is True
	assert regular_video.duration_seconds > 60


def test_trusting_channel_discovers_and_publishes_both_video_formats(api, youtube):
	if not has_model("YouTubeTrustedChannel"):
		pytest.skip("Migration 0010 is not applied to the test database")
	admin = api.make_admin()
	response = api.post(
		"/admin/videos/youtube/channels/trust",
		admin["token"],
		{
			"channel_id": TRUSTED_CHANNEL_ID,
			"channel_title": "Kids Science",
			"rights_status": "cleared",
		},
	)
	assert response.status_code == 200, response.text
	assert response.json()["initial_discovery"]["automatically_published"] == 2
	Review = get_model("YouTubeContentReview")
	Video = get_model("Video")
	for video_id in (VIDEO_ID, REGULAR_ID):
		review = api.session.query(Review).filter_by(youtube_video_id=video_id).one()
		video = api.session.query(Video).filter_by(id=review.video_id).one()
		assert review.status == "approved"
		assert video.is_published is True
		assert video.category_id is None
	assert youtube.upload_calls == [TRUSTED_CHANNEL_ID]


def test_trusted_channel_discovers_future_uploads_and_keeps_formats_separate(api, youtube):
	if not has_model("YouTubeTrustedChannel"):
		pytest.skip("Migration 0010 is not applied to the test database")
	admin = api.make_admin()
	ctx = _family_with_age(api, age=10)
	youtube.upload_ids = [VIDEO_ID, REGULAR_ID, VIDEO_ID]
	response = api.post(
		"/admin/videos/youtube/channels/trust",
		admin["token"],
		{"channel_id": TRUSTED_CHANNEL_ID, "rights_status": "cleared"},
	)
	assert response.status_code == 200, response.text
	assert response.json()["initial_discovery"]["created"] == 2
	assert response.json()["initial_discovery"]["automatically_published"] == 2

	future_id = "futvideo123"
	youtube.items[future_id] = _item(future_id)
	youtube.upload_ids.insert(0, future_id)
	actor = api.session.query(get_model("User")).filter_by(id=admin["id"]).one()
	first_future_run = discover_trusted(api.session, actor, youtube, max_results=1)
	second_future_run = discover_trusted(api.session, actor, youtube, max_results=1)
	assert first_future_run["created"] == 1
	assert first_future_run["automatically_published"] == 1
	assert second_future_run["created"] == 0
	assert second_future_run["automatically_published"] == 0

	short_ids = _feed_ids(api, ctx["child"]["token"], "/videos/shorts")
	regular_ids = _feed_ids(api, ctx["child"]["token"], "/videos/feed")
	assert short_ids == {VIDEO_ID, future_id}
	assert regular_ids == {REGULAR_ID}


def test_trusted_channel_does_not_override_explicit_video_rights_denial(api, youtube):
	if not has_model("YouTubeTrustedChannel"):
		pytest.skip("Migration 0010 is not applied to the test database")
	admin = api.make_admin()
	actor = api.session.query(get_model("User")).filter_by(id=admin["id"]).one()
	discover(api.session, actor, youtube, YouTubeDiscoverRequest(topic="science"))
	Review = get_model("YouTubeContentReview")
	Video = get_model("Video")
	review = api.session.query(Review).filter_by(youtube_video_id=VIDEO_ID).one()
	video = api.session.query(Video).filter_by(id=review.video_id).one()
	review.rights_status = "not_cleared"
	api.session.commit()
	trusted = get_model("YouTubeTrustedChannel")(
		channel_id=TRUSTED_CHANNEL_ID,
		age_min=9,
		age_max=12,
		language_code="en",
		rights_status="cleared",
		is_active=True,
		created_by=actor.id,
	)
	api.session.add(trusted)
	api.session.commit()
	youtube.upload_ids = [VIDEO_ID]
	discover_trusted(api.session, actor, youtube, max_results=50)
	api.session.refresh(review)
	api.session.refresh(video)
	assert review.status == "pending_review"
	assert review.rights_status == "not_cleared"
	assert video.is_published is False


def test_child_watch_history_is_independent_and_completed_shorts_stay_listed(api, youtube):
	if not has_model("ChildVideoWatchHistory"):
		pytest.skip("Migration 0011 is not applied to the test database")
	admin = api.make_admin()
	ctx = _family_with_age(api, age=7)
	review = _discover(api, admin)[VIDEO_ID]
	assert _approve(api, admin, review["id"], age_min=6, age_max=8).status_code == 200
	child = ctx["child"]
	first = api.post(
		f"/videos/watch-history/{review['video_id']}/progress",
		child["token"],
		{"position_seconds": 10},
	)
	assert first.status_code == 200, first.text
	assert first.json()["is_completed"] is False

	History = get_model("ChildVideoWatchHistory")
	history = api.session.query(History).filter_by(child_id=child["id"], video_id=review["video_id"]).one()
	for position in (20, 45):
		history.last_watched_at = datetime.now(timezone.utc) - timedelta(seconds=30)
		api.session.commit()
		response = api.post(
			f"/videos/watch-history/{review['video_id']}/progress",
			child["token"],
			{"position_seconds": position},
		)
		assert response.status_code == 200, response.text
	assert response.json()["is_completed"] is True
	assert VIDEO_ID in _feed_ids(api, child["token"], "/videos/shorts")  # finished videos stay browsable

	second_child = api.create_child(ctx["parent"]["token"], ctx["family"]["id"], "Sibling")
	ChildProfile = get_model("ChildProfile")
	second_profile = api.session.query(ChildProfile).filter_by(id=second_child["id"]).one()
	second_profile.date_of_birth = date.today().replace(year=date.today().year - 7)
	api.session.commit()
	second_response = api.post(
		f"/videos/watch-history/{review['video_id']}/progress",
		second_child["token"],
		{"position_seconds": 5},
	)
	assert second_response.status_code == 200, second_response.text
	assert api.session.query(History).filter_by(video_id=review["video_id"]).count() == 2


def test_parent_history_and_replay_preserve_original_record(api, youtube):
	if not has_model("ChildVideoWatchHistory"):
		pytest.skip("Migration 0011 is not applied to the test database")
	admin = api.make_admin()
	ctx = _family_with_age(api, age=7)
	review = _discover(api, admin)[VIDEO_ID]
	assert _approve(api, admin, review["id"], age_min=6, age_max=8).status_code == 200
	History = get_model("ChildVideoWatchHistory")
	history = History(
		child_id=ctx["child"]["id"],
		video_id=review["video_id"],
		youtube_video_id=VIDEO_ID,
		video_format="short",
		started_at=datetime.now(timezone.utc),
		last_watched_at=datetime.now(timezone.utc),
		last_position_seconds=45,
		watch_duration_seconds=45,
		completion_percentage=100,
		is_completed=True,
		parent_replay_authorized=False,
	)
	api.session.add(history)
	api.session.commit()
	parent_history = api.get(f"/videos/watch-history/children/{ctx['child']['id']}", ctx["parent"]["token"])
	assert parent_history.status_code == 200, parent_history.text
	assert len(parent_history.json()) == 1
	assert api.get(
		f"/videos/watch-history/children/{ctx['child']['id']}",
		ctx["child"]["token"],
	).status_code == 403
	replay = api.post(
		f"/videos/watch-history/children/{ctx['child']['id']}/{review['video_id']}/replay",
		ctx["parent"]["token"],
	)
	assert replay.status_code == 204, replay.text
	assert api.session.query(History).filter_by(child_id=ctx["child"]["id"], video_id=review["video_id"]).count() == 1
	assert VIDEO_ID in _feed_ids(api, ctx["child"]["token"], "/videos/shorts")


def test_partially_watched_regular_video_is_continue_watching_not_a_short(api, youtube):
	if not has_model("ChildVideoWatchHistory") or not has_model("YouTubeTrustedChannel"):
		pytest.skip("Migrations 0010 and 0011 are not applied to the test database")
	admin = api.make_admin()
	ctx = _family_with_age(api, age=7)
	actor = api.session.query(get_model("User")).filter_by(id=admin["id"]).one()
	Trusted = get_model("YouTubeTrustedChannel")
	api.session.add(Trusted(
		channel_id=TRUSTED_CHANNEL_ID,
		channel_title="Kids Science",
		age_min=6,
		age_max=8,
		language_code="en",
		category_id=_science_category(api),
		rights_status="cleared",
		is_active=True,
		created_by=actor.id,
	))
	api.session.commit()
	discover_trusted(api.session, actor, youtube, 10)
	Review = get_model("YouTubeContentReview")
	Video = get_model("Video")
	review = api.session.query(Review).filter_by(youtube_video_id=REGULAR_ID).one()
	video = api.session.query(Video).filter_by(id=review.video_id).one()
	assert video.is_published is True
	assert REGULAR_ID in _feed_ids(api, ctx["child"]["token"], "/videos/feed")
	assert REGULAR_ID not in _feed_ids(api, ctx["child"]["token"], "/videos/shorts")
	progress = api.post(
		f"/videos/watch-history/{video.id}/progress",
		ctx["child"]["token"],
		{"position_seconds": 60},
	)
	assert progress.status_code == 200, progress.text
	assert progress.json()["is_completed"] is False
	continue_rows = api.get("/videos/watch-history/continue-watching", ctx["child"]["token"])
	assert continue_rows.status_code == 200, continue_rows.text
	assert continue_rows.json()[0]["video_id"] == str(video.id)
	assert continue_rows.json()[0]["last_position_seconds"] == 60


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
	ctx = _family_with_age(api, 7)  # inside the default 6-8 approval band
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
	# Discovered as not made for kids: screening quarantines it, and a quarantined
	# video must be re-evaluated before it can even be approved.
	review = _discover(api, admin)[OTHER_ID]
	assert review["status"] == "quarantined"
	response = _approve(api, admin, review["id"], notes="looked fine")
	assert response.status_code == 409 and response.json()["error"]["code"] == "youtube_re_evaluation_required"
	reevaluated = api.post(f"/admin/videos/youtube/reviews/{review['id']}/reevaluate", admin["token"], {})
	assert reevaluated.status_code == 200 and reevaluated.json()["status"] == "quarantined"
	assert _approve(api, admin, review["id"]).status_code == 409
	assert reevaluated.json()["is_published"] is False


def test_pending_video_that_stops_being_made_for_kids_cannot_be_approved(api, youtube):
	admin = api.make_admin()
	review = _discover(api, admin)[VIDEO_ID]
	assert review["status"] == "pending_review"
	youtube.items[VIDEO_ID]["status"]["madeForKids"] = False  # YouTube changed its mind
	response = _approve(api, admin, review["id"])
	assert response.status_code == 409 and response.json()["error"]["code"] == "not_made_for_kids"
	rows = api.get("/admin/videos/youtube/reviews", admin["token"]).json()
	assert next(r for r in rows if r["id"] == review["id"])["is_published"] is False


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
	ctx = _family_with_age(api, 7)  # inside the default 6-8 approval band
	review = _discover(api, admin)[VIDEO_ID]
	assert _approve(api, admin, review["id"]).status_code == 200
	assert _feed_ids(api, ctx["child"]["token"]) == {VIDEO_ID}  # visible while fresh
	fresh = api.get("/admin/videos/youtube/diagnostics", admin["token"]).json()
	assert fresh["approved_stale"] == 0 and fresh["reverify_hours"] == 72
	assert fresh["oldest_approved_verification"] is not None
	Review = get_model("YouTubeContentReview")
	row = api.session.query(Review).filter(Review.id == review["id"]).one()
	row.last_verified_at = datetime.now(timezone.utc) - timedelta(days=60)
	api.session.commit()
	assert _feed_ids(api, ctx["child"]["token"]) == set()
	stale = api.get("/admin/videos/youtube/diagnostics", admin["token"]).json()
	assert stale["approved_stale"] == 1  # the admin page can show recheck has lapsed


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


def test_admin_discovery_approves_and_publishes_eligible_video_automatically(api, youtube):
	admin = api.make_admin()
	ctx = _family_with_age(api)
	created = _discover(api, admin, auto=True)
	assert created[VIDEO_ID]["status"] == "approved"
	assert created[VIDEO_ID]["publication_source"] == "automatic"
	assert created[VIDEO_ID]["reviewed_by"] is None
	# A video YouTube does not mark made-for-kids is quarantined, never published.
	assert created[OTHER_ID]["status"] == "quarantined"
	assert created[OTHER_ID]["is_published"] is False
	assert _feed_ids(api, ctx["child"]["token"]) == {VIDEO_ID}


def test_auto_review_endpoint_processes_waiting_videos_once(api, youtube):
	admin = api.make_admin()
	ctx = _family_with_age(api)
	created = _discover(api, admin)  # manual mode: both wait
	assert created[VIDEO_ID]["status"] == "pending_review"
	first = api.post("/admin/videos/youtube/auto-review", admin["token"], {"limit": 50})
	assert first.status_code == 200, first.text
	body = first.json()
	assert body["auto_approved"] == 1 and body["error"] is None
	assert _feed_ids(api, ctx["child"]["token"]) == {VIDEO_ID}
	second = api.post("/admin/videos/youtube/auto-review", admin["token"], {"limit": 50}).json()
	assert second["auto_approved"] == 0
	# The still-quarantined (not made for kids) video keeps its reason.
	assert second["quarantine_reasons"].get("not_made_for_kids") == 1


def test_auto_review_leaves_a_manual_approval_untouched(api, youtube):
	admin = api.make_admin()
	review = _discover(api, admin)[VIDEO_ID]
	assert _approve(api, admin, review["id"]).status_code == 200
	youtube.items[VIDEO_ID]["snippet"]["title"] = "Zombie gore"
	api.post("/admin/videos/youtube/auto-review", admin["token"], {"limit": 50})
	rows = api.get("/admin/videos/youtube/reviews?status=approved", admin["token"]).json()
	row = next(item for item in rows if item["youtube_video_id"] == VIDEO_ID)
	assert row["publication_source"] == "manual" and row["is_published"] is True


def test_auto_review_requires_video_write_permission(api, youtube):
	parent = api.register_parent()
	response = api.post("/admin/videos/youtube/auto-review", parent["token"], {"limit": 5})
	assert response.status_code == 403


def test_auto_approved_video_gets_the_configured_supported_age_band(api, youtube):
	admin = api.make_admin()
	created = _discover(api, admin, auto=True)
	assert (created[VIDEO_ID]["age_min"], created[VIDEO_ID]["age_max"]) == (9, 12)
	batch = api.post("/admin/videos/youtube/publish-approved", admin["token"], {"limit": 50})
	assert batch.status_code == 200, batch.text
	assert "unsupported_age_band" not in batch.json()["blocked_by_reason"]


def test_unknown_duration_requires_review_and_is_in_neither_feed(api, youtube):
	"""A duration YouTube does not report (P0D) is screened as ``duration_unknown``:
	it waits for review, cannot be approved without resolving the flag, and is in no feed."""
	youtube.items[VIDEO_ID] = _item(VIDEO_ID, duration="P0D")
	admin = api.make_admin()
	ctx = _family_with_age(api, 7)
	review = _discover(api, admin)[VIDEO_ID]
	assert review["status"] == "pending_review" and "duration_unknown" in review["screening_flags"]
	approval = _approve(api, admin, review["id"])
	assert approval.status_code == 409 and approval.json()["error"]["code"] == "youtube_screening_failed"
	token = ctx["child"]["token"]
	assert VIDEO_ID not in _feed_items(api, token, "/videos/shorts")
	assert VIDEO_ID not in _feed_items(api, token, "/videos/feed")


def test_command_line_recheck_leaves_an_audit_row_without_an_actor(api, youtube):
	"""``python -m app.cli youtube-recheck`` has no signed-in user; its run must still be traceable."""
	from app.services.youtube_review_service import recheck

	admin = api.make_admin()
	review = _discover(api, admin)[VIDEO_ID]
	assert _approve(api, admin, review["id"]).status_code == 200
	counts = recheck(api.session, youtube, 200)  # actor_id=None, as the CLI calls it
	assert counts["checked"] >= 1
	AuditLog = get_model("AuditLog")
	rows = api.session.query(AuditLog).filter(AuditLog.action == "youtube.recheck.completed").all()
	assert len(rows) == 1 and rows[0].actor_user_id is None and rows[0].details["checked"] == counts["checked"]


def test_auto_approval_is_safe_when_the_age_band_is_unset(api, youtube, monkeypatch):
	"""Default deployment: YOUTUBE_AUTO_PUBLISH_AGE_BAND is not set. Nothing from a
	non-trusted channel may be published, and each video must say why it waits."""
	from app.core.config import settings

	monkeypatch.setattr(settings, "youtube_auto_publish_age_band", None)
	admin = api.make_admin()
	ctx = _family_with_age(api, 7)
	created = _discover(api, admin, auto=True)  # policy on, band unset
	assert created[VIDEO_ID]["status"] == "pending_review" and created[VIDEO_ID]["is_published"] is False
	assert "no age band is configured" in created[VIDEO_ID]["not_published_reason"]
	assert created[VIDEO_ID]["rights_status"] == "unreviewed"
	assert (created[VIDEO_ID]["age_min"], created[VIDEO_ID]["age_max"]) == (4, 12)  # untouched, not guessed
	assert _feed_ids(api, ctx["child"]["token"]) == set()
	# Re-review does not publish it either...
	body = api.post("/admin/videos/youtube/auto-review", admin["token"], {"limit": 50}).json()
	assert body["auto_approved"] == 0 and body["blocked_reasons"].get("age_band_not_configured") == 1
	# ...but an administrator can still approve it by hand with an explicit band.
	assert _approve(api, admin, created[VIDEO_ID]["id"]).status_code == 200
	assert _feed_ids(api, ctx["child"]["token"]) == {VIDEO_ID}


def test_old_verification_does_not_hide_the_video(api, youtube):
	child, video = _child_feed(api, age=8, language="en")
	created = youtube.import_video(f"https://youtu.be/{VIDEO_ID}")
	youtube.approve(created["id"], {"age_min": 6, "age_max": 8, "language_code": "en", "rights_status": "cleared"}, by="admin")

	fresh = api.client.get("/api/v1/videos", headers=api.auth(child))
	assert {item["id"] for item in fresh.json()} == {str(video.id)}
	fresh_diag = api.client.get("/api/v1/admin/videos/youtube/diagnostics", headers=api.auth("admin"))
	assert fresh_diag.status_code == 200
	assert fresh_diag.json()["approved_stale"] == 0 and fresh_diag.json()["reverify_hours"] == 72

	Review = get_model("YouTubeContentReview")
	with api.session_factory() as session:
		review = session.query(Review).filter(Review.youtube_video_id == VIDEO_ID).one()
		review.last_verified_at = utc_naive(datetime.now(timezone.utc)) - timedelta(hours=73)
		session.commit()

	stale = api.client.get("/api/v1/videos", headers=api.auth(child))
	assert {item["id"] for item in stale.json()} == {str(video.id)}

	stale_diag = api.client.get("/api/v1/admin/videos/youtube/diagnostics", headers=api.auth("admin"))
	assert stale_diag.status_code == 200
	assert stale_diag.json()["approved_stale"] == 1  # informational: recheck is overdue, but feed eligibility is unchanged

	# Recheck makes the same already-approved video freshly verified again; a person never has to re-approve it.
	api.youtube = FakeYouTube(VIDEO_ID)
	recheck = api.client.post("/api/v1/admin/videos/youtube/recheck?limit=50", headers=api.auth("admin"))
	assert recheck.json()["verified"] == 1 and recheck.json()["quarantined"] == 0
	restored = api.client.get("/api/v1/videos", headers=api.auth(child))
	assert {item["id"] for item in restored.json()} == {str(video.id)}


def test_channel_discover_more_is_restricted_to_selected_channel_and_not_global(api, youtube):
	if not has_model("YouTubeTrustedChannel"):
		pytest.skip("Migration 0010 is not applied to the test database")
	if not has_model("YouTubeChannelDiscoveryRun"):
		pytest.skip("Migration 0016 is not applied to the test database")
	admin = api.make_admin()
	other_channel_id = "UC2222222222222222222222"
	# Avoid initial trust-time discovery side effects so this test targets the Discover More action.
	youtube.upload_ids = []
	for channel_id, title in (
		(TRUSTED_CHANNEL_ID, "Kids Science"),
		(other_channel_id, "Other Channel"),
	):
		response = api.post(
			"/admin/videos/youtube/channels/trust",
			admin["token"],
			{"channel_id": channel_id, "channel_title": title, "rights_status": "cleared"},
		)
		assert response.status_code == 200, response.text

	def uploads_playlist(channel_id):
		youtube.upload_calls.append(channel_id)
		return f"UU{channel_id[2:]}"

	def playlist_items(playlist_id, *, page_token=None, max_results=50):
		if playlist_id.endswith(TRUSTED_CHANNEL_ID[2:]):
			return {"video_ids": [VIDEO_ID, OTHER_ID, REGULAR_ID], "next_page_token": None}
		if playlist_id.endswith(other_channel_id[2:]):
			return {"video_ids": ["zyxwvutsrqp"], "next_page_token": None}
		return {"video_ids": [], "next_page_token": None}

	youtube.uploads_playlist = uploads_playlist
	youtube.playlist_items = playlist_items
	youtube.search_calls.clear()
	youtube.upload_calls.clear()

	response = api.post(
		f"/admin/videos/youtube/channels/{TRUSTED_CHANNEL_ID}/discover",
		admin["token"],
		{},
	)
	assert response.status_code == 200, response.text
	data = response.json()
	assert data["channel_id"] == TRUSTED_CHANNEL_ID
	assert data["status"] == "completed"
	assert data["scanned_videos"] == 3
	assert data["new_videos"] == 3
	assert data["duplicate_videos"] == 0
	assert data["shorts_count"] + data["long_videos_count"] == 3
	assert data["error_count"] == 0
	# Channel-specific Discover More must not run topic/global discovery or scan other trusted channels.
	assert youtube.search_calls == []
	assert youtube.upload_calls == [TRUSTED_CHANNEL_ID]

	# Re-running should scan the channel again but only process genuinely new candidates (duplicates skipped).
	youtube.search_calls.clear()
	youtube.upload_calls.clear()
	response = api.post(
		f"/admin/videos/youtube/channels/{TRUSTED_CHANNEL_ID}/discover",
		admin["token"],
		{},
	)
	assert response.status_code == 200, response.text
	data = response.json()
	assert data["channel_id"] == TRUSTED_CHANNEL_ID
	assert data["scanned_videos"] == 3
	assert data["new_videos"] == 0
	assert data["duplicate_videos"] == 3
	assert youtube.search_calls == []
	assert youtube.upload_calls == [TRUSTED_CHANNEL_ID]

	# The other trusted channel must remain untouched by this selected-channel action.
	Review = get_model("YouTubeContentReview")
	assert api.session.query(Review).filter(Review.youtube_video_id == "zyxwvutsrqp").count() == 0
	assert api.session.query(Review).filter(Review.channel_id == TRUSTED_CHANNEL_ID).count() == 3
	assert api.session.query(Review).filter(Review.channel_id == other_channel_id).count() == 0
