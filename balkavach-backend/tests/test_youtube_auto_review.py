"""Automatic YouTube approval, run against an in-memory SQLite copy of the tables.

This executes the real ``auto_review`` / ``auto_approval_blocker`` code, with only
``get_model`` pointed at lookalike tables, so it needs no database server. It does
not replace the PostgreSQL suite (JSONB, row locks and constraints are not
exercised). YouTube is an in-memory fake; no network call is made.
"""

from datetime import datetime
from types import SimpleNamespace
from uuid import uuid4

import pytest
from sqlalchemy import JSON, Boolean, DateTime, Integer, String, Text, Uuid, create_engine
from sqlalchemy.orm import DeclarativeBase, Mapped, mapped_column, sessionmaker

from app.core.config import settings
from app.integrations.youtube import YouTubeQuotaError
from app.services import admin_service, youtube_review_service as svc


class Base(DeclarativeBase):
	pass


def _id():
	return mapped_column(Uuid(as_uuid=True), primary_key=True, default=uuid4)


class Video(Base):
	__tablename__ = "videos"
	id: Mapped[object] = _id()
	title: Mapped[str] = mapped_column(String(200))
	description: Mapped[str | None] = mapped_column(Text, nullable=True)
	video_source: Mapped[str] = mapped_column(String(20), default="youtube")
	video_url: Mapped[str] = mapped_column(Text, default="")
	external_video_id: Mapped[str | None] = mapped_column(String(200), nullable=True)
	thumbnail_url: Mapped[str | None] = mapped_column(Text, nullable=True)
	duration_seconds: Mapped[int] = mapped_column(Integer)
	category_id: Mapped[object | None] = mapped_column(Uuid(as_uuid=True), nullable=True)
	language_code: Mapped[str] = mapped_column(String(10), default="en")
	age_min: Mapped[int] = mapped_column(Integer, default=4)
	age_max: Mapped[int] = mapped_column(Integer, default=12)
	content_rating: Mapped[str] = mapped_column(String(30), default="parent_review_required")
	is_published: Mapped[bool] = mapped_column(Boolean, default=False)
	published_at: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)


class Review(Base):
	__tablename__ = "youtube_content_reviews"
	id: Mapped[object] = _id()
	video_id: Mapped[object] = mapped_column(Uuid(as_uuid=True))
	youtube_video_id: Mapped[str] = mapped_column(String(11), unique=True)
	channel_id: Mapped[str | None] = mapped_column(String(64), nullable=True)
	made_for_kids: Mapped[bool | None] = mapped_column(Boolean, nullable=True)
	status: Mapped[str] = mapped_column(String(20), default="discovered")
	screening_flags: Mapped[list] = mapped_column(JSON, default=list)
	rights_status: Mapped[str] = mapped_column(String(20), default="unreviewed")
	reviewed_by: Mapped[object | None] = mapped_column(Uuid(as_uuid=True), nullable=True)
	reviewed_at: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)
	last_verified_at: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)
	updated_at: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)
	youtube_category_id: Mapped[str | None] = mapped_column(String(20), nullable=True)
	publication_source: Mapped[str] = mapped_column(String(20), default="manual")
	publication_reason: Mapped[str | None] = mapped_column(Text, nullable=True)


class Trusted(Base):
	__tablename__ = "youtube_trusted_channels"
	id: Mapped[object] = _id()
	channel_id: Mapped[str] = mapped_column(String(64))
	is_active: Mapped[bool] = mapped_column(Boolean, default=True)
	rights_status: Mapped[str] = mapped_column(String(20), default="cleared")
	age_min: Mapped[int] = mapped_column(Integer, default=6)
	age_max: Mapped[int] = mapped_column(Integer, default=8)
	language_code: Mapped[str] = mapped_column(String(10), default="en")
	category_id: Mapped[object | None] = mapped_column(Uuid(as_uuid=True), nullable=True)


class Report(Base):
	__tablename__ = "content_reports"
	id: Mapped[object] = _id()
	video_id: Mapped[object] = mapped_column(Uuid(as_uuid=True))
	status: Mapped[str] = mapped_column(String(20), default="open")


class Audit(Base):
	__tablename__ = "audit_logs"
	id: Mapped[object] = _id()
	actor_user_id: Mapped[object | None] = mapped_column(Uuid(as_uuid=True), nullable=True)
	action: Mapped[str] = mapped_column(String(80))
	entity_type: Mapped[str] = mapped_column(String(40))
	entity_id: Mapped[object | None] = mapped_column(Uuid(as_uuid=True), nullable=True)
	details: Mapped[dict] = mapped_column(JSON)
	created_at: Mapped[datetime] = mapped_column(DateTime)


