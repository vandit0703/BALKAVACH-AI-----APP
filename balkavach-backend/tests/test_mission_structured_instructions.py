"""Structured mission instructions: validation, classification, API contract, admin publish/edit, seeder safety.

Uses the in-memory SQLite world and pure functions. This is NOT a PostgreSQL test: migration 0019 was written but
never executed against any database, and nothing here proves JSONB behaviour on PostgreSQL.
"""

from types import SimpleNamespace
from uuid import uuid4

import pytest

from app.api.v1.daily_missions import (
	create_daily_variation,
	get_daily_template,
	preview_variation,
	publish_daily_template,
	update_daily_variation,
)
from app.content.daily_missions import AGE_BANDS, LOCALES, MISSIONS, variation_payload
from app.core.exceptions import APIError
from app.schemas.daily_mission import DailyMissionVariationCreate, DailyMissionVariationUpdate
from app.services.daily_mission_service import public_assignment
from app.services.mission_audit_service import (
	COMPLETE,
	INCOMPLETE,
	NEEDS_IMPROVEMENT,
	SAFETY_REVIEW,
	audit_catalogue,
	audit_database,
	classify_variation,
)
from app.services.mission_catalogue_service import apply_catalogue, compare_catalogue, retire_placeholders
from app.services.mission_instructions import (
	band_distinctness_errors,
	instruction_status,
	parse_numbered_steps,
	structured_content,
	validate_content,
)
from tests.sqlite_world import DailyMissionTemplate, DailyMissionVariation, world_session  # noqa: F401  (fixture)

PLACEHOLDER = "Try the steps, notice what you discover, and tell a trusted grown-up what you learned."


def _good(**over):
	base = {
		"learning_objective": "Understand what a small plant needs to grow.",
		"steps": ["Find a small plant.", "Look at its leaves.", "Give it a little water.", "Draw what you see."],
		"required_materials": ["A small plant", "Water"],
		"duration_minutes": 10,
		"observation_guidance": "Notice whether the leaves change.",
		"submission_requirements": "Share a drawing and one thing you noticed.",
		"safety_instructions": "Ask a grown-up before touching unfamiliar plants.",
		"completion_criteria": "A drawing and one sentence are shared.",
	}
	return structured_content({**base, **over})


def _codes(content, band="7_10", **kw):
	issues = validate_content(content, age_band=band, **kw)
	return [c for c, _ in issues["errors"]], [c for c, _ in issues["warnings"]]


# ---- pure validation -------------------------------------------------------------------------------------------------------------


def test_a_fully_structured_mission_has_no_errors_or_warnings():
	assert _codes(_good()) == ([], [])


@pytest.mark.parametrize("steps", [None, [], ["", "  "], ["Only one step."]])
def test_missing_empty_or_too_few_steps_are_errors(steps):
	errors, _ = _codes(_good(steps=steps, instructions=None))
	assert any(code in errors for code in ("steps_missing", "steps_malformed", "steps_too_few"))


def test_a_non_text_step_is_malformed():
	errors, _ = _codes({**_good(), "steps": ["ok step", 7, None]})
	assert "steps_malformed" in errors


def test_missing_submission_requirement_is_an_error():
	errors, _ = _codes(_good(submission_requirements=None))
	assert "submission_missing" in errors
	assert "submission_missing" in _codes(_good(submission_requirements="ok"))[0]  # too short to mean anything


def test_materials_must_be_stated_but_nothing_needed_counts():
	assert "materials_missing" in _codes(_good(required_materials=[]))[0]
	assert _codes(_good(required_materials=["Nothing needed"])) == ([], [])


def test_objective_and_observation_missing_are_warnings_not_errors():
	errors, warnings = _codes(_good(learning_objective=None, observation_guidance=None))
	assert errors == [] and set(warnings) == {"objective_missing", "observation_missing"}


@pytest.mark.parametrize("text", [PLACEHOLDER, "Complete the steps and share one thing you discovered.", "TBD"])
def test_placeholder_text_is_never_actionable(text):
	assert "placeholder_text" in _codes(_good(steps=[text, "Do the second thing."]))[0]
	assert "placeholder_text" in _codes(_good(), instructions=text)[0]


