"""Second-pass audit: classification, child-facing submission text, edit-vs-publication behaviour, seeder safety.

SQLite/in-memory and pure-function tests (not PostgreSQL).
"""

import copy
from datetime import date
from uuid import uuid4

import pytest

from app.api.v1.daily_missions import publish_daily_template, update_daily_variation
from app.content.daily_missions import AGE_BANDS, LOCALES, MISSIONS, variation_payload
from app.core.exceptions import APIError
from app.schemas.daily_mission import DailyMissionVariationUpdate
from app.services.daily_mission_service import public_assignment
from app.services.mission_audit_service import (
    COMPLETE,
    INCOMPLETE,
    NEEDS_IMPROVEMENT,
    audit_catalogue,
    classify_variation,
)
from app.services.mission_catalogue_service import apply_catalogue, compare_catalogue, validate_catalogue
from app.services.mission_instructions import structured_content
from tests.sqlite_world import DailyMissionAssignment, DailyMissionTemplate, DailyMissionVariation, world_session  # noqa: F401


def _good(**over):
    base = {
        "learning_objective": None,
        "steps": ["Find a plant.", "Look at its leaves.", "Draw what you see."],
        "required_materials": ["A small plant"],
        "duration_minutes": 10,
        "observation_guidance": None,
        "submission_requirements": "Draw the plant and show your drawing to a grown-up.",
        "safety_instructions": "Ask a grown-up before touching unfamiliar plants.",
        "completion_criteria": "A drawing is shared.",
    }
    return structured_content({**base, **over})


def _classify(content, band="7_10", locale="en"):
    return classify_variation(content, age_band=band, locale=locale)


# ---- classification: essential blockers vs enrichment ----------------------------------------------------------------------------


def test_missing_enrichment_alone_is_complete_and_publish_ready():
    result = _classify(_good())
    assert result["classification"] == COMPLETE and result["publish_ready"] is True
    assert result["learning_objective_missing"] and result["observation_guidance_missing"]
    assert result["actionable"] and result["steps_ok"] and result["materials_clear"] and result["duration_present"]
    assert result["safety_guidance_present"] and result["submission_clear_to_child"] and result["completion_clear_to_reviewer"]


def test_each_essential_field_is_a_blocker_not_enrichment():
    for override, code in (
        ({"required_materials": []}, "materials_missing"),
        ({"submission_requirements": None}, "submission_missing"),
        ({"safety_instructions": None}, "safety_missing"),
        ({"completion_criteria": None}, "completion_missing"),
    ):
        result = _classify(_good(**override))
        assert result["classification"] == NEEDS_IMPROVEMENT and code in result["publish_blockers"], code
        assert result["publish_ready"] is False and result["actionable"] is True  # the child can still follow the steps


def test_only_a_missing_or_placeholder_step_list_is_incomplete():
    assert _classify(_good(steps=[]))["classification"] == INCOMPLETE
    assert _classify(_good(steps=["Try the steps, notice what you discover", "Do more."]))["classification"] == INCOMPLETE
    assert _classify(_good(steps=["Only one."]))["classification"] == INCOMPLETE


def test_step_count_guidelines_are_advisory_only():
    result = _classify(_good(steps=["Do a first thing.", "Do a second thing."]), band="11_15")
    assert "step_count_guideline" in result["warnings"] and result["classification"] == COMPLETE


def test_wording_too_hard_for_ages_4_to_6_is_a_quality_problem():
    long_steps = [" ".join(["carefully"] * 25)] * 3
    long_steps = [f"{s} {i}" for i, s in enumerate(long_steps)]
    result = _classify(_good(steps=long_steps), band="4_6")
    assert result["classification"] == NEEDS_IMPROVEMENT and result["steps_ok"] is False


def test_unsafe_activity_text_is_safety_review_even_if_everything_else_is_fine():
    result = _classify(_good(steps=["Light a candle.", "Watch the flame."]))
    assert result["classification"] == "SAFETY REVIEW" and result["needs_safety_review"] and result["publish_ready"] is False


def test_gujarati_and_hindi_always_need_native_review_english_does_not():
    assert _classify(_good(), locale="en")["needs_native_review"] is False
    assert _classify(_good(), locale="gu")["needs_native_review"] and _classify(_good(), locale="hi")["needs_native_review"]


# ---- child-facing submission vs reviewer check -----------------------------------------------------------------------------------


def test_a_submission_written_about_the_child_is_not_clear_to_the_child():
    result = _classify(_good(submission_requirements="The child names three different sounds they heard."))
    assert result["submission_clear_to_child"] is False and result["classification"] == NEEDS_IMPROVEMENT
    assert result["publish_ready"] is True  # it is a quality problem, not a safety/essential blocker


