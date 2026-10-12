from datetime import datetime
from uuid import UUID

from pydantic import BaseModel, ConfigDict, field_serializer

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