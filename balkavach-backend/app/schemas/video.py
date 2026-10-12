from datetime import datetime
from typing import Literal
from uuid import UUID

from pydantic import BaseModel, ConfigDict, Field, HttpUrl, field_serializer, model_validator

from app.utils import utc_aware


class VideoCategoryCreate(BaseModel):
	name: str = Field(min_length=2, max_length=100)
	slug: str = Field(pattern=r"^[a-z0-9]+(?:-[a-z0-9]+)*$", max_length=120)
	description: str | None = Field(default=None, max_length=2000)
	icon_url: HttpUrl | None = None
	display_order: int = Field(default=0, ge=0)


class VideoCategoryPublic(BaseModel):
	model_config = ConfigDict(from_attributes=True)

	id: UUID
	name: str
	slug: str
	description: str | None
	icon_url: str | None
	display_order: int


class VideoCategoryUpdate(BaseModel):
	name: str | None = Field(default=None, min_length=2, max_length=100)
	slug: str | None = Field(default=None, pattern=r"^[a-z0-9]+(?:-[a-z0-9]+)*$", max_length=120)
	description: str | None = Field(default=None, max_length=2000)
	icon_url: HttpUrl | None = None
	display_order: int | None = Field(default=None, ge=0)
	is_active: bool | None = None


class VideoCreate(BaseModel):
	title: str = Field(min_length=2, max_length=200)
	description: str | None = Field(default=None, max_length=5000)
	video_source: Literal["hosted", "youtube", "external"] = "hosted"
	video_url: HttpUrl
	external_video_id: str | None = Field(default=None, max_length=200)
	storage_key: str | None = Field(default=None, max_length=2000)
	thumbnail_url: HttpUrl | None = None
	duration_seconds: int = Field(gt=0, le=86400)
	category_id: UUID | None = None
	language_code: str = Field(default="en", min_length=2, max_length=10)
	age_min: int = Field(default=4, ge=0, le=18)
	age_max: int = Field(default=18, ge=0, le=18)
	content_rating: Literal["general", "educational", "parent_review_required"] = "general"
	display_order: int = Field(default=0, ge=0)

	@model_validator(mode="after")
	def validate_age_range(self):
		if self.age_max < self.age_min:
			raise ValueError("age_max must be greater than or equal to age_min")
		return self


class VideoUpdate(BaseModel):
	title: str | None = Field(default=None, min_length=2, max_length=200)
	description: str | None = Field(default=None, max_length=5000)
	video_url: HttpUrl | None = None
	external_video_id: str | None = Field(default=None, max_length=200)
	storage_key: str | None = Field(default=None, max_length=2000)
	thumbnail_url: HttpUrl | None = None
	duration_seconds: int | None = Field(default=None, gt=0, le=86400)
	category_id: UUID | None = None
	language_code: str | None = Field(default=None, min_length=2, max_length=10)
	age_min: int | None = Field(default=None, ge=0, le=18)
	age_max: int | None = Field(default=None, ge=0, le=18)
	content_rating: Literal["general", "educational", "parent_review_required"] | None = None
	display_order: int | None = Field(default=None, ge=0)


class VideoAdminPublic(BaseModel):
	model_config = ConfigDict(from_attributes=True)

	id: UUID
	title: str
	description: str | None
	video_source: str
	video_url: str
	external_video_id: str | None
	thumbnail_url: str | None
	duration_seconds: int
	category_id: UUID | None
	language_code: str
	age_min: int
	age_max: int
	content_rating: str
	is_published: bool
	published_at: datetime | None
	display_order: int

	@field_serializer("published_at")
	def serialize_published_at(self, value: datetime | None) -> datetime | None:
		return utc_aware(value) if value else None


class VideoFeedItem(BaseModel):
	id: UUID
	title: str
	description: str | None
	thumbnail_url: str | None
	duration_seconds: int
	category_id: UUID | None
	language_code: str
	content_rating: str


class VideoCollectionCreate(BaseModel):
	name: str = Field(min_length=2, max_length=160)
	description: str | None = Field(default=None, max_length=3000)
	language_code: str = Field(default="en", min_length=2, max_length=10)
	age_min: int = Field(default=4, ge=0, le=18)
	age_max: int = Field(default=18, ge=0, le=18)

	@model_validator(mode="after")
	def validate_age_range(self):
		if self.age_max < self.age_min:
			raise ValueError("age_max must be greater than or equal to age_min")
		return self


class CollectionItemCreate(BaseModel):
	video_id: UUID
	display_order: int = Field(default=0, ge=0)


class PlaybackStartRequest(BaseModel):
	video_id: UUID
	entitlement_id: UUID
	device_session_id: str = Field(min_length=8, max_length=180)


class PlaybackHeartbeatRequest(BaseModel):
	session_id: UUID


class PlaybackSessionPublic(BaseModel):
	session_id: UUID
	playback_url: HttpUrl
	remaining_seconds: int


class PlaybackHeartbeatPublic(BaseModel):
	session_id: UUID
	accepted_seconds: int
	watched_seconds: int
	remaining_seconds: int
	status: str