def test_the_catalogue_gives_children_their_own_text_and_reviewers_theirs():
    mission = MISSIONS[0]
    payload = variation_payload(mission, "4_6", "en")
    text = mission["ages"]["4_6"]["locales"]["en"]
    assert payload["submission_requirements"] == text["submit"] != text["show"]  # `show` is reviewer-facing, not copied
    assert text["show"] in payload["completion_criteria"]  # the reviewer still gets it, with the parent check


def _authored(mission):
    mission = copy.deepcopy(mission)
    for age in mission["ages"].values():
        for text in age["locales"].values():
            text["submit"] = text["steps"][-1]  # stand-in child-direct wording for the test
    return mission


def test_authored_child_text_makes_the_catalogue_publish_ready():
    missions = [_authored(m) for m in MISSIONS]
    assert validate_catalogue(missions) == []
    report = audit_catalogue(missions)
    assert report["publish_ready"] == 378 and report["submission_not_clear_to_child"] == 0
    assert report["classification"][COMPLETE] >= 370  # the rest are real wording warnings, reported not hidden


def test_validate_catalogue_rejects_reviewer_voiced_or_wrong_script_submit_text():
    broken = copy.deepcopy(_authored(MISSIONS[0]))
    broken["ages"]["4_6"]["locales"]["en"]["submit"] = "The child names three sounds."
    broken["ages"]["4_6"]["locales"]["hi"]["submit"] = "Show your drawing."
    problems = validate_catalogue([broken, *MISSIONS[1:]])
    assert any("submit is written about the child" in p for p in problems)
    assert any("submit has no hi script" in p for p in problems)


# ---- seeder: publish uses the same checks; idempotent; conflicts ----------------------------------------------------------------


def test_seeder_publish_runs_the_instruction_checks_and_blocks_a_template_that_fails(world_session):
    missions = copy.deepcopy(list(MISSIONS))
    del missions[3]["ages"]["7_10"]["locales"]["hi"]["submit"]  # one variation loses its child-facing submission
    report = apply_catalogue(world_session, missions, publish=True)
    world_session.commit()
    assert report["published"] == 41
    assert [(b["template"], b["problems"]) for b in report["publish_blocked"]] == [(MISSIONS[3]["slug"], ["submission_missing"])]
    assert world_session.query(DailyMissionTemplate).filter_by(is_published=True).count() == 41


def test_seeder_publishes_when_the_content_is_actually_ready(world_session):
    report = apply_catalogue(world_session, [_authored(m) for m in MISSIONS], publish=True)
    assert report["published"] == 42 and report["publish_blocked"] == []


def test_rerunning_the_seeder_is_idempotent(world_session):
    missions = [_authored(m) for m in MISSIONS]
    first = apply_catalogue(world_session, missions, backfill_structured=True)
    world_session.commit()
    second = apply_catalogue(world_session, missions, backfill_structured=True)
    world_session.commit()
    assert first["variations_created"] == 378 and second["variations_created"] == 0
    assert second["templates_created"] == 0 and second["structured_fields_backfilled"] == 0 and second["variations_differing"] == []
    assert world_session.query(DailyMissionVariation).count() == 378
    assert compare_catalogue(world_session, missions)["variations_identical"] == 378


def test_backfill_does_not_touch_a_row_whose_structured_fields_an_admin_wrote(world_session):
    missions = [_authored(m) for m in MISSIONS]
    apply_catalogue(world_session, missions)
    template = world_session.query(DailyMissionTemplate).filter_by(slug=MISSIONS[0]["slug"]).one()
    row = world_session.query(DailyMissionVariation).filter_by(template_id=template.id, age_band="7_10", locale="en").one()
    row.steps = ["Admin step one.", "Admin step two."]  # structured edited, legacy untouched
    row.submission_requirements = None
    world_session.commit()
    report = compare_catalogue(world_session, missions)
    assert report["structured_differs"] == [f"{MISSIONS[0]['slug']}/7_10/en"]  # reported as admin-authored
    apply_catalogue(world_session, missions, backfill_structured=True)
    world_session.commit()
    world_session.refresh(row)
    assert row.steps == ["Admin step one.", "Admin step two."]  # never overwritten
    assert row.submission_requirements == variation_payload(missions[0], "7_10", "en")["submission_requirements"]  # only the NULL was filled


# ---- editing vs publication and history -----------------------------------------------------------------------------------------


def _published_template(session):
    apply_catalogue(session, [_authored(m) for m in MISSIONS])
    template = session.query(DailyMissionTemplate).filter_by(slug=MISSIONS[0]["slug"]).one()
    session.commit()
    assert publish_daily_template(template.id, True, admin=None, session=session)["is_published"] is True
    return template


