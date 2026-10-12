from datetime import datetime
from importlib import import_module
from typing import Protocol
from uuid import UUID

from app.core.config import settings
from app.core.exceptions import APIError


class VideoPlaybackProvider(Protocol):
	def issue_playback_url(self, video, session_id: UUID, expires_at: datetime) -> str: ...

	def revoke_playback(self, session_id: UUID) -> None: ...


class PushNotificationProvider(Protocol):
	def send(self, user_id: UUID, title: str, message: str, payload: dict) -> None: ...


def get_push_notification_provider() -> PushNotificationProvider | None:
	provider_path = settings.notification_provider
	if not provider_path:
		return None
	try:
		module_name, factory_name = provider_path.split(":", 1)
		factory = getattr(import_module(module_name), factory_name)
		provider = factory()
	except (ImportError, AttributeError, ValueError) as error:
		raise APIError(503, "push_unavailable", "Configured notification provider could not be loaded") from error
	if not callable(getattr(provider, "send", None)):
		raise APIError(503, "push_unavailable", "Configured notification provider is incomplete")
	return provider


def get_video_playback_provider() -> VideoPlaybackProvider:
	provider_path = settings.video_playback_provider
	if not provider_path:
		raise APIError(503, "playback_unavailable", "Authorized video playback is not configured")
	try:
		module_name, factory_name = provider_path.split(":", 1)
		factory = getattr(import_module(module_name), factory_name)
		provider = factory()
	except (ImportError, AttributeError, ValueError) as error:
		raise APIError(503, "playback_unavailable", "Configured video playback provider could not be loaded") from error
	if not callable(getattr(provider, "issue_playback_url", None)) or not callable(
		getattr(provider, "revoke_playback", None)
	):
		raise APIError(503, "playback_unavailable", "Configured video playback provider is incomplete")
	return provider
