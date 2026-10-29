"""YouTube discovery, screening and visibility rules that need no Postgres.

The YouTube client runs against ``httpx.MockTransport``; the feed visibility
condition runs as real SQL on an in-memory SQLite database built from minimal
stand-in tables. Behaviour that needs the reflected Neon schema (approval,
recheck, reports end to end) lives in ``test_api_youtube.py``.
"""

import logging
from datetime import datetime, timedelta, timezone
from types import SimpleNamespace
from uuid import uuid4

import httpx
import pytest
from fastapi.testclient import TestClient
from sqlalchemy import Boolean, Column, DateTime, JSON, String, create_engine
from sqlalchemy.orm import Session, declarative_base

from app.core.config import Settings, settings
from app.core.dependencies import get_current_user
from app.core.exceptions import APIError
from app.db.session import get_db
from app.integrations import youtube as yt
from app.integrations.youtube import (
	YouTubeClient,
	YouTubeNotConfiguredError,
	YouTubeQuotaError,
	YouTubeUnavailableError,
	parse_iso8601_duration,
	parse_youtube_video_id,
)
from app.services import youtube_review_service as reviews
from app.services.video_service import child_age
from app.services.youtube_review_service import can_transition, screen_candidate

KEY = "AIza-test-secret-key-0000"
VIDEO_ID = "dQw4w9WgXcQ"


def client_with(handler, **kwargs) -> YouTubeClient:
	return YouTubeClient(KEY, transport=httpx.MockTransport(handler), sleep=lambda _: None, **kwargs)


def video_item(video_id=VIDEO_ID, **overrides):
	item = {
		"id": video_id,
		"snippet": {
			"title": "Why is the sky blue?",
			"description": "A science video for children.",
			"channelId": "UC123",
			"channelTitle": "Kids Science",
			"publishedAt": "2025-01-02T03:04:05Z",
			"liveBroadcastContent": "none",
			"thumbnails": {"high": {"url": f"https://i.ytimg.com/vi/{video_id}/hqdefault.jpg"}},
		},
		"contentDetails": {"duration": "PT3M20S"},
		"status": {"privacyStatus": "public", "embeddable": True, "uploadStatus": "processed", "madeForKids": True},
	}
	for path, value in overrides.items():
		section, field = path.split("__")
		item[section][field] = value
	return item