def _variation(session, template, band="7_10", locale="en"):
    return session.query(DailyMissionVariation).filter_by(template_id=template.id, age_band=band, locale=locale).one()


def _assign(session, template, variation):
    snapshot = {
        "title": variation.title, "description": variation.description, "instructions": variation.instructions,
        "required_materials": list(variation.required_materials), "duration_minutes": variation.duration_minutes,
        "safety_instructions": variation.safety_instructions, "completion_criteria": variation.completion_criteria,
        "mission_type": "offline", "theme": template.theme, "star_reward": 10, "xp_reward": 15, "locale": "en",
        "steps": list(variation.steps), "submission_requirements": variation.submission_requirements,
    }
    row = DailyMissionAssignment(
        child_id=uuid4(), family_id=uuid4(), local_date=date(2026, 11, 22), choice_slot=1, age_band=variation.age_band,
        template_id=template.id, variation_id=variation.id, task_id=uuid4(), status="in_progress", snapshot=snapshot,
    )
    session.add(row)
    session.commit()
    return row


def test_a_valid_edit_keeps_the_template_published_and_other_versions_untouched(world_session):
    template = _published_template(world_session)
    row, other = _variation(world_session, template), _variation(world_session, template, "11_15", "hi")
    other_steps, row_id = list(other.steps), row.id
    result = update_daily_variation(
        template.id, row.id, DailyMissionVariationUpdate(title="A better title", steps=["New first step.", "New second step.", "New third step."]),
        admin=None, session=world_session,
    )
    assert result["is_published"] is True and result["id"] == row_id
    world_session.refresh(template)
    assert template.is_published is True
    assert _variation(world_session, template, "11_15", "hi").steps == other_steps
    assert world_session.query(DailyMissionVariation).filter_by(template_id=template.id).count() == 9


def test_editing_never_changes_an_existing_assignment_or_its_history(world_session):
    template = _published_template(world_session)
    row = _variation(world_session, template)
    assignment = _assign(world_session, template, row)
    snapshot_before = copy.deepcopy(assignment.snapshot)
    shown_before = public_assignment(assignment)["content"]
    update_daily_variation(
        template.id, row.id, DailyMissionVariationUpdate(steps=["Totally new one.", "Totally new two."]), admin=None, session=world_session
    )
    world_session.refresh(assignment)
    assert assignment.snapshot == snapshot_before and assignment.variation_id == row.id and assignment.status == "in_progress"
    shown_after = public_assignment(assignment)["content"]
    assert shown_after["steps"] == shown_before["steps"] != ["Totally new one.", "Totally new two."]
    assert (shown_after["star_reward"], shown_after["xp_reward"]) == (shown_before["star_reward"], shown_before["xp_reward"])


def test_an_edit_that_would_break_a_published_mission_is_refused_and_changes_nothing(world_session):
    template = _published_template(world_session)
    row = _variation(world_session, template)
    before = (list(row.steps), row.instructions, row.submission_requirements)
    for bad in (
        DailyMissionVariationUpdate(steps=[]),
        DailyMissionVariationUpdate(submission_requirements="x"),
        DailyMissionVariationUpdate(required_materials=[]),
        DailyMissionVariationUpdate(locale="fr"),  # would leave a hole in the nine versions
    ):
        with pytest.raises(APIError) as error:
            update_daily_variation(template.id, row.id, bad, admin=None, session=world_session)
        assert error.value.code == "published_variation_edit_invalid" and error.value.details["problems"]
        world_session.refresh(row)
        world_session.refresh(template)
        assert (list(row.steps), row.instructions, row.submission_requirements) == before and template.is_published is True


def test_an_unpublished_mission_can_be_edited_into_any_state_and_stays_unpublished(world_session):
    template = _published_template(world_session)
    publish_daily_template(template.id, False, admin=None, session=world_session)
    row = _variation(world_session, template)
    result = update_daily_variation(template.id, row.id, DailyMissionVariationUpdate(steps=["Only one step."]), admin=None, session=world_session)
    assert result["is_published"] is False


def test_a_published_mission_that_was_already_broken_is_unpublished_by_an_edit(world_session):
    template = _published_template(world_session)
    row = _variation(world_session, template)
    row.steps = []  # legacy state: published although a version has no steps
    world_session.commit()
    other = _variation(world_session, template, "4_6", "gu")
    update_daily_variation(template.id, other.id, DailyMissionVariationUpdate(title="Another title"), admin=None, session=world_session)
    world_session.refresh(template)
    assert template.is_published is False


def test_fixing_the_last_problem_of_a_published_mission_keeps_it_published(world_session):
    template = _published_template(world_session)
    row = _variation(world_session, template)
    row.steps = []
    world_session.commit()
    update_daily_variation(template.id, row.id, DailyMissionVariationUpdate(steps=["Fixed first step.", "Fixed second step."]), admin=None, session=world_session)
    world_session.refresh(template)
    assert template.is_published is True


