"""The 42-template catalogue (milestone C2, part 2): size, distinct activities, scripts, seeding and health.

Content tests need no database. Seeding, health and rotation tests run on the in-memory SQLite "world"
(``tests/sqlite_world.py``): they prove the logic, **not** PostgreSQL behaviour.
"""

import copy
import re
from collections import Counter, defaultdict
from datetime import datetime, timedelta, timezone

import pytest

from app.content.daily_missions import (
	ACTIVITIES,
	AGE_BANDS,
	CATALOGUE_VARIATION_KEY,
	LOCALES,
	MISSIONS,
	variation_payload,
)
from app.services import mission_catalogue_service as service
from app.services.daily_mission_service import THEMES_BY_WEEKDAY, ensure_daily_choices, select_assignment
from app.services.mission_catalogue_service import (
	apply_catalogue,
	catalogue_health,
	catalogue_summary,
	distinct_activity_problems,
	target_problems,
	validate_catalogue,
)
from tests.sqlite_world import (
	DailyMissionTemplate,
	DailyMissionVariation,
	make_family,
	world_session,  # noqa: F401  (fixture)
)

# The 14 templates seeded before this milestone. Their slugs and rewards must never change.
ORIGINAL_SLUGS = (
	"cat1_monday_sound_detective", "cat1_tuesday_memory_master", "cat1_wednesday_magic_story_maker",
	"cat1_thursday_paper_architect", "cat1_friday_emotion_detective", "cat1_saturday_rhythm_rockstar",
	"cat1_sunday_future_inventor", "cat1_monday_look_closer", "cat1_tuesday_picnic_memory",
	"cat1_wednesday_mystery_clues", "cat1_thursday_paper_flight", "cat1_friday_kind_clues",
	"cat1_saturday_mirror_moves", "cat1_sunday_helper_plan",
)
GUJARATI = re.compile(r"[઀-૿]")
DEVANAGARI = re.compile(r"[ऀ-ॿ]")
NOW = datetime(2026, 11, 23, 9, 0, tzinfo=timezone.utc)  # a Monday


# -- size and structure ------------------------------------------------------------------------------------

def test_exactly_42_unique_templates_and_no_duplicate_slugs():
	slugs = [m["slug"] for m in MISSIONS]
	assert len(slugs) == len(set(slugs)) == 42
	assert all(slug.startswith("cat1_") for slug in slugs)


def test_six_templates_in_each_of_the_seven_weekday_themes():
	counts = Counter(m["theme"] for m in MISSIONS)
	assert set(counts) == set(THEMES_BY_WEEKDAY.values())
	assert set(counts.values()) == {6}
	assert target_problems() == []


def test_126_age_specific_variations_and_378_localized_versions():
	age_specific = [(m["slug"], age) for m in MISSIONS for age in m["ages"]]
	assert len(age_specific) == len(set(age_specific)) == 126
	versions = [(m["slug"], age, locale) for m in MISSIONS for age in AGE_BANDS for locale in LOCALES]
	assert len(versions) == len(set(versions)) == 378
	assert Counter(locale for _, _, locale in versions) == {"en": 126, "gu": 126, "hi": 126}
	summary = catalogue_summary()
	assert (summary["templates"], summary["age_specific_missions"], summary["variations"]) == (42, 126, 378)
	assert (summary["variations_en"], summary["variations_gu"], summary["variations_hi"]) == (126, 126, 126)


def test_the_original_fourteen_keep_their_slugs_order_and_rewards():
	assert tuple(m["slug"] for m in MISSIONS[:14]) == ORIGINAL_SLUGS
	assert {(m["star_reward"], m["xp_reward"], m["is_surprise"] if "is_surprise" in m else False) for m in MISSIONS} == {(1, 10, False)}


def test_every_template_has_every_required_field_in_all_nine_versions():
	for mission in MISSIONS:
		assert mission["skill"] and mission["mission_type"] in {"offline", "interactive", "creative"}
		for age_band in AGE_BANDS:
			age = mission["ages"][age_band]
			assert 5 <= age["minutes"] <= 15 and age["rationale"].strip() and age["parent_involvement"].strip()
			for locale in LOCALES:
				payload = variation_payload(mission, age_band, locale)
				for field in ("title", "description", "instructions", "safety_instructions", "completion_criteria"):
					assert payload[field].strip(), (mission["slug"], age_band, locale, field)
				assert payload["required_materials"] and payload["variation_key"] == CATALOGUE_VARIATION_KEY
				lines = payload["instructions"].splitlines()
				assert all(line.startswith(f"{n}. ") for n, line in enumerate(lines[:-1], start=1))
				assert len(lines) - 1 >= 3


