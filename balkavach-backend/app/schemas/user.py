from datetime import date, datetime
import re
from uuid import UUID

from pydantic import BaseModel, ConfigDict, Field, HttpUrl, field_serializer, field_validator, model_validator

from app.utils import utc_aware


class FamilyCreate(BaseModel):
	family_name: str = Field(min_length=2, max_length=160)


class FamilyPublic(BaseModel):
	model_config = ConfigDict(from_attributes=True)

	id: UUID
	family_name: str
	created_by: UUID
	created_at: datetime

	@field_serializer("created_at")
	def serialize_created_at(self, value: datetime) -> datetime:
		return utc_aware(value)


class ChildCreate(BaseModel):
	display_name: str = Field(min_length=1, max_length=100)
	username: str = Field(min_length=3, max_length=32)
	password: str = Field(min_length=12, max_length=128)
	date_of_birth: date | None = None
	avatar_url: HttpUrl | None = None
	preferred_language: str = Field(default="en", min_length=2, max_length=10)

	@field_validator("username")
	@classmethod
	def normalize_username(cls, value: str) -> str:
		username = value.strip().lower()
		if not re.fullmatch(r"[a-z][a-z0-9._-]{2,31}", username):
			raise ValueError("username must start with a letter and contain only letters, numbers, dots, underscores, or hyphens")
		return username

	@model_validator(mode="after")
	def validate_age(self):
		if self.date_of_birth:
			today = date.today()
			if self.date_of_birth >= today:
				raise ValueError("date_of_birth must be in the past")
			age = today.year - self.date_of_birth.year - (
				(today.month, today.day) < (self.date_of_birth.month, self.date_of_birth.day)
			)
			if age >= 18:
				raise ValueError("child profiles must be younger than 18")
		return self


class ChildUpdate(BaseModel):
	display_name: str | None = Field(default=None, min_length=1, max_length=100)
	date_of_birth: date | None = None
	avatar_url: HttpUrl | None = None
	is_active: bool | None = None

	@model_validator(mode="after")
	def validate_age(self):
		if self.date_of_birth:
			today = date.today()
			if self.date_of_birth >= today:
				raise ValueError("date_of_birth must be in the past")
			age = today.year - self.date_of_birth.year - (
				(today.month, today.day) < (self.date_of_birth.month, self.date_of_birth.day)
			)
			if age >= 18:
				raise ValueError("child profiles must be younger than 18")
		return self


class ChildPublic(BaseModel):
	model_config = ConfigDict(from_attributes=True)

	id: UUID
	user_id: UUID
	family_id: UUID
	display_name: str
	date_of_birth: date | None
	avatar_url: str | None
	is_active: bool
	created_at: datetime

	@field_serializer("created_at")
	def serialize_created_at(self, value: datetime) -> datetime:
		return utc_aware(value)


class ChildCredentialsPublic(BaseModel):
	username: str
	password: str


class ChildCredentialsUpdate(BaseModel):
	username: str = Field(min_length=3, max_length=32)
	password: str = Field(min_length=12, max_length=128)

	@field_validator("username")
	@classmethod
	def normalize_username(cls, value: str) -> str:
		username = value.strip().lower()
		if not re.fullmatch(r"[a-z][a-z0-9._-]{2,31}", username):
			raise ValueError("username must start with a letter and contain only letters, numbers, dots, underscores, or hyphens")
		return username
