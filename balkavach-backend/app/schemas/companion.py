from typing import Literal
from uuid import UUID

from pydantic import BaseModel, Field, field_validator


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