def test_the_catalogue_validates_clean_with_the_distinct_activity_checks():
	assert validate_catalogue() == []


# -- scripts and translations ------------------------------------------------------------------------------

def test_gujarati_uses_gujarati_script_and_hindi_uses_devanagari_never_the_other():
	for mission in MISSIONS:
		for age in mission["ages"].values():
			for field in ("title", "description", "alt", "safety", "show", "parent_check"):
				gu, hi = age["locales"]["gu"][field], age["locales"]["hi"][field]
				assert GUJARATI.search(gu) and not DEVANAGARI.search(gu), (mission["slug"], field, gu[:30])
				assert DEVANAGARI.search(hi) and not GUJARATI.search(hi), (mission["slug"], field, hi[:30])
			for step in age["locales"]["gu"]["steps"]:
				assert GUJARATI.search(step) and not DEVANAGARI.search(step), (mission["slug"], step[:30])
			for step in age["locales"]["hi"]["steps"]:
				assert DEVANAGARI.search(step) and not GUJARATI.search(step), (mission["slug"], step[:30])


def test_no_gujarati_or_hindi_field_is_a_copy_of_the_english_or_of_the_other_language():
	for mission in MISSIONS:
		for age in mission["ages"].values():
			en, gu, hi = (age["locales"][locale] for locale in LOCALES)
			for field in ("title", "description", "alt", "safety", "show", "parent_check"):
				assert len({en[field], gu[field], hi[field]}) == 3, (mission["slug"], field)


def test_translations_agree_on_steps_materials_and_every_number():
	for mission in MISSIONS:
		for age_band, age in mission["ages"].items():
			en = age["locales"]["en"]
			for locale in ("gu", "hi"):
				other = age["locales"][locale]
				where = (mission["slug"], age_band, locale)
				assert len(other["steps"]) == len(en["steps"]), where
				assert len(other["materials"]) == len(en["materials"]), where
				for en_step, step in zip(en["steps"], other["steps"]):
					assert sorted(re.findall(r"\d+", en_step)) == sorted(re.findall(r"\d+", step)), (where, step[:40])
				assert sorted(re.findall(r"\d+", en["show"])) == sorted(re.findall(r"\d+", other["show"])), where
				assert sorted(re.findall(r"\d+", en["parent_check"])) == sorted(re.findall(r"\d+", other["parent_check"])), where


def test_every_parent_check_tells_the_parent_what_to_do_in_every_language():
	for mission in MISSIONS:
		for age_band in AGE_BANDS:
			for locale in LOCALES:
				payload = variation_payload(mission, age_band, locale)
				last = payload["completion_criteria"].splitlines()[-1]
				assert len(last) > 60, (mission["slug"], age_band, locale)


# -- genuinely different activities ------------------------------------------------------------------------

def test_every_template_records_a_distinct_activity():
	slugs = {m["slug"] for m in MISSIONS}
	assert set(ACTIVITIES) == slugs  # no missing entry, no entry for a template that does not exist
	mechanics = [ACTIVITIES[slug]["mechanic"] for slug in sorted(slugs)]
	assert len(mechanics) == len(set(mechanics)) == 42
	assert all(ACTIVITIES[slug]["summary"].strip() and ACTIVITIES[slug]["evidence"] in {"guide_activity_type", "design_assumption"} for slug in slugs)
	assert catalogue_summary()["distinct_activities"] == 42


def test_the_six_activities_of_each_theme_have_six_different_summaries_and_titles():
	by_theme = defaultdict(list)
	for mission in MISSIONS:
		by_theme[mission["theme"]].append(mission)
	for theme, group in by_theme.items():
		summaries = {ACTIVITIES[m["slug"]]["summary"] for m in group}
		assert len(summaries) == 6, theme
		for age_band in AGE_BANDS:
			titles = {m["ages"][age_band]["locales"]["en"]["title"] for m in group}
			assert len(titles) == 6, (theme, age_band)


