"""A tiny real database (in-memory SQLite) for service-level tests that do not need the PostgreSQL baseline.

The production schema is reflected from PostgreSQL (``app/db/base.py``) and is not in the repository, so
these models declare **only the columns the code under test touches**. They keep the PostgreSQL
guarantees that matter to the logic (e.g. the partial unique index on the current choice slot).

This is *not* a substitute for the PostgreSQL integration suite (``tests/test_api_*``): SQLite has no
row locks (``FOR UPDATE`` is ignored) and no ``ON CONFLICT`` through the PostgreSQL dialect, so code
that uses those (``review_submission``) cannot run here.
"""

from __future__ import annotations

from datetime import date, datetime, timezone
from uuid import UUID, uuid4

import pytest
from sqlalchemy import JSON, Boolean, Date, DateTime, ForeignKey, Index, Integer, String, UniqueConstraint, Uuid, create_engine, text
from sqlalchemy.orm import DeclarativeBase, Mapped, Session, mapped_column, sessionmaker


class World(DeclarativeBase):
	pass


class User(World):
	__tablename__ = "users"
	id: Mapped[UUID] = mapped_column(Uuid, primary_key=True, default=uuid4)
	preferred_language: Mapped[str] = mapped_column(String, default="en")
	email: Mapped[str | None] = mapped_column(String)
	role: Mapped[str] = mapped_column(String, default="parent")
	is_active: Mapped[bool] = mapped_column(Boolean, default=True)
	password_hash: Mapped[str | None] = mapped_column(String)


class AuthSession(World):
	__tablename__ = "auth_sessions"
	id: Mapped[UUID] = mapped_column(Uuid, primary_key=True, default=uuid4)
	user_id: Mapped[UUID] = mapped_column(Uuid)
	issued_by: Mapped[UUID | None] = mapped_column(Uuid)
	kind: Mapped[str] = mapped_column(String, default="parent")
	refresh_token_hash: Mapped[str] = mapped_column(String, default="h")
	previous_token_hash: Mapped[str | None] = mapped_column(String)
	device_label: Mapped[str | None] = mapped_column(String)
	expires_at: Mapped[datetime] = mapped_column(DateTime)
	revoked_at: Mapped[datetime | None] = mapped_column(DateTime)
	last_used_at: Mapped[datetime | None] = mapped_column(DateTime)


class PasswordResetToken(World):
	__tablename__ = "password_reset_tokens"
	id: Mapped[UUID] = mapped_column(Uuid, primary_key=True, default=uuid4)
	user_id: Mapped[UUID] = mapped_column(Uuid)
	token_hash: Mapped[str] = mapped_column(String)
	expires_at: Mapped[datetime] = mapped_column(DateTime)
	used_at: Mapped[datetime | None] = mapped_column(DateTime)


class Family(World):
	__tablename__ = "families"
	id: Mapped[UUID] = mapped_column(Uuid, primary_key=True, default=uuid4)


class FamilySetting(World):
	__tablename__ = "family_settings"
	family_id: Mapped[UUID] = mapped_column(Uuid, primary_key=True)
	default_language: Mapped[str] = mapped_column(String, default="en")
	mission_settings: Mapped[dict] = mapped_column(JSON, default=dict)
	reward_settings: Mapped[dict] = mapped_column(JSON, default=dict)
	video_settings: Mapped[dict] = mapped_column(JSON, default=dict)
	updated_at: Mapped[datetime | None] = mapped_column(DateTime)


class ChildProfile(World):
	__tablename__ = "child_profiles"
	id: Mapped[UUID] = mapped_column(Uuid, primary_key=True, default=uuid4)
	user_id: Mapped[UUID] = mapped_column(Uuid, ForeignKey("users.id"))
	family_id: Mapped[UUID] = mapped_column(Uuid)
	display_name: Mapped[str] = mapped_column(String, default="Mia")
	date_of_birth: Mapped[date | None] = mapped_column(Date)


