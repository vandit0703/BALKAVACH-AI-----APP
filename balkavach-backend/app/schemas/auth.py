from datetime import datetime
from uuid import UUID

from pydantic import BaseModel, ConfigDict, EmailStr, Field, model_validator


class RegistrationRequest(BaseModel):
	full_name: str = Field(min_length=2, max_length=160)
	email: EmailStr
	password: str = Field(min_length=12, max_length=128)


class LoginRequest(BaseModel):
	email: EmailStr | None = None
	username: str | None = Field(default=None, min_length=3, max_length=32)
	password: str = Field(min_length=1, max_length=128)

	@model_validator(mode="after")
	def require_login_identifier(self):
		if (self.email is None) == (self.username is None):
			raise ValueError("provide exactly one of email or username")
		if self.username is not None:
			from app.core.child_credentials import normalize_username

			self.username = normalize_username(self.username)
		return self


class UserPublic(BaseModel):
	model_config = ConfigDict(from_attributes=True)

	id: UUID
	full_name: str
	email: EmailStr | None
	role: str
	preferred_language: str


class TokenResponse(BaseModel):
	access_token: str
	token_type: str = "bearer"
	expires_at: datetime
	refresh_token: str | None = None
	refresh_expires_at: datetime | None = None
	user: UserPublic


class RefreshRequest(BaseModel):
	refresh_token: str = Field(min_length=20, max_length=200)