# ---- publishing templates that already exist -------------------------------------------------------------------------------------


def test_publish_existing_publishes_unedited_valid_templates_once_and_only_when_asked(world_session):
    apply_catalogue(world_session)  # creates 42 unpublished templates
    world_session.commit()
    assert apply_catalogue(world_session)["published_existing"] == 0  # not without the flag
    assert world_session.query(DailyMissionTemplate).filter_by(is_published=True).count() == 0
    first = apply_catalogue(world_session, publish_existing=True)
    world_session.commit()
    assert first["published_existing"] == 42 and first["published"] == 0 and first["publish_blocked"] == []
    assert world_session.query(DailyMissionTemplate).filter_by(is_published=True).count() == 42
    again = apply_catalogue(world_session, publish_existing=True)
    assert again["published_existing"] == 0 and again["templates_created"] == 0


def test_publish_existing_skips_a_template_an_admin_edited_and_blocks_an_invalid_one(world_session):
    apply_catalogue(world_session)
    first, second = (world_session.query(DailyMissionTemplate).filter_by(slug=m["slug"]).one() for m in MISSIONS[:2])
    edited = world_session.query(DailyMissionVariation).filter_by(template_id=first.id, age_band="4_6", locale="en").one()
    edited.title = "Renamed by an admin"
    broken = world_session.query(DailyMissionVariation).filter_by(template_id=second.id, age_band="7_10", locale="gu").one()
    broken.steps = []  # structured field emptied, legacy text still equal to the catalogue
    world_session.commit()
    report = apply_catalogue(world_session, publish_existing=True)
    world_session.commit()
    assert report["publish_skipped_conflict"] == [MISSIONS[0]["slug"]]
    assert [b["template"] for b in report["publish_blocked"]] == [MISSIONS[1]["slug"]]
    assert report["published_existing"] == 40
    world_session.refresh(first)
    world_session.refresh(second)
    assert first.is_published is False and second.is_published is False
    assert world_session.get(DailyMissionVariation, edited.id).title == "Renamed by an admin"


def test_publish_existing_never_unpublishes_or_touches_published_templates(world_session):
    apply_catalogue(world_session, publish=True)
    world_session.commit()
    before = {r.id: (r.title, r.steps) for r in world_session.query(DailyMissionVariation).all()}
    report = apply_catalogue(world_session, publish_existing=True, backfill_structured=True)
    world_session.commit()
    assert report["published_existing"] == 0 and report["structured_fields_backfilled"] == 0
    assert {r.id: (r.title, r.steps) for r in world_session.query(DailyMissionVariation).all()} == before
    assert world_session.query(DailyMissionTemplate).filter_by(is_published=True).count() == 42


# ---- what the child API returns for the published catalogue ---------------------------------------------------------------------

_BIRTHS = [(date(2021, 3, 1), "4_6"), (date(2017, 5, 1), "7_10"), (date(2012, 5, 1), "11_15")]
_GENERIC = ("learning adventure for ages", "Try the steps, notice", "Complete the steps and share")


@pytest.mark.parametrize("birth, band", _BIRTHS)
@pytest.mark.parametrize("language", LOCALES)
def test_published_catalogue_reaches_the_child_api_complete_and_without_placeholders(world_session, birth, band, language):
    from datetime import datetime, timezone

    from app.schemas.daily_mission import DailyMissionAssignmentPublic
    from app.services.daily_mission_service import ensure_daily_choices
    from tests.sqlite_world import make_family

    apply_catalogue(world_session, publish=True)
    world_session.commit()
    child = make_family(world_session, birth=birth, language=language)
    _, age_band, choices = ensure_daily_choices(world_session, child, datetime(2026, 11, 18, 9, 0, tzinfo=timezone.utc))
    assert age_band == band and len(choices) == 3
    for choice in choices:
        content = DailyMissionAssignmentPublic(**public_assignment(choice)).content
        mission = next(m for m in MISSIONS if m["slug"] == world_session.get(DailyMissionTemplate, choice.template_id).slug)
        text = mission["ages"][band]["locales"][language]
        assert content.instruction_status == "ready" and content.locale == language
        assert content.steps == text["steps"] and content.materials == text["materials"]
        assert content.submission_requirements == text["submit"] != text["show"]
        assert content.duration_minutes > 0 and content.safety_instructions == text["safety"]
        assert text["show"] in content.completion_criteria  # the reviewer's text is still there, separately
        assert (content.star_reward, content.xp_reward) == (10, 15)
        everything = " ".join([content.title, content.description, content.instructions, content.completion_criteria, *content.steps])
        assert not any(g.lower() in everything.lower() for g in _GENERIC)
