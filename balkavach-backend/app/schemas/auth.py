from datetime import datetime
from uuid import UUID

from pydantic import BaseModel, ConfigDict, EmailStr, Field, model_validator


class RegistrationRequest(BaseModel):
	full_name: str = Field(min_length=2, max_length=160)
	email: EmailStr
	password: str = Field(min_length=12, max_length=128)


class RegistrationAccepted(BaseModel):
	email: EmailStr


class EmailVerificationRequest(BaseModel):
	email: EmailStr
	otp: str = Field(min_length=6, max_length=6, pattern=r"^\d{6}$")


class EmailVerificationResendRequest(BaseModel):
	email: EmailStr


class LoginCodeRequest(BaseModel):
	"""Ask for a passwordless sign-in code (existing, verified parent accounts)."""

	email: EmailStr


class LoginCodeVerify(BaseModel):
	email: EmailStr
	otp: str = Field(min_length=6, max_length=6, pattern=r"^\d{6}$")


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
	child_id: UUID | None = None
	refresh_token: str | None = None
	refresh_expires_at: datetime | None = None
	user: UserPublic


class RefreshRequest(BaseModel):
	refresh_token: str = Field(min_length=20, max_length=200)


class PasswordResetRequest(BaseModel):
	email: EmailStr


class PasswordResetConfirm(BaseModel):
	token: str = Field(min_length=20, max_length=200)
	password: str = Field(min_length=12, max_length=128)


class PasswordChangeRequest(BaseModel):
	current_password: str = Field(min_length=1, max_length=128)
	# Same rule as registration and password reset.
	new_password: str = Field(min_length=12, max_length=128)


class ParentPinSetRequest(BaseModel):
	"""A new PIN. When a PIN already exists, the current PIN *or* the account password must be proven."""

	pin: str = Field(min_length=6, max_length=8, pattern=r"^\d{6,8}$")
	current_pin: str | None = Field(default=None, min_length=4, max_length=8, pattern=r"^\d{4,8}$")
	current_password: str | None = Field(default=None, min_length=1, max_length=128)

	@model_validator(mode="after")
	def at_most_one_proof(self):
		if self.current_pin is not None and self.current_password is not None:
			raise ValueError("provide only one of current_pin or current_password")
		return self


class ParentPinStatus(BaseModel):
	is_set: bool


class ParentModeEnterRequest(BaseModel):
	"""Same credentials as the parent login form; sent from an authenticated child session."""

	email: EmailStr
	password: str = Field(min_length=1, max_length=128)
