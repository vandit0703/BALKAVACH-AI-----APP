"""In-memory SQLite world for the video-time path (allowance ledgers, alerts,
watch history) and the deferred D6 ``video_play_tickets`` table.

Declares only the columns the code under test touches. SQLite has no row
locks and no partial unique indexes: concurrency is NOT covered here and
still needs the PostgreSQL suite (TEST_DATABASE_URL). Nothing here is a
production store, and nothing here changes a real database.
"""

from __future__ import annotations

from datetime import date, datetime, timedelta, timezone
from uuid import UUID, uuid4

import pytest
from sqlalchemy import JSON, Boolean, Date, DateTime, Integer, String, Uuid, create_engine
from sqlalchemy.pool import StaticPool
from sqlalchemy.orm import DeclarativeBase, Mapped, Session, mapped_column, sessionmaker

from app.core.exceptions import APIError
from app.services import video_time_alerts as alerts
from app.services.video_time_alerts import EXHAUSTED, NEARLY_EXHAUSTED, alert_text, crossed_event
from app.utils import utc_naive


class Base(DeclarativeBase):
	pass


class User(Base):
	__tablename__ = "users"
	id: Mapped[UUID] = mapped_column(Uuid, primary_key=True, default=uuid4)
	preferred_language: Mapped[str] = mapped_column(String, default="en")


class ChildProfile(Base):
	__tablename__ = "child_profiles"
	id: Mapped[UUID] = mapped_column(Uuid, primary_key=True, default=uuid4)
	user_id: Mapped[UUID] = mapped_column(Uuid)
	family_id: Mapped[UUID] = mapped_column(Uuid)
	is_active: Mapped[bool] = mapped_column(Boolean, default=True)


class FamilySetting(Base):
	__tablename__ = "family_settings"
	family_id: Mapped[UUID] = mapped_column(Uuid, primary_key=True)
	mission_settings: Mapped[dict] = mapped_column(JSON, default=dict)
	video_settings: Mapped[dict] = mapped_column(JSON, default=dict)


class Video(Base):
	__tablename__ = "videos"
	id: Mapped[UUID] = mapped_column(Uuid, primary_key=True, default=uuid4)
	title: Mapped[str] = mapped_column(String, default="Stars")
	description: Mapped[str | None] = mapped_column(String)
	thumbnail_url: Mapped[str | None] = mapped_column(String)
	duration_seconds: Mapped[int] = mapped_column(Integer, default=600)
	category_id: Mapped[UUID | None] = mapped_column(Uuid)
	language_code: Mapped[str] = mapped_column(String, default="en")
	video_source: Mapped[str] = mapped_column(String, default="youtube")
	external_video_id: Mapped[str] = mapped_column(String, default="abcdefghijk")


class ChildVideoWatchHistory(Base):
	__tablename__ = "child_video_watch_history"
	id: Mapped[UUID] = mapped_column(Uuid, primary_key=True, default=uuid4)
	child_id: Mapped[UUID] = mapped_column(Uuid)
	video_id: Mapped[UUID] = mapped_column(Uuid)
	youtube_video_id: Mapped[str | None] = mapped_column(String)
	video_format: Mapped[str] = mapped_column(String)
	started_at: Mapped[datetime] = mapped_column(DateTime)
	last_watched_at: Mapped[datetime] = mapped_column(DateTime)
	completed_at: Mapped[datetime | None] = mapped_column(DateTime)
	last_position_seconds: Mapped[int] = mapped_column(Integer, default=0)
	watch_duration_seconds: Mapped[int] = mapped_column(Integer, default=0)
	completion_percentage: Mapped[int] = mapped_column(Integer, default=0)
	is_completed: Mapped[bool] = mapped_column(Boolean, default=False)
	parent_replay_authorized: Mapped[bool] = mapped_column(Boolean, default=False)


