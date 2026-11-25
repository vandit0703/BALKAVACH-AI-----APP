"""Achievements: locked and earned badges with real progress, level progress, and idempotent awarding.

Uses the rolled-back PostgreSQL transaction fixture (skipped without TEST_DATABASE_URL); the race test uses
separate committed connections and cleans up after itself.
"""

from concurrent.futures import ThreadPoolExecutor
from datetime import date
from uuid import uuid4

import pytest
from sqlalchemy import func
from sqlalchemy.orm import sessionmaker

from app.db.base import get_model
from app.services import achievement_service
from tests.test_api_quizzes import correct_answers, make_quiz, ready_child, start, submit


def _badge(api, name=None, criteria="total_xp", threshold=5, active=True):
    Badge = get_model("Badge")
    badge = Badge(
        name=name or f"Test badge {uuid4().hex[:8]}",
        description="d",
        criteria_type=criteria,
        criteria_value={"threshold": threshold},
        is_active=active,
    )
    api.session.add(badge)
    api.session.commit()
    return badge


def _achievements(api, ctx, token=None):
    return api.get(f"/progress/children/{ctx['child']['id']}/achievements", token or ctx["child"]["token"])


def _by_name(body):
    return {b["name"]: b for b in body["badges"]}


def test_a_new_child_sees_every_badge_locked_with_zero_progress(api):
    badge = _badge(api, threshold=7)
    ctx = ready_child(api)
    response = _achievements(api, ctx)
    assert response.status_code == 200, response.text
    body = response.json()
    mine = _by_name(body)[badge.name]
    assert mine["unlocked"] is False and mine["unlocked_at"] is None
    assert mine["threshold"] == 7 and mine["current"] == 0
    assert all(not b["unlocked"] for b in body["badges"])
    # Level 1 at zero XP, with the next level's real threshold.
    level = body["level"]
    assert level["total_xp"] == 0 and level["level_number"] == 1
    assert level["next_minimum_xp"] is not None and level["next_minimum_xp"] > 0


def test_unsupported_criteria_show_no_invented_progress(api):
    badge = _badge(api, criteria="some_future_criterion", threshold=3)
    ctx = ready_child(api)
    mine = _by_name(_achievements(api, ctx).json())[badge.name]
    assert mine["threshold"] is None and mine["current"] is None and mine["unlocked"] is False


def test_inactive_badges_are_hidden_until_earned(api):
    hidden = _badge(api, active=False)
    ctx = ready_child(api)
    assert hidden.name not in _by_name(_achievements(api, ctx).json())


def test_a_quiz_reward_unlocks_a_total_based_badge_exactly_once(api):
    badge = _badge(api, threshold=5)
    admin = api.make_admin()
    quiz = make_quiz(api, admin, star_reward=2, xp_reward=10)
    full = api.get(f"/admin/quizzes/{quiz['id']}", admin["token"]).json()
    ctx = ready_child(api)
    child = ctx["child"]
    session = api.session
    ChildBadge = get_model("ChildBadge")

    first = start(api, child, quiz["id"])
    assert submit(api, child, first["attempt_id"], correct_answers(full)).status_code == 200
    mine = _by_name(_achievements(api, ctx).json())[badge.name]
    assert mine["unlocked"] is True and mine["unlocked_at"] is not None and mine["current"] >= 5
    held = session.query(func.count(ChildBadge.id)).filter_by(child_id=child["id"], badge_id=badge.id).scalar()
    assert held == 1

    # Retakes and repeated submits never award it again, nor notify again.
    again = start(api, child, quiz["id"])
    submit(api, child, again["attempt_id"], correct_answers(full))
    submit(api, child, first["attempt_id"], correct_answers(full))
    assert session.query(func.count(ChildBadge.id)).filter_by(child_id=child["id"], badge_id=badge.id).scalar() == 1
    Notification = get_model("Notification")
    notified = session.query(func.count(Notification.id)).filter(
        Notification.recipient_user_id == child["user_id"], Notification.notification_type == "badge_unlocked"
    ).scalar()
    assert notified == 1


def test_a_failed_quiz_unlocks_nothing(api):
    badge = _badge(api, threshold=1)
    admin = api.make_admin()
    quiz = make_quiz(api, admin, star_reward=2, xp_reward=10)
    ctx = ready_child(api)
    attempt = start(api, ctx["child"], quiz["id"])
    submit(api, ctx["child"], attempt["attempt_id"], [])
    assert _by_name(_achievements(api, ctx).json())[badge.name]["unlocked"] is False