def test_age_band_guidelines_are_warnings_only():
	_, warnings = _codes(_good(steps=["a b", "c d"]), band="11_15")
	assert "step_count_guideline" in warnings
	long_steps = ["word " * 25] * 3
	assert "wording_too_long_for_age" in _codes(_good(steps=long_steps), band="4_6")[1]


def test_bands_may_not_reuse_identical_steps():
	same = _good()
	assert band_distinctness_errors({"4_6": same, "7_10": same, "11_15": _good(steps=["x one", "y two", "z three", "w four", "v five"])})
	assert not band_distinctness_errors({"4_6": same, "7_10": _good(steps=["x one", "y two", "z three"])})


def test_legacy_rows_get_steps_extracted_not_invented():
	legacy = {"instructions": "1. Listen.\n2. Name three sounds.\nAnother way: look instead.", "required_materials": ["Ears"]}
	assert structured_content(legacy)["steps"] == ["Listen.", "Name three sounds."]
	assert parse_numbered_steps(PLACEHOLDER) == []
	assert structured_content({"instructions": PLACEHOLDER})["steps"] == []


# ---- audit / classification ------------------------------------------------------------------------------------------------------


def test_catalogue_audit_counts_match_the_source_files():
	report = audit_catalogue()
	assert report["templates"] == 42 and report["age_specific_missions"] == 126 and report["variations_audited"] == 378
	assert {band: sum(c.values()) for band, c in report["by_age_band"].items()} == {"4_6": 126, "7_10": 126, "11_15": 126}
	assert {loc: sum(c.values()) for loc, c in report["by_locale"].items()} == {"en": 126, "gu": 126, "hi": 126}
	assert sum(report["classification"].values()) == 378
	assert report["classification"][INCOMPLETE] == 0 and report["classification"][SAFETY_REVIEW] == 0
	# Every variation has real steps and its own child-facing "what to submit", so all 378 are publish-ready.
	assert report["actionable"] == 378 and report["submission_not_clear_to_child"] == 0 and report["publish_ready"] == 378
	# Only wording-length quality warnings (ages 4-6 steps) keep two rows from COMPLETE; enrichment never decides the class.
	assert report["classification"][COMPLETE] == 376 and report["classification"][NEEDS_IMPROVEMENT] == 2
	assert report["enrichment_missing"] == {"learning_objective": 378, "observation_guidance": 378}
	assert report["needs_native_review"] == 252


def test_placeholder_rows_are_incomplete_and_flagged_for_admin_review():
	content = structured_content({"instructions": PLACEHOLDER, "required_materials": ["safe household objects"], "safety_instructions": "Be safe."})
	result = classify_variation(content, age_band="11_15", locale="en", description="A creative learning adventure for ages 11 to 15.", instructions=PLACEHOLDER)
	assert result["classification"] == INCOMPLETE and result["admin_review"] is True


def test_unsafe_activity_text_goes_to_safety_review():
	content = _good(steps=["Light a candle.", "Watch the flame."])
	assert classify_variation(content, age_band="7_10", locale="en")["classification"] == SAFETY_REVIEW


def test_a_complete_variation_classifies_complete_and_missing_enrichment_does_not_lower_it():
	assert classify_variation(_good(), age_band="7_10", locale="en")["classification"] == COMPLETE
	# optional enrichment alone never lowers the class
	missing = classify_variation(_good(learning_objective=None, observation_guidance=None), age_band="7_10", locale="en")
	assert missing["classification"] == COMPLETE and missing["learning_objective_missing"] and missing["observation_guidance_missing"]
	assert missing["publish_ready"] is True


def test_database_audit_is_select_only_and_reports_placeholders(world_session):
	template = DailyMissionTemplate(slug="old_placeholder", theme="monday_sound_detective", mission_type="offline", is_published=True)
	world_session.add(template)
	world_session.flush()
	world_session.add(DailyMissionVariation(template_id=template.id, age_band="4_6", locale="en", instructions=PLACEHOLDER, required_materials=["safe household objects"]))
	world_session.commit()
	before = world_session.query(DailyMissionVariation).count()
	report = audit_database(world_session)
	assert report["classification"][INCOMPLETE] == 1 and report["published_templates_with_incomplete_or_safety_rows"] == ["old_placeholder"]
	assert report["missing_localizations"][0]["template"] == "old_placeholder"
	assert world_session.query(DailyMissionVariation).count() == before and not world_session.new and not world_session.dirty


