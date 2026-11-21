"""In-memory SQLite world that runs the REAL parent approval code (``review_submission``) and the REAL review routes.

The production schema is reflected from PostgreSQL and is not in the repository, so this world declares the
columns the approval path reads and writes, including the unique idempotency keys the ledgers rely on. The
PostgreSQL-only upserts (``ON CONFLICT DO UPDATE``) compile and run on SQLite, so the actual service code runs
unchanged. What SQLite cannot show: row locks (``FOR UPDATE`` is ignored, so truly concurrent requests are NOT
exercised), the live schema, and PostgreSQL error behaviour. It touches no real database.
"""

from __future__ import annotations

import sys
from datetime import date, datetime, timezone
from types import SimpleNamespace
from uuid import UUID, uuid4

import pytest
from sqlalchemy import JSON, Boolean, Date, DateTime, Integer, String, UniqueConstraint, Uuid, create_engine
from sqlalchemy.orm import DeclarativeBase, Mapped, Session, mapped_column, sessionmaker
from sqlalchemy.pool import StaticPool

from tests import sqlite_world as shared
from tests import video_world as allowance


class Base(DeclarativeBase):
	pass


def _now() -> datetime:
	return datetime.now(timezone.utc).replace(tzinfo=None)


class ChildProfile(Base):
	__tablename__ = "child_profiles"
	id: Mapped[UUID] = mapped_column(Uuid, primary_key=True, default=uuid4)
	user_id: Mapped[UUID] = mapped_column(Uuid)
	family_id: Mapped[UUID] = mapped_column(Uuid)
	display_name: Mapped[str] = mapped_column(String, default="hshs")
	date_of_birth: Mapped[date | None] = mapped_column(Date)
	is_active: Mapped[bool] = mapped_column(Boolean, default=True)
	current_level_id: Mapped[UUID | None] = mapped_column(Uuid)


class TaskCategory(Base):
	__tablename__ = "task_categories"
	id: Mapped[UUID] = mapped_column(Uuid, primary_key=True, default=uuid4)
	name: Mapped[str] = mapped_column(String, default="Creativity")


class Task(Base):
	__tablename__ = "tasks"
	id: Mapped[UUID] = mapped_column(Uuid, primary_key=True, default=uuid4)
	family_id: Mapped[UUID] = mapped_column(Uuid)
	created_by: Mapped[UUID] = mapped_column(Uuid)
	assigned_child_id: Mapped[UUID | None] = mapped_column(Uuid)
	category_id: Mapped[UUID | None] = mapped_column(Uuid)
	title: Mapped[str] = mapped_column(String, default="Saturday Rhythm Rockstar")
	description: Mapped[str | None] = mapped_column(String)
	star_reward: Mapped[int] = mapped_column(Integer, default=10)
	xp_reward: Mapped[int] = mapped_column(Integer, default=15)
	required_video_seconds: Mapped[int | None] = mapped_column(Integer)
	repeat_rule: Mapped[str | None] = mapped_column(String)
	is_custom: Mapped[bool] = mapped_column(Boolean, default=False)
	is_active: Mapped[bool] = mapped_column(Boolean, default=True)


class TaskSubmission(Base):
	__tablename__ = "task_submissions"
	id: Mapped[UUID] = mapped_column(Uuid, primary_key=True, default=uuid4)
	task_id: Mapped[UUID] = mapped_column(Uuid)
	child_id: Mapped[UUID] = mapped_column(Uuid)
	submission_number: Mapped[int] = mapped_column(Integer, default=1)
	proof_type: Mapped[str] = mapped_column(String, default="none")
	proof_url: Mapped[str | None] = mapped_column(String)
	proof_note: Mapped[str | None] = mapped_column(String)
	status: Mapped[str] = mapped_column(String, default="pending")
	submitted_at: Mapped[datetime] = mapped_column(DateTime, default=_now)
	reviewed_at: Mapped[datetime | None] = mapped_column(DateTime)