def test_level_progress_follows_real_xp(api):
    admin = api.make_admin()
    quiz = make_quiz(api, admin, xp_reward=150)
    full = api.get(f"/admin/quizzes/{quiz['id']}", admin["token"]).json()
    ctx = ready_child(api)
    attempt = start(api, ctx["child"], quiz["id"])
    submit(api, ctx["child"], attempt["attempt_id"], correct_answers(full))
    level = _achievements(api, ctx).json()["level"]
    assert level["total_xp"] == 150
    assert level["minimum_xp"] <= 150
    assert level["next_minimum_xp"] is None or level["next_minimum_xp"] > 150


def test_who_may_read_achievements(api):
    ctx = ready_child(api)
    other = ready_child(api)
    path = f"/progress/children/{ctx['child']['id']}/achievements"
    assert api.get(path, ctx["parent"]["token"]).status_code == 200  # the child's own parent
    assert api.get(path, other["child"]["token"]).status_code == 404  # another child
    assert api.get(path, other["parent"]["token"]).status_code == 404  # another family's parent
    assert api.get(path).status_code in (401, 403)


def test_awarding_is_idempotent_when_called_repeatedly(api):
    badge = _badge(api, threshold=1)
    ctx = ready_child(api)
    ChildProfile = get_model("ChildProfile")
    child = api.session.query(ChildProfile).filter_by(id=ctx["child"]["id"]).one()
    api.grant_stars(ctx["child"]["id"], 3)
    api.session.commit()
    badge_star = _badge(api, criteria="total_stars", threshold=3)
    first = achievement_service.award_qualifying_badges(api.session, child)
    second = achievement_service.award_qualifying_badges(api.session, child)
    assert badge_star.id in {b.id for b in first}
    assert second == []
    assert badge.id not in {b.id for b in first}  # total_xp is still 0


@pytest.fixture
def committed_child(isolated_test_engine):
    factory = sessionmaker(bind=isolated_test_engine, expire_on_commit=False, autoflush=False)
    User, Family = get_model("User"), get_model("Family")
    Child, Badge, Star = get_model("ChildProfile"), get_model("Badge"), get_model("StarTransaction")
    with factory() as session:
        user = User(full_name="Race Kid", role="child", preferred_language="en", email=f"{uuid4().hex}@example.com")
        session.add(user)
        session.flush()
        family = Family(family_name="Race", created_by=user.id)
        session.add(family)
        session.flush()
        child = Child(user_id=user.id, family_id=family.id, display_name="Kid", date_of_birth=date(2018, 1, 1))
        session.add(child)
        session.flush()
        badge = Badge(
            name=f"Race badge {uuid4().hex[:8]}",
            criteria_type="total_stars",
            criteria_value={"threshold": 2},
            is_active=True,
        )
        session.add(badge)
        session.add(
            Star(
                child_id=child.id,
                amount=5,
                transaction_type="admin_adjustment",
                idempotency_key=f"race:{uuid4()}",
                description="t",
            )
        )
        session.commit()
        ids = {"user": user.id, "family": family.id, "child": child.id, "badge": badge.id}
    try:
        yield factory, ids
    finally:
        with factory() as session:
            session.query(Badge).filter(Badge.id == ids["badge"]).delete()
            session.query(Family).filter(Family.id == ids["family"]).delete()
            session.query(User).filter(User.id == ids["user"]).delete()
            session.commit()


def test_concurrent_awards_unlock_a_badge_once(committed_child):
    factory, ids = committed_child
    ChildBadge, Child = get_model("ChildBadge"), get_model("ChildProfile")

    def go(_):
        with factory() as session:
            child = session.query(Child).filter_by(id=ids["child"]).one()
            newly = achievement_service.award_qualifying_badges(session, child)
            session.commit()
            return [b.id for b in newly if b.id == ids["badge"]]

    with ThreadPoolExecutor(8) as pool:
        results = list(pool.map(go, range(8)))
    assert sum(len(r) for r in results) == 1  # exactly one caller awarded it
    with factory() as session:
        count = session.query(func.count(ChildBadge.id)).filter_by(child_id=ids["child"], badge_id=ids["badge"]).scalar()
    assert count == 1