# ---- child API contract ------------------------------------------------------------------------------------------------------------


def _assignment(snapshot, status="available"):
	return SimpleNamespace(id=uuid4(), local_date=None, choice_slot=1, age_band="7_10", status=status, task_id=None, selected_at=None, started_at=None, skipped_at=None, snapshot=snapshot)


def _snapshot(**over):
	return {
		"title": "Plants", "description": "d", "instructions": "1. a\n2. b", "required_materials": ["Water"], "duration_minutes": 10,
		"safety_instructions": "s", "completion_criteria": "c", "mission_type": "offline", "theme": "t", "star_reward": 1, "xp_reward": 1, "locale": "en", **over,
	}


def test_new_snapshot_serialises_structured_fields_and_standard_rewards():
	content = public_assignment(_assignment(_snapshot(steps=["Do a thing.", "Do another."], learning_objective="Learn.", observation_guidance="Look.", submission_requirements="Show it."), status="selected"))["content"]
	assert content["steps"] == ["Do a thing.", "Do another."] and content["materials"] == ["Water"]
	assert content["learning_objective"] == "Learn." and content["observation_guidance"] == "Look." and content["submission_requirements"] == "Show it."
	assert content["instruction_status"] == "ready"
	assert content["required_materials"] == ["Water"] and content["instructions"] == "1. a\n2. b"  # backward-compatible fields intact
	assert (content["star_reward"], content["xp_reward"]) == (10, 15)


def test_old_snapshots_stay_readable_and_placeholders_are_reported_incomplete():
	legacy = public_assignment(_assignment(_snapshot()))["content"]
	assert legacy["steps"] == ["a", "b"] and legacy["instruction_status"] == "ready" and legacy["learning_objective"] is None
	generic = public_assignment(_assignment(_snapshot(instructions=PLACEHOLDER)))["content"]
	assert generic["steps"] == [] and generic["instruction_status"] == "incomplete"


def test_approved_history_keeps_the_rewards_it_was_earned_with():
	content = public_assignment(_assignment(_snapshot(star_reward=3, xp_reward=7), status="approved"))["content"]
	assert (content["star_reward"], content["xp_reward"]) == (3, 7)


@pytest.mark.parametrize("locale", LOCALES)
@pytest.mark.parametrize("band", AGE_BANDS)
def test_catalogue_payloads_serialise_in_every_age_band_and_language(band, locale):
	payload = variation_payload(MISSIONS[0], band, locale)
	DailyMissionVariationCreate(**payload)
	content = public_assignment(_assignment({**_snapshot(), **{k: payload[k] for k in ("title", "description", "instructions", "required_materials", "steps", "submission_requirements")}}))["content"]
	assert content["steps"] == payload["steps"] and content["instruction_status"] == "ready"
	assert content["submission_requirements"] == payload["submission_requirements"]


# ---- admin: publish validation, edit, preview ------------------------------------------------------------------------------------


def _seed(session):
	apply_catalogue(session)
	session.commit()
	return session.query(DailyMissionTemplate).filter(DailyMissionTemplate.slug == MISSIONS[0]["slug"]).one()


def test_a_template_with_placeholder_variations_cannot_be_published(world_session):
	template = DailyMissionTemplate(slug="generic_one", theme="monday_sound_detective", mission_type="offline", is_published=False)
	world_session.add(template)
	world_session.flush()
	for band in AGE_BANDS:
		for locale in LOCALES:
			world_session.add(DailyMissionVariation(template_id=template.id, age_band=band, locale=locale, instructions=PLACEHOLDER, required_materials=["safe household objects"]))
	world_session.commit()
	with pytest.raises(APIError) as error:
		publish_daily_template(template.id, True, admin=None, session=world_session)
	assert error.value.code == "daily_template_instructions_incomplete"
	assert {p["code"] for p in error.value.details["problems"]} >= {"steps_missing", "submission_missing"}
	world_session.refresh(template)
	assert template.is_published is False