class TestClientRequests:
	def test_search_uses_strict_filters_and_sends_the_key_only_as_a_header(self):
		seen = []

		def handler(request: httpx.Request):
			seen.append(request)
			return httpx.Response(200, json={"items": [{"id": {"videoId": VIDEO_ID}}], "nextPageToken": "CAUQAA"})

		page = client_with(handler).search("science", short=True, page_token="CAoQAA", relevance_language="hi", region_code="IN")
		request = seen[0]
		params = request.url.params
		assert params["safeSearch"] == "strict"
		assert params["type"] == "video"
		assert params["videoEmbeddable"] == "true"
		assert params["videoDuration"] == "short"
		assert params["pageToken"] == "CAoQAA"
		assert params["relevanceLanguage"] == "hi" and params["regionCode"] == "IN"
		assert params["q"] == yt.DISCOVERY_TOPICS["science"]
		assert request.headers["X-Goog-Api-Key"] == KEY
		assert KEY not in str(request.url)
		assert page == {"video_ids": [VIDEO_ID], "next_page_token": "CAUQAA"}

	def test_standard_search_does_not_restrict_duration(self):
		seen = []
		client_with(lambda r: seen.append(r) or httpx.Response(200, json={"items": []})).search("animals")
		assert "videoDuration" not in seen[0].url.params

	def test_empty_results(self):
		page = client_with(lambda r: httpx.Response(200, json={})).search("art")
		assert page == {"video_ids": [], "next_page_token": None}

	def test_search_results_are_deduplicated_and_malformed_ids_dropped(self):
		items = [{"id": {"videoId": VIDEO_ID}}, {"id": {"videoId": VIDEO_ID}}, {"id": {"videoId": "bad id"}}, {"id": {}}]
		page = client_with(lambda r: httpx.Response(200, json={"items": items})).search("math")
		assert page["video_ids"] == [VIDEO_ID]

	@pytest.mark.parametrize(
		"kwargs",
		[{"topic": "anything goes"}, {"page_token": "../../etc"}, {"relevance_language": "english!"}, {"region_code": "india"}],
	)
	def test_rejects_unvalidated_parameters_before_calling_youtube(self, kwargs):
		calls = []
		client = client_with(lambda r: calls.append(r) or httpx.Response(200, json={}))
		topic = kwargs.pop("topic", "science")
		with pytest.raises(ValueError):
			client.search(topic, **kwargs)
		assert calls == []

	def test_a_returned_page_token_that_is_malformed_is_dropped(self):
		page = client_with(lambda r: httpx.Response(200, json={"items": [], "nextPageToken": "<script>"})).search("art")
		assert page["next_page_token"] is None

	def test_videos_lookup_rejects_malformed_ids(self):
		with pytest.raises(ValueError):
			client_with(lambda r: httpx.Response(200, json={})).videos(["not-an-id"])

	def test_responses_are_cached(self):
		calls = []

		def handler(request):
			calls.append(request)
			return httpx.Response(200, json={"items": [video_item()]})

		client = client_with(handler)
		client.videos([VIDEO_ID])
		client.videos([VIDEO_ID])
		assert len(calls) == 1
		client.videos([VIDEO_ID], use_cache=False)
		assert len(calls) == 2


class TestClientFailures:
	def test_quota_exhaustion_is_a_controlled_error(self):
		body = {"error": {"code": 403, "errors": [{"reason": "quotaExceeded"}]}}
		with pytest.raises(YouTubeQuotaError):
			client_with(lambda r: httpx.Response(403, json=body)).search("science")
		assert yt.to_api_error(YouTubeQuotaError()).code == "youtube_quota_exhausted"

	def test_timeouts_are_retried_a_bounded_number_of_times(self):
		attempts = []

		def handler(request):
			attempts.append(request)
			raise httpx.ReadTimeout("slow", request=request)

		with pytest.raises(YouTubeUnavailableError):
			client_with(handler, max_retries=2).search("science")
		assert len(attempts) == 3

	def test_server_errors_are_retried_then_succeed(self):
		responses = iter([httpx.Response(503), httpx.Response(200, json={"items": []})])
		assert client_with(lambda r: next(responses)).search("science")["video_ids"] == []

	def test_missing_key_never_calls_youtube(self):
		calls = []
		client = YouTubeClient(None, transport=httpx.MockTransport(lambda r: calls.append(r) or httpx.Response(200)))
		with pytest.raises(YouTubeNotConfiguredError):
			client.search("science")
		assert calls == []

	def test_missing_key_is_a_503_from_the_shared_client(self, monkeypatch):
		monkeypatch.setattr(settings, "youtube_api_key", None)
		with pytest.raises(APIError) as error:
			yt.get_youtube_client()
		assert error.value.status_code == 503 and error.value.code == "youtube_not_configured"

	def test_local_rate_limit_protects_the_quota(self):
		limiter = yt._RateLimiter(max_calls=2, per_seconds=60, clock=lambda: 0.0)
		client = client_with(lambda r: httpx.Response(200, json={}), rate_limiter=limiter, cache_ttl_seconds=0)
		client.search("science")
		client.search("animals")
		with pytest.raises(YouTubeQuotaError):
			client.search("art")


