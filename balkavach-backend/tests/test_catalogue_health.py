"""Admin view of rotation capacity (milestone C2). SQLite world: logic only, not PostgreSQL."""

from datetime import datetime, timedelta, timezone

from app.api.v1.daily_missions import catalogue_health_endpoint, list_daily_templates, publish_daily_template
from app.services.daily_mission_service import THEMES_BY_WEEKDAY, ensure_daily_choices, select_assignment
from app.services.mission_catalogue_service import catalogue_health
from tests.sqlite_world import (
	DailyMissionAssignment,
	DailyMissionTemplate,
	DailyMissionVariation,
	make_family,
	make_pool,
	world_session,  # noqa: F401  (fixture)
)

NOW = datetime(2026, 11, 20, 9, 0, tzinfo=timezone.utc)


def at(days: int) -> datetime:
	return NOW + timedelta(days=days)


def test_every_theme_below_six_eligible_templates_is_flagged_with_its_shortfall(world_session):
	make_pool(world_session, per_theme=2, locales=("en", "gu", "hi"))
	health = catalogue_health(world_session, NOW)
	assert health["min_eligible_per_theme"] == 6
	assert [t["theme"] for t in health["themes"]] == list(THEMES_BY_WEEKDAY.values())
	for theme in health["themes"]:
		assert (theme["templates"], theme["published"], theme["eligible"]) == (2, 2, 2)
		assert theme["insufficient"] is True and theme["shortfall"] == 4
	assert len(health["warnings"]) == 7 and "monday_sound_detective" in health["warnings"][0]


def test_six_eligible_templates_per_theme_clears_the_warning(world_session):
	make_pool(world_session, per_theme=6, locales=("en", "gu", "hi"))
	health = catalogue_health(world_session, NOW)
	assert all(not t["insufficient"] and t["shortfall"] == 0 for t in health["themes"])
	assert health["warnings"] == []


def test_unpublished_and_incomplete_templates_are_listed_and_do_not_count_as_eligible(world_session):
	pool = make_pool(world_session, per_theme=2, locales=("en", "gu", "hi"))
	monday = [t for t in pool if t.theme == "monday_sound_detective"]
	monday[0].is_published = False
	world_session.query(DailyMissionVariation).filter(
		DailyMissionVariation.template_id == monday[1].id, DailyMissionVariation.locale == "hi"
	).delete()
	world_session.commit()
	theme = next(t for t in catalogue_health(world_session, NOW)["themes"] if t["theme"] == "monday_sound_detective")
	assert theme["eligible"] == 0 and theme["published"] == 1
	assert theme["unpublished"] == [monday[0].slug]
	assert theme["incomplete"] == [monday[1].slug]


def test_age_band_and_language_capacity_is_reported_per_theme(world_session):
	make_pool(world_session, per_theme=2, age_bands=("4_6", "7_10"), locales=("en", "gu"))
	theme = catalogue_health(world_session, NOW)["themes"][0]
	assert theme["age_bands"] == {"4_6": 2, "7_10": 2, "11_15": 0}
	assert theme["locales"] == {"en": 0, "gu": 0, "hi": 0}  # no template has all three age bands in a language
	assert theme["eligible"] == 0


def test_assignment_frequency_and_recent_cooldown_fallbacks_are_visible(world_session):
	make_pool(world_session, per_theme=1)  # 7 templates
	for template in world_session.query(DailyMissionTemplate).all()[3:]:
		template.is_published = False
	world_session.commit()  # 3 published: from day 2 one choice per day is a cooldown fallback
	child = make_family(world_session)
	for day in range(3):
		_, _, choices = ensure_daily_choices(world_session, child, at(day))
		select_assignment(world_session, child, choices[0].id).status = "approved"
		world_session.commit()
	health = catalogue_health(world_session, at(2))
	assert health["fallbacks"]["days"] == 14 and health["fallbacks"]["count"] >= 2
	assert health["fallbacks"]["children"] == 1
	assert sum(row["count"] for row in health["fallbacks"]["by_template"]) == health["fallbacks"]["count"]
	counts = {t["slug"]: t["assignment_count"] for t in health["templates"]}
	assert sum(counts.values()) == 9 and sorted(counts.values())[-3:] == [3, 3, 3]
	listing = list_daily_templates(admin=None, session=world_session)
	assert sorted(r["assignment_count"] for r in listing)[-3:] == [3, 3, 3]


def test_old_fallbacks_fall_out_of_the_window(world_session):
	make_pool(world_session, per_theme=1)
	for template in world_session.query(DailyMissionTemplate).all()[3:]:
		template.is_published = False
	world_session.commit()
	child = make_family(world_session)
	for day in range(3):
		_, _, choices = ensure_daily_choices(world_session, child, at(day))
		select_assignment(world_session, child, choices[0].id).status = "approved"
		world_session.commit()
	assert catalogue_health(world_session, at(40))["fallbacks"]["count"] == 0


def test_retiring_a_template_keeps_every_assignment_and_marks_it_unpublished(world_session):
	make_pool(world_session, per_theme=2)
	child = make_family(world_session)
	_, _, choices = ensure_daily_choices(world_session, child, at(0))
	world_session.commit()
	before = world_session.query(DailyMissionAssignment).count()
	template = world_session.get(DailyMissionTemplate, choices[0].template_id)
	assert publish_daily_template(template.id, False, admin=None, session=world_session)["is_published"] is False
	assert world_session.query(DailyMissionAssignment).count() == before
	health = catalogue_health(world_session, at(0))
	assert template.slug in [slug for t in health["themes"] for slug in t["unpublished"]]
	counts = {t["slug"]: t["assignment_count"] for t in health["templates"]}
	assert counts[template.slug] == 1  # its history is still counted


def test_the_endpoint_returns_the_same_report(world_session):
	make_pool(world_session, per_theme=2)
	assert catalogue_health_endpoint(admin=None, session=world_session)["min_eligible_per_theme"] == 6
