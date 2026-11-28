from datetime import datetime
from typing import Any, Literal
from uuid import UUID

from pydantic import BaseModel, ConfigDict, Field, HttpUrl, field_serializer, field_validator, model_validator

from app.utils import utc_aware

# Video time a parent may attach to one custom mission: 0 up to the largest daily cap a family can set
# (video_entitlement_service.MAX_DAILY_ALLOWANCE_SECONDS); the default is the standard mission amount
# (MISSION_REWARD_ALLOWANCE_SECONDS). Kept as literals so this module imports no service code.
REWARD_VIDEO_SECONDS_MAX = 14400
REWARD_VIDEO_SECONDS_DEFAULT = 225


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
	star_reward: int = Field(default=10, ge=0, le=10000)
	xp_reward: int = Field(default=15, ge=0, le=100000)
	required_video_seconds: int | None = Field(default=None, ge=1, le=86400)
	# Video seconds an approval of this custom mission unlocks (stored server-side; the child never sends it).
	reward_video_seconds: int = Field(default=REWARD_VIDEO_SECONDS_DEFAULT, ge=0, le=REWARD_VIDEO_SECONDS_MAX, strict=True)
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
	required_video_seconds: int | None = Field(default=None, ge=1, le=86400)
	reward_video_seconds: int | None = Field(default=None, ge=0, le=REWARD_VIDEO_SECONDS_MAX, strict=True)
	due_at: datetime | None = None
	repeat_rule: dict[str, Any] | None = Field(default=None, max_length=30)

	@field_validator("due_at")
	@classmethod
	def validate_due_at_timezone(cls, value: datetime | None) -> datetime | None:
		if value is not None and (value.tzinfo is None or value.utcoffset() is None):
			raise ValueError("due_at must include a timezone")
		return value

	@model_validator(mode="after")
	def reward_video_seconds_is_not_null(self):
		# Omit the field to keep the stored value; an explicit null would erase the parent's setting.
		if "reward_video_seconds" in self.model_fields_set and self.reward_video_seconds is None:
			raise ValueError("reward_video_seconds must be a number of seconds")
		return self


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
	required_video_seconds: int | None = None
	# Parent-configured video seconds for a custom mission (None: a daily mission or a legacy row, which earn
	# the standard amount).
	reward_video_seconds: int | None = None
	is_custom: bool | None = None
	# A repeating mission's rule as stored (JSON object; None = one-time). A legacy text value that is not a JSON
	# object is shown as None rather than failing the whole list.
	repeat_rule: dict[str, Any] | None = None
	due_at: datetime | None
	is_active: bool
	created_at: datetime

	@field_validator("repeat_rule", mode="before")
	@classmethod
	def stored_repeat_rule(cls, value: Any) -> Any:
		if isinstance(value, str):
			import json

			try:
				value = json.loads(value) if value.strip() else None
			except ValueError:
				return None
		return value if isinstance(value, dict) or value is None else None

	@field_serializer("due_at", "created_at")
	def serialize_timestamp(self, value: datetime | None) -> datetime | None:
		return utc_aware(value) if value else None


class TaskSubmissionCreate(BaseModel):
	proof_type: Literal["none", "note", "image", "video", "file"] = "none"
	proof_url: HttpUrl | None = None
	proof_upload_id: UUID | None = None
	proof_note: str | None = Field(default=None, max_length=2000)

	@model_validator(mode="after")
	def image_proof_needs_a_photo(self):
		if self.proof_type == "image" and self.proof_upload_id is None and self.proof_url is None:
			raise ValueError("An image proof needs an uploaded photo (proof_upload_id)")
		if self.proof_upload_id is not None and self.proof_type != "image":
			raise ValueError("proof_upload_id is only valid with proof_type image")
		return self


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


class TaskReviewResultPublic(TaskSubmissionPublic):
	"""A review decision plus the video time it actually granted, read from the entitlement ledger.

	``video_seconds_granted`` can be lower than ``video_seconds_reward`` when the daily cap reduced the grant,
	or 0 when a repeating mission already earned video time that family-local day."""

	video_seconds_reward: int = 0
	video_seconds_granted: int = 0


class TaskReviewCreate(BaseModel):
	decision: Literal["approved", "rejected", "resubmission_requested"]
	review_note: str | None = Field(default=None, max_length=2000)


class PendingSubmissionPublic(TaskSubmissionPublic):
	"""A submission joined with what a reviewer needs to decide without more requests."""

	family_id: UUID
	task_title: str
	category_name: str | None
	child_name: str
	star_reward: int
	xp_reward: int
	# Minutes of video time an approval unlocks (the backend's rule; the app only displays it).
	video_minutes_reward: int = 0
	# The same in seconds (exact; the standard mission amount is not a whole number of minutes).
	video_seconds_reward: int = 0
	required_video_seconds: int | None = None
	verified_video_seconds: int = 0


class MissionVideoWatchStartRequest(BaseModel):
	video_id: UUID
	client_session_id: str = Field(pattern=r"^[a-f0-9]{32}$")


class MissionVideoWatchHeartbeatRequest(BaseModel):
	sequence: int = Field(ge=0, le=2_147_483_647)
	position_seconds: int = Field(ge=0, le=86400)
	is_playing: bool = True


class MissionVideoProgressPublic(BaseModel):
	task_id: UUID
	required_video_seconds: int
	verified_video_seconds: int
	remaining_video_seconds: int
	is_complete: bool


class MissionVideoWatchPublic(MissionVideoProgressPublic):
	session_id: UUID
	accepted_seconds: int = 0
	status: str


class MySubmissionPublic(TaskSubmissionPublic):
	"""A child's own submission with the task title and the parent's feedback."""

	task_title: str
	review_note: str | None
	# What this attempt actually earned, read from the star and XP ledgers (0 unless approved). Historical
	# amounts are shown as recorded, never recalculated.
	stars_awarded: int = 0
	xp_awarded: int = 0
