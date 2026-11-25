"""Quiz contracts.

Child-facing models never carry ``is_correct`` or an explanation: those appear only in
``AttemptResult.review`` after the attempt is submitted (and in admin models).
"""

from datetime import datetime
from typing import Literal
from uuid import UUID

from pydantic import BaseModel, ConfigDict, Field, field_serializer, field_validator, model_validator

from app.utils import utc_aware

QuestionType = Literal["single", "multiple", "true_false"]
Difficulty = Literal["easy", "medium", "hard"]
SUPPORTED_LANGUAGES = {"en", "hi", "gu"}


# -- admin input ---------------------------------------------------------------------------------


class QuizOptionIn(BaseModel):
	text: str = Field(min_length=1, max_length=300)
	is_correct: bool = False

	@field_validator("text")
	@classmethod
	def _strip(cls, value: str) -> str:
		value = value.strip()
		if not value:
			raise ValueError("Option text cannot be blank")
		return value


class QuizQuestionIn(BaseModel):
	prompt: str = Field(min_length=1, max_length=1000)
	question_type: QuestionType = "single"
	explanation: str | None = Field(default=None, max_length=1000)
	options: list[QuizOptionIn] = Field(min_length=2, max_length=8)

	@field_validator("prompt")
	@classmethod
	def _strip_prompt(cls, value: str) -> str:
		value = value.strip()
		if not value:
			raise ValueError("Question prompt cannot be blank")
		return value

	@model_validator(mode="after")
	def _validate_shape(self):
		correct = sum(1 for option in self.options if option.is_correct)
		if len({option.text.casefold() for option in self.options}) != len(self.options):
			raise ValueError("Answer options must be different from each other")
		if self.question_type == "true_false" and len(self.options) != 2:
			raise ValueError("A true/false question has exactly two options")
		if self.question_type in {"single", "true_false"} and correct != 1:
			raise ValueError("This question type needs exactly one correct answer")
		if self.question_type == "multiple" and correct < 1:
			raise ValueError("A multiple-answer question needs at least one correct answer")
		if self.question_type == "multiple" and correct == len(self.options):
			raise ValueError("A multiple-answer question needs at least one incorrect option")
		return self


class QuizWrite(BaseModel):
	title: str = Field(min_length=2, max_length=200)
	description: str | None = Field(default=None, max_length=2000)
	subject: str = Field(default="general", min_length=1, max_length=60)
	difficulty: Difficulty = "easy"
	language_code: str = Field(default="en", min_length=2, max_length=10)
	age_min: int = Field(default=4, ge=0, le=18)
	age_max: int = Field(default=15, ge=0, le=18)
	pass_percent: int = Field(default=60, ge=1, le=100)
	star_reward: int = Field(default=0, ge=0, le=1000)
	xp_reward: int = Field(default=0, ge=0, le=1000)
	allow_retry: bool = True
	questions: list[QuizQuestionIn] = Field(default_factory=list, max_length=50)

	@field_validator("language_code")
	@classmethod
	def _language(cls, value: str) -> str:
		if value not in SUPPORTED_LANGUAGES:
			raise ValueError("language_code must be one of en, hi, gu")
		return value

	@model_validator(mode="after")
	def _ages(self):
		if self.age_max < self.age_min:
			raise ValueError("age_max cannot be below age_min")
		return self


class PublishedUpdate(BaseModel):
	is_published: bool


# -- admin output --------------------------------------------------------------------------------


class AdminQuizOption(BaseModel):
	id: UUID
	position: int
	text: str
	is_correct: bool


class AdminQuizQuestion(BaseModel):
	id: UUID
	position: int
	prompt: str
	question_type: str
	explanation: str | None
	options: list[AdminQuizOption]


class AdminQuizSummary(BaseModel):
	id: UUID
	title: str
	subject: str
	difficulty: str
	language_code: str
	age_min: int
	age_max: int
	pass_percent: int
	star_reward: int
	xp_reward: int
	allow_retry: bool
	is_published: bool
	question_count: int
	attempt_count: int
	revision: int
	created_at: datetime
	updated_at: datetime


class AdminQuizDetail(AdminQuizSummary):
	description: str | None
	questions: list[AdminQuizQuestion]


# -- child output --------------------------------------------------------------------------------

QuizStatus = Literal["pending", "in_progress", "attempted", "passed"]


class ChildQuizSummary(BaseModel):
	id: UUID
	title: str
	description: str | None
	subject: str
	difficulty: str
	language_code: str
	age_min: int
	age_max: int
	question_count: int
	pass_percent: int
	star_reward: int
	xp_reward: int
	allow_retry: bool
	status: QuizStatus
	attempts: int
	best_score_percent: int | None
	reward_claimed: bool
	can_start: bool


class AttemptOption(BaseModel):
	id: UUID
	text: str


class AttemptQuestion(BaseModel):
	id: UUID
	position: int
	prompt: str
	question_type: str
	options: list[AttemptOption]


class AttemptStarted(BaseModel):
	attempt_id: UUID
	quiz_id: UUID
	title: str
	pass_percent: int
	star_reward: int
	xp_reward: int
	started_at: datetime
	questions: list[AttemptQuestion]


class SubmittedAnswer(BaseModel):
	question_id: UUID
	option_ids: list[UUID] = Field(default_factory=list, max_length=8)


class AttemptSubmit(BaseModel):
	answers: list[SubmittedAnswer] = Field(default_factory=list, max_length=50)


class ReviewOption(BaseModel):
	id: UUID
	text: str
	is_correct: bool


class ReviewItem(BaseModel):
	question_id: UUID
	position: int
	prompt: str
	question_type: str
	explanation: str | None
	selected_option_ids: list[UUID]
	correct_option_ids: list[UUID]
	is_correct: bool
	options: list[ReviewOption]


class AttemptResult(BaseModel):
	model_config = ConfigDict(from_attributes=True)

	attempt_id: UUID
	quiz_id: UUID
	quiz_title: str
	status: str
	total_questions: int
	correct_count: int
	incorrect_count: int
	score_percent: int
	passed: bool
	pass_percent: int
	stars_awarded: int
	xp_awarded: int
	submitted_at: datetime | None
	can_retry: bool
	# None when the quiz was edited after this attempt, so the stored answers no longer line up.
	review: list[ReviewItem] | None


class AttemptHistoryItem(BaseModel):
	attempt_id: UUID
	quiz_id: UUID
	quiz_title: str
	score_percent: int
	correct_count: int
	total_questions: int
	passed: bool
	stars_awarded: int
	xp_awarded: int
	submitted_at: datetime

	# Stored naive UTC; sent with an offset so the app can show the viewer's own date.
	@field_serializer("submitted_at")
	def serialize_submitted_at(self, value: datetime) -> datetime:
		return utc_aware(value)
