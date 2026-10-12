from datetime import datetime
from uuid import UUID

from pydantic import BaseModel, ConfigDict, EmailStr, Field


class RegistrationRequest(BaseModel):
	full_name: str = Field(min_length=2, max_length=160)
	email: EmailStr
	password: str = Field(min_length=12, max_length=128)


class LoginRequest(BaseModel):
	email: EmailStr
	password: str = Field(min_length=1, max_length=128)


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
	user: UserPublic
