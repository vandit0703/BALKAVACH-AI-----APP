from datetime import date, datetime, time, timedelta, timezone
from uuid import UUID
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

from sqlalchemy.orm import Session

from app.db.base import get_model

DEFAULT_TIMEZONE = "UTC"
TIMEZONE_SETTING_KEY = "timezone"


def parse_timezone(name: str) -> ZoneInfo:
	"""Return the IANA zone or raise ValueError; used for both validation and lookup."""
	if not isinstance(name, str) or not name or len(name) > 64:
		raise ValueError("timezone must be an IANA zone name such as Asia/Kolkata")
	try:
		return ZoneInfo(name)
	except (ZoneInfoNotFoundError, ValueError, OSError) as error:
		raise ValueError(f"unknown timezone: {name}") from error


def family_timezone_name(session: Session, family_id: UUID) -> str:
	FamilySetting = get_model("FamilySetting")
	row = session.query(FamilySetting.mission_settings).filter(FamilySetting.family_id == family_id).first()
	configured = (row[0] or {}).get(TIMEZONE_SETTING_KEY) if row else None
	if configured:
		try:
			parse_timezone(configured)
			return configured
		except ValueError:
			pass
	return DEFAULT_TIMEZONE


def local_today(session: Session, family_id: UUID, now: datetime | None = None) -> date:
	zone = parse_timezone(family_timezone_name(session, family_id))
	return (now or datetime.now(timezone.utc)).astimezone(zone).date()


def local_day_bounds_utc_naive(zone: ZoneInfo, first_day: date, day_count: int) -> tuple[datetime, datetime]:
	"""UTC-naive [start, end) covering ``day_count`` local days starting at ``first_day``."""
	start_local = datetime.combine(first_day, time.min, tzinfo=zone)
	end_local = datetime.combine(first_day + timedelta(days=day_count), time.min, tzinfo=zone)
	return (
		start_local.astimezone(timezone.utc).replace(tzinfo=None),
		end_local.astimezone(timezone.utc).replace(tzinfo=None),
	)
