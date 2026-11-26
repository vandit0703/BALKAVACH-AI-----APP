"""Family notification preferences and quiet hours (Phase 7, no schema change).

Where it is stored
------------------
``user_settings`` has only scalar columns (``language_code``, ``push_enabled``,
``email_notifications_enabled``), so it cannot hold per-category preferences
without a migration. The family's existing JSON document
``family_settings.mission_settings`` already carries the family time zone, so the
preferences live next to it under :data:`PREFERENCES_KEY`. The generic
``PATCH /settings/families/{id}`` endpoint never changes that key (see
``app/api/v1/settings.py``); only the dedicated preferences endpoint does.
Moving it to a dedicated column is listed in ``docs/deferred-database-integration.md``.

What a preference controls
--------------------------
Preferences and quiet hours decide whether a **push** is sent. The in-app
notification is always created: it is the durable record, and the app relies on
some of them (for example ``mission_video_time_granted`` refreshes the
allowance). Nothing is delayed: there is no durable queue to hold a push until
quiet hours end, so a push that falls inside quiet hours is **suppressed** and
the notification waits in the in-app centre.

Safety notifications (``parent_mode_locked``) cannot be switched off and ignore
quiet hours.
"""

from __future__ import annotations

import re
from dataclasses import dataclass
from datetime import datetime, time, timezone
from typing import Any
from uuid import UUID
from zoneinfo import ZoneInfo

from fastapi import HTTPException
from sqlalchemy.orm import Session

from app.db.base import get_model
from app.services.timezone_service import TIMEZONE_SETTING_KEY, family_timezone_name, parse_timezone
from app.utils import utc_naive

PREFERENCES_KEY = "notification_preferences"
SCHEMA_VERSION = 1

SAFETY = "safety"


@dataclass(frozen=True)
class Category:
	key: str
	types: frozenset[str]
	default: bool = True
	locked: bool = False  # cannot be switched off
	quiet_hours_exempt: bool = False


CATEGORIES: tuple[Category, ...] = (
	Category("new_missions", frozenset({"task_assigned", "daily_missions_ready"})),
	Category(
		"mission_reviews",
		# interest_requested: a child's topic request waiting for the parent's review.
		frozenset(
			{"task_submitted", "task_approved", "task_rejected", "task_resubmission_requested", "interest_requested"}
		),
	),
	Category(
		"rewards",
		frozenset({"reward_requested", "reward_approved", "reward_rejected", "reward_fulfilled", "badge_unlocked"}),
	),
	Category(
		"streaks",
		frozenset(
			{
				"streak_at_risk",
				"streak_one_day_left",
				"streak_continued",
				"streak_milestone",
				"streak_new_after_break",
			}
		),
	),
	Category("video_allowance", frozenset({"mission_video_time_granted", "video_time_nearly_exhausted"})),
	Category("video_time_up", frozenset({"video_time_exhausted"})),
	Category(SAFETY, frozenset({"parent_mode_locked"}), locked=True, quiet_hours_exempt=True),
)

CATEGORY_BY_KEY = {category.key: category for category in CATEGORIES}
_CATEGORY_BY_TYPE = {notification_type: category for category in CATEGORIES for notification_type in category.types}

DEFAULT_QUIET_HOURS = {"enabled": False, "start": "21:00", "end": "07:00"}
_TIME = re.compile(r"^([01]\d|2[0-3]):([0-5]\d)$")


def category_of(notification_type: str) -> Category | None:
	"""``None`` for a type no category knows about; such pushes follow quiet hours but are never muted."""
	return _CATEGORY_BY_TYPE.get(notification_type)


def parse_hhmm(value: Any) -> time:
	if not isinstance(value, str) or not _TIME.match(value):
		raise ValueError("time must be HH:MM (24-hour), e.g. 21:30")
	hours, minutes = value.split(":")
	return time(int(hours), int(minutes))


def default_preferences() -> dict[str, Any]:
	return {
		"categories": {category.key: category.default for category in CATEGORIES},
		"quiet_hours": dict(DEFAULT_QUIET_HOURS),
	}