class Task(World):
	__tablename__ = "tasks"
	id: Mapped[UUID] = mapped_column(Uuid, primary_key=True, default=uuid4)
	family_id: Mapped[UUID] = mapped_column(Uuid)
	created_by: Mapped[UUID] = mapped_column(Uuid)
	assigned_child_id: Mapped[UUID | None] = mapped_column(Uuid)
	title: Mapped[str] = mapped_column(String)
	description: Mapped[str] = mapped_column(String)
	star_reward: Mapped[int] = mapped_column(Integer, default=0)
	xp_reward: Mapped[int] = mapped_column(Integer, default=0)
	is_custom: Mapped[bool] = mapped_column(Boolean, default=False)
	is_active: Mapped[bool] = mapped_column(Boolean, default=True)


class TaskSubmission(World):
	__tablename__ = "task_submissions"
	id: Mapped[UUID] = mapped_column(Uuid, primary_key=True, default=uuid4)
	task_id: Mapped[UUID] = mapped_column(Uuid)
	child_id: Mapped[UUID] = mapped_column(Uuid)
	status: Mapped[str] = mapped_column(String, default="pending")


class DailyMissionTemplate(World):
	__tablename__ = "daily_mission_templates"
	id: Mapped[UUID] = mapped_column(Uuid, primary_key=True, default=uuid4)
	slug: Mapped[str] = mapped_column(String, unique=True)
	theme: Mapped[str] = mapped_column(String)
	mission_type: Mapped[str] = mapped_column(String, default="activity")
	is_surprise: Mapped[bool] = mapped_column(Boolean, default=False)
	is_published: Mapped[bool] = mapped_column(Boolean, default=True)
	star_reward: Mapped[int] = mapped_column(Integer, default=5)
	xp_reward: Mapped[int] = mapped_column(Integer, default=10)
	mystery_bonus: Mapped[dict | None] = mapped_column(JSON)


class DailyMissionVariation(World):
	__tablename__ = "daily_mission_variations"
	id: Mapped[UUID] = mapped_column(Uuid, primary_key=True, default=uuid4)
	template_id: Mapped[UUID] = mapped_column(Uuid, ForeignKey("daily_mission_templates.id"))
	age_band: Mapped[str] = mapped_column(String)
	locale: Mapped[str] = mapped_column(String)
	title: Mapped[str] = mapped_column(String, default="t")
	description: Mapped[str] = mapped_column(String, default="d")
	instructions: Mapped[str] = mapped_column(String, default="i")
	required_materials: Mapped[list | None] = mapped_column(JSON)
	duration_minutes: Mapped[int] = mapped_column(Integer, default=5)
	safety_instructions: Mapped[str] = mapped_column(String, default="s")
	completion_criteria: Mapped[str] = mapped_column(String, default="c")
	variation_key: Mapped[str] = mapped_column(String, default="v1")
	# Migration 0019 (nullable, additive)
	learning_objective: Mapped[str | None] = mapped_column(String)
	steps: Mapped[list | None] = mapped_column(JSON)
	observation_guidance: Mapped[str | None] = mapped_column(String)
	submission_requirements: Mapped[str | None] = mapped_column(String)

	__table_args__ = (UniqueConstraint("template_id", "age_band", "locale", "variation_key", name="uq_daily_variation_version"),)


