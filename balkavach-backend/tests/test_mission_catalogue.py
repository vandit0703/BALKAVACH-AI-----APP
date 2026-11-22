"""The real localized daily-mission catalogue (milestone C1): completeness, scripts, age fit, safety, seeding.

Content tests need no database. Seeding and availability tests run on the in-memory SQLite "world"
(``tests/sqlite_world.py``): they prove the logic, **not** PostgreSQL behaviour.
"""

import copy
import re
import unicodedata
from datetime import date, datetime, timezone

import pytest

from app.content.daily_missions import (
	AGE_BANDS,
	CATALOGUE_VARIATION_KEY,
	LABELS,
	LOCALES,
	MISSIONS,
	variation_payload,
)
from app.core.exceptions import APIError
from app.schemas.daily_mission import DailyMissionAssignmentPublic, DailyMissionVariationCreate
from app.services.daily_mission_service import (
	THEMES_BY_WEEKDAY,
	_public,
	ensure_daily_choices,
	has_complete_localized_variations,
	select_assignment,
)
from app.services.mission_catalogue_service import (
	apply_catalogue,
	catalogue_summary,
	retire_placeholders,
	validate_catalogue,
)
from tests.sqlite_world import (
	DailyMissionTemplate,
	DailyMissionVariation,
	Task,
	make_family,
	world_session,  # noqa: F401  (fixture)
)

pytestmark = pytest.mark.usefixtures("standin_submit")  # the catalogue has no child-facing submit text yet (see conftest)

SCRIPT_PREFIX = {"gu": "GUJARATI", "hi": "DEVANAGARI"}


def _all_text(text: dict) -> list[str]:
	return [text[k] for k in ("title", "description", "alt", "safety", "show", "parent_check")] + list(text["steps"]) + list(text["materials"])


# -- completeness ---------------------------------------------------------------------------------

def test_every_weekday_theme_has_a_mission_for_all_age_bands_and_locales():
	themes = {m["theme"] for m in MISSIONS}
	assert themes == set(THEMES_BY_WEEKDAY.values())
	assert len(MISSIONS) == 42
	assert all(sum(m["theme"] == t for m in MISSIONS) == 6 for t in themes)
	for mission in MISSIONS:
		assert set(mission["ages"]) == set(AGE_BANDS)
		for age in mission["ages"].values():
			assert set(age["locales"]) == set(LOCALES)


def test_counts_match_the_published_inventory():
	assert catalogue_summary() == {
		"templates": 42, "themes": 7, "distinct_activities": 42, "variations": 378, "age_specific_missions": 126,
		"variations_en": 126, "variations_gu": 126, "variations_hi": 126,
	}


def test_the_catalogue_validates_clean():
	assert validate_catalogue() == []


def test_every_variation_is_accepted_by_the_admin_validator_and_has_all_mandatory_fields():
	for mission in MISSIONS:
		for age_band in AGE_BANDS:
			for locale in LOCALES:
				payload = variation_payload(mission, age_band, locale)
				DailyMissionVariationCreate(**payload)
				for field in ("title", "description", "instructions", "safety_instructions", "completion_criteria"):
					assert payload[field].strip(), (mission["slug"], age_band, locale, field)
				assert payload["required_materials"] and 5 <= payload["duration_minutes"] <= 15
				assert payload["variation_key"] == CATALOGUE_VARIATION_KEY


def test_the_nine_combinations_of_each_template_satisfy_the_admin_publish_rule():
	rows = [(a, loc) for a in AGE_BANDS for loc in LOCALES]
	assert has_complete_localized_variations(rows)
	assert not has_complete_localized_variations(rows[:-1])


def test_each_mission_records_skill_rationale_and_parent_involvement():
	for mission in MISSIONS:
		assert mission["skill"]
		for age in mission["ages"].values():
			assert len(age["rationale"]) > 40 and age["parent_involvement"]


# -- scripts and translations ------------------------------------------------------------------------

