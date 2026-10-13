"""The garden is a server-derived view of progress: stage from level, items from badges."""

import pytest

from app.db.seed_data import seed_progression_defaults
from app.services.garden_service import GARDEN_ITEMS, GARDEN_STAGES, build_garden


@pytest.fixture
def seeded(isolated_test_session):
    seed_progression_defaults(isolated_test_session)
    isolated_test_session.commit()


def _approve(api, ctx, **overrides):
    task = api.create_task(ctx["parent"]["token"], ctx["family"]["id"], **overrides)
    sub = api.submit(ctx["child"]["token"], task["id"]).json()
    assert api.review(ctx["parent"]["token"], sub["id"], "approved").status_code == 200


def test_new_child_starts_with_a_seed_and_nothing_unlocked(api, seeded):
    ctx = api.family_with_child()
    garden = api.get(f"/progress/children/{ctx['child']['id']}", ctx["child"]["token"]).json()["garden"]
    assert garden["stage"] == 1
    assert garden["stage_key"] == GARDEN_STAGES[0]["key"]
    assert garden["xp_to_next_stage"] == 100
    assert garden["items"] and not any(item["unlocked"] for item in garden["items"])


def test_stage_follows_xp_and_items_follow_badges(api, seeded):
    ctx = api.family_with_child()
    _approve(api, ctx, xp_reward=150)
    garden = api.get(f"/progress/children/{ctx['child']['id']}", ctx["child"]["token"]).json()["garden"]
    assert garden["stage"] == 2
    assert garden["xp_to_next_stage"] == 150  # 300 - 150
    unlocked = {item["key"] for item in garden["items"] if item["unlocked"]}
    assert unlocked == {"first-mission"}


def test_top_stage_has_no_next_target(api, seeded):
    ctx = api.family_with_child()
    _approve(api, ctx, xp_reward=100000, star_reward=0)
    garden = api.get(f"/progress/children/{ctx['child']['id']}", ctx["child"]["token"]).json()["garden"]
    assert garden["stage"] == len(GARDEN_STAGES)
    assert garden["xp_to_next_stage"] is None


def test_parent_sees_the_same_garden(api, seeded):
    ctx = api.family_with_child()
    _approve(api, ctx, xp_reward=120)
    child_view = api.get(f"/progress/children/{ctx['child']['id']}", ctx["child"]["token"]).json()["garden"]
    parent_view = api.get(f"/progress/children/{ctx['child']['id']}", ctx["parent"]["token"]).json()["garden"]
    assert child_view == parent_view


def test_garden_with_no_levels_configured_is_still_valid(api):
    # the shared test database may or may not hold seeded levels; a child with no XP is stage 1 either way
    ctx = api.family_with_child()
    garden = api.get(f"/progress/children/{ctx['child']['id']}", ctx["child"]["token"]).json()["garden"]
    assert garden["stage"] == 1


def test_build_garden_is_pure_and_defensive():
    assert build_garden(total_xp=0, earned_badge_names=set())["stage"] == 1
    assert build_garden(total_xp=-5, earned_badge_names=set())["stage"] == 1
    assert build_garden(total_xp=299, earned_badge_names=set())["stage"] == 2
    assert build_garden(total_xp=300, earned_badge_names=set())["stage"] == 3
    names = {item["badge"] for item in GARDEN_ITEMS}
    garden = build_garden(total_xp=0, earned_badge_names=names | {"Unknown badge"})
    assert all(item["unlocked"] for item in garden["items"])