class DailyMissionAssignment(World):
	__tablename__ = "daily_mission_assignments"
	id: Mapped[UUID] = mapped_column(Uuid, primary_key=True, default=uuid4)
	child_id: Mapped[UUID] = mapped_column(Uuid)
	family_id: Mapped[UUID] = mapped_column(Uuid)
	local_date: Mapped[date] = mapped_column(Date)
	choice_slot: Mapped[int] = mapped_column(Integer)
	age_band: Mapped[str] = mapped_column(String)
	template_id: Mapped[UUID] = mapped_column(Uuid)
	variation_id: Mapped[UUID] = mapped_column(Uuid)
	task_id: Mapped[UUID | None] = mapped_column(Uuid)
	status: Mapped[str] = mapped_column(String, default="available")
	is_current: Mapped[bool] = mapped_column(Boolean, default=True)
	snapshot: Mapped[dict] = mapped_column(JSON)
	selected_at: Mapped[datetime | None] = mapped_column(DateTime)
	started_at: Mapped[datetime | None] = mapped_column(DateTime)
	skipped_at: Mapped[datetime | None] = mapped_column(DateTime)
	created_at: Mapped[datetime] = mapped_column(DateTime, default=lambda: datetime.now(timezone.utc).replace(tzinfo=None))

	__table_args__ = (
		# the same partial unique index migration 0015 creates on PostgreSQL
		Index("uq_daily_assignment_current_slot", "child_id", "local_date", "choice_slot", unique=True, sqlite_where=text("is_current")),
	)


class ChildStreak(World):
	__tablename__ = "child_streaks"
	child_id: Mapped[UUID] = mapped_column(Uuid, primary_key=True)
	current_streak: Mapped[int] = mapped_column(Integer, default=0)
	longest_streak: Mapped[int] = mapped_column(Integer, default=0)
	last_activity_date: Mapped[date | None] = mapped_column(Date)
	last_activity_at: Mapped[datetime | None] = mapped_column(DateTime)
	streak_state: Mapped[str | None] = mapped_column(String)
	grace_deadline: Mapped[datetime | None] = mapped_column(DateTime)
	streak_notified_state: Mapped[str | None] = mapped_column(String)
	updated_at: Mapped[datetime | None] = mapped_column(DateTime)


class FamilyMember(World):
	__tablename__ = "family_members"
	id: Mapped[UUID] = mapped_column(Uuid, primary_key=True, default=uuid4)
	family_id: Mapped[UUID] = mapped_column(Uuid)
	user_id: Mapped[UUID] = mapped_column(Uuid)
	is_active: Mapped[bool] = mapped_column(Boolean, default=True)


class UserSetting(World):
	__tablename__ = "user_settings"
	user_id: Mapped[UUID] = mapped_column(Uuid, primary_key=True)
	language_code: Mapped[str] = mapped_column(String, default="en")
	push_enabled: Mapped[bool] = mapped_column(Boolean, default=True)
	email_notifications_enabled: Mapped[bool] = mapped_column(Boolean, default=True)


class DeviceToken(World):
	__tablename__ = "device_tokens"
	id: Mapped[UUID] = mapped_column(Uuid, primary_key=True, default=uuid4)
	user_id: Mapped[UUID] = mapped_column(Uuid)
	token: Mapped[str] = mapped_column(String, unique=True)
	platform: Mapped[str] = mapped_column(String, default="android")
	app_version: Mapped[str | None] = mapped_column(String)
	is_active: Mapped[bool] = mapped_column(Boolean, default=True)
	created_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
	last_seen_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))


class Notification(World):
	__tablename__ = "notifications"
	id: Mapped[UUID] = mapped_column(Uuid, primary_key=True, default=uuid4)
	recipient_user_id: Mapped[UUID] = mapped_column(Uuid)
	notification_type: Mapped[str] = mapped_column(String)
	title: Mapped[str] = mapped_column(String, default="t")
	message: Mapped[str] = mapped_column(String, default="m")
	related_task_id: Mapped[UUID | None] = mapped_column(Uuid)
	related_submission_id: Mapped[UUID | None] = mapped_column(Uuid)
	related_redemption_id: Mapped[UUID | None] = mapped_column(Uuid)
	is_read: Mapped[bool] = mapped_column(Boolean, default=False)
	read_at: Mapped[datetime | None] = mapped_column(DateTime)
	created_at: Mapped[datetime] = mapped_column(DateTime, default=lambda: datetime.now(timezone.utc).replace(tzinfo=None))


