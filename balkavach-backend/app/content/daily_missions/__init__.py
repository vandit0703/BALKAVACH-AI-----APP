"""The localized daily-mission catalogue, version ``c1`` (seven weekday themes x six missions each = 42 templates, x 3 age bands x en/gu/hi = 378 localized versions).

Plain data; it is written to the database by ``app.services.mission_catalogue_service`` (CLI:
``python -m app.cli seed-daily-missions``), never by importing this package.

Fields the database stores per variation: title, description, instructions, required_materials,
duration_minutes, safety_instructions, completion_criteria. The schema has no column for the skill
category, the age rationale or the parent-involvement note, so those stay here (and in
``docs/mission-catalogue-inventory.md``). The parent verification instruction is stored as the last line of
``completion_criteria`` and the "another way" (accessible alternative) as the last line of ``instructions``.
"""

from __future__ import annotations

from typing import Any

from app.content.daily_missions import (
	activities,
	friday,
	friday_calm_words,
	friday_face_clues,
	friday_feelings_in_stories,
	friday_kind_clues,
	friday_listen_and_help,
	monday,
	monday_look_closer,
	monday_loud_and_soft,
	monday_sound_order,
	monday_sound_words,
	monday_where_is_it,
	saturday,
	saturday_body_beats,
	saturday_home_band,
	saturday_mirror_moves,
	saturday_name_rhythm,
	saturday_song_speeds,
	sunday,
	sunday_helper_plan,
	sunday_many_uses,
	sunday_routine_fixer,
	sunday_waste_less,
	sunday_water_saver,
	thursday,
	thursday_paper_boat,
	thursday_paper_flight,
	thursday_paper_shelter,
	thursday_paper_weave,
	thursday_strong_shapes,
	tuesday,
	tuesday_draw_from_memory,
	tuesday_list_tricks,
	tuesday_my_day_replay,
	tuesday_picnic_memory,
	tuesday_what_comes_next,
	wednesday,
	wednesday_character_card,
	wednesday_mystery_clues,
	wednesday_new_ending,
	wednesday_story_order,
	wednesday_what_if_place,
)

# slug -> what the child actually does (see activities.py); used to check that six templates are six different activities
ACTIVITIES = activities.ACTIVITIES

CATALOGUE_VARIATION_KEY = "c1"
AGE_BANDS = ("4_6", "7_10", "11_15")
LOCALES = ("en", "gu", "hi")

# Labels that introduce the two extra lines inside the stored text.
LABELS = {
	"parent_check": {"en": "Parent check:", "gu": "વાલી માટે ચકાસણી:", "hi": "अभिभावक के लिए जाँच:"},
	"another_way": {"en": "Another way:", "gu": "બીજી રીત:", "hi": "दूसरा तरीका:"},
}

MISSIONS: tuple[dict[str, Any], ...] = (
	monday.MISSION,
	tuesday.MISSION,
	wednesday.MISSION,
	thursday.MISSION,
	friday.MISSION,
	saturday.MISSION,
	sunday.MISSION,
	# second mission of each weekday theme (a different activity, same format)
	monday_look_closer.MISSION,
	tuesday_picnic_memory.MISSION,
	wednesday_mystery_clues.MISSION,
	thursday_paper_flight.MISSION,
	friday_kind_clues.MISSION,
	saturday_mirror_moves.MISSION,
	sunday_helper_plan.MISSION,
	# milestone C2 part 2: four more per theme, so six per theme (genuinely different activities, listed in activities.py)
	monday_loud_and_soft.MISSION,
	monday_sound_order.MISSION,
	monday_where_is_it.MISSION,
	monday_sound_words.MISSION,
	tuesday_draw_from_memory.MISSION,
	tuesday_what_comes_next.MISSION,
	tuesday_list_tricks.MISSION,
	tuesday_my_day_replay.MISSION,
	wednesday_story_order.MISSION,
	wednesday_new_ending.MISSION,
	wednesday_character_card.MISSION,
	wednesday_what_if_place.MISSION,
	thursday_strong_shapes.MISSION,
	thursday_paper_boat.MISSION,
	thursday_paper_shelter.MISSION,
	thursday_paper_weave.MISSION,
	friday_face_clues.MISSION,
	friday_feelings_in_stories.MISSION,
	friday_calm_words.MISSION,
	friday_listen_and_help.MISSION,
	saturday_name_rhythm.MISSION,
	saturday_home_band.MISSION,
	saturday_body_beats.MISSION,
	saturday_song_speeds.MISSION,
	sunday_water_saver.MISSION,
	sunday_waste_less.MISSION,
	sunday_routine_fixer.MISSION,
	sunday_many_uses.MISSION,
)


def instructions_text(locale: str, text: dict[str, Any]) -> str:
	steps = "\n".join(f"{number}. {step}" for number, step in enumerate(text["steps"], start=1))
	return f"{steps}\n{LABELS['another_way'][locale]} {text['alt']}"


def completion_text(locale: str, text: dict[str, Any]) -> str:
	return f"{text['show']}\n{LABELS['parent_check'][locale]} {text['parent_check']}"


def variation_payload(mission: dict[str, Any], age_band: str, locale: str) -> dict[str, Any]:
	"""Keyword arguments for ``DailyMissionVariationCreate`` (and the ``daily_mission_variations`` columns)."""
	age = mission["ages"][age_band]
	text = age["locales"][locale]
	return {
		"age_band": age_band,
		"locale": locale,
		"title": text["title"],
		"description": text["description"],
		"instructions": instructions_text(locale, text),
		"required_materials": list(text["materials"]),
		"duration_minutes": age["minutes"],
		"safety_instructions": text["safety"],
		"completion_criteria": completion_text(locale, text),
		"variation_key": CATALOGUE_VARIATION_KEY,
		# Structured instructions (migration 0019). ``show`` is the catalogue's own statement of what the child
		# produces, so it is the submission requirement. ``objective`` / ``observe`` are optional authored keys; where
		# a mission has none they stay None and the audit reports it. Nothing is written on the authors' behalf.
		"steps": list(text["steps"]),
		"submission_requirements": text["show"],
		"learning_objective": text.get("objective"),
		"observation_guidance": text.get("observe"),
	}


def template_payload(mission: dict[str, Any]) -> dict[str, Any]:
	return {
		"slug": mission["slug"],
		"theme": mission["theme"],
		"mission_type": mission["mission_type"],
		"is_surprise": False,
		"star_reward": mission["star_reward"],
		"xp_reward": mission["xp_reward"],
		"mystery_bonus": None,
	}
