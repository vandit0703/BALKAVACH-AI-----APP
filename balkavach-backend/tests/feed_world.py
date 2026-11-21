"""In-memory SQLite world for the child video and Shorts feeds, with the REAL eligibility queries.

Unlike the older feed tests (which replace ``eligible_feed`` with a mock), this world declares the columns
the feed, playback eligibility, allowance, recheck and diagnostics read, so the actual SQL rules run:
publication, age band, rating, language, category, YouTube approval and freshness, duplicates,
completed-video exclusion, short/regular split, and the allowance ledger.

It is NOT PostgreSQL: SQLite has no row locks and no partial indexes, so concurrency and PostgreSQL
behaviour stay unverified here. Nothing in it touches a real database. The allowance tables are reused
from ``tests/video_world.py``; the video tables are declared here with every column the feed needs.
"""

from __future__ import annotations

from datetime import date, datetime, timedelta, timezone
from types import SimpleNamespace
from uuid import UUID, uuid4

import pytest
from sqlalchemy import JSON, Boolean, Date, DateTime, Integer, String, Uuid, create_engine
from sqlalchemy.orm import DeclarativeBase, Mapped, Session, mapped_column, sessionmaker
from sqlalchemy.pool import StaticPool

from app.utils import utc_naive
from tests import video_world as allowance_tables
from tests.video_world import ChildVideoDailyUsage, ChildVideoWatchHistory  # noqa: F401  (re-exported for tests)


class Base(DeclarativeBase):
	pass


class User(Base):
	__tablename__ = "users"
	id: Mapped[UUID] = mapped_column(Uuid, primary_key=True, default=uuid4)
	preferred_language: Mapped[str] = mapped_column(String, default="en")


class Task(Base):
	__tablename__ = "tasks"
	id: Mapped[UUID] = mapped_column(Uuid, primary_key=True, default=uuid4)
	family_id: Mapped[UUID] = mapped_column(Uuid)
	assigned_child_id: Mapped[UUID | None] = mapped_column(Uuid)
	title: Mapped[str] = mapped_column(String, default="Watch and learn")
	required_video_seconds: Mapped[int | None] = mapped_column(Integer)
	star_reward: Mapped[int] = mapped_column(Integer, default=10)
	xp_reward: Mapped[int] = mapped_column(Integer, default=15)
	is_active: Mapped[bool] = mapped_column(Boolean, default=True)


class MissionVideoWatchSession(Base):
	__tablename__ = "mission_video_watch_sessions"
	id: Mapped[UUID] = mapped_column(Uuid, primary_key=True, default=uuid4)
	client_session_id: Mapped[str] = mapped_column(String(32), unique=True)
	task_id: Mapped[UUID] = mapped_column(Uuid)
	child_id: Mapped[UUID] = mapped_column(Uuid)
	video_id: Mapped[UUID] = mapped_column(Uuid)
	started_at: Mapped[datetime] = mapped_column(DateTime)
	last_heartbeat_at: Mapped[datetime] = mapped_column(DateTime)
	ended_at: Mapped[datetime | None] = mapped_column(DateTime)
	last_position_seconds: Mapped[int] = mapped_column(Integer, default=0)
	watched_seconds: Mapped[int] = mapped_column(Integer, default=0)
	last_sequence: Mapped[int] = mapped_column(Integer, default=-1)
	is_playing: Mapped[bool] = mapped_column(Boolean, default=False)
	status: Mapped[str] = mapped_column(String, default="active")


class ChildProfile(Base):
	__tablename__ = "child_profiles"
	id: Mapped[UUID] = mapped_column(Uuid, primary_key=True, default=uuid4)
	user_id: Mapped[UUID] = mapped_column(Uuid)
	family_id: Mapped[UUID] = mapped_column(Uuid)
	display_name: Mapped[str] = mapped_column(String, default="Mia")
	date_of_birth: Mapped[date | None] = mapped_column(Date)
	is_active: Mapped[bool] = mapped_column(Boolean, default=True)


class VideoCategory(Base):
	__tablename__ = "video_categories"
	id: Mapped[UUID] = mapped_column(Uuid, primary_key=True, default=uuid4)
	name: Mapped[str] = mapped_column(String, default="Learn")
	is_active: Mapped[bool] = mapped_column(Boolean, default=True)
	display_order: Mapped[int] = mapped_column(Integer, default=0)


