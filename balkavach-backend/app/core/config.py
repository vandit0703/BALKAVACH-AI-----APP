from functools import lru_cache
from uuid import UUID

from pydantic import AliasChoices, Field
from pydantic_settings import BaseSettings, SettingsConfigDict
from sqlalchemy.engine import make_url


class Settings(BaseSettings):
	model_config = SettingsConfigDict(env_file=".env", env_file_encoding="utf-8", extra="ignore")

	app_name: str = "BalKavach API"
	environment: str = "development"
	debug: bool = False
	database_url: str | None = Field(default=None, repr=False)
	jwt_secret_key: str | None = Field(default=None, repr=False)
	child_credentials_encryption_key: str | None = Field(default=None, repr=False)
	jwt_algorithm: str = "HS256"
	access_token_expire_minutes: int = Field(default=30, ge=1, le=1440)
	refresh_token_expire_days: int = Field(default=30, ge=1, le=365)
	child_refresh_token_expire_days: int = Field(default=14, ge=1, le=90)
	login_rate_limit: int = Field(default=8, ge=1, le=100)
	login_rate_window_seconds: int = Field(default=300, ge=10, le=3600)
	registration_rate_limit: int = Field(default=5, ge=1, le=50)
	verification_resend_rate_limit: int = Field(default=1, ge=1, le=10)
	password_reset_rate_limit: int = Field(default=3, ge=1, le=20)
	password_reset_window_seconds: int = Field(default=900, ge=60, le=86400)
	parent_pin_rate_limit: int = Field(default=5, ge=1, le=30)
	parent_pin_window_seconds: int = Field(default=300, ge=30, le=3600)
	# Parent-mode entry (leaving child mode): email + password step-up. Failures are tracked per
	# target account, per family and per child device session, never per client IP.
	parent_mode_rate_limit: int = Field(default=10, ge=1, le=100)
	parent_mode_rate_window_seconds: int = Field(default=300, ge=10, le=3600)
	parent_mode_max_failures: int = Field(default=5, ge=3, le=20)
	parent_mode_failure_window_seconds: int = Field(default=900, ge=60, le=86400)
	parent_mode_lock_seconds: int = Field(default=900, ge=30, le=86400)
	parent_mode_lock_max_seconds: int = Field(default=3600, ge=60, le=86400)
	parent_mode_strike_window_seconds: int = Field(default=86400, ge=60, le=604800)
	parent_mode_refresh_hours: int = Field(default=12, ge=1, le=720)
	password_reset_expire_minutes: int = Field(default=30, ge=5, le=1440)
	password_reset_url: str | None = None
	password_reset_from_email: str | None = Field(
		default=None,
		validation_alias=AliasChoices("SMTP_FROM_EMAIL", "PASSWORD_RESET_FROM_EMAIL"),
	)
	redis_url: str | None = Field(default=None, repr=False)
	redis_rate_limit_prefix: str = "balkavach:auth-rate-limit"
	smtp_host: str | None = None
	smtp_port: int = Field(default=587, ge=1, le=65535)
	smtp_username: str | None = Field(default=None, repr=False)
	smtp_password: str | None = Field(default=None, repr=False)
	smtp_use_tls: bool = True
	smtp_use_ssl: bool = False
	cors_origins: list[str] = Field(default_factory=list)
	video_playback_provider: str | None = None
	# D6 play tickets. Off by default. Has no effect until the deferred
	# video_play_tickets table exists (app/services/charging_path.py).
	video_play_tickets_enabled: bool = False
	youtube_api_key: str | None = Field(
		default=None,
		validation_alias=AliasChoices("YOUTUBE_DATA_API_KEY", "YOUTUBE_API_KEY"),
		repr=False,
	)
	youtube_region_code: str = Field(default="IN", pattern=r"^[A-Z]{2}$")
	youtube_discovery_topics: list[str] = Field(
		default_factory=lambda: [
			"early_learning",
			"math",
			"science",
			"coding",
			"stories",
			"academic_explainers",
			"nature",
		]
	)
	youtube_discovery_max_results: int = Field(default=10, ge=1, le=50)
	youtube_auto_publish_max_seconds: int = Field(default=180, ge=1, le=600)
	youtube_trusted_auto_publish_max_seconds: int = Field(default=3600, ge=61, le=86400)
	youtube_short_watch_completion_percent: int = Field(default=80, ge=1, le=100)
	youtube_short_min_watch_seconds: int = Field(default=6, ge=1, le=60)
	youtube_long_watch_completion_percent: int = Field(default=90, ge=1, le=100)
	youtube_auto_publish_non_trusted: bool = True
	# Audience for automatically approved videos from non-trusted channels: one of
	# 3-5, 6-8, 9-12, 13-15. Unset means such videos wait for a person.
	youtube_auto_publish_age_band: str | None = None
	youtube_discovery_actor_id: UUID | None = Field(default=None, repr=False)
	youtube_reverify_hours: int = Field(default=72, ge=1, le=720)
	notification_provider: str | None = None
	fcm_service_account_json: str | None = Field(default=None, repr=False)
	fcm_service_account_file: str | None = None
	allow_schema_migrations: bool = False
	storage_provider: str = "local"
	upload_dir: str = "uploads"
	max_upload_bytes: int = Field(default=5_000_000, ge=1024, le=20_000_000)
	max_unattached_uploads: int = Field(default=10, ge=1, le=100)
	s3_bucket: str | None = None
	s3_endpoint_url: str | None = None
	s3_region: str | None = None
	s3_access_key_id: str | None = Field(default=None, repr=False)
	s3_secret_access_key: str | None = Field(default=None, repr=False)
	log_level: str = "INFO"


@lru_cache
def get_settings() -> Settings:
	return Settings()


settings = get_settings()


def get_database_url() -> str | None:
	if not settings.database_url:
		return None
	url = make_url(settings.database_url)
	if url.drivername in {"postgres", "postgresql"}:
		url = url.set(drivername="postgresql+psycopg")
	return url.render_as_string(hide_password=False)
from pydantic_settings import BaseSettings