class ChildVideoDailyUsage(Base):
	__tablename__ = "child_video_daily_usage"
	id: Mapped[UUID] = mapped_column(Uuid, primary_key=True, default=uuid4)
	child_id: Mapped[UUID] = mapped_column(Uuid)
	local_date: Mapped[date] = mapped_column(Date)
	free_watched_seconds: Mapped[int] = mapped_column(Integer, default=0)
	last_heartbeat_at: Mapped[datetime | None] = mapped_column(DateTime)
	is_playing: Mapped[bool] = mapped_column(Boolean, default=False)


class VideoAccessEntitlement(Base):
	__tablename__ = "video_access_entitlements"
	id: Mapped[UUID] = mapped_column(Uuid, primary_key=True, default=uuid4)
	child_id: Mapped[UUID] = mapped_column(Uuid)
	source_type: Mapped[str] = mapped_column(String)
	task_id: Mapped[UUID | None] = mapped_column(Uuid)
	submission_id: Mapped[UUID | None] = mapped_column(Uuid)
	video_id: Mapped[UUID | None] = mapped_column(Uuid)
	video_collection_id: Mapped[UUID | None] = mapped_column(Uuid)
	granted_seconds: Mapped[int] = mapped_column(Integer)
	consumed_seconds: Mapped[int] = mapped_column(Integer, default=0)
	granted_at: Mapped[datetime] = mapped_column(DateTime)
	valid_from: Mapped[datetime | None] = mapped_column(DateTime)
	expires_at: Mapped[datetime | None] = mapped_column(DateTime)
	status: Mapped[str] = mapped_column(String, default="active")


class Notification(Base):
	__tablename__ = "notifications"
	id: Mapped[UUID] = mapped_column(Uuid, primary_key=True, default=uuid4)
	recipient_user_id: Mapped[UUID] = mapped_column(Uuid)
	notification_type: Mapped[str] = mapped_column(String)
	title: Mapped[str] = mapped_column(String)
	message: Mapped[str] = mapped_column(String)
	related_task_id: Mapped[UUID | None] = mapped_column(Uuid)
	related_submission_id: Mapped[UUID | None] = mapped_column(Uuid)
	related_redemption_id: Mapped[UUID | None] = mapped_column(Uuid)
	is_read: Mapped[bool] = mapped_column(Boolean, default=False)
	read_at: Mapped[datetime | None] = mapped_column(DateTime)
	created_at: Mapped[datetime] = mapped_column(DateTime)


class VideoPlayTicket(Base):
	"""The deferred D6 table, declared for tests only (docs/deferred-database-integration.md).
	SQLite cannot express the partial unique index, so the one-active rule is
	checked by the repository double in the tests."""

	__tablename__ = "video_play_tickets"
	id: Mapped[UUID] = mapped_column(Uuid, primary_key=True, default=uuid4)
	child_id: Mapped[UUID] = mapped_column(Uuid)
	video_id: Mapped[UUID] = mapped_column(Uuid)
	device_session_id: Mapped[str] = mapped_column(String)
	token_hash: Mapped[str] = mapped_column(String, unique=True)
	state: Mapped[str] = mapped_column(String)
	issued_at: Mapped[datetime] = mapped_column(DateTime)
	expires_at: Mapped[datetime] = mapped_column(DateTime)
	started_at: Mapped[datetime | None] = mapped_column(DateTime)
	last_heartbeat_at: Mapped[datetime | None] = mapped_column(DateTime)
	ended_at: Mapped[datetime | None] = mapped_column(DateTime)
	last_sequence: Mapped[int] = mapped_column(Integer, default=-1)
	charged_seconds: Mapped[int] = mapped_column(Integer, default=0)
	free_charged_seconds: Mapped[int] = mapped_column(Integer, default=0)
	local_date: Mapped[date] = mapped_column(Date)
	superseded_by: Mapped[UUID | None] = mapped_column(Uuid)
	end_reason: Mapped[str | None] = mapped_column(String)
	created_at: Mapped[datetime] = mapped_column(DateTime)


MODELS = {cls.__name__: cls for cls in Base.__subclasses__()}


