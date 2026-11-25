"""Achievements: the full badge catalogue with each child's real progress, level progress, and awarding.

Everything is derived from the same records the rest of the app uses (the star and XP ledgers, approved
submissions, the streak table). Nothing here stores progress separately, so there is nothing to fake or
drift. Badge awards are idempotent: ``child_badges`` is unique on (child, badge), and the insert uses
``ON CONFLICT DO NOTHING``, so a badge is awarded once however often the check runs or races.
"""

from datetime import datetime, timezone
from uuid import UUID

from sqlalchemy import func
from sqlalchemy.dialects.postgresql import insert as pg_insert
from sqlalchemy.orm import Session

from app.db.base import get_model
from app.services.ledger_service import lifetime_stars_earned, xp_total
from app.services.progress_service import SUPPORTED_BADGE_CRITERIA, badge_qualifies
from app.utils import utc_naive


def criteria_values(session: Session, child_id: UUID) -> dict[str, int]:
	"""The numbers badge criteria are measured against, as the awarding code reads them."""
	TaskSubmission = get_model("TaskSubmission")
	from app.services.streak_service import get_streak_summary

	approved = session.query(func.count(TaskSubmission.id)).filter(
		TaskSubmission.child_id == child_id, TaskSubmission.status == "approved"
	).scalar()
	return {
		"approved_tasks": int(approved or 0),
		"total_stars": lifetime_stars_earned(session, child_id),
		"total_xp": xp_total(session, child_id),
		"current_streak": int(get_streak_summary(session, child_id).get("current_streak") or 0),
	}


def _threshold(criteria_value) -> int | None:
	value = criteria_value.get("threshold") if isinstance(criteria_value, dict) else None
	return value if type(value) is int and value > 0 else None


def level_progress(session: Session, total_xp: int) -> dict:
	Level = get_model("Level")
	current = (
		session.query(Level).filter(Level.minimum_xp <= total_xp).order_by(Level.minimum_xp.desc()).first()
	)
	following = (
		session.query(Level).filter(Level.minimum_xp > total_xp).order_by(Level.minimum_xp.asc()).first()
	)
	return {
		"level_number": current.level_number if current else None,
		"name": current.name if current else None,
		"minimum_xp": int(current.minimum_xp) if current else 0,
		"next_level_number": following.level_number if following else None,
		"next_level_name": following.name if following else None,
		"next_minimum_xp": int(following.minimum_xp) if following else None,
		"total_xp": int(total_xp),
	}


def get_achievements(session: Session, child_id: UUID) -> dict:
	Badge = get_model("Badge")
	ChildBadge = get_model("ChildBadge")
	values = criteria_values(session, child_id)
	unlocked = {
		badge_id: at
		for badge_id, at in session.query(ChildBadge.badge_id, ChildBadge.unlocked_at).filter(
			ChildBadge.child_id == child_id
		)
	}
	badges = []
	for badge in session.query(Badge).filter(Badge.is_active.is_(True)).order_by(Badge.name):
		measurable = badge.criteria_type in SUPPORTED_BADGE_CRITERIA
		badges.append(
			{
				"badge_id": badge.id,
				"name": badge.name,
				"description": badge.description,
				"icon_url": badge.icon_url,
				"unlocked": badge.id in unlocked,
				"unlocked_at": unlocked.get(badge.id),
				"criteria_type": badge.criteria_type,
				"threshold": _threshold(badge.criteria_value) if measurable else None,
				"current": values.get(badge.criteria_type) if measurable else None,
			}
		)
	# A badge earned earlier stays listed even if an admin has since deactivated it.
	listed = {badge["badge_id"] for badge in badges}
	for badge in session.query(Badge).filter(Badge.id.in_(list(unlocked)), Badge.is_active.is_(False)):
		if badge.id not in listed:
			badges.append(
				{
					"badge_id": badge.id,
					"name": badge.name,
					"description": badge.description,
					"icon_url": badge.icon_url,
					"unlocked": True,
					"unlocked_at": unlocked[badge.id],
					"criteria_type": badge.criteria_type,
					"threshold": None,
					"current": None,
				}
			)
	return {"level": level_progress(session, values["total_xp"]), "badges": badges}


def award_qualifying_badges(session: Session, child, now: datetime | None = None) -> list:
	"""Unlock every active badge the child now qualifies for. Returns the badges newly unlocked.

	Stages rows in the caller's transaction (the caller commits). Safe to call repeatedly or concurrently:
	an already-held badge is never inserted again and never notified again."""
	from app.services.notification_service import create_notification

	now = now or utc_naive(datetime.now(timezone.utc))
	Badge = get_model("Badge")
	ChildBadge = get_model("ChildBadge")
	values = criteria_values(session, child.id)
	held = {badge_id for (badge_id,) in session.query(ChildBadge.badge_id).filter(ChildBadge.child_id == child.id)}
	newly = []
	for badge in session.query(Badge).filter(Badge.is_active.is_(True)).all():
		if badge.id in held or not badge_qualifies(badge.criteria_type, badge.criteria_value, values):
			continue
		inserted = session.execute(
			pg_insert(ChildBadge)
			.values(child_id=child.id, badge_id=badge.id, unlocked_at=now)
			.on_conflict_do_nothing(index_elements=[ChildBadge.child_id, ChildBadge.badge_id])
			.returning(ChildBadge.id)
		).scalar_one_or_none()
		if inserted is None:
			continue  # a concurrent request unlocked it first
		create_notification(
			session, child.user_id, "badge_unlocked", "New badge unlocked", f"You earned {badge.name}.", now=now
		)
		newly.append(badge)
	return newly
