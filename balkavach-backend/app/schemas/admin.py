from datetime import datetime
from typing import Any, Literal
from uuid import UUID

from pydantic import BaseModel, ConfigDict, Field, HttpUrl, field_serializer, model_validator

from app.utils import utc_aware


class AdminSummary(BaseModel):
    users: int
    families: int
    children: int
    active_tasks: int
    published_videos: int
    pending_redemptions: int


class UserStatusUpdate(BaseModel):
    is_active: bool


class AdminRolePublic(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: UUID
    name: str
    description: str | None
    permissions: Any


class BadgeCreate(BaseModel):
    name: str = Field(min_length=2, max_length=100)
    description: str | None = Field(default=None, max_length=2000)
    icon_url: HttpUrl | None = None
    criteria_type: Literal["approved_tasks", "total_stars", "total_xp", "current_streak"]
    threshold: int = Field(gt=0, le=1000000)


class AdminBadgePublic(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: UUID
    name: str
    description: str | None
    icon_url: str | None
    criteria_type: str
    criteria_value: dict[str, Any]
    is_active: bool


class AuditLogPublic(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: UUID
    actor_user_id: UUID | None
    action: str
    entity_type: str
    entity_id: UUID | None
    details: dict[str, Any]
    created_at: datetime

    @field_serializer("created_at")
    def serialize_created_at(self, value: datetime) -> datetime:
        return utc_aware(value)


class EducationalContentCreate(BaseModel):
    title: str = Field(min_length=2, max_length=200)
    description: str | None = Field(default=None, max_length=5000)
    content_type: Literal["video", "article", "link", "document", "activity"]
    category_id: UUID | None = None
    language_code: str = Field(default="en", min_length=2, max_length=10)
    content_url: HttpUrl | None = None
    thumbnail_url: HttpUrl | None = None
    video_id: UUID | None = None
    collection_id: UUID | None = None
    requires_entitlement: bool = False

    @model_validator(mode="after")
    def validate_target(self):
        if self.video_id and self.collection_id:
            raise ValueError("Choose a video or collection, not both")
        if self.content_type == "video" and not (self.video_id or self.collection_id or self.content_url):
            raise ValueError("Video content requires a video, collection, or URL")
        if self.requires_entitlement and not (self.video_id or self.collection_id):
            raise ValueError("Entitlement-required content must reference a video or collection")
        return self


class EducationalContentPublic(BaseModel):
    id: UUID
    title: str
    description: str | None
    content_type: str
    category_id: UUID | None
    language_code: str
    content_url: str | None
    thumbnail_url: str | None
    video_id: UUID | None
    collection_id: UUID | None
    requires_entitlement: bool
    is_active: bool


class EducationalContentAdminPublic(EducationalContentPublic):
    model_config = ConfigDict(from_attributes=True)

    content_url: str | None