@pytest.mark.parametrize("locale", ["gu", "hi"])
def test_gujarati_and_hindi_are_written_in_their_own_script_not_romanised(locale):
	checked = 0
	for mission in MISSIONS:
		for age in mission["ages"].values():
			for value in _all_text(age["locales"][locale]):
				letters = [c for c in value if c.isalpha()]
				assert letters, value
				for char in letters:
					name = unicodedata.name(char)
					# Latin is allowed only for the rhythm symbols X (clap) and O (tap)
					assert name.startswith(SCRIPT_PREFIX[locale]) or char in "XO", (locale, mission["slug"], value[:40], char)
				assert any(unicodedata.name(c).startswith(SCRIPT_PREFIX[locale]) for c in letters)
				checked += 1
	assert checked == len(MISSIONS) * 3 * 6 + sum(
		len(a["locales"][locale]["steps"]) + len(a["locales"][locale]["materials"]) for m in MISSIONS for a in m["ages"].values()
	)


def test_english_text_is_plain_ascii():
	for mission in MISSIONS:
		for age in mission["ages"].values():
			for value in _all_text(age["locales"]["en"]):
				assert value.isascii(), value


def test_translations_match_the_english_in_structure_and_numbers():
	for mission in MISSIONS:
		for age_band, age in mission["ages"].items():
			en = age["locales"]["en"]
			for locale in ("gu", "hi"):
				other = age["locales"][locale]
				assert len(other["steps"]) == len(en["steps"]), (mission["slug"], age_band, locale)
				assert len(other["materials"]) == len(en["materials"]), (mission["slug"], age_band, locale)
				for en_step, step in zip(en["steps"], other["steps"]):
					assert sorted(re.findall(r"\d+", en_step)) == sorted(re.findall(r"\d+", step)), (en_step, step)
				assert sorted(re.findall(r"\d+", en["show"])) == sorted(re.findall(r"\d+", other["show"]))


def test_localized_labels_for_parent_check_and_alternative_are_in_the_stored_text():
	for mission in MISSIONS:
		for age_band in AGE_BANDS:
			for locale in LOCALES:
				payload = variation_payload(mission, age_band, locale)
				assert payload["completion_criteria"].splitlines()[-1].startswith(LABELS["parent_check"][locale])
				assert payload["instructions"].splitlines()[-1].startswith(LABELS["another_way"][locale])


def test_titles_are_unique_per_locale_across_the_whole_catalogue():
	for locale in LOCALES:
		titles = [a["locales"][locale]["title"] for m in MISSIONS for a in m["ages"].values()]
		assert len(titles) == len(set(titles)) == 126


# -- age appropriateness -------------------------------------------------------------------------------

def test_age_bands_have_genuinely_different_instructions_not_relabelled_copies():
	def words(value):
		return set(value.lower().split())

	for mission in MISSIONS:
		by_age = {a: " ".join(mission["ages"][a]["locales"]["en"]["steps"]) for a in AGE_BANDS}
		for first, second in (("4_6", "7_10"), ("7_10", "11_15"), ("4_6", "11_15")):
			overlap = len(words(by_age[first]) & words(by_age[second])) / len(words(by_age[first]) | words(by_age[second]))
			assert overlap < 0.6, (mission["slug"], first, second, overlap)


def test_effort_grows_with_age_without_exceeding_the_time_budget():
	for mission in MISSIONS:
		minutes = [mission["ages"][a]["minutes"] for a in AGE_BANDS]
		assert minutes == sorted(minutes) and max(minutes) <= 15 and min(minutes) >= 5


def test_memory_master_follows_the_three_six_and_positions_progression():
	memory = next(m for m in MISSIONS if m["theme"] == "tuesday_memory_master")
	young, middle, older = (" ".join(memory["ages"][a]["locales"]["en"]["steps"]).lower() for a in AGE_BANDS)
	assert "three" in young and "10 seconds" in young
	assert "six" in middle and "20 seconds" in middle
	assert "arrangement" in older and "next to" in older and "8 " in older