MODELS = {
	"Video": Video,
	"YouTubeContentReview": Review,
	"YouTubeTrustedChannel": Trusted,
	"ContentReport": Report,
	"AuditLog": Audit,
}
ACTOR = SimpleNamespace(id=uuid4())
CHANNEL = "UC1111111111111111111111"


def _yt(video_id, duration="PT45S", title="Counting with animals", **status):
	return {
		"id": video_id,
		"snippet": {
			"title": title,
			"description": "Learning for children.",
			"channelId": CHANNEL,
			"liveBroadcastContent": "none",
			"thumbnails": {"high": {"url": f"https://i.ytimg.com/vi/{video_id}/hqdefault.jpg"}},
		},
		"contentDetails": {"duration": duration},
		"status": {"privacyStatus": "public", "embeddable": True, "uploadStatus": "processed", "madeForKids": True, **status},
	}


class FakeYouTube:
	def __init__(self, *items, error=None):
		self.items = {item["id"]: item for item in items}
		self.error = error
		self.calls = 0

	def videos(self, ids, use_cache=True):
		self.calls += 1
		if self.error:
			raise self.error
		return {i: self.items[i] for i in ids if i in self.items}


@pytest.fixture
def session(monkeypatch):
	engine = create_engine("sqlite://")
	Base.metadata.create_all(engine)
	monkeypatch.setattr(svc, "get_model", lambda name: MODELS[name])
	monkeypatch.setattr(svc, "has_model", lambda name: name in MODELS)
	monkeypatch.setattr(admin_service, "get_model", lambda name: MODELS[name])
	monkeypatch.setattr(settings, "youtube_auto_publish_non_trusted", True)
	monkeypatch.setattr(settings, "youtube_auto_publish_age_band", "6-8")
	monkeypatch.setattr(settings, "youtube_auto_publish_max_seconds", 180)
	monkeypatch.setattr(settings, "youtube_region_code", "IN")
	with sessionmaker(bind=engine, expire_on_commit=False)() as db:
		yield db


def _add(db, video_id, status="pending_review", *, flags=(), duration=45, published=False, **review):
	video = Video(title=video_id, duration_seconds=duration, is_published=published,
		content_rating="educational" if published else "parent_review_required")
	db.add(video)
	db.flush()
	review.setdefault("made_for_kids", True)
	row = Review(
		video_id=video.id, youtube_video_id=video_id, channel_id=CHANNEL,
		status=status, screening_flags=list(flags), **review,
	)
	db.add(row)
	db.commit()
	return row, video


def _run(db, client, **kwargs):
	return svc.auto_review(db, ACTOR, client, **kwargs)


# --- blocker policy (pure) ---------------------------------------------------

def _candidate(**over):
	review = SimpleNamespace(
		status="pending_review", screening_flags=[], made_for_kids=True, rights_status="cleared",
		channel_id=CHANNEL, youtube_video_id="aaaaaaaaaaa", id=uuid4(),
	)
	video = SimpleNamespace(duration_seconds=45)
	for key, value in over.items():
		setattr(video if key == "duration_seconds" else review, key, value)
	return review, video


def test_clean_short_candidate_has_no_blocker(monkeypatch):
	monkeypatch.setattr(settings, "youtube_auto_publish_non_trusted", True)
	monkeypatch.setattr(settings, "youtube_auto_publish_age_band", "6-8")
	assert svc.auto_approval_blocker(*_candidate()) is None


@pytest.mark.parametrize(
	"over,reason",
	[
		({"screening_flags": ["keyword:fight"]}, "screening_flags"),
		({"made_for_kids": None}, "made_for_kids_not_true"),
		({"made_for_kids": False}, "made_for_kids_not_true"),
		({"duration_seconds": 181}, "duration_exceeds_limit"),
		({"rights_status": "not_cleared"}, "rights_not_cleared"),
		({"rights_status": "unreviewed"}, "rights_not_cleared"),
		({"status": "quarantined"}, "review_not_pending"),
		({"status": "approved"}, "review_not_pending"),
	],
)
def test_blocker_reasons(monkeypatch, over, reason):
	monkeypatch.setattr(settings, "youtube_auto_publish_non_trusted", True)
	monkeypatch.setattr(settings, "youtube_auto_publish_age_band", "6-8")
	assert svc.auto_approval_blocker(*_candidate(**over))[0] == reason