class TestNoKeyLeakage:
	def test_errors_logs_and_reprs_never_contain_the_key(self, caplog):
		caplog.set_level(logging.DEBUG)
		body = {"error": {"code": 400, "message": f"bad key {KEY}", "errors": [{"reason": "badRequest"}]}}
		client = client_with(lambda r: httpx.Response(400, json=body))
		with pytest.raises(yt.YouTubeError) as error:
			client.search("science")
		assert KEY not in str(error.value)
		assert KEY not in yt.to_api_error(error.value).message
		assert KEY not in caplog.text
		assert KEY not in repr(client)

	def test_settings_repr_hides_the_key(self):
		assert KEY not in repr(Settings(youtube_api_key=KEY, _env_file=None))


class TestParsing:
	@pytest.mark.parametrize(
		"value",
		[
			VIDEO_ID,
			f"https://www.youtube.com/watch?v={VIDEO_ID}",
			f"https://m.youtube.com/watch?v={VIDEO_ID}&t=10",
			f"https://youtu.be/{VIDEO_ID}",
			f"https://www.youtube.com/shorts/{VIDEO_ID}",
			f"https://www.youtube-nocookie.com/embed/{VIDEO_ID}",
		],
	)
	def test_accepts_youtube_video_urls(self, value):
		assert parse_youtube_video_id(value) == VIDEO_ID

	@pytest.mark.parametrize(
		"value",
		[
			"",
			"short",
			f"http://www.youtube.com/watch?v={VIDEO_ID}",
			f"https://evil.example/watch?v={VIDEO_ID}",
			f"https://www.youtube.com.evil.example/watch?v={VIDEO_ID}",
			f"https://user@www.youtube.com/watch?v={VIDEO_ID}",
			"https://www.youtube.com/watch?v=tooShort",
			f"https://www.youtube.com/watch?v={VIDEO_ID}&v=aaaaaaaaaaa",
			"https://www.youtube.com/playlist?list=PL123",
			"https://www.youtube.com/@channel",
			"javascript:alert(1)",
		],
	)
	def test_rejects_everything_else(self, value):
		assert parse_youtube_video_id(value) is None

	@pytest.mark.parametrize(
		("value", "seconds"),
		[("PT3M20S", 200), ("PT1H", 3600), ("P1DT1S", 86401), ("PT45S", 45), ("P0D", 0), ("", None), ("3:20", None)],
	)
	def test_durations(self, value, seconds):
		assert parse_iso8601_duration(value) == seconds

	def test_thumbnails_only_from_youtube_image_host(self):
		assert yt.safe_thumbnail_url({"thumbnails": {"high": {"url": "https://evil.example/x.jpg"}}}) is None
		assert yt.safe_thumbnail_url({"thumbnails": {"high": {"url": "http://i.ytimg.com/x.jpg"}}}) is None


class TestScreening:
	def test_a_clean_made_for_kids_video_still_needs_a_human(self):
		assert screen_candidate(video_item()) == ("pending_review", [])

	@pytest.mark.parametrize(
		("override", "flag"),
		[
			({"status__privacyStatus": "unlisted"}, "not_public"),
			({"status__embeddable": False}, "not_embeddable"),
			({"status__uploadStatus": "uploaded"}, "not_processed"),
		],
	)
	def test_unplayable_videos_are_unavailable(self, override, flag):
		status, flags = screen_candidate(video_item(**override))
		assert status == "unavailable" and flag in flags

	def test_region_block(self):
		item = video_item(contentDetails__regionRestriction={"blocked": ["IN"]})
		assert screen_candidate(item, "IN")[0] == "unavailable"
		assert screen_candidate(item, "US")[0] == "pending_review"

	@pytest.mark.parametrize(
		("override", "flag"),
		[
			({"status__madeForKids": False}, "not_made_for_kids"),
			({"status__madeForKids": None}, "made_for_kids_unknown"),
			({"contentDetails__contentRating": {"ytRating": "ytAgeRestricted"}}, "age_restricted"),
			({"contentDetails__duration": "P0D"}, "duration_unknown"),
			({"snippet__liveBroadcastContent": "live"}, "live_content"),
			({"snippet__title": "Scary zombie prank"}, "keyword:zombie"),
			({"snippet__tags": ["Horror"]}, "keyword:horror"),
		],
	)
	def test_uncertain_videos_are_quarantined(self, override, flag):
		status, flags = screen_candidate(video_item(**override))
		assert status == "quarantined" and flag in flags

	def test_keywords_match_whole_words_only(self):
		assert screen_candidate(video_item(snippet__title="Skilled gunnery? no: warthogs and killdeer birds"))[0] == "pending_review"