def test_young_children_always_work_with_a_grown_up_nearby():
	for mission in MISSIONS:
		young = mission["ages"]["4_6"]["locales"]["en"]
		text = " ".join([*young["steps"], young["safety"], young["parent_check"]]).lower()
		assert "grown-up" in text, mission["slug"]


def test_each_mission_offers_an_accessible_alternative():
	for mission in MISSIONS:
		for age in mission["ages"].values():
			for text in age["locales"].values():
				assert len(text["alt"]) > 25


def test_feelings_missions_never_require_a_child_to_share_a_reason_or_a_diary():
	friday = next(m for m in MISSIONS if m["theme"] == "friday_emotion_detective")
	for age in friday["ages"].values():
		text = age["locales"]["en"]
		joined = " ".join([*text["steps"], text["parent_check"], text["safety"]]).lower()
		assert any(
			phrase in joined
			for phrase in ("do not want", "can skip", "you decide what to share", "share only", "stays private", "do not read", "would rather not")
		)


# -- safety / content rules ---------------------------------------------------------------------------

def test_no_mission_asks_for_unsafe_tools_permissions_purchases_or_links():
	forbidden = ("scissors", "knife", "blade", "fire", "candle", "matches", "chemical", "stove", "oven", "climb", "camera", "photo", "microphone", "location", "buy", "purchase", "http", "www", "stranger")
	for mission in MISSIONS:
		for age in mission["ages"].values():
			text = age["locales"]["en"]
			asked = " ".join([*text["steps"], text["alt"], text["show"], text["parent_check"], *text["materials"]]).lower()
			for word in forbidden:
				assert not re.search(rf"\b{word}", asked), (mission["slug"], word)


def test_every_safety_note_is_present_and_substantive_in_every_language():
	for mission in MISSIONS:
		for age in mission["ages"].values():
			for locale, text in age["locales"].items():
				assert len(text["safety"]) > 40, (mission["slug"], locale)


def test_stored_task_text_stays_within_the_limit_used_for_the_parent_visible_task():
	for mission in MISSIONS:
		for age_band in AGE_BANDS:
			for locale in LOCALES:
				p = variation_payload(mission, age_band, locale)
				assert len(p["description"]) + len(p["instructions"]) + len(p["completion_criteria"]) <= 1900


# -- the validator really rejects bad content --------------------------------------------------------

def _mutated(edit) -> list[str]:
	missions = copy.deepcopy(list(MISSIONS))
	edit(missions)
	return validate_catalogue(missions)


def test_validator_flags_romanised_gujarati():
	problems = _mutated(lambda m: m[0]["ages"]["4_6"]["locales"]["gu"].update(title="Tran avaj ni shodh"))
	assert any("Latin" in p and "gu" in p for p in problems)


def test_validator_flags_a_missing_translation():
	problems = _mutated(lambda m: m[1]["ages"]["7_10"]["locales"].pop("hi"))
	assert any("locales" in p for p in problems)


def test_validator_flags_a_missing_instruction_step_and_empty_fields():
	assert any("steps" in p for p in _mutated(lambda m: m[2]["ages"]["4_6"]["locales"]["en"].update(steps=["Only one."])))
	assert any("safety missing" in p for p in _mutated(lambda m: m[2]["ages"]["4_6"]["locales"]["en"].update(safety="  ")))
	assert any("parent_check missing" in p for p in _mutated(lambda m: m[2]["ages"]["4_6"]["locales"]["gu"].update(parent_check="")))


def test_validator_flags_a_missing_theme_and_a_missing_age_band():
	assert any("no mission" in p for p in validate_catalogue([m for m in MISSIONS if m["theme"] != "sunday_future_inventor"]))
	assert any("age bands" in p for p in _mutated(lambda m: m[0]["ages"].pop("11_15")))


