"""Defaults and display helpers for configured mission rewards."""

MISSION_STAR_REWARD = 10
MISSION_XP_REWARD = 15


def effective_star_reward(stored: int | None = None) -> int:
	"""Configured stars, falling back to the product default for old/null rows."""
	return MISSION_STAR_REWARD if stored is None else int(stored)


def effective_xp_reward(stored: int | None = None) -> int:
	"""Configured XP, falling back to the product default for old/null rows."""
	return MISSION_XP_REWARD if stored is None else int(stored)