def _words(mission, age_band):
	steps = " ".join(mission["ages"][age_band]["locales"]["en"]["steps"]).lower()
	return set(re.findall(r"[a-z]+", steps)) - service._STEP_STOP_WORDS


def test_no_two_templates_are_the_same_activity_reworded():
	"""Within a theme the English steps share under 40% of their words in every age band; across the catalogue under 50%."""
	worst_theme = worst_all = 0.0
	for index, first in enumerate(MISSIONS):
		for second in MISSIONS[index + 1:]:
			for age_band in AGE_BANDS:
				a, b = _words(first, age_band), _words(second, age_band)
				overlap = len(a & b) / len(a | b)
				worst_all = max(worst_all, overlap)
				if first["theme"] == second["theme"]:
					worst_theme = max(worst_theme, overlap)
					assert overlap < service.MAX_STEP_SIMILARITY, (first["slug"], second["slug"], age_band, overlap)
				assert overlap < 0.5, (first["slug"], second["slug"], age_band, overlap)
	assert worst_theme < 0.4 and worst_all < 0.5


def test_the_validator_rejects_a_template_that_is_an_existing_activity_in_new_words():
	missions = copy.deepcopy(list(MISSIONS))
	clone = copy.deepcopy(missions[7])  # Look-Closer Hunt
	clone["slug"] = "cat1_monday_look_closer_again"
	clone["ages"]["4_6"]["locales"]["en"]["title"] = "A Different Title"
	missions.append(clone)
	problems = distinct_activity_problems(missions)
	assert any("no activity entry" in p and "look_closer_again" in p for p in problems)
	# even with a (dishonest) new mechanic key the near-identical steps are caught
	monkey = {**ACTIVITIES, "cat1_monday_look_closer_again": {"mechanic": "new_key", "summary": "x", "evidence": "design_assumption"}}
	original = service.ACTIVITIES
	service.ACTIVITIES = monkey
	try:
		problems = distinct_activity_problems(missions)
	finally:
		service.ACTIVITIES = original
	assert any("near-identical" in p and "look_closer_again" in p for p in problems)


def test_the_validator_rejects_a_repeated_mechanic_and_a_theme_short_of_six():
	missions = copy.deepcopy(list(MISSIONS))
	service.ACTIVITIES["cat1_monday_where_is_it"]["mechanic"] = ACTIVITIES["cat1_monday_loud_and_soft"]["mechanic"]
	try:
		assert any("same activity mechanic" in p for p in distinct_activity_problems(missions))
		assert any("distinct activities" in p for p in target_problems(missions))
	finally:
		service.ACTIVITIES["cat1_monday_where_is_it"]["mechanic"] = "locate_sound_and_barriers"
	assert any("5 templates, target 6" in p for p in target_problems([m for m in missions if m["slug"] != "cat1_sunday_many_uses"]))


# -- seeding -----------------------------------------------------------------------------------------------

def _counts(session):
	return session.query(DailyMissionTemplate).count(), session.query(DailyMissionVariation).count()


def test_seeding_the_expanded_catalogue_twice_creates_no_duplicates(world_session):
	first = apply_catalogue(world_session)
	world_session.commit()
	assert (first["templates_created"], first["variations_created"]) == (42, 378)
	again = apply_catalogue(world_session)
	world_session.commit()
	assert (again["templates_created"], again["variations_created"]) == (0, 0)
	assert (again["templates_existing"], again["variations_existing"], again["variations_differing"]) == (42, 378, [])
	assert _counts(world_session) == (42, 378)
	slugs = [t.slug for t in world_session.query(DailyMissionTemplate).all()]
	assert len(slugs) == len(set(slugs))


