"""Allow-listed global settings (admin-managed, publicly readable subset)."""

import re
from datetime import datetime, timezone
from typing import Any

from sqlalchemy.orm import Session

from app.core.exceptions import APIError
from app.db.base import get_model

DEFAULT_CONSENT_VERSIONS = {"parent_guardian_terms": "2026-10-draft"}
DEFAULTS: dict[str, Any] = {
	"consent_versions": DEFAULT_CONSENT_VERSIONS,
	"maintenance": {"enabled": False, "message": ""},
}


def _invalid(message: str) -> APIError:
	return APIError(422, "invalid_setting", message)


def validate_setting(key: str, value: Any) -> Any:
	if key not in DEFAULTS:
		raise APIError(404, "unknown_setting", "Unknown setting")
	if key == "consent_versions":
		if not isinstance(value, dict) or not value or len(value) > 20:
			raise _invalid("consent_versions must be an object with 1-20 entries")
		cleaned = {}
		for name, version in value.items():
			if not isinstance(name, str) or not re.fullmatch(r"[a-z][a-z0-9_]{1,59}", name):
				raise _invalid("Consent type names use lowercase letters, digits and underscores")
			if not isinstance(version, str) or not version.strip() or len(version.strip()) > 40:
				raise _invalid("Each consent version must be a non-empty string up to 40 characters")
			cleaned[name] = version.strip()
		if "parent_guardian_terms" not in cleaned:
			raise _invalid("parent_guardian_terms is required")
		return cleaned
	if key == "maintenance":
		if not isinstance(value, dict) or set(value) - {"enabled", "message"}:
			raise _invalid("maintenance accepts only enabled and message")
		enabled = value.get("enabled", False)
		message = value.get("message", "")
		if not isinstance(enabled, bool) or not isinstance(message, str) or len(message) > 300:
			raise _invalid("enabled must be true/false and message at most 300 characters")
		return {"enabled": enabled, "message": message.strip()}
	raise APIError(404, "unknown_setting", "Unknown setting")


def _model():
	try:
		return get_model("AppSetting")
	except (KeyError, AttributeError):
		return None


def read_all(session: Session) -> tuple[dict[str, Any], set[str]]:
	"""Return (effective values, keys that are overridden by an admin)."""
	values = {key: default for key, default in DEFAULTS.items()}
	overridden: set[str] = set()
	AppSetting = _model()
	if AppSetting is not None:
		for row in session.query(AppSetting).all():
			if row.key in DEFAULTS:
				values[row.key] = row.value
				overridden.add(row.key)
	return values, overridden


def write_setting(session: Session, admin_id, key: str, value: Any):
	cleaned = validate_setting(key, value)
	AppSetting = _model()
	if AppSetting is None:
		raise APIError(501, "settings_unavailable", "Application settings are not available on this server")
	row = session.query(AppSetting).filter(AppSetting.key == key).with_for_update().one_or_none()
	now = datetime.now(timezone.utc)
	if row is None:
		row = AppSetting(key=key, value=cleaned, updated_by=admin_id, updated_at=now)
		session.add(row)
	else:
		row.value = cleaned
		row.updated_by = admin_id
		row.updated_at = now
	return row