@pytest.fixture
def db(monkeypatch) -> Session:
	import app.services.notification_service as notifications
	import app.services.timezone_service as zones
	import app.services.video_entitlement_service as entitlements
	import app.services.video_watch_history_service as history

	import app.services.play_ticket_service as tickets

	for module in (history, entitlements, alerts, notifications, zones, tickets):
		monkeypatch.setattr(module, "get_model", MODELS.__getitem__)
	monkeypatch.setattr(history, "_eligible_video", lambda session, child, video_id: session.get(Video, video_id))
	monkeypatch.setattr(tickets, "_eligible_video", lambda session, child, video_id: _eligible(session, video_id))
	# One shared connection: FastAPI test routes run in another thread.
	engine = create_engine("sqlite://", connect_args={"check_same_thread": False}, poolclass=StaticPool)
	Base.metadata.create_all(engine)
	session = sessionmaker(bind=engine, autoflush=False, expire_on_commit=False)()
	try:
		yield session
	finally:
		session.close()
		engine.dispose()


def _today(db, child) -> date:
	from app.services.timezone_service import local_today

	return local_today(db, child.family_id)


def make_child(db, *, language="en", free_left=900, timezone_name="Asia/Kolkata"):
	"""A child who has watched some free time and is mid-video (last report 30 s ago, playing)."""
	user = User(preferred_language=language)
	db.add(user)
	db.flush()
	child = ChildProfile(user_id=user.id, family_id=uuid4())
	db.add(child)
	db.add(FamilySetting(family_id=child.family_id, mission_settings={"timezone": timezone_name}, video_settings={}))
	db.flush()
	db.add(
		ChildVideoDailyUsage(
			child_id=child.id,
			local_date=_today(db, child),
			free_watched_seconds=900 - free_left,
			last_heartbeat_at=utc_naive(datetime.now(timezone.utc)) - timedelta(seconds=30),
			is_playing=True,
		)
	)
	video = Video()
	db.add(video)
	db.flush()
	now = utc_naive(datetime.now(timezone.utc))
	db.add(
		ChildVideoWatchHistory(
			child_id=child.id,
			video_id=video.id,
			youtube_video_id=video.external_video_id,
			video_format="regular",
			started_at=now - timedelta(seconds=70),
			last_watched_at=now - timedelta(seconds=30),
			last_position_seconds=70,
			watch_duration_seconds=70,
			completion_percentage=0,
			is_completed=False,
			parent_replay_authorized=False,
		)
	)
	db.commit()
	return child, video


def tick(db, child, seconds=30):
	"""Let `seconds` of playback pass since the last report (server clock)."""
	usage = db.query(ChildVideoDailyUsage).filter_by(child_id=child.id).one()
	usage.last_heartbeat_at = utc_naive(datetime.now(timezone.utc)) - timedelta(seconds=seconds)
	db.commit()


def report(db, child, video, position=100):
	from app.services.video_watch_history_service import record_progress

	return record_progress(db, child, video.id, position, is_playing=True)


def alerts_of(db, child, kind=None):
	query = db.query(Notification).filter(Notification.recipient_user_id == child.user_id)
	if kind:
		query = query.filter(Notification.notification_type == kind)
	return query.all()


def grant(db, child, seconds=900, at=None):
	at = at or utc_naive(datetime.now(timezone.utc))
	db.add(
		VideoAccessEntitlement(
			child_id=child.id, source_type="mission_reward", submission_id=uuid4(), granted_seconds=seconds,
			consumed_seconds=0, granted_at=at, valid_from=at, expires_at=at + timedelta(hours=12), status="active",
		)
	)
	db.commit()


def _eligible(session, video_id):
	"""Test stand-in for the feed eligibility rules: a video marked unpublished is refused."""
	from fastapi import HTTPException

	video = session.get(Video, video_id)
	if video is None or getattr(video, "title", "") == "UNPUBLISHED":
		raise HTTPException(status_code=404, detail="Video not found")
	return video