class Video(Base):
	__tablename__ = "videos"
	id: Mapped[UUID] = mapped_column(Uuid, primary_key=True, default=uuid4)
	title: Mapped[str] = mapped_column(String, default="Counting Song")
	description: Mapped[str | None] = mapped_column(String)
	thumbnail_url: Mapped[str | None] = mapped_column(String)
	duration_seconds: Mapped[int] = mapped_column(Integer, default=300)
	category_id: Mapped[UUID | None] = mapped_column(Uuid)
	language_code: Mapped[str] = mapped_column(String, default="en")
	age_min: Mapped[int] = mapped_column(Integer, default=3)
	age_max: Mapped[int] = mapped_column(Integer, default=15)
	content_rating: Mapped[str] = mapped_column(String, default="educational")
	is_published: Mapped[bool] = mapped_column(Boolean, default=True)
	published_at: Mapped[datetime | None] = mapped_column(DateTime)
	display_order: Mapped[int] = mapped_column(Integer, default=0)
	video_source: Mapped[str] = mapped_column(String, default="youtube")
	external_video_id: Mapped[str] = mapped_column(String, default="abcdefghijk")


class YouTubeContentReview(Base):
	__tablename__ = "youtube_content_reviews"
	id: Mapped[UUID] = mapped_column(Uuid, primary_key=True, default=uuid4)
	video_id: Mapped[UUID] = mapped_column(Uuid)
	youtube_video_id: Mapped[str] = mapped_column(String)
	channel_id: Mapped[str | None] = mapped_column(String)
	channel_title: Mapped[str | None] = mapped_column(String)
	status: Mapped[str] = mapped_column(String, default="approved")
	made_for_kids: Mapped[bool | None] = mapped_column(Boolean)
	rights_status: Mapped[str] = mapped_column(String, default="cleared")
	last_verified_at: Mapped[datetime | None] = mapped_column(DateTime)
	screening_flags: Mapped[list] = mapped_column(JSON, default=list)
	reviewed_by: Mapped[UUID | None] = mapped_column(Uuid)
	reviewed_at: Mapped[datetime | None] = mapped_column(DateTime)
	review_notes: Mapped[str | None] = mapped_column(String)
	revoked_reason: Mapped[str | None] = mapped_column(String)
	revoked_at: Mapped[datetime | None] = mapped_column(DateTime)
	youtube_category_id: Mapped[str | None] = mapped_column(String)
	publication_source: Mapped[str | None] = mapped_column(String)
	publication_reason: Mapped[str | None] = mapped_column(String)
	discovered_at: Mapped[datetime | None] = mapped_column(DateTime)
	updated_at: Mapped[datetime | None] = mapped_column(DateTime)


class AuditLog(Base):
	__tablename__ = "audit_logs"
	id: Mapped[UUID] = mapped_column(Uuid, primary_key=True, default=uuid4)
	actor_user_id: Mapped[UUID | None] = mapped_column(Uuid)
	action: Mapped[str] = mapped_column(String)
	entity_type: Mapped[str] = mapped_column(String)
	entity_id: Mapped[UUID | None] = mapped_column(Uuid)
	details: Mapped[dict] = mapped_column(JSON, default=dict)
	created_at: Mapped[datetime] = mapped_column(DateTime)


OWN_MODELS = {cls.__name__: cls for cls in Base.__subclasses__()}
MODELS = {
	**OWN_MODELS,
	"ChildVideoWatchHistory": allowance_tables.ChildVideoWatchHistory,
	"ChildVideoDailyUsage": allowance_tables.ChildVideoDailyUsage,
	"VideoAccessEntitlement": allowance_tables.VideoAccessEntitlement,
	"FamilySetting": allowance_tables.FamilySetting,
	"Notification": allowance_tables.Notification,
}
_SHARED_TABLES = [model.__table__ for name, model in MODELS.items() if name not in OWN_MODELS]


def _get_model(name: str):
	return MODELS[name]


def _has_model(name: str) -> bool:
	return name in MODELS


