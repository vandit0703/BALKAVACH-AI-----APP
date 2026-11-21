"""The one age rule for missions: a child's age, age group, and which daily missions are eligible.

Age groups (the catalogue's bands, ``app/content/daily_missions.AGE_BANDS`` and the ``daily_mission_variations``
CHECK constraint): ``4_6`` = ages 4-6, ``7_10`` = ages 7-10, ``11_15`` = ages 11-15, all inclusive. Daily missions
are for ages 4 through 15.

* Age is whole years on the **family-local** date (``timezone_service.local_today``), so the group changes on the
  child's birthday in the family's timezone, not the server's.
* A missing birth date is never guessed: ``birth_date_required`` (422). A birth date in the future is
  ``birth_date_invalid`` (422). An age outside 4-15 is ``daily_missions_age_range`` (422).
* A daily assignment keeps the ``age_band`` it was generated for. It is **eligible** only while that band is the
  child's current band. Assignments generated for another band (the birth date was corrected, or a birthday moved
  the child to the next group) stay in history but are never offered, carried forward, opened or submitted as
  current missions. Nothing is deleted or rewritten here.
"""

from __future__ import annotations

from datetime import date, datetime, timezone

from sqlalchemy.orm import Session

from app.core.exceptions import APIError
from app.db.base import get_model
from app.services.timezone_service import local_today

# (band, youngest age, oldest age), inclusive.
AGE_GROUPS: tuple[tuple[str, int, int], ...] = (("4_6", 4, 6), ("7_10", 7, 10), ("11_15", 11, 15))
MIN_AGE = AGE_GROUPS[0][1]
MAX_AGE = AGE_GROUPS[-1][2]

# A chosen daily mission the child can still act on. Pending (sent to a parent) and approved ones are progress
# and history, not something to do, so they are not hidden when the band changes.
ACTIONABLE_STATUSES = ("selected", "in_progress", "rejected")


def age_on(birth_date: date, today: date) -> int:
	"""Whole years on ``today`` (a birthday counts from that day)."""
	return today.year - birth_date.year - ((today.month, today.day) < (birth_date.month, birth_date.day))


def age_band_for_age(age: int) -> str | None:
	for band, youngest, oldest in AGE_GROUPS:
		if youngest <= age <= oldest:
			return band
	return None


def age_band_for_birth_date(birth_date: date, today: date) -> str | None:
	"""The age group on ``today``, or ``None`` outside 4-15 (or for a birth date after ``today``)."""
	if birth_date > today:
		return None
	return age_band_for_age(age_on(birth_date, today))


def child_age_band(session: Session, child, now_utc: datetime | None = None) -> tuple[date, str]:
	"""``(family-local today, age band)`` for ``child``; a clear 422 when it cannot be determined."""
	today = local_today(session, child.family_id, now_utc or datetime.now(timezone.utc))
	birth_date = child.date_of_birth
	if birth_date is None:
		raise APIError(422, "birth_date_required", "A birth date is required for daily missions")
	if birth_date > today:
		raise APIError(422, "birth_date_invalid", "The birth date is in the future; a parent needs to correct it")
	band = age_band_for_birth_date(birth_date, today)
	if band is None:
		raise APIError(422, "daily_missions_age_range", "Daily missions are available for ages 4 through 15")
	return today, band


def child_age_band_or_none(session: Session, child, now_utc: datetime | None = None) -> str | None:
	"""Like :func:`child_age_band` for listings that must not fail: ``None`` when the band is unknown."""
	try:
		return child_age_band(session, child, now_utc)[1]
	except APIError:
		return None


def is_eligible(assignment, band: str | None) -> bool:
	"""A daily assignment is eligible only for the band it was generated for, and only while that is current."""
	return band is not None and assignment.age_band == band


def ensure_assignment_eligible(assignment, band: str | None) -> None:
	if not is_eligible(assignment, band):
		raise APIError(
			409,
			"mission_not_age_eligible",
			"This mission was made for a different age group and is no longer available",
		)


def ineligible_daily_task_ids(session: Session, child, band: str | None):
	"""Subquery: tasks of this child's chosen daily missions that are still actionable but were generated for
	another age group (all of them when the band is unknown). Used to keep those tasks out of the child's list and
	to refuse submitting them."""
	Assignment = get_model("DailyMissionAssignment")
	query = session.query(Assignment.task_id).filter(
		Assignment.child_id == child.id,
		Assignment.task_id.isnot(None),
		Assignment.status.in_(ACTIONABLE_STATUSES),
	)
	if band is not None:
		query = query.filter(Assignment.age_band != band)
	return query


def ensure_task_age_eligible(session: Session, child, task_id, now_utc: datetime | None = None) -> None:
	"""Refuse acting on a task that belongs to one of the child's daily missions for another age group.
	Family missions created by a parent carry no age group and are always eligible."""
	band = child_age_band_or_none(session, child, now_utc)
	blocked = ineligible_daily_task_ids(session, child, band).filter(
		get_model("DailyMissionAssignment").task_id == task_id
	)
	if blocked.first() is not None:
		raise APIError(
			409,
			"mission_not_age_eligible",
			"This mission was made for a different age group and is no longer available",
		)