def test_validator_flags_unsafe_content_in_every_language():
	def add(index, locale, step):
		return _mutated(lambda m: m[index]["ages"]["7_10"]["locales"][locale]["steps"].append(step))

	assert any("unsafe" in p for p in add(3, "en", "Cut the paper with scissors."))
	assert any("unsafe" in p for p in add(3, "gu", "કાતરથી કાગળ કાપો."))
	assert any("unsafe" in p for p in add(3, "hi", "चाकू से कागज़ काटो।"))
	assert any("unsafe" in p or "rejected" in p for p in add(0, "en", "Share your location with the app."))
	assert any("unsafe" in p for p in _mutated(lambda m: m[0]["ages"]["4_6"]["locales"]["en"]["materials"].append("Buy a drum.")))


def test_validator_does_not_confuse_everyday_words_with_unsafe_ones():
	# 'આગલી' (next) and 'आगे' (ahead) merely begin with the word for fire
	text = copy.deepcopy(list(MISSIONS))
	text[0]["ages"]["4_6"]["locales"]["gu"]["steps"][0] += " આગલી વાર."
	text[0]["ages"]["4_6"]["locales"]["hi"]["steps"][0] += " आगे बढ़ो।"
	assert not any("unsafe" in p for p in validate_catalogue(text))


def test_validator_flags_pressure_wording_bad_duration_duplicates_and_long_text():
	assert any("pressure" in p for p in _mutated(lambda m: m[0]["ages"]["4_6"]["locales"]["en"].update(description="Be the fastest listener!")))
	assert any("duration" in p for p in _mutated(lambda m: m[0]["ages"]["4_6"].update(minutes=40)))
	assert any(
		"title also used" in p
		for p in _mutated(lambda m: m[1]["ages"]["4_6"]["locales"]["en"].update(title=m[0]["ages"]["4_6"]["locales"]["en"]["title"]))
	)
	assert any("characters of task text" in p for p in _mutated(lambda m: m[0]["ages"]["4_6"]["locales"]["en"].update(description="x" * 2000)))
	assert any("step counts differ" in p for p in _mutated(lambda m: m[0]["ages"]["4_6"]["locales"]["hi"]["steps"].pop()))


def test_validator_flags_a_slug_that_collides_with_a_migration_placeholder():
	assert any("placeholder" in p for p in _mutated(lambda m: m[0].update(slug="monday_sound_detective_2")))


# -- seeding (SQLite world) --------------------------------------------------------------------------------

def _counts(session):
	return session.query(DailyMissionTemplate).count(), session.query(DailyMissionVariation).count()


def test_seeding_creates_everything_once_and_is_idempotent(world_session):
	first = apply_catalogue(world_session)
	world_session.commit()
	assert first["templates_created"] == 42 and first["variations_created"] == 378
	assert _counts(world_session) == (42, 378)
	second = apply_catalogue(world_session)
	world_session.commit()
	assert (second["templates_created"], second["variations_created"]) == (0, 0)
	assert second["templates_existing"] == 42 and second["variations_existing"] == 378 and second["variations_differing"] == []
	assert _counts(world_session) == (42, 378)


def test_seeding_creates_unpublished_templates_unless_asked(world_session):
	apply_catalogue(world_session)
	assert world_session.query(DailyMissionTemplate).filter(DailyMissionTemplate.is_published.is_(True)).count() == 0


def test_publish_flag_publishes_the_forty_two_created_templates(world_session):
	report = apply_catalogue(world_session, publish=True)
	assert report["published"] == 42
	assert world_session.query(DailyMissionTemplate).filter(DailyMissionTemplate.is_published.is_(True)).count() == 42


def test_seeding_never_overwrites_an_edited_variation_and_reports_it(world_session):
	apply_catalogue(world_session)
	row = world_session.query(DailyMissionVariation).filter(DailyMissionVariation.locale == "gu").first()
	row.title = "Admin's own title"
	world_session.commit()
	report = apply_catalogue(world_session)
	assert len(report["variations_differing"]) == 1
	world_session.refresh(row)
	assert row.title == "Admin's own title"