def test_seeding_on_top_of_the_fourteen_template_database_adds_only_the_new_28_and_leaves_old_rows_alone(world_session):
	older = [m for m in MISSIONS if m["slug"] in ORIGINAL_SLUGS]
	apply_catalogue(world_session, older, publish=True)
	world_session.commit()
	assert _counts(world_session) == (14, 126)
	snapshot = {
		(row.template_id, row.age_band, row.locale): (row.title, row.instructions, row.completion_criteria, row.duration_minutes)
		for row in world_session.query(DailyMissionVariation).all()
	}
	published_before = {t.slug: t.is_published for t in world_session.query(DailyMissionTemplate).all()}
	rewards_before = {t.slug: (t.star_reward, t.xp_reward) for t in world_session.query(DailyMissionTemplate).all()}
	report = apply_catalogue(world_session)  # no --publish
	world_session.commit()
	assert (report["templates_created"], report["variations_created"], report["templates_existing"]) == (28, 252, 14)
	assert _counts(world_session) == (42, 378)
	for row in world_session.query(DailyMissionVariation).all():
		key = (row.template_id, row.age_band, row.locale)
		if key in snapshot:
			assert snapshot[key] == (row.title, row.instructions, row.completion_criteria, row.duration_minutes)
	for template in world_session.query(DailyMissionTemplate).all():
		if template.slug in published_before:
			assert template.is_published is published_before[template.slug]  # old templates keep their publish state
			assert (template.star_reward, template.xp_reward) == rewards_before[template.slug]
		else:
			assert template.is_published is False  # the 28 new ones start unpublished
	assert world_session.query(DailyMissionTemplate).filter(DailyMissionTemplate.is_published.is_(True)).count() == 14


def test_an_admin_edit_to_an_old_or_new_variation_survives_the_expansion(world_session):
	apply_catalogue(world_session, [m for m in MISSIONS if m["slug"] in ORIGINAL_SLUGS])
	old = world_session.query(DailyMissionVariation).filter(DailyMissionVariation.locale == "hi").first()
	old.title = "Edited by an administrator"
	world_session.commit()
	apply_catalogue(world_session)
	new_row = (
		world_session.query(DailyMissionVariation)
		.join(DailyMissionTemplate, DailyMissionTemplate.id == DailyMissionVariation.template_id)
		.filter(DailyMissionTemplate.slug == "cat1_sunday_many_uses", DailyMissionVariation.locale == "gu", DailyMissionVariation.age_band == "11_15")
		.one()
	)
	new_row.title = "Another edit"
	world_session.commit()
	report = apply_catalogue(world_session)
	assert len(report["variations_differing"]) == 2 and (report["templates_created"], report["variations_created"]) == (0, 0)
	world_session.refresh(old)
	world_session.refresh(new_row)
	assert (old.title, new_row.title) == ("Edited by an administrator", "Another edit")


def test_new_templates_are_published_only_with_all_nine_versions(world_session):
	apply_catalogue(world_session)
	template = world_session.query(DailyMissionTemplate).filter(DailyMissionTemplate.slug == "cat1_friday_calm_words").one()
	world_session.query(DailyMissionVariation).filter(
		DailyMissionVariation.template_id == template.id, DailyMissionVariation.locale == "hi", DailyMissionVariation.age_band == "7_10"
	).delete()
	world_session.commit()
	health = catalogue_health(world_session, NOW)
	assert "cat1_friday_calm_words" in next(t for t in health["themes"] if t["theme"] == "friday_emotion_detective")["incomplete"]
	assert health["totals"]["incomplete"] == 1 and health["totals"]["complete"] == 41


# -- health ------------------------------------------------------------------------------------------------

def _publish_all(session):
	apply_catalogue(session, publish=True)
	session.commit()


def test_health_of_the_full_catalogue_is_green_and_counts_are_exact(world_session):
	_publish_all(world_session)
	health = catalogue_health(world_session, NOW)
	assert health["warnings"] == [] and health["activity_warnings"] == []
	assert health["totals"] == {
		"templates": 42, "published": 42, "unpublished": 0, "complete": 42, "incomplete": 0, "never_assigned": 42, "most_assigned": 0,
	}
	assert len(health["themes"]) == 7
	for theme in health["themes"]:
		assert (theme["templates"], theme["published"], theme["eligible"], theme["verified_distinct"]) == (6, 6, 6, 6)
		assert theme["healthy"] is True and theme["insufficient"] is False and theme["unverified"] == [] and theme["duplicate_activities"] == []
		assert theme["age_bands"] == {"4_6": 6, "7_10": 6, "11_15": 6} and theme["locales"] == {"en": 6, "gu": 6, "hi": 6}