def test_child_age_requires_a_valid_recorded_birth_date():
	today = datetime.now(timezone.utc).date()
	assert child_age(SimpleNamespace(date_of_birth=None)) is None
	assert child_age(SimpleNamespace(date_of_birth=today.replace(year=today.year + 1))) is None
	assert child_age(SimpleNamespace(date_of_birth=today.replace(year=today.year - 10))) == 10


def test_discovery_topic_set_covers_curated_learning_areas():
	assert {
		"early_learning",
		"math",
		"science",
		"coding",
		"stories",
		"academic_explainers",
		"nature",
	} <= yt.DISCOVERY_TOPICS.keys()


def test_approval_only_accepts_configured_age_bands():
	from pydantic import ValidationError

	from app.schemas.video import YouTubeApproveRequest

	for age_min, age_max in ((3, 5), (6, 8), (9, 12), (13, 15)):
		YouTubeApproveRequest(
			age_min=age_min,
			age_max=age_max,
			language_code="en",
			rights_status="cleared",
		)
	for age_min, age_max in ((0, 12), (3, 6), (8, 9), (12, 16), (7, 8)):
		with pytest.raises(ValidationError):
			YouTubeApproveRequest(
				age_min=age_min,
				age_max=age_max,
				language_code="en",
				rights_status="cleared",
			)


class TestTransitions:
	@pytest.mark.parametrize(
		("current", "target"),
		[("pending_review", "approved"), ("quarantined", "approved"), ("approved", "revoked"), ("revoked", "pending_review")],
	)
	def test_allowed(self, current, target):
		assert can_transition(current, target)

	@pytest.mark.parametrize(
		("current", "target"),
		[
			("discovered", "approved"),
			("rejected", "approved"),
			("revoked", "approved"),
			("unavailable", "approved"),
			("approved", "approved"),
			("approved", "pending_review"),
		],
	)
	def test_forbidden(self, current, target):
		assert not can_transition(current, target)


# --- Feed visibility, as real SQL -------------------------------------------

Stub = declarative_base()


class StubVideo(Stub):
	__tablename__ = "videos"
	id = Column(String, primary_key=True)
	video_source = Column(String, nullable=False)


class StubReview(Stub):
	__tablename__ = "youtube_content_reviews"
	id = Column(String, primary_key=True)
	video_id = Column(String, nullable=False)
	status = Column(String, nullable=False)
	rights_status = Column(String, nullable=False)
	made_for_kids = Column(Boolean)
	last_verified_at = Column(DateTime)
	channel_id = Column(String)
	publication_source = Column(String, nullable=False, default="manual")


class StubTrustedChannel(Stub):
	__tablename__ = "youtube_trusted_channels"
	id = Column(String, primary_key=True)
	channel_id = Column(String, nullable=False)
	is_active = Column(Boolean, nullable=False)


@pytest.fixture
def stub_db(monkeypatch):
	engine = create_engine("sqlite://")
	Stub.metadata.create_all(engine)
	monkeypatch.setattr(reviews, "has_model", lambda name: True)
	monkeypatch.setattr(
		reviews,
		"get_model",
		lambda name: StubTrustedChannel if name == "YouTubeTrustedChannel" else StubReview,
	)
	with Session(engine) as session:
		yield session


def visible(session, now=None):
	rows = session.query(StubVideo.id).filter(reviews.youtube_visibility_clause(StubVideo, now)).all()
	return {row[0] for row in rows}


