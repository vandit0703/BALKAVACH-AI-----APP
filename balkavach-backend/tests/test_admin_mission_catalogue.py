"""Admin view of the daily-mission catalogue: completeness, per-locale inspection, preview, publish errors.

The admin endpoint functions are called directly against the in-memory SQLite world (permission checks are
route dependencies and are covered by ``test_authorization_boundaries``). Not a PostgreSQL test.
"""

import pytest

from app.api.v1.daily_missions import (
	get_daily_template,
	list_daily_templates,
	publish_daily_template,
)
from app.content.daily_missions import AGE_BANDS, LOCALES, MISSIONS, variation_payload
from app.core.exceptions import APIError
from app.services.mission_catalogue_service import apply_catalogue
from tests.sqlite_world import DailyMissionTemplate, DailyMissionVariation, world_session  # noqa: F401  (fixture)

pytestmark = pytest.mark.usefixtures("standin_submit")  # the catalogue has no child-facing submit text yet (see conftest)


def _seed(session, publish=False):
	apply_catalogue(session, publish=publish)
	session.commit()


def test_listing_shows_all_themes_and_templates_with_completeness(world_session):
	_seed(world_session)
	rows = list_daily_templates(admin=None, session=world_session)
	assert len(rows) == 42
	assert {r["theme"] for r in rows} == {m["theme"] for m in MISSIONS}
	for row in rows:
		assert row["variation_count"] == 9 and row["is_complete"] is True and row["missing"] == []
		assert row["is_published"] is False


def test_listing_identifies_missing_translations(world_session):
	template = DailyMissionTemplate(slug="partial_one", theme="monday_sound_detective", mission_type="offline", is_published=False)
	world_session.add(template)
	world_session.flush()
	for age_band in AGE_BANDS:
		for locale in ("en", "gu"):
			world_session.add(DailyMissionVariation(template_id=template.id, age_band=age_band, locale=locale))
	world_session.commit()
	row = next(r for r in list_daily_templates(admin=None, session=world_session) if r["slug"] == "partial_one")
	assert row["is_complete"] is False and row["variation_count"] == 6
	assert row["missing"] == ["4_6:hi", "7_10:hi", "11_15:hi"]


def test_detail_lists_every_age_band_and_locale_with_the_child_facing_preview(world_session):
	_seed(world_session)
	template = world_session.query(DailyMissionTemplate).filter(DailyMissionTemplate.slug == MISSIONS[1]["slug"]).one()
	detail = get_daily_template(template.id, admin=None, session=world_session)
	assert detail["slug"] == MISSIONS[1]["slug"] and detail["missing"] == []
	assert [(v["age_band"], v["locale"]) for v in detail["variations"]] == [(a, loc) for a in AGE_BANDS for loc in LOCALES]
	hindi = next(v for v in detail["variations"] if (v["age_band"], v["locale"]) == ("7_10", "hi"))
	expected = variation_payload(MISSIONS[1], "7_10", "hi")
	assert hindi["title"] == expected["title"]
	assert hindi["preview"].startswith(expected["description"])
	assert expected["instructions"] in hindi["preview"] and expected["completion_criteria"] in hindi["preview"]
	assert hindi["required_materials"] == expected["required_materials"] and hindi["duration_minutes"] == expected["duration_minutes"]


def test_unknown_template_is_a_clear_404(world_session):
	from uuid import uuid4

	with pytest.raises(APIError) as error:
		get_daily_template(uuid4(), admin=None, session=world_session)
	assert error.value.status_code == 404 and error.value.code == "daily_template_not_found"


def test_publishing_an_incomplete_template_names_what_is_missing(world_session):
	template = DailyMissionTemplate(slug="partial_two", theme="tuesday_memory_master", mission_type="interactive", is_published=False)
	world_session.add(template)
	world_session.flush()
	world_session.add(DailyMissionVariation(template_id=template.id, age_band="4_6", locale="en"))
	world_session.commit()
	with pytest.raises(APIError) as error:
		publish_daily_template(template.id, True, admin=None, session=world_session)
	assert error.value.status_code == 422 and error.value.code == "daily_template_incomplete"
	assert "4_6:gu" in error.value.details["missing"] and "11_15:hi" in error.value.details["missing"]
	assert len(error.value.details["missing"]) == 8
	world_session.refresh(template)
	assert template.is_published is False


def test_a_complete_template_publishes_and_unpublishes(world_session):
	_seed(world_session)
	template = world_session.query(DailyMissionTemplate).first()
	assert publish_daily_template(template.id, True, admin=None, session=world_session)["is_published"] is True
	assert publish_daily_template(template.id, False, admin=None, session=world_session)["is_published"] is False
