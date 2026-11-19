from datetime import datetime
from uuid import UUID

from pydantic import BaseModel, Field


class PlayTicketCreate(BaseModel):
	video_id: UUID
	device_session_id: str = Field(min_length=8, max_length=64, pattern=r"^[A-Za-z0-9_-]+$")


class PlayTicketPublic(BaseModel):
	ticket_id: UUID
	ticket_token: str
	video_id: UUID
	youtube_video_id: str | None
	expires_at: datetime
	heartbeat_interval_seconds: int
	remaining_seconds: int


class PlayTicketHeartbeat(BaseModel):
	ticket_token: str = Field(min_length=20, max_length=128)
	sequence: int = Field(ge=0, le=1_000_000)
	is_playing: bool
	position_seconds: int = Field(ge=0, le=86_400)


class PlayTicketEnd(BaseModel):
	ticket_token: str = Field(min_length=20, max_length=128)
	sequence: int = Field(ge=0, le=1_000_000)
	position_seconds: int = Field(ge=0, le=86_400)


class PlayTicketStatus(BaseModel):
	ticket_id: UUID
	state: str
	accepted_seconds: int
	remaining_seconds: int
	is_exhausted: bool
	duplicate: bool
