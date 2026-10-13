from datetime import datetime, timezone
from uuid import UUID

from sqlalchemy.orm import Session

from app.core.exceptions import APIError
from app.db.base import get_model


def _device_model():
	try:
		return get_model("DeviceToken")
	except (KeyError, AttributeError) as error:
		raise APIError(501, "push_unavailable", "Push notifications are not available on this server") from error


def register_device(session: Session, user_id: UUID, token: str, platform: str, app_version: str | None) -> None:
	"""Upsert. A token belongs to exactly one user: a shared device follows whoever signed in last."""
	DeviceToken = _device_model()
	now = datetime.now(timezone.utc)
	row = session.query(DeviceToken).filter(DeviceToken.token == token).with_for_update().one_or_none()
	if row is None:
		session.add(
			DeviceToken(
				user_id=user_id,
				token=token,
				platform=platform,
				app_version=app_version,
				is_active=True,
				created_at=now,
				last_seen_at=now,
			)
		)
	else:
		row.user_id = user_id
		row.platform = platform
		row.app_version = app_version
		row.is_active = True
		row.last_seen_at = now
	session.commit()


def unregister_device(session: Session, user_id: UUID, token: str) -> None:
	"""Deletes only the caller's own token; anything else is a silent no-op (no existence oracle)."""
	DeviceToken = _device_model()
	session.query(DeviceToken).filter(DeviceToken.token == token, DeviceToken.user_id == user_id).delete(
		synchronize_session=False
	)
	session.commit()
