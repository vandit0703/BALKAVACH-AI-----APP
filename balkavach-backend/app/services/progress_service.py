from uuid import UUID

from sqlalchemy.orm import Session

from app.db.base import get_model
from app.services.ledger_service import star_balance, xp_total


SUPPORTED_BADGE_CRITERIA = {"approved_tasks", "total_stars", "total_xp", "current_streak"}


def badge_qualifies(criteria_type: str, criteria_value, values: dict[str, int]) -> bool:
	if criteria_type not in SUPPORTED_BADGE_CRITERIA or not isinstance(criteria_value, dict):
		return False
	threshold = criteria_value.get("threshold")
	value = values.get(criteria_type)
	return type(threshold) is int and threshold > 0 and value is not None and value >= threshold


def get_progress(session: Session, child_id: UUID) -> dict:
	ChildProgress = get_model("ChildProgress")
	ChildStreak = get_model("ChildStreak")
	ChildActivityDay = get_model("ChildActivityDay")
	ChildBadge = get_model("ChildBadge")
	Badge = get_model("Badge")
	Level = get_model("Level")

	progress = session.query(ChildProgress).filter(ChildProgress.child_id == child_id).one_or_none()
	level = None
	if progress and progress.current_level_id:
		level = session.query(Level).filter(Level.id == progress.current_level_id).one_or_none()
	streak = session.query(ChildStreak).filter(ChildStreak.child_id == child_id).one_or_none()
	activities = (
		session.query(ChildActivityDay)
		.filter(ChildActivityDay.child_id == child_id)
		.order_by(ChildActivityDay.activity_date.desc())
		.limit(90)
		.all()
	)
	badges = (
		session.query(ChildBadge, Badge)
		.join(Badge, Badge.id == ChildBadge.badge_id)
		.filter(ChildBadge.child_id == child_id)
		.order_by(ChildBadge.unlocked_at.desc())
		.all()
	)
	return {
		"child_id": child_id,
		"star_balance": star_balance(session, child_id),
		"total_xp": xp_total(session, child_id),
		"level_number": level.level_number if level else None,
		"level_name": level.name if level else None,
		"current_streak": streak.current_streak if streak else 0,
		"longest_streak": streak.longest_streak if streak else 0,
		"activity_days": [
			{
				"activity_date": activity.activity_date,
				"completed_tasks": activity.completed_tasks,
				"stars_earned": activity.stars_earned,
				"xp_earned": activity.xp_earned,
			}
			for activity in activities
		],
		"badges": [
			{
				"badge_id": earned.Badge.id,
				"name": earned.Badge.name,
				"description": earned.Badge.description,
				"icon_url": earned.Badge.icon_url,
				"unlocked_at": earned.ChildBadge.unlocked_at,
			}
			for earned in badges
		],
	}
