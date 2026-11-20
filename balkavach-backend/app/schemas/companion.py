from datetime import datetime
from typing import Literal
from uuid import UUID

from pydantic import BaseModel, Field, field_serializer, field_validator

from app.utils import utc_aware


class CompanionChatRequest(BaseModel):
	"""One thing the child said (recognised speech or typed text).

	The text is used once to pick a reply and is never stored or logged."""

	text: str = Field(min_length=1, max_length=300)
	locale: Literal["en", "hi", "gu"] | None = None
	# Client-generated id for this turn: a repeated id returns the same reply
	# instead of answering twice (double taps, retries).
	turn_id: UUID
	# The `follow_up` of Panda's previous reply, so "yes" can be understood.
	context_intent: str | None = Field(default=None, pattern=r"^[a-z_]{1,40}$")
	# How the child entered this turn. "voice" turns (speech recognition) need
	# parental consent; older apps send nothing and are treated as typed text.
	# Client-declared: the real control is that the app never opens the mic.
	input: Literal["text", "voice"] = "text"

	@field_validator("text")
	@classmethod
	def _strip(cls, value: str) -> str:
		return value.strip()


class CompanionChatReply(BaseModel):
	reply: str
	locale: Literal["en", "hi", "gu"]
	mood: Literal["talking", "happy", "curious", "sleepy", "concerned"]
	intent: str
	follow_up: str | None = None
	safety: Literal["ok", "redirected"]
	suggestions: list[Literal["mission", "video", "joke", "fact", "draw", "stars"]]


class CompanionVoiceConsentPublic(BaseModel):
	"""What the child app needs: may the microphone be offered?"""

	granted: bool
	document_version: str


class PandaVoiceConsentPublic(BaseModel):
	"""Parent view of one child's Talk to Panda microphone consent."""

	child_id: UUID
	granted: bool
	granted_at: datetime | None
	granted_by: UUID | None
	document_version: str

	@field_serializer("granted_at")
	def serialize_granted_at(self, value: datetime | None) -> datetime | None:
		return utc_aware(value) if value else None


class PandaVoiceConsentUpdate(BaseModel):
	granted: bool
	# Required to grant: the consent-text version the parent was shown.
	document_version: str | None = Field(default=None, min_length=1, max_length=40)
