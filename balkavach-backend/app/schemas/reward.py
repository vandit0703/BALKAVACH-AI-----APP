from datetime import datetime
from typing import Literal
from uuid import UUID

from pydantic import BaseModel, ConfigDict, Field, HttpUrl, field_serializer

from app.utils import utc_aware

RewardType = Literal["screen_time", "video_time", "book", "outdoor_activity", "gift", "custom"]


class RewardCreate(BaseModel):
	family_id: UUID
	name: str = Field(min_length=2, max_length=180)
	description: str | None = Field(default=None, max_length=3000)
	reward_type: RewardType
	star_cost: int = Field(gt=0, le=100000)
	image_url: HttpUrl | None = None
	video_id: UUID | None = None
	video_collection_id: UUID | None = None
	access_duration_seconds: int | None = Field(default=None, gt=0, le=86400)
	access_validity_seconds: int | None = Field(default=None, gt=0, le=31536000)
	max_uses: int | None = Field(default=None, gt=0)


class RewardPublic(BaseModel):
	model_config = ConfigDict(from_attributes=True)

	id: UUID
	family_id: UUID
	name: str
	description: str | None
	reward_type: str
	star_cost: int
	image_url: str | None
	video_id: UUID | None
	video_collection_id: UUID | None
	access_duration_seconds: int | None
	access_validity_seconds: int | None
	max_uses: int | None
	is_active: bool


class RedemptionReview(BaseModel):
	review_note: str | None = Field(default=None, max_length=2000)


class RedemptionCreate(BaseModel):
	reward_id: UUID


class RedemptionPublic(BaseModel):
	model_config = ConfigDict(from_attributes=True)

	id: UUID
	reward_id: UUID
	child_id: UUID
	star_cost_at_request: int
	status: str
	review_note: str | None
	requested_at: datetime
	reviewed_at: datetime | None
	fulfilled_at: datetime | None

	@field_serializer("requested_at", "reviewed_at", "fulfilled_at")
	def serialize_timestamp(self, value: datetime | None) -> datetime | None:
		return utc_aware(value) if value else None


class RewardUpdate(BaseModel):
	name: str | None = Field(default=None, min_length=2, max_length=180)
	description: str | None = Field(default=None, max_length=3000)
	star_cost: int | None = Field(default=None, gt=0, le=100000)
	image_url: HttpUrl | None = None
	max_uses: int | None = Field(default=None, gt=0)
	is_active: bool | None = None


class RedemptionDetailPublic(RedemptionPublic):
	"""A redemption joined with the names a parent needs to review it."""

	family_id: UUID
	reward_name: str
	child_name: str
