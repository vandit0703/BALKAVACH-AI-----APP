"""The garden, derived on the server from a child's real progress.

There is no garden state to tamper with: the stage comes from total XP and each
decoration unlocks when the matching badge has been earned. Nothing here grants
anything; it only describes progress that parents already approved.
"""

from typing import Any

# (key, minimum XP). Thresholds mirror the default levels so the garden grows
# with the level the child sees elsewhere.
GARDEN_STAGES: list[dict[str, Any]] = [
	{"key": "seed", "minimum_xp": 0},
	{"key": "sprout", "minimum_xp": 100},
	{"key": "sapling", "minimum_xp": 300},
	{"key": "young-tree", "minimum_xp": 700},
	{"key": "blossom", "minimum_xp": 1500},
	{"key": "orchard", "minimum_xp": 3000},
]

# Decorations and the badge (by name) that unlocks each.
GARDEN_ITEMS: list[dict[str, str]] = [
	{"key": "first-mission", "badge": "First Mission"},
	{"key": "mission-master", "badge": "Mission Master"},
	{"key": "star-collector", "badge": "Star Collector"},
	{"key": "xp-climber", "badge": "XP Climber"},
	{"key": "three-day-streak", "badge": "Three-Day Streak"},
	{"key": "week-warrior", "badge": "Week Warrior"},
]


def build_garden(total_xp: int, earned_badge_names: set[str]) -> dict[str, Any]:
	xp = max(int(total_xp), 0)
	stage_index = 0
	for index, stage in enumerate(GARDEN_STAGES):
		if xp >= stage["minimum_xp"]:
			stage_index = index
	next_stage = GARDEN_STAGES[stage_index + 1] if stage_index + 1 < len(GARDEN_STAGES) else None
	return {
		"stage": stage_index + 1,
		"stage_key": GARDEN_STAGES[stage_index]["key"],
		"xp_to_next_stage": (next_stage["minimum_xp"] - xp) if next_stage else None,
		"items": [
			{"key": item["key"], "badge": item["badge"], "unlocked": item["badge"] in earned_badge_names}
			for item in GARDEN_ITEMS
		],
	}
