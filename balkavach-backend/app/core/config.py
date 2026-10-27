from functools import lru_cache
from uuid import UUID

from pydantic import Field
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
	cors_origins: list[str] = Field(default_factory=list)
	video_playback_provider: str | None = None
	youtube_api_key: str | None = Field(default=None, repr=False)
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
