from datetime import datetime, timezone


def utc_naive(value: datetime) -> datetime:
	if value.tzinfo is None or value.utcoffset() is None:
		raise ValueError("A timezone-aware datetime is required")
	return value.astimezone(timezone.utc).replace(tzinfo=None)


def utc_aware(value: datetime) -> datetime:
	if value.tzinfo is None or value.utcoffset() is None:
		return value.replace(tzinfo=timezone.utc)
	return value.astimezone(timezone.utc)