def test_feed_shows_only_approved_cleared_recently_verified_youtube_videos(stub_db):
	now = datetime(2026, 10, 23, 12, tzinfo=timezone.utc)
	fresh = (now - timedelta(hours=1)).replace(tzinfo=None)
	stale = (now - timedelta(hours=settings.youtube_reverify_hours + 1)).replace(tzinfo=None)
	stub_db.add(StubVideo(id="hosted", video_source="hosted"))
	cases = {
		"approved": ("approved", "cleared", True, fresh),
		"stale": ("approved", "cleared", True, stale),
		"never_verified": ("approved", "cleared", True, None),
		"rights_unreviewed": ("approved", "unreviewed", True, fresh),
		"not_made_for_kids": ("approved", "cleared", False, fresh),
		"unknown_made_for_kids": ("approved", "cleared", None, fresh),
		"pending": ("pending_review", "unreviewed", True, fresh),
		"quarantined": ("quarantined", "unreviewed", True, fresh),
		"revoked": ("revoked", "cleared", True, fresh),
		"unavailable": ("unavailable", "cleared", True, fresh),
		"rejected": ("rejected", "unreviewed", True, fresh),
		"discovered": ("discovered", "unreviewed", True, fresh),
	}
	for name, (status, rights, made_for_kids, verified) in cases.items():
		stub_db.add(StubVideo(id=name, video_source="youtube"))
		stub_db.add(
			StubReview(
				id=f"r-{name}",
				video_id=name,
				status=status,
				rights_status=rights,
				made_for_kids=made_for_kids,
				last_verified_at=verified,
			)
		)
	stub_db.add(StubVideo(id="no_review", video_source="youtube"))
	stub_db.commit()
	assert visible(stub_db, now) == {"hosted", "approved"}


def test_without_migration_0008_no_youtube_video_is_visible(stub_db, monkeypatch):
	monkeypatch.setattr(reviews, "has_model", lambda name: False)
	stub_db.add_all([StubVideo(id="hosted", video_source="hosted"), StubVideo(id="yt", video_source="youtube")])
	stub_db.commit()
	assert visible(stub_db) == {"hosted"}


def test_automatic_publication_does_not_require_an_active_trusted_channel(stub_db):
	now = datetime(2026, 10, 23, 12, tzinfo=timezone.utc)
	fresh = (now - timedelta(hours=1)).replace(tzinfo=None)
	for name, channel_id in (
		("auto_active", "UC1234567890123456789012"),
		("auto_disabled", "UC2234567890123456789012"),
	):
		stub_db.add(StubVideo(id=name, video_source="youtube"))
		stub_db.add(
			StubReview(
				id=f"r-{name}",
				video_id=name,
				status="approved",
				rights_status="cleared",
				made_for_kids=True,
				last_verified_at=fresh,
				channel_id=channel_id,
				publication_source="automatic",
			)
		)
	stub_db.add(
		StubTrustedChannel(
			id="trusted-1",
			channel_id="UC1234567890123456789012",
			is_active=True,
		)
	)
	stub_db.add(
		StubTrustedChannel(
			id="trusted-2",
			channel_id="UC2234567890123456789012",
			is_active=False,
		)
	)
	stub_db.commit()
	assert visible(stub_db, now) == {"auto_active", "auto_disabled"}


# --- Route authorisation (no database reached) --------------------------------


@pytest.fixture
def as_role():
	from app.main import app

	def use(role: str):
		app.dependency_overrides[get_current_user] = lambda: SimpleNamespace(id=uuid4(), role=role)
		app.dependency_overrides[get_db] = lambda: iter([None])
		return TestClient(app)

	yield use
	app.dependency_overrides.pop(get_current_user, None)
	app.dependency_overrides.pop(get_db, None)


