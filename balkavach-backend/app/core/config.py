from functools import lru_cache

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
	jwt_algorithm: str = "HS256"
	access_token_expire_minutes: int = Field(default=30, ge=1, le=1440)
	cors_origins: list[str] = Field(default_factory=list)
	video_playback_provider: str | None = None
	notification_provider: str | None = None
	allow_schema_migrations: bool = False
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