def test_seeding_leaves_an_existing_template_and_its_publish_state_alone(world_session):
	existing = DailyMissionTemplate(slug=MISSIONS[0]["slug"], theme="custom_theme", mission_type="creative", is_published=True, star_reward=9, xp_reward=99)
	world_session.add(existing)
	world_session.commit()
	report = apply_catalogue(world_session, publish=True)
	world_session.refresh(existing)
	assert (existing.theme, existing.star_reward, existing.is_published) == ("custom_theme", 9, True)
	assert report["templates_created"] == 41 and report["templates_existing"] == 1


def test_seeding_refuses_an_invalid_catalogue_and_writes_nothing(world_session):
	broken = copy.deepcopy(list(MISSIONS))
	broken[0]["ages"]["4_6"]["locales"]["gu"]["title"] = "romanised title"
	with pytest.raises(ValueError):
		apply_catalogue(world_session, broken)
	assert _counts(world_session) == (0, 0)


def test_seeding_coexists_with_existing_placeholder_content_and_retiring_it_is_explicit(world_session):
	placeholder = DailyMissionTemplate(slug="monday_sound_detective", theme="monday_sound_detective", mission_type="offline", is_published=True)
	edited = DailyMissionTemplate(slug="tuesday_memory_master", theme="tuesday_memory_master", mission_type="interactive", is_published=True)
	world_session.add_all([placeholder, edited])
	world_session.flush()
	placeholder_text = {
		"en": "Try the steps, notice what you discover, and tell a trusted grown-up what you learned.",
		"gu": "Pagala ajmavo, shu malyu te dhyanthi juo ane vishvasu mota vyaktine kaho.",
		"hi": "Kadam aazmaiye, jo dekha use dhyan se samajhiye aur kisi bharosemand bade ko batayiye.",
	}
	for locale, text in placeholder_text.items():
		world_session.add(DailyMissionVariation(template_id=placeholder.id, age_band="4_6", locale=locale, instructions=text))
	world_session.add(DailyMissionVariation(template_id=edited.id, age_band="4_6", locale="en", instructions="An administrator wrote this."))
	world_session.commit()

	apply_catalogue(world_session, publish=True)
	world_session.refresh(placeholder)
	assert placeholder.is_published is True  # seeding alone never touches existing content

	report = retire_placeholders(world_session)
	world_session.commit()
	assert report["unpublished"] == ["monday_sound_detective"] and report["kept_edited"] == ["tuesday_memory_master"]
	world_session.refresh(placeholder)
	assert placeholder.is_published is False
	assert world_session.query(DailyMissionTemplate).filter(DailyMissionTemplate.slug == "monday_sound_detective").count() == 1  # nothing deleted
	assert retire_placeholders(world_session)["unpublished"] == []  # idempotent


# -- what a child receives -------------------------------------------------------------------------------------

def _published_world(session):
	apply_catalogue(session, publish=True)
	session.commit()


AGE_CASES = [(date(2021, 3, 1), "4_6"), (date(2017, 5, 1), "7_10"), (date(2012, 5, 1), "11_15")]
NOW = datetime(2026, 11, 18, 9, 0, tzinfo=timezone.utc)  # a Wednesday


@pytest.mark.parametrize("birth, band", AGE_CASES)
@pytest.mark.parametrize("language", LOCALES)
def test_each_child_gets_three_distinct_choices_in_their_age_band_and_language(world_session, birth, band, language):
	_published_world(world_session)
	child = make_family(world_session, birth=birth, language=language)
	_, age_band, choices = ensure_daily_choices(world_session, child, NOW)
	assert age_band == band and len(choices) == 3 and len({c.template_id for c in choices}) == 3
	for choice in choices:
		slug = world_session.get(DailyMissionTemplate, choice.template_id).slug
		mission = next(m for m in MISSIONS if m["slug"] == slug)
		expected = variation_payload(mission, band, language)
		assert choice.snapshot["locale"] == language
		assert choice.snapshot["title"] == expected["title"]
		assert choice.snapshot["instructions"] == expected["instructions"]
		DailyMissionAssignmentPublic(**_public(choice))  # the public API model accepts the seeded content