def effective_preferences(stored: Any) -> dict[str, Any]:
	"""Defaults overlaid with whatever valid values are stored. Junk is ignored, never trusted."""
	result = default_preferences()
	if not isinstance(stored, dict):
		return result
	categories = stored.get("categories")
	if isinstance(categories, dict):
		for key, value in categories.items():
			category = CATEGORY_BY_KEY.get(key)
			if category is not None and not category.locked and isinstance(value, bool):
				result["categories"][key] = value
	quiet = stored.get("quiet_hours")
	if isinstance(quiet, dict):
		candidate = dict(result["quiet_hours"])
		if isinstance(quiet.get("enabled"), bool):
			candidate["enabled"] = quiet["enabled"]
		for field in ("start", "end"):
			try:
				parse_hhmm(quiet.get(field))
				candidate[field] = quiet[field]
			except ValueError:
				pass
		if candidate["start"] == candidate["end"]:
			candidate["enabled"] = False
		result["quiet_hours"] = candidate
	return result


def is_quiet(quiet_hours: dict[str, Any], zone: ZoneInfo, now: datetime) -> bool:
	"""True when ``now`` falls inside the family-local quiet window ``[start, end)``.

	The comparison uses the family's local wall-clock time at ``now``, so it is
	right on both sides of a daylight-saving change, and a window whose start is
	later than its end (21:00 → 07:00) runs overnight.
	"""
	if not quiet_hours.get("enabled"):
		return False
	try:
		start = parse_hhmm(quiet_hours.get("start"))
		end = parse_hhmm(quiet_hours.get("end"))
	except ValueError:
		return False
	if start == end:
		return False
	if now.tzinfo is None:
		now = now.replace(tzinfo=timezone.utc)
	local = now.astimezone(zone).time().replace(second=0, microsecond=0, tzinfo=None)
	if start < end:
		return start <= local < end
	return local >= start or local < end


def push_decision(preferences: dict[str, Any], zone: ZoneInfo, notification_type: str, now: datetime) -> str:
	"""``send``, ``muted`` (category off) or ``quiet_hours``."""
	category = category_of(notification_type)
	if category is not None and category.locked:
		return "send"
	if category is not None and not preferences["categories"].get(category.key, category.default):
		return "muted"
	if (category is None or not category.quiet_hours_exempt) and is_quiet(preferences["quiet_hours"], zone, now):
		return "quiet_hours"
	return "send"


# --------------------------------------------------------------------- storage


def family_ids_for_user(session: Session, user_id: UUID, role: str | None) -> list[UUID]:
	"""Families whose preferences govern pushes to this user (a child has one; a parent usually one)."""
	if role == "child":
		ChildProfile = get_model("ChildProfile")
		row = session.query(ChildProfile.family_id).filter(ChildProfile.user_id == user_id).first()
		return [row[0]] if row else []
	FamilyMember = get_model("FamilyMember")
	rows = (
		session.query(FamilyMember.family_id)
		.filter(FamilyMember.user_id == user_id, FamilyMember.is_active.is_(True))
		.all()
	)
	return [row[0] for row in rows]


def load_family_preferences(session: Session, family_id: UUID) -> tuple[dict[str, Any], dict[str, Any]]:
	"""(effective preferences, stored metadata such as ``updated_at``)."""
	FamilySetting = get_model("FamilySetting")
	row = session.query(FamilySetting.mission_settings).filter(FamilySetting.family_id == family_id).first()
	stored = (row[0] or {}).get(PREFERENCES_KEY) if row else None
	meta = {}
	if isinstance(stored, dict):
		meta = {key: stored.get(key) for key in ("updated_at", "updated_by") if isinstance(stored.get(key), str)}
	return effective_preferences(stored), meta


def require_parent_of_family(session: Session, family_id: UUID, parent_id: UUID) -> None:
	"""404 (not 403) for a family the parent is not an active member of: no existence oracle."""
	FamilyMember = get_model("FamilyMember")
	if not (
		session.query(FamilyMember.id)
		.filter(
			FamilyMember.family_id == family_id,
			FamilyMember.user_id == parent_id,
			FamilyMember.is_active.is_(True),
		)
		.first()
	):
		raise HTTPException(status_code=404, detail="Family not found")


