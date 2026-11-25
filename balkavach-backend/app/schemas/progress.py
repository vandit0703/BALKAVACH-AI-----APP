from datetime import date, datetime
from uuid import UUID

from pydantic import BaseModel, field_serializer

from app.utils import utc_aware


class ActivityDayPublic(BaseModel):
	activity_date: date
	completed_tasks: int
	stars_earned: int
	xp_earned: int


class BadgePublic(BaseModel):
	badge_id: UUID
	name: str
	description: str | None
	icon_url: str | None
	unlocked_at: datetime

	@field_serializer("unlocked_at")
	def serialize_unlocked_at(self, value: datetime) -> datetime:
		return utc_aware(value)


class GardenItemPublic(BaseModel):
	key: str
	badge: str
	unlocked: bool


class GardenPublic(BaseModel):
	stage: int
	stage_key: str
	xp_to_next_stage: int | None
	items: list[GardenItemPublic]


class ProgressPublic(BaseModel):
	child_id: UUID
	star_balance: int
	total_xp: int
	level_number: int | None
	level_name: str | None
	current_streak: int
	longest_streak: int
	activity_days: list[ActivityDayPublic]
	badges: list[BadgePublic]
	garden: GardenPublic | None = None
	streak_state: str = "active"
	grace_deadline: datetime | None = None
	seconds_until_grace_expires: int | None = None

	@field_serializer("grace_deadline")
	def serialize_grace_deadline(self, value: datetime | None) -> datetime | None:
		return utc_aware(value) if value is not None else None


class StreakPublic(BaseModel):
	child_id: UUID
	current_streak: int
	longest_streak: int
	streak_state: str
	grace_deadline: datetime | None = None
	seconds_until_grace_expires: int | None = None
	last_activity_date: date | None = None
	last_activity_at: datetime | None = None

	@field_serializer("grace_deadline")
	def serialize_grace_deadline(self, value: datetime | None) -> datetime | None:
		return utc_aware(value) if value is not None else None

	@field_serializer("last_activity_at")
	def serialize_last_activity_at(self, value: datetime | None) -> datetime | None:
		return utc_aware(value) if value is not None else None


class ReportTotals(BaseModel):
	completed_tasks: int
	stars_earned: int
	xp_earned: int


class ReportDay(ReportTotals):
	date: date


class ReportCategory(ReportTotals):
	category_id: UUID | None
	name: str


class ReportRecentItem(BaseModel):
	title: str
	reviewed_at: datetime
	stars_earned: int
	xp_earned: int

	@field_serializer("reviewed_at")
	def serialize_reviewed_at(self, value: datetime) -> datetime:
		return utc_aware(value)


class WeeklyReportPublic(BaseModel):
	child_id: UUID
	timezone: str
	period_start: date
	period_end: date
	totals: ReportTotals
	days: list[ReportDay]
	categories: list[ReportCategory]
	pending_submissions: int
	rejected_submissions: int
	current_streak: int
	longest_streak: int
	recent_approved: list[ReportRecentItem]


class AchievementBadgePublic(BaseModel):
	badge_id: UUID
	name: str
	description: str | None
	icon_url: str | None
	unlocked: bool
	unlocked_at: datetime | None = None
	criteria_type: str
	# Only for criteria the server can measure; the child sees real progress, never an invented number.
	threshold: int | None = None
	current: int | None = None

	@field_serializer("unlocked_at")
	def serialize_unlocked_at(self, value: datetime | None) -> datetime | None:
		return utc_aware(value) if value is not None else None


class LevelProgressPublic(BaseModel):
	level_number: int | None
	name: str | None
	minimum_xp: int
	next_level_number: int | None
	next_level_name: str | None
	next_minimum_xp: int | None
	total_xp: int


class AchievementsPublic(BaseModel):
	level: LevelProgressPublic
	badges: list[AchievementBadgePublic]
