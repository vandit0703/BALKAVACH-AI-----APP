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
