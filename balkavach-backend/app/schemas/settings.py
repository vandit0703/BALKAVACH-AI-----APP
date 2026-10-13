from datetime import datetime
from typing import Any
from uuid import UUID

from pydantic import BaseModel, ConfigDict, Field, field_serializer, field_validator

from app.utils import utc_aware


class UserSettingsUpdate(BaseModel):
    language_code: str | None = Field(default=None, min_length=2, max_length=10)
    push_enabled: bool | None = None
    email_notifications_enabled: bool | None = None


class UserSettingsPublic(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    user_id: UUID
    language_code: str
    push_enabled: bool
    email_notifications_enabled: bool
    updated_at: datetime | None

    @field_serializer("updated_at")
    def serialize_updated_at(self, value: datetime | None) -> datetime | None:
        return utc_aware(value) if value else None


class FamilySettingsUpdate(BaseModel):
    default_language: str | None = Field(default=None, min_length=2, max_length=10)
    mission_settings: dict[str, Any] | None = Field(default=None, max_length=100)
    reward_settings: dict[str, Any] | None = Field(default=None, max_length=100)
    video_settings: dict[str, Any] | None = Field(default=None, max_length=100)

    @field_validator("mission_settings")
    @classmethod
    def validate_timezone(cls, value: dict[str, Any] | None) -> dict[str, Any] | None:
        from app.services.timezone_service import TIMEZONE_SETTING_KEY, parse_timezone

        if value and TIMEZONE_SETTING_KEY in value:
            parse_timezone(value[TIMEZONE_SETTING_KEY])
        return value


class FamilySettingsPublic(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    family_id: UUID
    default_language: str
    mission_settings: dict[str, Any]
    reward_settings: dict[str, Any]
    video_settings: dict[str, Any]
    updated_at: datetime | None

    @field_serializer("updated_at")
    def serialize_updated_at(self, value: datetime | None) -> datetime | None:
        return utc_aware(value) if value else None


class ConsentCreate(BaseModel):
    child_id: UUID | None = None
    consent_type: str = Field(min_length=2, max_length=60)
    document_version: str = Field(min_length=1, max_length=40)
    accepted: bool


class ConsentPublic(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: UUID
    family_id: UUID
    child_id: UUID | None
    parent_user_id: UUID
    consent_type: str
    document_version: str
    accepted: bool
    accepted_at: datetime | None
    revoked_at: datetime | None
    created_at: datetime

    @field_serializer("accepted_at", "revoked_at", "created_at")
    def serialize_timestamp(self, value: datetime | None) -> datetime | None:
        return utc_aware(value) if value else None