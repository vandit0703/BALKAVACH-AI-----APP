"""Progression (levels, badges, streaks), timezone handling and the weekly report."""

from datetime import datetime, timezone
from zoneinfo import ZoneInfo

import pytest

from app.db.seed_data import seed_progression_defaults


@pytest.fixture
def seeded(isolated_test_session):
    seed_progression_defaults(isolated_test_session)
    isolated_test_session.commit()


def _approve_one(api, ctx, **task_overrides):
    task = api.create_task(ctx["parent"]["token"], ctx["family"]["id"], **task_overrides)
    sub = api.submit(ctx["child"]["token"], task["id"]).json()
    assert api.review(ctx["parent"]["token"], sub["id"], "approved").status_code == 200
    return task


def test_seed_is_idempotent(isolated_test_session):
    from app.db.base import get_model
    from app.db.seed_data import BADGES, LEVELS

    isolated_test_session.query(get_model("ChildBadge")).delete()
    isolated_test_session.query(get_model("Badge")).delete()
    isolated_test_session.query(get_model("Level")).delete()
    isolated_test_session.commit()
    first = seed_progression_defaults(isolated_test_session)
    assert first == {"levels": len(LEVELS), "badges": len(BADGES)}
    second = seed_progression_defaults(isolated_test_session)
    assert second == {"levels": 0, "badges": 0}
    assert isolated_test_session.query(get_model("Level")).count() == len(LEVELS)
    assert isolated_test_session.query(get_model("Badge")).count() == len(BADGES)


def test_first_approval_unlocks_badge_once_and_sets_level(api, seeded):
    ctx = api.family_with_child()
    child = ctx["child"]
    _approve_one(api, ctx, title="First task", star_reward=2, xp_reward=150)
    progress = api.get(f"/progress/children/{child['id']}", child["token"]).json()
    assert progress["level_number"] == 2
    names = [b["name"] for b in progress["badges"]]
    assert "First Mission" in names
    types = [n["notification_type"] for n in api.get("/notifications", child["token"]).json()]
    assert types.count("badge_unlocked") == len(names)

    _approve_one(api, ctx, title="Second task", star_reward=1, xp_reward=1)
    again = api.get(f"/progress/children/{child['id']}", child["token"]).json()
    assert [b["name"] for b in again["badges"]].count("First Mission") == 1


def test_streak_counts_consecutive_days_only_once_per_day(api, seeded):
    ctx = api.family_with_child()
    _approve_one(api, ctx, title="Task one")
    _approve_one(api, ctx, title="Task two")
    progress = api.get(f"/progress/children/{ctx['child']['id']}", ctx["child"]["token"]).json()
    assert progress["current_streak"] == 1
    assert progress["activity_days"][0]["completed_tasks"] == 2


@pytest.mark.parametrize("zone", ["Pacific/Kiritimati", "Pacific/Pago_Pago", "Asia/Kolkata"])
def test_activity_day_uses_the_family_timezone(api, zone):
    ctx = api.family_with_child()
    set_tz = api.patch(f"/settings/families/{ctx['family']['id']}", ctx["parent"]["token"], {"mission_settings": {"timezone": zone}})
    assert set_tz.status_code == 200, set_tz.text
    _approve_one(api, ctx)
    expected = datetime.now(timezone.utc).astimezone(ZoneInfo(zone)).date().isoformat()
    progress = api.get(f"/progress/children/{ctx['child']['id']}", ctx["child"]["token"]).json()
    assert progress["activity_days"][0]["activity_date"] == expected


def test_invalid_timezone_is_rejected(api):
    ctx = api.family_with_child()
    response = api.patch(
        f"/settings/families/{ctx['family']['id']}", ctx["parent"]["token"], {"mission_settings": {"timezone": "Mars/Base"}}
    )
    assert response.status_code == 422


def test_weekly_report_totals_categories_and_scope(api):
    ctx = api.family_with_child("Asha")
    other = api.family_with_child()
    categories = api.get("/tasks/categories", ctx["parent"]["token"]).json()
    learning = next(c for c in categories if c["name"] == "Learning")
    fitness = next(c for c in categories if c["name"] == "Fitness")
    _approve_one(api, ctx, title="Read", category_id=learning["id"], star_reward=3, xp_reward=30)
    _approve_one(api, ctx, title="Run", category_id=fitness["id"], star_reward=2, xp_reward=10)
    _approve_one(api, ctx, title="Run again", category_id=fitness["id"], star_reward=2, xp_reward=10)
    pending_task = api.create_task(ctx["parent"]["token"], ctx["family"]["id"], title="Still waiting")
    api.submit(ctx["child"]["token"], pending_task["id"])

    report = api.get(f"/progress/children/{ctx['child']['id']}/weekly", ctx["parent"]["token"])
    assert report.status_code == 200, report.text
    body = report.json()
    assert body["totals"] == {"completed_tasks": 3, "stars_earned": 7, "xp_earned": 50}
    assert body["pending_submissions"] == 1
    assert {c["name"]: c["completed_tasks"] for c in body["categories"]} == {"Learning": 1, "Fitness": 2}
    assert len(body["days"]) == 7
    assert sum(d["completed_tasks"] for d in body["days"]) == 3
    assert body["timezone"] == "UTC"
    assert body["period_start"] <= body["period_end"]

    # the child may read their own; another family may not
    assert api.get(f"/progress/children/{ctx['child']['id']}/weekly", ctx["child"]["token"]).status_code == 200
    assert api.get(f"/progress/children/{ctx['child']['id']}/weekly", other["parent"]["token"]).status_code == 404

    previous = api.get(f"/progress/children/{ctx['child']['id']}/weekly?weeks_back=1", ctx["parent"]["token"]).json()
    assert previous["totals"]["completed_tasks"] == 0
    assert api.get(f"/progress/children/{ctx['child']['id']}/weekly?weeks_back=-1", ctx["parent"]["token"]).status_code == 422