class TaskReview(Base):
	__tablename__ = "task_reviews"
	id: Mapped[UUID] = mapped_column(Uuid, primary_key=True, default=uuid4)
	submission_id: Mapped[UUID] = mapped_column(Uuid)
	reviewed_by: Mapped[UUID] = mapped_column(Uuid)
	decision: Mapped[str] = mapped_column(String)
	review_note: Mapped[str | None] = mapped_column(String)
	created_at: Mapped[datetime] = mapped_column(DateTime, default=_now)


class StarTransaction(Base):
	__tablename__ = "star_transactions"
	id: Mapped[UUID] = mapped_column(Uuid, primary_key=True, default=uuid4)
	child_id: Mapped[UUID] = mapped_column(Uuid)
	amount: Mapped[int] = mapped_column(Integer)
	transaction_type: Mapped[str] = mapped_column(String)
	submission_id: Mapped[UUID | None] = mapped_column(Uuid)
	idempotency_key: Mapped[str | None] = mapped_column(String, unique=True)
	description: Mapped[str | None] = mapped_column(String)
	created_at: Mapped[datetime] = mapped_column(DateTime, default=_now)


class XPTransaction(Base):
	__tablename__ = "xp_transactions"
	id: Mapped[UUID] = mapped_column(Uuid, primary_key=True, default=uuid4)
	child_id: Mapped[UUID] = mapped_column(Uuid)
	amount: Mapped[int] = mapped_column(Integer)
	submission_id: Mapped[UUID | None] = mapped_column(Uuid)
	reason: Mapped[str] = mapped_column(String)
	idempotency_key: Mapped[str | None] = mapped_column(String, unique=True)
	created_at: Mapped[datetime] = mapped_column(DateTime, default=_now)


class ChildProgress(Base):
	__tablename__ = "child_progress"
	child_id: Mapped[UUID] = mapped_column(Uuid, primary_key=True)
	total_xp: Mapped[int] = mapped_column(Integer, default=0)
	current_level_id: Mapped[UUID | None] = mapped_column(Uuid)
	garden_progress: Mapped[dict] = mapped_column(JSON, default=dict)
	updated_at: Mapped[datetime | None] = mapped_column(DateTime)


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


class Level(Base):
	__tablename__ = "levels"
	id: Mapped[UUID] = mapped_column(Uuid, primary_key=True, default=uuid4)
	minimum_xp: Mapped[int] = mapped_column(Integer)
	name: Mapped[str] = mapped_column(String, default="Seedling")


class ChildActivityDay(Base):
	__tablename__ = "child_activity_days"
	child_id: Mapped[UUID] = mapped_column(Uuid, primary_key=True)
	activity_date: Mapped[date] = mapped_column(Date, primary_key=True)
	completed_tasks: Mapped[int] = mapped_column(Integer, default=0)
	stars_earned: Mapped[int] = mapped_column(Integer, default=0)
	xp_earned: Mapped[int] = mapped_column(Integer, default=0)
	created_at: Mapped[datetime | None] = mapped_column(DateTime)


class Badge(Base):
	__tablename__ = "badges"
	id: Mapped[UUID] = mapped_column(Uuid, primary_key=True, default=uuid4)
	name: Mapped[str] = mapped_column(String)
	criteria_type: Mapped[str] = mapped_column(String)
	criteria_value: Mapped[int] = mapped_column(Integer)
	is_active: Mapped[bool] = mapped_column(Boolean, default=True)


class ChildBadge(Base):
	__tablename__ = "child_badges"
	id: Mapped[UUID] = mapped_column(Uuid, primary_key=True, default=uuid4)
	child_id: Mapped[UUID] = mapped_column(Uuid)
	badge_id: Mapped[UUID] = mapped_column(Uuid)
	unlocked_at: Mapped[datetime | None] = mapped_column(DateTime)

	__table_args__ = (UniqueConstraint("child_id", "badge_id"),)


