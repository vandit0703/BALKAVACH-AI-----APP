"""Default progression content.

Used by the data migration and by tests, so the shipped defaults are exactly the
tested ones. The numbers are proposed product defaults (see the delivery report):
changing them is a content decision, not a code change, and existing children are
re-levelled on their next approval.
"""

from sqlalchemy.orm import Session

from app.db.base import get_model

LEVELS = [
	# (level_number, name, minimum_xp)
	(1, "Seedling", 0),
	(2, "Sprout", 100),
	(3, "Explorer", 300),
	(4, "Guardian", 700),
	(5, "Hero", 1500),
	(6, "Champion", 3000),
]

BADGES = [
	# (name, description, criteria_type, threshold)
	("First Mission", "Complete your first mission.", "approved_tasks", 1),
	("Mission Master", "Complete 10 missions.", "approved_tasks", 10),
	("Star Collector", "Earn 50 stars.", "total_stars", 50),
	("XP Climber", "Earn 500 XP.", "total_xp", 500),
	("Three-Day Streak", "Complete missions 3 days in a row.", "current_streak", 3),
	("Week Warrior", "Complete missions 7 days in a row.", "current_streak", 7),
]


def seed_progression_defaults(session: Session) -> dict[str, int]:
	"""Insert missing levels and badges; never modifies or removes existing rows."""
	Level = get_model("Level")
	Badge = get_model("Badge")
	existing_levels = {number for (number,) in session.query(Level.level_number).all()}
	existing_badges = {name for (name,) in session.query(Badge.name).all()}
	added_levels = added_badges = 0
	for number, name, minimum_xp in LEVELS:
		if number not in existing_levels:
			session.add(Level(level_number=number, name=name, minimum_xp=minimum_xp))
			added_levels += 1
	for name, description, criteria_type, threshold in BADGES:
		if name not in existing_badges:
			session.add(
				Badge(
					name=name,
					description=description,
					criteria_type=criteria_type,
					criteria_value={"threshold": threshold},
					is_active=True,
				)
			)
			added_badges += 1
	session.flush()
	return {"levels": added_levels, "badges": added_badges}
