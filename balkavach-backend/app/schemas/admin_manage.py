from datetime import datetime
from typing import Any, Literal
from uuid import UUID

from pydantic import BaseModel, ConfigDict, Field, HttpUrl, field_serializer, model_validator

from app.utils import utc_aware


class _Timestamped(BaseModel):
	@staticmethod
	def _utc(value: datetime | None) -> datetime | None:
		return utc_aware(value) if value else None


class AdminUserPublic(_Timestamped):
	model_config = ConfigDict(from_attributes=True)

	id: UUID
	full_name: str
	email: str | None
	role: str
	preferred_language: str
	is_active: bool
	created_at: datetime
	last_login_at: datetime | None

	@field_serializer("created_at", "last_login_at")
	def _ser(self, value):
		return self._utc(value)


class ActiveUpdate(BaseModel):
	is_active: bool


class AdminFamilyRow(_Timestamped):
	id: UUID
	family_name: str
	created_at: datetime
	member_count: int
	parent_count: int
	child_count: int
	active_task_count: int

	@field_serializer("created_at")
	def _ser(self, value):
		return self._utc(value)


class AdminFamilyParent(BaseModel):
	user_id: UUID
	full_name: str
	email: str | None
	is_active: bool


class AdminFamilyChild(_Timestamped):
	id: UUID
	user_id: UUID
	display_name: str
	is_active: bool
	created_at: datetime

	@field_serializer("created_at")
	def _ser(self, value):
		return self._utc(value)


class AdminFamilyDetail(AdminFamilyRow):
	timezone: str
	parents: list[AdminFamilyParent]
	children: list[AdminFamilyChild]


class AdminChildStatus(BaseModel):
	id: UUID
	family_id: UUID
	display_name: str
	is_active: bool


class AdminTaskPublic(_Timestamped):
	id: UUID
	family_id: UUID
	family_name: str
	title: str
	category_name: str | None
	assigned_child_name: str | None
	star_reward: int
	xp_reward: int
	due_at: datetime | None
	is_active: bool
	created_at: datetime

	@field_serializer("due_at", "created_at")
	def _ser(self, value):
		return self._utc(value)


class AdminRewardPublic(_Timestamped):
	id: UUID
	family_id: UUID
	family_name: str
	name: str
	reward_type: str
	star_cost: int
	is_active: bool
	created_at: datetime

	@field_serializer("created_at")
	def _ser(self, value):
		return self._utc(value)


class AdminRedemptionPublic(_Timestamped):
	id: UUID
	family_id: UUID
	family_name: str
	reward_name: str
	child_name: str
	status: str
	star_cost_at_request: int
	requested_at: datetime
	reviewed_at: datetime | None

	@field_serializer("requested_at", "reviewed_at")
	def _ser(self, value):
		return self._utc(value)


class AdminTaskCategoryPublic(BaseModel):
	model_config = ConfigDict(from_attributes=True)

	id: UUID
	name: str
	description: str | None
	icon_name: str | None
	is_default: bool
	is_active: bool


class TaskCategoryUpdate(BaseModel):
	name: str | None = Field(default=None, min_length=2, max_length=100)
	description: str | None = Field(default=None, max_length=2000)
	icon_name: str | None = Field(default=None, max_length=100)
	is_active: bool | None = None


class PresetTaskCreate(BaseModel):
	title: str = Field(min_length=2, max_length=180)
	description: str | None = Field(default=None, max_length=5000)
	category_id: UUID | None = None
	language_code: str = Field(default="en", min_length=2, max_length=10)
	suggested_star_reward: int = Field(default=1, ge=0, le=10000)
	suggested_xp_reward: int = Field(default=10, ge=0, le=100000)
	age_min: int = Field(default=3, ge=0, le=18)
	age_max: int = Field(default=17, ge=0, le=18)

	@model_validator(mode="after")
	def _ages(self):
		if self.age_max < self.age_min:
			raise ValueError("age_max must not be below age_min")
		return self


class PresetTaskUpdate(BaseModel):
	title: str | None = Field(default=None, min_length=2, max_length=180)
	description: str | None = Field(default=None, max_length=5000)
	category_id: UUID | None = None
	language_code: str | None = Field(default=None, min_length=2, max_length=10)
	suggested_star_reward: int | None = Field(default=None, ge=0, le=10000)
	suggested_xp_reward: int | None = Field(default=None, ge=0, le=100000)
	age_min: int | None = Field(default=None, ge=0, le=18)
	age_max: int | None = Field(default=None, ge=0, le=18)
	is_active: bool | None = None


class PresetTaskPublic(BaseModel):
	model_config = ConfigDict(from_attributes=True)

	id: UUID
	category_id: UUID | None
	category_name: str | None = None
	title: str
	description: str | None
	language_code: str
	suggested_star_reward: int
	suggested_xp_reward: int
	age_min: int
	age_max: int
	is_active: bool


class BadgeUpdate(BaseModel):
	name: str | None = Field(default=None, min_length=2, max_length=100)
	description: str | None = Field(default=None, max_length=2000)
	icon_url: HttpUrl | None = None
	criteria_type: Literal["approved_tasks", "total_stars", "total_xp", "current_streak"] | None = None
	threshold: int | None = Field(default=None, gt=0, le=1000000)
	is_active: bool | None = None


class EducationalContentUpdate(BaseModel):
	title: str | None = Field(default=None, min_length=2, max_length=200)
	description: str | None = Field(default=None, max_length=5000)
	content_type: Literal["video", "article", "link", "document", "activity"] | None = None
	category_id: UUID | None = None
	language_code: str | None = Field(default=None, min_length=2, max_length=10)
	content_url: HttpUrl | None = None
	thumbnail_url: HttpUrl | None = None
	requires_entitlement: bool | None = None
	is_active: bool | None = None


class RoleAssignment(BaseModel):
	role_id: UUID


class SettingValue(BaseModel):
	value: Any


class SettingPublic(_Timestamped):
	key: str
	value: Any
	overridden: bool


class DailyCount(BaseModel):
	date: str
	new_users: int
	submissions: int
	approvals: int


class AnalyticsTotals(BaseModel):
	new_users: int
	submissions: int
	approvals: int
	rejections: int
	redemptions: int


class AnalyticsOverview(BaseModel):
	period_days: int
	totals: AnalyticsTotals
	daily: list[DailyCount]
	redemptions_by_status: dict[str, int]
	top_categories: list[dict[str, Any]]


class AppConfigPublic(BaseModel):
	consent_versions: dict[str, str]
	consent_source: Literal["default", "admin"]
	maintenance: dict[str, Any]


class AdminMePublic(BaseModel):
	user: AdminUserPublic
	roles: list[str]
	permissions: list[str]