OWN = {
	cls.__name__: cls
	for cls in (
		ChildProfile, TaskCategory, Task, TaskSubmission, TaskReview, StarTransaction, XPTransaction, ChildProgress,
		Level, ChildActivityDay, Badge, ChildBadge, MissionVideoWatchSession,
	)
}
MODELS = {
	**{name: getattr(shared, name) for name in (
		"User", "FamilyMember", "FamilySetting", "DailyMissionAssignment", "ChildStreak", "Notification",
		"UserSetting", "DeviceToken",
	)},
	**OWN,
	"VideoAccessEntitlement": allowance.VideoAccessEntitlement,
}
_SHARED_TABLES = [
	shared.World.metadata.tables[name]
	for name in (
		"users", "family_members", "family_settings", "daily_mission_assignments", "child_streaks", "notifications",
		"user_settings", "device_tokens",
	)
]


def _get_model(name: str):
	return MODELS[name]


@pytest.fixture
def approval_db(monkeypatch) -> Session:
	"""A session shaped like production (``autoflush=False``) with every ``get_model`` pointing at this world."""
	import app.db.base as db_base

	original = db_base.get_model
	original_has = db_base.has_model
	for module in list(sys.modules.values()):
		name = getattr(module, "__name__", "")
		if not name.startswith("app."):
			continue
		if getattr(module, "get_model", None) is original:
			monkeypatch.setattr(module, "get_model", _get_model)
		if getattr(module, "has_model", None) is original_has:
			monkeypatch.setattr(module, "has_model", lambda model_name: model_name in MODELS)
	engine = create_engine("sqlite://", connect_args={"check_same_thread": False}, poolclass=StaticPool)
	Base.metadata.create_all(engine)
	shared.World.metadata.create_all(engine, tables=_SHARED_TABLES)
	allowance.Base.metadata.create_all(engine, tables=[allowance.VideoAccessEntitlement.__table__])
	session = sessionmaker(bind=engine, autoflush=False, expire_on_commit=False)()
	try:
		yield session
	finally:
		session.close()
		engine.dispose()


def make_family(session: Session):
	"""A family with a parent, a child (``hshs``), a level and the family settings row. Returns a namespace."""
	family_id = uuid4()
	parent = shared.User(role="parent", email="parent@example.test")
	child_user = shared.User(role="child")
	session.add_all([parent, child_user])
	session.flush()
	session.add(shared.FamilyMember(family_id=family_id, user_id=parent.id))
	session.add(shared.FamilySetting(family_id=family_id, mission_settings={"timezone": "Asia/Kolkata"}))
	child = ChildProfile(user_id=child_user.id, family_id=family_id, date_of_birth=date(2017, 5, 1))
	session.add(child)
	session.add(Level(minimum_xp=0, name="Seedling"))
	session.commit()
	return SimpleNamespace(family_id=family_id, parent=parent, child=child, child_user=child_user)


def make_submission(session: Session, family, *, title: str = "Saturday Rhythm Rockstar", task_family=None, daily=True):
	"""A task for the family's child with one pending submission, optionally with its daily-mission assignment."""
	task = Task(family_id=task_family or family.family_id, created_by=family.parent.id, assigned_child_id=family.child.id, title=title)
	session.add(task)
	session.flush()
	submission = TaskSubmission(task_id=task.id, child_id=family.child.id)
	session.add(submission)
	if daily:
		session.add(
			shared.DailyMissionAssignment(
				child_id=family.child.id, family_id=family.family_id, local_date=date.today(), choice_slot=1,
				age_band="7_10", template_id=uuid4(), variation_id=uuid4(), task_id=task.id,
				status="pending_parent_approval", snapshot={"mystery_bonus": {"type": "stars", "amount": 3}},
			)
		)
	session.commit()
	return SimpleNamespace(task=task, submission=submission)