MODERATION_CALLS = [
	("post", "/api/v1/admin/videos/youtube/discover", {"topic": "science"}),
	("post", "/api/v1/admin/videos/youtube/import", {"url": f"https://youtu.be/{VIDEO_ID}"}),
	("get", "/api/v1/admin/videos/youtube/channels", None),
	("post", "/api/v1/admin/videos/youtube/channels/trust", {"channel_id": "UC1234567890123456789012", "age_min": 3, "age_max": 5, "language_code": "en", "rights_status": "cleared"}),
	("post", "/api/v1/admin/videos/youtube/channels/UC1234567890123456789012/untrust", {}),
	("get", "/api/v1/admin/videos/youtube/reviews", None),
	("post", f"/api/v1/admin/videos/youtube/reviews/{uuid4()}/approve", {"age_min": 4, "age_max": 8, "language_code": "en", "rights_status": "cleared"}),
	("post", f"/api/v1/admin/videos/youtube/reviews/{uuid4()}/revoke", {"reason": "unsafe"}),
	("post", "/api/v1/admin/videos/youtube/recheck", {}),
	("get", "/api/v1/admin/videos/reports", None),
]


@pytest.mark.parametrize("role", ["parent", "child"])
@pytest.mark.parametrize(("method", "path", "body"), MODERATION_CALLS)
def test_moderation_endpoints_refuse_non_administrators(as_role, role, method, path, body):
	client = as_role(role)
	response = client.request(method, path, json=body)
	assert response.status_code == 403


def test_moderation_endpoints_require_authentication(as_role):
	from app.main import app

	as_role("parent")
	app.dependency_overrides.pop(get_current_user)
	response = TestClient(app).post("/api/v1/admin/videos/youtube/discover", json={"topic": "science"})
	assert response.status_code == 401


def test_discovery_rejects_free_text_topics():
	"""Validation runs before any YouTube call; arbitrary search terms are never sent."""
	from pydantic import ValidationError

	from app.schemas.video import YouTubeDiscoverRequest

	with pytest.raises(ValidationError):
		YouTubeDiscoverRequest(topic="anything at all")


def test_scheduled_discovery_actor_requires_active_admin_with_video_write(monkeypatch):
	from app import cli

	base = declarative_base()

	class User(base):
		__tablename__ = "discovery_users"
		id = Column(String, primary_key=True)
		role = Column(String, nullable=False)
		is_active = Column(Boolean, nullable=False)

	class AdminRole(base):
		__tablename__ = "discovery_admin_roles"
		id = Column(String, primary_key=True)
		permissions = Column(JSON, nullable=False)

	class UserAdminRole(base):
		__tablename__ = "discovery_user_admin_roles"
		user_id = Column(String, primary_key=True)
		admin_role_id = Column(String, primary_key=True)

	engine = create_engine("sqlite://")
	base.metadata.create_all(engine)
	monkeypatch.setattr(
		cli,
		"get_model",
		lambda name: {
			"User": User,
			"AdminRole": AdminRole,
			"UserAdminRole": UserAdminRole,
		}[name],
	)
	with Session(engine) as session:
		session.add_all(
			[
				User(id="authorized", role="admin", is_active=True),
				User(id="read_only", role="staff", is_active=True),
				User(id="inactive", role="admin", is_active=False),
				User(id="parent", role="parent", is_active=True),
				AdminRole(id="video_writer", permissions=["video:write"]),
				AdminRole(id="read_only_role", permissions=["video:read"]),
			]
		)
		session.flush()
		session.add_all(
			[
				UserAdminRole(user_id="authorized", admin_role_id="video_writer"),
				UserAdminRole(user_id="read_only", admin_role_id="read_only_role"),
			]
		)
		session.flush()
		assert cli._youtube_discovery_actor(session, "authorized").id == "authorized"
		assert cli._youtube_discovery_actor(session, "read_only") is None
		assert cli._youtube_discovery_actor(session, "inactive") is None
		assert cli._youtube_discovery_actor(session, "parent") is None
		assert cli._youtube_discovery_actor(session, "unassigned") is None