def test_the_weekday_theme_is_offered(world_session):
	_published_world(world_session)
	child = make_family(world_session, language="en")
	_, _, choices = ensure_daily_choices(world_session, child, NOW)  # a Wednesday
	assert "wednesday_magic_story_maker" in {c.snapshot["theme"] for c in choices}


def test_an_unsupported_language_falls_back_to_english(world_session):
	_published_world(world_session)
	child = make_family(world_session, language="fr")
	_, _, choices = ensure_daily_choices(world_session, child, NOW)
	assert {c.snapshot["locale"] for c in choices} == {"en"}


def test_unpublished_catalogue_is_never_offered(world_session):
	apply_catalogue(world_session)  # created unpublished
	world_session.commit()
	child = make_family(world_session)
	with pytest.raises(APIError) as error:
		ensure_daily_choices(world_session, child, NOW)
	assert error.value.code == "daily_missions_unavailable"


def test_selecting_a_mission_gives_the_parent_the_instructions_and_the_parent_check(world_session):
	_published_world(world_session)
	child = make_family(world_session, language="hi")
	_, _, choices = ensure_daily_choices(world_session, child, NOW)
	picked = select_assignment(world_session, child, choices[0].id)
	world_session.commit()
	task = world_session.get(Task, picked.task_id)
	assert picked.snapshot["completion_criteria"].splitlines()[-1] in task.description
	assert LABELS["parent_check"]["hi"] in task.description
	assert picked.snapshot["instructions"] in task.description


# -- expansion batch (milestone C2): variety, not rewritten titles -------------------------------------------------

def test_missions_in_the_same_theme_are_different_activities_not_reworded_titles():
	by_theme: dict[str, list] = {}
	for mission in MISSIONS:
		by_theme.setdefault(mission["theme"], []).append(mission)

	stop = {
		"a", "an", "the", "and", "to", "of", "in", "it", "you", "your", "for", "on", "with", "at", "is", "are", "or", "then",
		"that", "this", "each", "one", "do", "can", "as", "about", "until", "every", "from", "by", "up", "out", "them", "they",
	}

	def words(mission, age_band):
		text = " ".join(mission["ages"][age_band]["locales"]["en"]["steps"]).lower()
		return set(re.findall(r"[a-z]+", text)) - stop

	for theme, missions in by_theme.items():
		assert len(missions) >= 2, theme
		for index, first in enumerate(missions):
			for second in missions[index + 1:]:
				assert first["slug"] != second["slug"]
				for age_band in AGE_BANDS:
					a, b = words(first, age_band), words(second, age_band)
					assert len(a & b) / len(a | b) < 0.4, (theme, first["slug"], second["slug"], age_band)


def test_completion_criteria_and_parent_checks_are_not_repeated_across_the_catalogue():
	for locale in LOCALES:
		shows, checks = [], []
		for mission in MISSIONS:
			for age in mission["ages"].values():
				shows.append(age["locales"][locale]["show"])
				checks.append(age["locales"][locale]["parent_check"])
		assert len(shows) == len(set(shows)), locale
		assert len(checks) == len(set(checks)), locale


def test_every_new_template_has_all_three_age_bands_and_three_languages_with_numbered_steps():
	for mission in MISSIONS:
		for age_band in AGE_BANDS:
			for locale in LOCALES:
				payload = variation_payload(mission, age_band, locale)
				lines = [line for line in payload["instructions"].splitlines()[:-1]]
				assert all(line.startswith(f"{number}. ") for number, line in enumerate(lines, start=1)), (mission["slug"], age_band, locale)


def test_each_slug_is_unique_and_none_collides_with_the_migration_placeholders():
	slugs = [m["slug"] for m in MISSIONS]
	assert len(slugs) == len(set(slugs)) == 42
	assert all(slug.startswith("cat1_") for slug in slugs)