def test_age_bands_that_reuse_each_others_steps_block_publishing(world_session, standin_submit):
	template = _seed(world_session)
	rows = world_session.query(DailyMissionVariation).filter_by(template_id=template.id, locale="en").all()
	reference = next(r for r in rows if r.age_band == "7_10")
	for row in rows:
		row.steps, row.instructions = list(reference.steps), reference.instructions
	world_session.commit()
	with pytest.raises(APIError) as error:
		publish_daily_template(template.id, True, admin=None, session=world_session)
	assert any(p["code"] == "bands_identical" for p in error.value.details["problems"])


def test_the_seeded_catalogue_template_publishes(world_session, standin_submit):
	template = _seed(world_session)
	assert publish_daily_template(template.id, True, admin=None, session=world_session)["is_published"] is True


def test_editing_a_variation_keeps_its_id_and_a_still_valid_template_stays_published(world_session, standin_submit):
	template = _seed(world_session)
	publish_daily_template(template.id, True, admin=None, session=world_session)
	row = world_session.query(DailyMissionVariation).filter_by(template_id=template.id, age_band="7_10", locale="en").one()
	original_id, old_extra = row.id, [l for l in row.instructions.splitlines() if not l[:1].isdigit()]
	update_daily_variation(template.id, row.id, DailyMissionVariationUpdate(steps=["First new step.", "Second new step.", "Third new step."], learning_objective="Learn something."), admin=None, session=world_session)
	world_session.refresh(row)
	assert row.id == original_id and row.steps == ["First new step.", "Second new step.", "Third new step."]
	assert row.instructions.startswith("1. First new step.\n2. Second new step.\n3. Third new step.")
	assert all(line in row.instructions for line in old_extra)  # the 'Another way' line survives
	assert row.learning_objective == "Learn something."
	assert world_session.get(DailyMissionTemplate, template.id).is_published is True


def test_a_bad_edit_is_rejected_and_changes_nothing(world_session):
	template = _seed(world_session)
	row = world_session.query(DailyMissionVariation).filter_by(template_id=template.id, age_band="4_6", locale="en").one()
	before = list(row.steps)
	with pytest.raises(ValueError):
		update_daily_variation(template.id, row.id, DailyMissionVariationUpdate(observation_guidance="Please share your phone number"), admin=None, session=world_session)
	world_session.rollback()
	world_session.refresh(row)
	assert row.steps == before and row.observation_guidance is None


def test_create_from_steps_derives_numbered_instructions(world_session):
	template = DailyMissionTemplate(slug="new_one", theme="tuesday_memory_master", mission_type="interactive", is_published=False)
	world_session.add(template)
	world_session.commit()
	request = DailyMissionVariationCreate(
		age_band="4_6", locale="en", title="Plants", description="Look at a plant.", steps=["Find a plant.", "Look closely."],
		required_materials=["Nothing needed"], duration_minutes=5, safety_instructions="Ask a grown-up.", completion_criteria="Draw it.",
		submission_requirements="Show your drawing.",
	)
	created = create_daily_variation(template.id, request, admin=None, session=world_session)
	row = world_session.get(DailyMissionVariation, created["id"])
	assert row.instructions == "1. Find a plant.\n2. Look closely." and row.steps == ["Find a plant.", "Look closely."]
	detail = get_daily_template(template.id, admin=None, session=world_session)["variations"][0]
	assert detail["steps"] == row.steps and detail["instruction_status"] == "ready" and detail["issues"]["errors"] == []


def test_create_without_steps_or_instructions_is_rejected():
	with pytest.raises(ValueError):
		DailyMissionVariationCreate(age_band="4_6", locale="en", title="Plants", description="Look.", duration_minutes=5, safety_instructions="Safe.", completion_criteria="Done.")


def test_preview_shows_the_child_content_and_what_blocks_publishing():
	request = DailyMissionVariationCreate(
		age_band="7_10", locale="en", title="Plants", description="Look at a plant.", instructions=PLACEHOLDER,
		duration_minutes=5, safety_instructions="Ask a grown-up.", completion_criteria="Draw it.",
	)
	result = preview_variation(request, admin=None)
	assert result["publishable"] is False and result["content"]["instruction_status"] == "incomplete"
	assert {e["code"] for e in result["errors"]} >= {"steps_missing", "submission_missing", "materials_missing"}


