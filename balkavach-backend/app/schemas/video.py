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
	video_source: str = "hosted"
	# Only for approved YouTube videos, which play in the official embedded
	# player. Hosted videos never expose a media URL here.
	youtube_video_id: str | None = None


YouTubeReviewStatus = Literal[
	"discovered", "pending_review", "approved", "rejected", "quarantined", "revoked", "unavailable"
]
ReportReason = Literal["inappropriate", "scary", "violent", "misleading", "advertising", "other"]


class YouTubeDiscoverRequest(BaseModel):
	topic: Literal["science", "animals", "language", "art", "preschool", "math", "nature"]
	shorts: bool = False
	page_token: str | None = Field(default=None, pattern=r"^[A-Za-z0-9_-]{1,128}$")
	relevance_language: str | None = Field(default=None, pattern=r"^[a-z]{2,3}(?:-[A-Za-z]{2,4})?$")
	region_code: str | None = Field(default=None, pattern=r"^[A-Z]{2}$")
	max_results: int = Field(default=25, ge=1, le=50)


class YouTubeImportRequest(BaseModel):
	url: str = Field(min_length=11, max_length=300)


class YouTubeReviewPublic(BaseModel):
	model_config = ConfigDict(from_attributes=True)

	id: UUID
	video_id: UUID
	youtube_video_id: str
	source_url: str
	channel_id: str | None
	channel_title: str | None
	source_published_at: datetime | None
	made_for_kids: bool | None
	status: str
	screening_flags: list[str]
	rights_status: str
	discovered_at: datetime
	reviewed_by: UUID | None
	reviewed_at: datetime | None
	review_notes: str | None
	last_verified_at: datetime | None
	revoked_reason: str | None
	revoked_at: datetime | None
	title: str | None = None
	thumbnail_url: str | None = None
	duration_seconds: int | None = None
	language_code: str | None = None
	age_min: int | None = None
	age_max: int | None = None


class YouTubeDiscoverResult(BaseModel):
	created: list[YouTubeReviewPublic]
	skipped_existing: int
	skipped_unplayable: int
	next_page_token: str | None


class YouTubeApproveRequest(BaseModel):
	age_min: int = Field(ge=0, le=18)
	age_max: int = Field(ge=0, le=18)
	language_code: str = Field(min_length=2, max_length=10)
	category_id: UUID | None = None
	# The reviewer attests that the licence and YouTube terms permit embedding
	# this video in Balkavach. Nothing in the YouTube API can establish that.
	rights_status: Literal["cleared"]
	notes: str | None = Field(default=None, max_length=2000)

	@model_validator(mode="after")
	def validate_age_range(self):
		if self.age_max < self.age_min:
			raise ValueError("age_max must be greater than or equal to age_min")
		return self


class YouTubeReviewDecision(BaseModel):
	notes: str | None = Field(default=None, max_length=2000)


class YouTubeRevokeRequest(BaseModel):
	reason: str = Field(min_length=3, max_length=2000)


class YouTubeRecheckRequest(BaseModel):
	limit: int = Field(default=100, ge=1, le=500)


class YouTubeRecheckResult(BaseModel):
	checked: int
	verified: int
	quarantined: int
	unavailable: int
	returned_to_review: int


class ContentReportCreate(BaseModel):
	video_id: UUID
	reason: ReportReason
	details: str | None = Field(default=None, max_length=1000)


class ContentReportReceipt(BaseModel):
	id: UUID
	status: str


class ContentReportPublic(BaseModel):
	model_config = ConfigDict(from_attributes=True)

	id: UUID
	video_id: UUID
	reported_by: UUID | None
	reason: str
	details: str | None
	status: str
	resolved_by: UUID | None
	resolved_at: datetime | None
	created_at: datetime


class ContentReportResolve(BaseModel):
	status: Literal["resolved", "dismissed"]


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