MODELS = {
	"Family": Family,
	"FamilyMember": FamilyMember,
	"UserSetting": UserSetting,
	"DeviceToken": DeviceToken,
	"Notification": Notification,
	"User": User,
	"AuthSession": AuthSession,
	"PasswordResetToken": PasswordResetToken,
	"FamilySetting": FamilySetting,
	"ChildProfile": ChildProfile,
	"Task": Task,
	"TaskSubmission": TaskSubmission,
	"DailyMissionTemplate": DailyMissionTemplate,
	"DailyMissionVariation": DailyMissionVariation,
	"DailyMissionAssignment": DailyMissionAssignment,
	"ChildStreak": ChildStreak,
}


def _get_model(name: str):
	return MODELS[name]


@pytest.fixture
def world_session(monkeypatch) -> Session:
	"""Session configured like production (``autoflush=False``) over an in-memory SQLite database."""
	import app.services.child_age as child_age
	import app.services.daily_mission_service as missions
	import app.services.streak_service as streaks
	import app.api.v1.daily_missions as missions_api
	import app.services.mission_catalogue_service as catalogue
	import app.services.mission_audit_service as audit
	import app.services.mission_rotation_service as rotation
	import app.services.password_reset_service as resets
	import app.services.session_service as sessions
	import app.services.timezone_service as zones

	for module in (missions, streaks, zones, sessions, resets, catalogue, missions_api, rotation, child_age, audit):
		monkeypatch.setattr(module, "get_model", _get_model)
	engine = create_engine("sqlite://")
	World.metadata.create_all(engine)
	session = sessionmaker(bind=engine, autoflush=False, expire_on_commit=False)()
	try:
		yield session
	finally:
		session.close()
		engine.dispose()


def make_family(
	session: Session, *, timezone_name: str | None = None, birth: date = date(2017, 5, 1), language: str = "en"
):
	"""A family with one child; the child is returned (``family_id`` on it)."""
	family_id = uuid4()
	user = User(preferred_language=language)
	session.add(user)
	session.flush()
	child = ChildProfile(user_id=user.id, family_id=family_id, date_of_birth=birth)
	session.add(child)
	if timezone_name:
		session.add(FamilySetting(family_id=family_id, mission_settings={"timezone": timezone_name}))
	session.flush()
	return child


def publish_templates(session: Session, count: int, *, age_band: str = "7_10") -> list[DailyMissionTemplate]:
	"""``count`` published templates, each with an English variation for ``age_band``."""
	rows = []
	for index in range(count):
		template = DailyMissionTemplate(slug=f"mission-{index}", theme="monday_sound_detective", is_surprise=index == 0)
		session.add(template)
		session.flush()
		session.add(DailyMissionVariation(template_id=template.id, age_band=age_band, locale="en", title=f"Mission {index}"))
		rows.append(template)
	session.flush()
	return rows


def make_pool(
	session: Session,
	per_theme: int,
	*,
	age_bands: tuple[str, ...] = ("4_6", "7_10", "11_15"),
	locales: tuple[str, ...] = ("en",),
) -> list[DailyMissionTemplate]:
	"""``per_theme`` published templates for each of the seven weekday themes (no surprise template)."""
	from app.services.daily_mission_service import THEMES_BY_WEEKDAY

	rows = []
	for theme in THEMES_BY_WEEKDAY.values():
		for index in range(per_theme):
			template = DailyMissionTemplate(slug=f"pool_{theme}_{index}", theme=theme, is_surprise=False, is_published=True)
			session.add(template)
			session.flush()
			for age_band in age_bands:
				for locale in locales:
					session.add(
						DailyMissionVariation(
							template_id=template.id, age_band=age_band, locale=locale, title=f"{template.slug}-{age_band}-{locale}"
						)
					)
			rows.append(template)
	session.flush()
	return rows
