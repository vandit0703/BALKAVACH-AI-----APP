from datetime import datetime
from uuid import UUID

from typing import Literal

from pydantic import BaseModel, ConfigDict, Field, field_serializer

from app.utils import utc_aware


class NotificationPublic(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: UUID
    notification_type: str
    title: str
    message: str
    related_task_id: UUID | None
    related_submission_id: UUID | None
    related_redemption_id: UUID | None
    is_read: bool
    read_at: datetime | None
    created_at: datetime

    @field_serializer("read_at", "created_at")
    def serialize_timestamp(self, value: datetime | None) -> datetime | None:
        return utc_aware(value) if value else None


class DeviceRegistration(BaseModel):
    token: str = Field(min_length=20, max_length=4096)
    platform: Literal["android", "ios", "web"]
    app_version: str | None = Field(default=None, max_length=40)


class DeviceUnregistration(BaseModel):
    token: str = Field(min_length=20, max_length=4096)
