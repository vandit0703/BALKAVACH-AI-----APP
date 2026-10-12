from datetime import datetime
from typing import Any, Literal
from uuid import UUID

from pydantic import BaseModel, ConfigDict, Field, HttpUrl, field_serializer, field_validator

from app.utils import utc_aware


class TaskCategoryPublic(BaseModel):
	model_config = ConfigDict(from_attributes=True)

	id: UUID
	name: str
	description: str | None
	icon_name: str | None
	is_default: bool


class TaskCategoryCreate(BaseModel):
	name: str = Field(min_length=2, max_length=100)
	description: str | None = Field(default=None, max_length=2000)
	icon_name: str | None = Field(default=None, max_length=100)


class TaskCreate(BaseModel):
	family_id: UUID
	category_id: UUID | None = None
	assigned_child_id: UUID | None = None
	title: str = Field(min_length=2, max_length=180)
	description: str | None = Field(default=None, max_length=5000)
	star_reward: int = Field(default=0, ge=0, le=10000)
	xp_reward: int = Field(default=0, ge=0, le=100000)
	due_at: datetime | None = None
	repeat_rule: dict[str, Any] | None = Field(default=None, max_length=30)

	@field_validator("due_at")
	@classmethod
	def validate_due_at_timezone(cls, value: datetime | None) -> datetime | None:
		if value is not None and (value.tzinfo is None or value.utcoffset() is None):
			raise ValueError("due_at must include a timezone")
		return value


class TaskUpdate(BaseModel):
	category_id: UUID | None = None
	assigned_child_id: UUID | None = None
	title: str | None = Field(default=None, min_length=2, max_length=180)
	description: str | None = Field(default=None, max_length=5000)
	star_reward: int | None = Field(default=None, ge=0, le=10000)
	xp_reward: int | None = Field(default=None, ge=0, le=100000)
	due_at: datetime | None = None
	repeat_rule: dict[str, Any] | None = Field(default=None, max_length=30)

	@field_validator("due_at")
	@classmethod
	def validate_due_at_timezone(cls, value: datetime | None) -> datetime | None:
		if value is not None and (value.tzinfo is None or value.utcoffset() is None):
			raise ValueError("due_at must include a timezone")
		return value


class TaskPublic(BaseModel):
	model_config = ConfigDict(from_attributes=True)

	id: UUID
	family_id: UUID
	category_id: UUID | None
	created_by: UUID
	assigned_child_id: UUID | None
	title: str
	description: str | None
	star_reward: int
	xp_reward: int
	due_at: datetime | None
	is_active: bool
	created_at: datetime

	@field_serializer("due_at", "created_at")
	def serialize_timestamp(self, value: datetime | None) -> datetime | None:
		return utc_aware(value) if value else None


class TaskSubmissionCreate(BaseModel):
	proof_type: Literal["none", "note", "image", "video", "file"] = "none"
	proof_url: HttpUrl | None = None
	proof_note: str | None = Field(default=None, max_length=2000)


class TaskSubmissionPublic(BaseModel):
	model_config = ConfigDict(from_attributes=True)

	id: UUID
	task_id: UUID
	child_id: UUID
	submission_number: int
	proof_type: str
	proof_url: str | None
	proof_note: str | None
	status: str
	submitted_at: datetime
	reviewed_at: datetime | None

	@field_serializer("submitted_at", "reviewed_at")
	def serialize_timestamp(self, value: datetime | None) -> datetime | None:
		return utc_aware(value) if value else None


class TaskReviewCreate(BaseModel):
	decision: Literal["approved", "rejected", "resubmission_requested"]
	review_note: str | None = Field(default=None, max_length=2000)