# --- scenarios against the real service --------------------------------------

def test_valid_video_is_approved_and_published_automatically(session):
	row, video = _add(session, "aaaaaaaaaaa")
	result = _run(session, FakeYouTube(_yt("aaaaaaaaaaa")))
	session.refresh(row), session.refresh(video)
	assert result["auto_approved"] == 1 and result["error"] is None
	assert (row.status, video.is_published) == ("approved", True)
	assert row.publication_source == "automatic" and row.reviewed_by is None
	assert row.rights_status == "cleared" and video.content_rating == "educational"


def test_keyword_hit_is_quarantined_not_published(session):
	row, video = _add(session, "aaaaaaaaaaa")
	result = _run(session, FakeYouTube(_yt("aaaaaaaaaaa", title="Zombie fight night")))
	session.refresh(row), session.refresh(video)
	assert result["newly_quarantined"] == 1 and result["auto_approved"] == 0
	assert (row.status, video.is_published) == ("quarantined", False)
	assert {"keyword:zombie", "keyword:fight"} <= set(row.screening_flags)


@pytest.mark.parametrize("override", [{"embeddable": False}, {"privacyStatus": "private"}])
def test_unplayable_metadata_is_never_published(session, override):
	row, video = _add(session, "aaaaaaaaaaa")
	result = _run(session, FakeYouTube(_yt("aaaaaaaaaaa", **override)))
	session.refresh(row), session.refresh(video)
	assert result["unavailable"] == 1
	assert (row.status, video.is_published) == ("unavailable", False)


def test_video_missing_from_youtube_is_unavailable(session):
	row, video = _add(session, "aaaaaaaaaaa")
	_run(session, FakeYouTube())
	session.refresh(row)
	assert row.status == "unavailable" and not video.is_published


def test_made_for_kids_unknown_is_quarantined(session):
	row, _ = _add(session, "aaaaaaaaaaa")
	item = _yt("aaaaaaaaaaa")
	item["status"]["madeForKids"] = None
	result = _run(session, FakeYouTube(item))
	session.refresh(row)
	assert row.status == "quarantined" and "made_for_kids_unknown" in result["quarantine_reasons"]


def test_youtube_outage_changes_nothing_and_is_retryable(session):
	row, video = _add(session, "aaaaaaaaaaa")
	before = row.last_verified_at
	result = _run(session, FakeYouTube(error=YouTubeQuotaError("quota")))
	session.refresh(row), session.refresh(video)
	assert result["error"] == "youtube_quota_exhausted" and result["retry_later"] == 1
	assert (row.status, video.is_published, row.last_verified_at) == ("pending_review", False, before)
	# ...and the next run, with YouTube back, succeeds.
	assert _run(session, FakeYouTube(_yt("aaaaaaaaaaa")))["auto_approved"] == 1


def test_rerun_is_idempotent(session):
	row, _ = _add(session, "aaaaaaaaaaa")
	client = FakeYouTube(_yt("aaaaaaaaaaa"))
	assert _run(session, client)["auto_approved"] == 1
	second = _run(session, client)
	assert second["checked"] == 0 and second["auto_approved"] == 0
	assert session.query(Review).count() == 1 and session.query(Video).count() == 1
	assert session.query(Audit).filter(Audit.action == "youtube.approved").count() == 1


def test_manual_approvals_are_never_touched(session):
	admin = uuid4()
	row, video = _add(
		session, "aaaaaaaaaaa", "approved", published=True, reviewed_by=admin,
		rights_status="cleared", publication_source="manual", publication_reason="administrator approval",
	)
	# Even if YouTube now returns something that would be quarantined, auto-review
	# does not look at approved rows (recheck owns that).
	result = _run(session, FakeYouTube(_yt("aaaaaaaaaaa", title="gore")))
	session.refresh(row), session.refresh(video)
	assert result["checked"] == 0
	assert (row.status, video.is_published, row.reviewed_by, row.publication_source) == ("approved", True, admin, "manual")


def test_rejected_and_revoked_decisions_are_never_reopened(session):
	rejected, _ = _add(session, "aaaaaaaaaaa", "rejected", reviewed_by=uuid4())
	revoked, _ = _add(session, "bbbbbbbbbbb", "revoked", reviewed_by=uuid4())
	result = _run(session, FakeYouTube(_yt("aaaaaaaaaaa"), _yt("bbbbbbbbbbb")))
	session.refresh(rejected), session.refresh(revoked)
	assert result["checked"] == 0 and (rejected.status, revoked.status) == ("rejected", "revoked")