def test_preview_of_a_complete_variation_is_publishable_and_rendered():
	payload = variation_payload(MISSIONS[0], "7_10", "en")
	payload["submission_requirements"] = "Draw what you found and show it to a grown-up."
	result = preview_variation(DailyMissionVariationCreate(**payload), admin=None)
	assert result["publishable"] is True and "1. " in result["task_text"] and "What to submit" in result["task_text"]


# ---- seeder safety ---------------------------------------------------------------------------------------------------------------


def test_compare_is_read_only_and_reports_conflicts(world_session):
	template = _seed(world_session)
	row = world_session.query(DailyMissionVariation).filter_by(template_id=template.id, age_band="4_6", locale="en").one()
	row.title = "Edited by an admin"
	world_session.commit()
	rows_before = world_session.query(DailyMissionVariation).count()
	report = compare_catalogue(world_session)
	assert report["conflicts"] == [f"{MISSIONS[0]['slug']}/4_6/en"] and report["variations_identical"] == 377
	assert world_session.query(DailyMissionVariation).count() == rows_before and not world_session.dirty and not world_session.new


def test_backfill_fills_only_empty_structured_columns_of_unedited_rows(world_session):
	template = _seed(world_session)
	rows = world_session.query(DailyMissionVariation).filter_by(template_id=template.id).all()
	for row in rows:  # pretend the catalogue was seeded before migration 0019
		row.steps = row.submission_requirements = row.learning_objective = row.observation_guidance = None
	edited = next(r for r in rows if (r.age_band, r.locale) == ("4_6", "en"))
	edited.title = "Admin title"  # edited: must be left alone
	authored = next(r for r in rows if (r.age_band, r.locale) == ("7_10", "en"))
	authored.learning_objective = "Written by an admin"  # authored: must be kept
	world_session.commit()
	assert len(compare_catalogue(world_session)["backfillable"]) >= 8

	plain = apply_catalogue(world_session)  # no flag: nothing is backfilled
	assert plain["structured_fields_backfilled"] == 0 and plain["variations_created"] == 0
	world_session.commit()
	assert world_session.get(DailyMissionVariation, authored.id).steps is None

	done = apply_catalogue(world_session, backfill_structured=True)
	world_session.commit()
	assert done["variations_differing"] == [f"{MISSIONS[0]['slug']}/4_6/en"] and done["variations_created"] == 0
	assert world_session.get(DailyMissionVariation, edited.id).steps is None and world_session.get(DailyMissionVariation, edited.id).title == "Admin title"
	authored = world_session.get(DailyMissionVariation, authored.id)
	assert authored.learning_objective == "Written by an admin" and authored.steps == variation_payload(MISSIONS[0], "7_10", "en")["steps"]
	assert authored.submission_requirements == variation_payload(MISSIONS[0], "7_10", "en")["submission_requirements"]
	assert all(r.id for r in world_session.query(DailyMissionVariation).all())


def test_apply_never_publishes_or_retires_unless_asked(world_session):
	placeholder = DailyMissionTemplate(slug="monday_sound_detective", theme="monday_sound_detective", mission_type="offline", is_published=True)
	world_session.add(placeholder)
	world_session.commit()
	report = apply_catalogue(world_session)
	world_session.commit()
	assert report["published"] == 0
	assert world_session.query(DailyMissionTemplate).filter_by(is_published=True).count() == 1  # the placeholder is still live
	assert compare_catalogue(world_session)["published_placeholders"] == ["monday_sound_detective"]
	retired = retire_placeholders(world_session)  # a separate, explicit call
	assert retired["kept_edited"] == ["monday_sound_detective"] or retired["unpublished"] == ["monday_sound_detective"]


def test_cli_flags_that_write_require_apply(capsys):
	from app.cli import main

	for flag in ("--backfill-structured", "--publish", "--retire-placeholders"):
		with pytest.raises(SystemExit):
			main(["seed-daily-missions", flag])
	with pytest.raises(SystemExit):
		main(["seed-daily-missions", "--compare-db", "--apply"])
	assert main(["seed-daily-missions"]) == 0  # default is an offline dry run
	assert "no database was contacted" in capsys.readouterr().out
	assert main(["audit-daily-missions"]) == 0