@pytest.fixture
def feed_db(monkeypatch) -> Session:
	"""A session shaped like production (``autoflush=False``) over a shared in-memory SQLite connection."""
	import app.api.v1.video_access as video_access_api
	import app.api.v1.videos as videos_api
	import app.api.v1.tasks as tasks_api
	import app.services.admin_service as admin
	import app.services.charging_path as charging
	import app.services.notification_service as notifications
	import app.services.timezone_service as zones
	import app.services.video_entitlement_service as entitlements
	import app.services.video_feed_diagnostics as diagnostics
	import app.services.video_service as videos
	import app.services.video_time_alerts as alerts
	import app.services.video_watch_history_service as history
	import app.services.mission_video_service as mission_video
	import app.services.youtube_review_service as reviews

	for module in (
		videos_api, video_access_api, tasks_api, admin, notifications, zones, entitlements, diagnostics, videos,
		alerts, history, mission_video,
		reviews,
	):
		if hasattr(module, "get_model"):
			monkeypatch.setattr(module, "get_model", _get_model)
		if hasattr(module, "has_model"):
			monkeypatch.setattr(module, "has_model", _has_model)
	monkeypatch.setattr(charging, "has_model", _has_model)  # no video_play_tickets table: tickets stay inactive
	engine = create_engine("sqlite://", connect_args={"check_same_thread": False}, poolclass=StaticPool)
	Base.metadata.create_all(engine)
	allowance_tables.Base.metadata.create_all(engine, tables=_SHARED_TABLES)
	session = sessionmaker(bind=engine, autoflush=False, expire_on_commit=False)()
	try:
		yield session
	finally:
		session.close()
		engine.dispose()


# ---- data builders ----------------------------------------------------------------------------------------


def make_child(session: Session, *, age: int | None = 8, language: str = "en", timezone_name: str = "Asia/Kolkata"):
	"""A child of ``age`` years (``None``: no birth date) with a family settings row."""
	user = User(preferred_language=language)
	session.add(user)
	session.flush()
	today = datetime.now(timezone.utc).date()
	born = None if age is None else date(today.year - age, 1, 1) - timedelta(days=1)
	child = ChildProfile(user_id=user.id, family_id=uuid4(), date_of_birth=born)
	session.add(child)
	session.add(allowance_tables.FamilySetting(family_id=child.family_id, mission_settings={"timezone": timezone_name}))
	session.commit()
	return child


def add_video(session: Session, **fields) -> Video:
	"""A published, general-rated, hosted (non-YouTube) video unless ``fields`` say otherwise."""
	fields.setdefault("video_source", "hosted")
	fields.setdefault("external_video_id", uuid4().hex[:11])
	video = Video(**fields)
	session.add(video)
	session.commit()
	return video


def add_youtube(
	session: Session,
	*,
	status: str = "approved",
	verified_hours_ago: float | None = 1,
	made_for_kids: bool | None = True,
	rights: str = "cleared",
	flags: list[str] | None = None,
	youtube_id: str | None = None,
	**video_fields,
):
	"""A YouTube video plus its review row. ``verified_hours_ago=None`` means never verified."""
	youtube_id = youtube_id or uuid4().hex[:11]
	video_fields.setdefault("title", f"Video {youtube_id}")
	video_fields.setdefault("external_video_id", youtube_id)
	video_fields["video_source"] = "youtube"
	video_fields.setdefault("is_published", status == "approved")
	video = Video(**video_fields)
	session.add(video)
	session.flush()
	verified = (
		None
		if verified_hours_ago is None
		else utc_naive(datetime.now(timezone.utc)) - timedelta(hours=verified_hours_ago)
	)
	review = YouTubeContentReview(
		video_id=video.id,
		youtube_video_id=youtube_id,
		status=status,
		made_for_kids=made_for_kids,
		rights_status=rights,
		last_verified_at=verified,
		screening_flags=flags or [],
		publication_source="manual",
	)
	session.add(review)
	session.commit()
	return SimpleNamespace(video=video, review=review)


def good_item(youtube_id: str, *, duration: str = "PT4M", title: str = "Counting Song", **overrides) -> dict:
	"""A ``videos.list`` item that screens clean (the shape ``screen_candidate`` reads)."""
	item = {
		"id": youtube_id,
		"snippet": {
			"title": title,
			"description": "Learn to count to ten.",
			"defaultAudioLanguage": "en",
			"liveBroadcastContent": "none",
			"categoryId": "27",
			"thumbnails": {"high": {"url": f"https://i.ytimg.com/vi/{youtube_id}/hqdefault.jpg"}},
		},
		"contentDetails": {"duration": duration},
		"status": {"privacyStatus": "public", "embeddable": True, "uploadStatus": "processed", "madeForKids": True},
	}
	item.update(overrides)
	return item


class FakeYouTube:
	"""Stands in for ``YouTubeClient``: returns the configured items, or raises the configured error."""

	def __init__(self, items: dict[str, dict] | None = None, error: Exception | None = None):
		self.items = items or {}
		self.error = error
		self.calls: list[list[str]] = []

	def videos(self, video_ids: list[str], *, use_cache: bool = True) -> dict[str, dict]:
		self.calls.append(list(video_ids))
		if self.error is not None:
			raise self.error
		return {video_id: self.items[video_id] for video_id in video_ids if video_id in self.items}