def test_unpublished_templates_lower_the_published_count_and_raise_a_capacity_warning(world_session):
	_publish_all(world_session)
	for slug in ("cat1_monday_sound_words", "cat1_monday_where_is_it"):
		world_session.query(DailyMissionTemplate).filter(DailyMissionTemplate.slug == slug).one().is_published = False
	world_session.commit()
	health = catalogue_health(world_session, NOW)
	assert health["totals"]["published"] == 40 and health["totals"]["unpublished"] == 2
	monday = health["themes"][0]
	assert (monday["published"], monday["eligible"], monday["shortfall"], monday["healthy"]) == (4, 4, 2, False)
	assert len(health["warnings"]) == 1 and "monday_sound_detective" in health["warnings"][0]
	assert health["activity_warnings"] == []  # the capacity warning already covers this


def test_six_database_rows_are_not_healthy_unless_they_are_six_distinct_activities(world_session):
	# six complete, published rows that the catalogue source does not know about: capacity is fine, activities are unverified
	theme = "monday_sound_detective"
	for index in range(6):
		template = DailyMissionTemplate(slug=f"admin_own_{index}", theme=theme, mission_type="offline", is_published=True)
		world_session.add(template)
		world_session.flush()
		for age_band in AGE_BANDS:
			for locale in LOCALES:
				world_session.add(DailyMissionVariation(template_id=template.id, age_band=age_band, locale=locale, title=f"t{index}"))
	world_session.commit()
	health = catalogue_health(world_session, NOW)
	monday = health["themes"][0]
	assert (monday["eligible"], monday["insufficient"]) == (6, False)
	assert monday["verified_distinct"] == 0 and len(monday["unverified"]) == 6 and monday["healthy"] is False
	assert any("only 0 verified distinct activities" in w and "6 not in the catalogue source" in w for w in health["activity_warnings"])


def test_two_templates_that_share_one_activity_are_flagged(world_session, monkeypatch):
	_publish_all(world_session)
	shared = dict(ACTIVITIES)
	shared["cat1_monday_where_is_it"] = dict(ACTIVITIES["cat1_monday_loud_and_soft"])
	monkeypatch.setattr(service, "ACTIVITIES", shared)
	monday = catalogue_health(world_session, NOW)["themes"][0]
	assert monday["eligible"] == 6 and monday["verified_distinct"] == 5 and monday["healthy"] is False
	assert monday["duplicate_activities"] == [
		{"mechanic": "compare_loudness_and_pitch", "slugs": ["cat1_monday_loud_and_soft", "cat1_monday_where_is_it"]}
	]


def test_assignment_frequency_is_reported_for_the_real_catalogue(world_session):
	_publish_all(world_session)
	child = make_family(world_session, language="gu")
	_, _, choices = ensure_daily_choices(world_session, child, NOW)
	select_assignment(world_session, child, choices[0].id).status = "approved"
	world_session.commit()
	health = catalogue_health(world_session, NOW)
	assert health["totals"]["most_assigned"] == 1 and health["totals"]["never_assigned"] == 39
	assert sum(t["assignment_count"] for t in health["templates"]) == 3


# -- rotation against the real catalogue (behaviour unchanged) -----------------------------------------------------

@pytest.mark.parametrize("language, birth_year", [("en", 2021), ("gu", 2017), ("hi", 2012)])
def test_a_child_who_picks_the_weekday_theme_sees_all_42_templates_once_in_42_days(world_session, language, birth_year):
	_publish_all(world_session)
	child = make_family(world_session, birth=datetime(birth_year, 3, 1).date(), language=language)
	seen, per_theme = [], Counter()
	for day in range(42):
		when = NOW + timedelta(days=day)
		_, _, choices = ensure_daily_choices(world_session, child, when)
		assert len(choices) == 3 and len({c.template_id for c in choices}) == 3
		assert all(c.snapshot["locale"] == language for c in choices)
		theme = THEMES_BY_WEEKDAY[when.weekday()]
		todays = [c for c in choices if c.snapshot["theme"] == theme]
		assert todays, (day, theme)  # the weekday theme is always offered
		picked = select_assignment(world_session, child, todays[0].id)
		picked.status = "approved"
		world_session.commit()
		seen.append(picked.template_id)
		per_theme[theme] += 1
	assert len(set(seen)) == 42  # no repeat inside 42 days, and nothing left unseen
	assert set(per_theme.values()) == {6}