def describe(session: Session, family_id: UUID) -> dict[str, Any]:
	preferences, meta = load_family_preferences(session, family_id)
	zone_name = family_timezone_name(session, family_id)
	return {
		"family_id": family_id,
		"categories": preferences["categories"],
		"locked_categories": sorted(category.key for category in CATEGORIES if category.locked),
		"quiet_hours": preferences["quiet_hours"],
		"quiet_hours_exempt_categories": sorted(category.key for category in CATEGORIES if category.quiet_hours_exempt),
		"timezone": zone_name,
		"timezone_is_default": not _has_explicit_timezone(session, family_id),
		"updated_at": meta.get("updated_at"),
	}


def _has_explicit_timezone(session: Session, family_id: UUID) -> bool:
	FamilySetting = get_model("FamilySetting")
	row = session.query(FamilySetting.mission_settings).filter(FamilySetting.family_id == family_id).first()
	configured = (row[0] or {}).get(TIMEZONE_SETTING_KEY) if row else None
	if not configured:
		return False
	try:
		parse_timezone(configured)
	except ValueError:
		return False
	return True


def update(
	session: Session,
	family_id: UUID,
	parent_id: UUID,
	*,
	categories: dict[str, bool] | None,
	quiet_hours: dict[str, Any] | None,
	now: datetime | None = None,
) -> dict[str, Any]:
	"""Merge a partial change into the family's preferences and commit. Raises 422 for invalid input."""
	categories = categories or {}
	for key in categories:
		category = CATEGORY_BY_KEY.get(key)
		if category is None:
			raise HTTPException(status_code=422, detail=f"Unknown notification category: {key}")
		if category.locked and categories[key] is not True:
			raise HTTPException(status_code=422, detail=f"The {key} category cannot be turned off")

	FamilySetting = get_model("FamilySetting")
	setting = (
		session.query(FamilySetting).filter(FamilySetting.family_id == family_id).with_for_update().one_or_none()
	)
	mission_settings = dict((setting.mission_settings if setting is not None else None) or {})
	current = effective_preferences(mission_settings.get(PREFERENCES_KEY))

	merged_quiet = dict(current["quiet_hours"])
	if quiet_hours:
		merged_quiet.update(quiet_hours)
	for field in ("start", "end"):
		try:
			parse_hhmm(merged_quiet[field])
		except ValueError as error:
			raise HTTPException(status_code=422, detail=f"quiet_hours.{field}: {error}") from error
	if merged_quiet["enabled"] and merged_quiet["start"] == merged_quiet["end"]:
		raise HTTPException(status_code=422, detail="Quiet hours need different start and end times")

	merged_categories = dict(current["categories"])
	merged_categories.update(categories)
	moment = now or datetime.now(timezone.utc)
	mission_settings[PREFERENCES_KEY] = {
		"version": SCHEMA_VERSION,
		"categories": merged_categories,
		"quiet_hours": {
			"enabled": bool(merged_quiet["enabled"]),
			"start": merged_quiet["start"],
			"end": merged_quiet["end"],
		},
		"updated_by": str(parent_id),
		"updated_at": moment.astimezone(timezone.utc).isoformat(),
	}
	if setting is None:
		values: dict[str, Any] = {"family_id": family_id, "mission_settings": mission_settings}
		columns = set(FamilySetting.__table__.columns.keys())
		defaults = {
			"default_language": "en",
			"reward_settings": {},
			"video_settings": {"enabled": True, "default_daily_limit_seconds": 0},
			"updated_at": utc_naive(moment),
		}
		values.update({key: value for key, value in defaults.items() if key in columns})
		session.add(FamilySetting(**values))
	else:
		# Assign a new dict so the JSON column is marked dirty.
		setting.mission_settings = mission_settings
		if hasattr(setting, "updated_at"):
			setting.updated_at = utc_naive(moment)
	session.commit()
	return describe(session, family_id)