def test_quarantine_with_cleared_flags_is_reevaluated_and_approved(session):
	row, video = _add(session, "aaaaaaaaaaa", "quarantined", flags=["made_for_kids_unknown"], made_for_kids=None)
	result = _run(session, FakeYouTube(_yt("aaaaaaaaaaa")))
	session.refresh(row), session.refresh(video)
	assert result["returned_to_pending"] == 1 and result["auto_approved"] == 1
	assert (row.status, video.is_published, row.screening_flags) == ("approved", True, [])


def test_quarantine_that_still_fails_stays_quarantined_with_reasons(session):
	row, video = _add(session, "aaaaaaaaaaa", "quarantined", flags=["keyword:fight"])
	result = _run(session, FakeYouTube(_yt("aaaaaaaaaaa", title="Big fight")))
	session.refresh(row)
	assert result["still_quarantined"] == 1 and result["quarantine_reasons"] == {"keyword:fight": 1}
	assert (row.status, video.is_published) == ("quarantined", False)


def test_report_and_administrator_quarantines_are_left_for_a_person(session):
	reported, rv = _add(session, "aaaaaaaaaaa", "quarantined", flags=["keyword:fight"])
	session.add(Report(video_id=rv.id, status="open"))
	by_admin, _ = _add(session, "bbbbbbbbbbb", "quarantined", flags=["age_restricted"], reviewed_by=uuid4())
	session.commit()
	result = _run(session, FakeYouTube(_yt("aaaaaaaaaaa"), _yt("bbbbbbbbbbb")))
	session.refresh(reported), session.refresh(by_admin)
	assert result["checked"] == 0
	assert (reported.status, by_admin.status) == ("quarantined", "quarantined")


def test_include_quarantined_false_skips_quarantine(session):
	row, _ = _add(session, "aaaaaaaaaaa", "quarantined", flags=["made_for_kids_unknown"])
	assert _run(session, FakeYouTube(_yt("aaaaaaaaaaa")), include_quarantined=False)["checked"] == 0
	session.refresh(row)
	assert row.status == "quarantined"


def test_long_video_waits_with_a_visible_reason(session):
	row, video = _add(session, "aaaaaaaaaaa", duration=45)
	result = _run(session, FakeYouTube(_yt("aaaaaaaaaaa", duration="PT10M")))
	session.refresh(row), session.refresh(video)
	assert result["needs_manual_review"] == 1 and result["blocked_reasons"] == {"duration_exceeds_limit": 1}
	assert (row.status, video.is_published) == ("pending_review", False)
	assert "longer than the automatic approval limit" in row.publication_reason


def test_explicitly_denied_rights_are_not_overridden(session):
	row, video = _add(session, "aaaaaaaaaaa", rights_status="not_cleared")
	_run(session, FakeYouTube(_yt("aaaaaaaaaaa")))
	session.refresh(row)
	assert (row.status, row.rights_status, video.is_published) == ("pending_review", "not_cleared", False)


def test_policy_switch_off_leaves_everything_for_a_person(session, monkeypatch):
	monkeypatch.setattr(settings, "youtube_auto_publish_non_trusted", False)
	row, video = _add(session, "aaaaaaaaaaa")
	result = _run(session, FakeYouTube(_yt("aaaaaaaaaaa")))
	session.refresh(row)
	assert result["needs_manual_review"] == 1
	assert (row.status, row.rights_status, video.is_published) == ("pending_review", "unreviewed", False)


def test_unknown_duration_is_filled_in_from_youtube(session):
	row, video = _add(session, "aaaaaaaaaaa", duration=1)
	_run(session, FakeYouTube(_yt("aaaaaaaaaaa", duration="PT30S")))
	session.refresh(video)
	assert video.duration_seconds == 30 and video.is_published


def test_trusted_channel_values_apply(session):
	session.add(Trusted(channel_id=CHANNEL, age_min=6, age_max=8, language_code="hi"))
	row, video = _add(session, "aaaaaaaaaaa")
	_run(session, FakeYouTube(_yt("aaaaaaaaaaa")))
	session.refresh(video)
	assert (video.age_min, video.age_max, video.language_code) == (6, 8, "hi")


# --- age bands ---------------------------------------------------------------

