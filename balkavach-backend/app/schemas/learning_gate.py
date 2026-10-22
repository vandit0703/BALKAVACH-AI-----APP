from datetime import date, datetime

from pydantic import BaseModel, field_serializer

from app.utils import utc_aware


class LearningGatePublic(BaseModel):
	"""Today's learning workflow for the signed-in child.

	`video_gate_available` is false when the gate cannot be satisfied at all (no
	playback provider configured, or a parent switched video off). Clients must
	then treat `missions_unlocked` as true and must not present the video gate
	as if progress towards it were being recorded.
	"""

	local_date: date
	timezone: str
	phase: str
	video_gate_available: bool
	video_enabled: bool
	playback_configured: bool
	first_session_target_seconds: int
	second_session_target_seconds: int
	daily_allowance_seconds: int
	watched_seconds_today: int
	remaining_allowance_seconds: int
	first_session_complete: bool
	second_session_complete: bool
	missions_unlocked: bool
	second_session_unlocked: bool
	missions_assigned: int
	missions_approved: int
	missions_pending_approval: int
	requires_parent_approval: bool
	blockers: list[str]
	generated_at: datetime

	@field_serializer("generated_at")
	def serialize_generated_at(self, value: datetime) -> datetime:
		return utc_aware(value)
