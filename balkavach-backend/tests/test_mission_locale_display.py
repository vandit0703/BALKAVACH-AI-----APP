from datetime import datetime, timezone
from uuid import uuid4

from app.services.daily_mission_service import (
    ensure_daily_choices,
    localized_task_fields,
    public_assignment,
    select_assignment,
)
from tests.sqlite_world import (  # noqa: F401  (fixture/models/helpers)
    DailyMissionVariation,
    Task,
    make_family,
    world_session,
)

WHEN = datetime(2026, 11, 19, 9, 0, tzinfo=timezone.utc)


def _template_with_locales(session, slug: str, age_band: str = "7_10"):
    from tests.sqlite_world import DailyMissionTemplate

    template = DailyMissionTemplate(
        slug=slug,
        theme="monday_sound_detective",
        mission_type="offline",
        is_surprise=False,
        is_published=True,
        star_reward=10,
        xp_reward=20,
    )
    session.add(template)
    session.flush()
    texts = {
        "en": ("English title", "English description", "English instructions"),
        "gu": ("Gujarati title", "Gujarati description", "Gujarati instructions"),
        "hi": ("Hindi title", "Hindi description", "Hindi instructions"),
    }
    for locale, (title, description, instructions) in texts.items():
        session.add(
            DailyMissionVariation(
                template_id=template.id,
                age_band=age_band,
                locale=locale,
                title=title,
                description=description,
                instructions=instructions,
                required_materials=["paper"],
                duration_minutes=10,
                safety_instructions=f"{locale} safety",
                completion_criteria=f"{locale} done",
                learning_objective=f"{locale} objective",
                steps=[f"{locale} step 1", f"{locale} step 2"],
                observation_guidance=f"{locale} observe",
                submission_requirements=f"{locale} submit",
                variation_key="v1",
            )
        )
    session.flush()
    return template


def _assignment_with_snapshot(session, child, template):
    from tests.sqlite_world import DailyMissionAssignment

    en = (
        session.query(DailyMissionVariation)
        .filter_by(template_id=template.id, age_band="7_10", locale="en")
        .one()
    )
    row = DailyMissionAssignment(
        child_id=child.id,
        family_id=child.family_id,
        local_date=WHEN.date(),
        choice_slot=1,
        age_band="7_10",
        template_id=template.id,
        variation_id=en.id,
        task_id=None,
        status="available",
        is_current=True,
        snapshot={
            "title": en.title,
            "description": en.description,
            "instructions": en.instructions,
            "required_materials": en.required_materials or [],
            "duration_minutes": en.duration_minutes,
            "safety_instructions": en.safety_instructions,
            "completion_criteria": en.completion_criteria,
            "mission_type": "offline",
            "theme": "monday_sound_detective",
            "star_reward": 10,
            "xp_reward": 20,
            "is_surprise": False,
            "mystery_bonus": None,
            "locale": "en",
            "learning_objective": en.learning_objective,
            "steps": en.steps,
            "observation_guidance": en.observation_guidance,
            "submission_requirements": en.submission_requirements,
        },
    )
    session.add(row)
    session.flush()
    return row


def test_public_assignment_uses_requested_locale_without_mutating_snapshot(world_session):
    child = make_family(world_session, language="en")
    template = _template_with_locales(world_session, "locale-template")
    row = _assignment_with_snapshot(world_session, child, template)
    snapshot_before = dict(row.snapshot)

    gu = public_assignment(row, session=world_session, display_locale="gu")
    hi = public_assignment(row, session=world_session, display_locale="hi")
    en = public_assignment(row, session=world_session, display_locale="en")

    assert gu["content"]["title"] == "Gujarati title"
    assert gu["content"]["description"] == "Gujarati description"
    assert gu["content"]["instructions"] == "Gujarati instructions"
    assert gu["content"]["steps"] == ["gu step 1", "gu step 2"]
    assert gu["content"]["locale"] == "gu"

    assert hi["content"]["title"] == "Hindi title"
    assert hi["content"]["steps"] == ["hi step 1", "hi step 2"]
    assert hi["content"]["locale"] == "hi"

    assert en["content"]["title"] == "English title"
    assert en["content"]["locale"] == "en"

    # Switching back and forth returns correct content and never mutates stored state.
    gu_again = public_assignment(row, session=world_session, display_locale="gu")
    assert gu_again["content"]["title"] == "Gujarati title"
    assert row.snapshot == snapshot_before
    assert row.status == "available"
    assert row.task_id is None
    assert row.template_id == template.id


def test_existing_assignments_do_not_duplicate_when_language_changes(world_session):
    child = make_family(world_session, language="en")
    # Create enough complete templates for today's choices.
    for i in range(3):
        template = _template_with_locales(world_session, f"pool-{i}")
        # publish_templates-like helper created full locale set for 7_10.
    from tests.sqlite_world import DailyMissionAssignment

    _, _, rows = ensure_daily_choices(world_session, child, WHEN)
    world_session.commit()
    count_before = world_session.query(DailyMissionAssignment).count()
    ids_before = sorted(str(r.id) for r in rows)

    # Reading in different locales must not create or duplicate assignments.
    for locale in ("gu", "hi", "en", "gu"):
        shown = [public_assignment(r, session=world_session, display_locale=locale) for r in rows]
        assert [item["id"] for item in shown] == [r.id for r in rows]
        assert all(item["status"] == r.status for item, r in zip(shown, rows))

    _, _, rows_after = ensure_daily_choices(world_session, child, WHEN)
    world_session.commit()
    assert world_session.query(DailyMissionAssignment).count() == count_before
    assert sorted(str(r.id) for r in rows_after) == ids_before


def test_localized_task_fields_resolve_daily_mission_task_without_mutating_task(world_session):
    child = make_family(world_session, language="en")
    # Need a full pool so ensure/select works; create 3 localized templates.
    for i in range(8):
        _template_with_locales(world_session, f"task-loc-{i}")
    _, _, choices = ensure_daily_choices(world_session, child, WHEN)
    world_session.commit()
    selected = select_assignment(world_session, child, choices[0].id)
    world_session.commit()
    task = world_session.get(Task, selected.task_id)
    assert task is not None
    original_title = task.title
    original_description = task.description

    hi = localized_task_fields(world_session, [task], "hi")
    en = localized_task_fields(world_session, [task], "en")

    assert hi[task.id]["title"] == "Hindi title"
    assert "Hindi description" in hi[task.id]["description"]
    assert en[task.id]["title"] == "English title"
    assert task.title == original_title
    assert task.description == original_description
    assert selected.status in {"selected", "in_progress", "available"}
    world_session.refresh(selected)
    assert selected.task_id == task.id
    assert selected.status in {"selected", "in_progress", "available"}
    # no duplicate assignments/tasks created by localized reads
    assert world_session.query(Task).filter(Task.id == task.id).count() == 1