@pytest.mark.parametrize("band", ["3-5", "6-8", "9-12", "13-15"])
def test_every_supported_band_is_accepted_and_applied(session, monkeypatch, band):
	monkeypatch.setattr(settings, "youtube_auto_publish_age_band", band)
	row, video = _add(session, "aaaaaaaaaaa")
	_run(session, FakeYouTube(_yt("aaaaaaaaaaa")))
	session.refresh(video)
	low, high = (int(part) for part in band.split("-"))
	assert (video.age_min, video.age_max) == (low, high) and video.is_published


@pytest.mark.parametrize("value,reason", [
	(None, "age_band_not_configured"),
	("", "age_band_not_configured"),
	("4-12", "unsupported_age_band"),
	("3-15", "unsupported_age_band"),
	("kids", "unsupported_age_band"),
])
def test_no_band_is_guessed_when_none_valid_is_configured(session, monkeypatch, value, reason):
	monkeypatch.setattr(settings, "youtube_auto_publish_age_band", value)
	row, video = _add(session, "aaaaaaaaaaa")
	result = _run(session, FakeYouTube(_yt("aaaaaaaaaaa")))
	session.refresh(row), session.refresh(video)
	assert result["blocked_reasons"] == {reason: 1}
	assert (row.status, video.is_published) == ("pending_review", False)
	assert (video.age_min, video.age_max) == (4, 12) and row.rights_status == "unreviewed"
	assert row.publication_reason.startswith("Waiting for manual review")


def test_trusted_channel_with_an_unsupported_band_is_blocked(session):
	session.add(Trusted(channel_id=CHANNEL, age_min=4, age_max=12))
	row, video = _add(session, "aaaaaaaaaaa")
	result = _run(session, FakeYouTube(_yt("aaaaaaaaaaa")))
	session.refresh(video)
	assert result["blocked_reasons"] == {"unsupported_age_band": 1} and not video.is_published


def test_trusted_channel_band_is_used_not_the_non_trusted_setting(session):
	session.add(Trusted(channel_id=CHANNEL, age_min=9, age_max=12))
	row, video = _add(session, "aaaaaaaaaaa")
	_run(session, FakeYouTube(_yt("aaaaaaaaaaa")))
	session.refresh(video)
	assert (video.age_min, video.age_max) == (9, 12)


def test_publish_batch_accepts_an_automatically_approved_video(session):
	row, video = _add(session, "aaaaaaaaaaa")
	client = FakeYouTube(_yt("aaaaaaaaaaa"))
	assert _run(session, client)["auto_approved"] == 1
	video.is_published = False  # e.g. withdrawn because it was not re-verified in time
	session.commit()
	result = svc.publish_approved_unpublished(session, ACTOR, client, 50)
	session.refresh(video)
	assert result["newly_published"] == 1 and "unsupported_age_band" not in result["blocked_by_reason"]
	assert video.is_published and (video.age_min, video.age_max) == (6, 8)


def test_publish_batch_still_blocks_a_legacy_4_12_video_without_changing_it(session):
	row, video = _add(
		session, "aaaaaaaaaaa", "approved", rights_status="cleared", publication_source="automatic"
	)
	client = FakeYouTube(_yt("aaaaaaaaaaa"))
	result = svc.publish_approved_unpublished(session, ACTOR, client, 50)
	session.refresh(row), session.refresh(video)
	assert result["blocked_by_reason"].get("unsupported_age_band") == 1 and result["newly_published"] == 0
	assert (row.status, video.is_published, video.age_min, video.age_max) == ("approved", False, 4, 12)


# --- recheck leaves an audit trail -------------------------------------------

def test_recheck_records_one_audit_row_per_run_and_refreshes_verification(session):
	row, video = _add(
		session, "aaaaaaaaaaa", "approved", published=True, rights_status="cleared",
		publication_source="manual", reviewed_by=uuid4(),
	)
	row.last_verified_at = datetime(2026, 1, 1)
	session.commit()
	counts = svc.recheck(session, FakeYouTube(_yt("aaaaaaaaaaa")), 200)
	session.refresh(row)
	assert counts["checked"] == 1 and counts["verified"] == 1
	assert row.last_verified_at > datetime(2026, 11, 1) and row.status == "approved" and video.is_published
	audit = session.query(Audit).filter(Audit.action == "youtube.recheck.completed").all()
	assert len(audit) == 1 and audit[0].actor_user_id is None and audit[0].details["verified"] == 1


def test_recheck_with_nothing_to_check_writes_no_audit_row(session):
	svc.recheck(session, FakeYouTube(), 200)
	assert session.query(Audit).filter(Audit.action == "youtube.recheck.completed").count() == 0
