from datetime import date, datetime
from typing import Any, Literal
from uuid import UUID

from pydantic import BaseModel, ConfigDict, Field, model_validator


AgeBand = Literal["4_6", "7_10", "11_15"]
MissionType = Literal["offline", "interactive", "creative"]
AssignmentStatus = Literal[
    "available",
    "selected",
    "in_progress",
    "pending_parent_approval",
    "approved",
    "rejected",
    "skipped",
]


class DailyMissionContent(BaseModel):
    model_config = ConfigDict(extra="ignore")

    title: str
    description: str
    instructions: str
    required_materials: list[Any] = Field(default_factory=list)
    duration_minutes: int
    safety_instructions: str
    completion_criteria: str
    mission_type: MissionType
    theme: str
    star_reward: int
    xp_reward: int
    is_surprise: bool = False
    mystery_bonus: dict[str, Any] | None = None
    locale: str = "en"


class DailyMissionAssignmentPublic(BaseModel):
    id: UUID
    local_date: date
    choice_slot: int
    age_band: AgeBand
    status: AssignmentStatus
    task_id: UUID | None = None
    selected_at: datetime | None = None
    started_at: datetime | None = None
    skipped_at: datetime | None = None
    content: DailyMissionContent


class DailyMissionChoicesPublic(BaseModel):
    local_date: date
    timezone: str
    age_band: AgeBand
    selected_assignment_id: UUID | None = None
    choices: list[DailyMissionAssignmentPublic]


class DailyMissionSubmitPublic(BaseModel):
    assignment_id: UUID
    task_id: UUID | None
    status: AssignmentStatus


class DailyMissionHistoryPublic(BaseModel):
    items: list[DailyMissionAssignmentPublic]
    limit: int
    offset: int


class WeeklyMissionSummary(BaseModel):
    week_start: date
    week_end: date
    completed_count: int
    approved_xp: int
    approved_stars: int
    skipped_count: int
    daily_status: dict[str, str]


class DailyMissionTemplateCreate(BaseModel):
    slug: str = Field(min_length=3, max_length=100, pattern=r"^[a-z0-9_]+$")
    theme: str = Field(min_length=2, max_length=40)
    mission_type: MissionType
    is_surprise: bool = False
    star_reward: int = Field(ge=0, le=10000)
    xp_reward: int = Field(ge=0, le=100000)
    mystery_bonus: dict[str, Any] | None = None


class DailyMissionTemplateUpdate(BaseModel):
    theme: str | None = Field(default=None, min_length=2, max_length=40)
    mission_type: MissionType | None = None
    is_surprise: bool | None = None
    star_reward: int | None = Field(default=None, ge=0, le=10000)
    xp_reward: int | None = Field(default=None, ge=0, le=100000)
    mystery_bonus: dict[str, Any] | None = None


class DailyMissionVariationCreate(BaseModel):
    age_band: AgeBand
    locale: str = Field(min_length=2, max_length=10)
    title: str = Field(min_length=2, max_length=180)
    description: str = Field(min_length=2, max_length=5000)
    instructions: str = Field(min_length=2, max_length=10000)
    required_materials: list[Any] = Field(default_factory=list)
    duration_minutes: int = Field(ge=1, le=180)
    safety_instructions: str = Field(min_length=2, max_length=5000)
    completion_criteria: str = Field(min_length=2, max_length=5000)
    variation_key: str = Field(default="v1", min_length=1, max_length=40)

    @model_validator(mode="after")
    def reject_personal_data_requirements(self):
        text = " ".join(
            [self.instructions, self.safety_instructions, self.completion_criteria]
        ).lower()
        forbidden = ("location", "contact details", "phone number", "microphone", "recording")
        if any(term in text for term in forbidden):
            raise ValueError("ordinary missions must not require personal data or recordings")
        return self


class DailyMissionVariationUpdate(BaseModel):
    age_band: AgeBand | None = None
    locale: str | None = Field(default=None, min_length=2, max_length=10)
    title: str | None = Field(default=None, min_length=2, max_length=180)
    description: str | None = Field(default=None, min_length=2, max_length=5000)
    instructions: str | None = Field(default=None, min_length=2, max_length=10000)
    required_materials: list[Any] | None = None
    duration_minutes: int | None = Field(default=None, ge=1, le=180)
    safety_instructions: str | None = Field(default=None, min_length=2, max_length=5000)
    completion_criteria: str | None = Field(default=None, min_length=2, max_length=5000)
    variation_key: str | None = Field(default=None, min_length=1, max_length=40)