def test_report_refuses_administrators(as_role):
	response = as_role("admin").post("/api/v1/videos/report", json={"video_id": str(uuid4()), "reason": "scary"})
	assert response.status_code == 403


def test_approval_accepts_no_status_or_safety_flags_from_the_client():
	"""The client attests rights clearance only; review status is never client-supplied."""
	from pydantic import ValidationError

	from app.schemas.video import YouTubeApproveRequest

	base = {"age_min": 3, "age_max": 5, "language_code": "en"}
	with pytest.raises(ValidationError):
		YouTubeApproveRequest(**base, rights_status="approved")
	request = YouTubeApproveRequest(**base, rights_status="cleared", status="approved", made_for_kids=True)
	assert not {"status", "made_for_kids"} & set(request.model_dump())


def test_trusted_channel_automatically_publishes_only_clean_short_candidates(monkeypatch):
	from app.services.youtube_review_service import _auto_publish

	monkeypatch.setattr(reviews, "record_audit", lambda *args, **kwargs: None)
	actor = SimpleNamespace(id=uuid4())
	channel = SimpleNamespace(
		id=uuid4(),
		channel_id="UC1234567890123456789012",
		is_active=True,
		age_min=6,
		age_max=8,
		language_code="en",
		category_id=None,
		rights_status="cleared",
	)
	review = SimpleNamespace(
		status="pending_review",
		channel_id=channel.channel_id,
		screening_flags=[],
		made_for_kids=True,
		 rights_status="unreviewed",
		last_verified_at=None,
		publication_source="manual",
		publication_reason=None,
		youtube_video_id=VIDEO_ID,
	)
	video = SimpleNamespace(
		duration_seconds=120,
		age_min=4,
		age_max=12,
		language_code="en",
		category_id=None,
		content_rating="parent_review_required",
		is_published=False,
		published_at=None,
		id=uuid4(),
	)
	assert _auto_publish(None, actor, review, video, channel) is True
	assert review.status == "approved"
	assert review.rights_status == "cleared"
	assert review.publication_source == "automatic"
	assert video.is_published is True
	assert (video.age_min, video.age_max) == (6, 8)

	for field, value in (("channel_id", "UCother123456789012345678"), ("screening_flags", ["keyword:scary"])):
		review.status = "pending_review"
		review.channel_id = channel.channel_id
		review.screening_flags = []
		setattr(review, field, value)
		assert _auto_publish(None, actor, review, video, channel) is False

	non_trusted_review = SimpleNamespace(
		status="pending_review",
		channel_id="UCother123456789012345678",
		screening_flags=[],
		made_for_kids=True,
		rights_status="cleared",
		last_verified_at=None,
		publication_source="manual",
		publication_reason=None,
		youtube_video_id=VIDEO_ID,
	)
	non_trusted_video = SimpleNamespace(
		duration_seconds=120,
		age_min=4,
		age_max=12,
		language_code="en",
		category_id=None,
		content_rating="parent_review_required",
		is_published=False,
		published_at=None,
		id=uuid4(),
	)
	assert _auto_publish(None, actor, non_trusted_review, non_trusted_video) is True
	assert non_trusted_review.status == "approved"
	assert non_trusted_review.publication_source == "automatic"
	assert non_trusted_video.is_published is True

	non_trusted_review.status = "pending_review"
	non_trusted_review.rights_status = "not_cleared"
	non_trusted_video.is_published = False
	assert _auto_publish(None, actor, non_trusted_review, non_trusted_video) is False


def test_feed_items_never_carry_a_key_or_moderation_fields():
	from app.schemas.video import VideoFeedItem

	fields = set(VideoFeedItem.model_fields)
	assert not fields & {"api_key", "screening_flags", "review_notes", "status", "rights_status", "video_url"}
