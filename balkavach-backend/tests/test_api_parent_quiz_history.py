"""Parent quiz history: read-only, family-authorized, summary fields only.

Uses the rolled-back PostgreSQL transaction fixture (skipped without TEST_DATABASE_URL).
"""

from datetime import datetime, timedelta, timezone
from uuid import uuid4

from sqlalchemy import func

from app.db.base import get_model
from tests.test_api_quizzes import correct_answers, make_quiz, ready_child, start, submit, wrong_answers


def _history(api, ctx, token=None, **params):
    return api.get(
        f"/quizzes/children/{ctx['child']['id']}/history",
        token or ctx["parent"]["token"],
        params=params or None,
    )


def _counts(api):
    session = api.session
    return {
        name: session.query(func.count(get_model(name).id)).scalar()
        for name in ("QuizAttempt", "QuizAttemptAnswer", "QuizRewardGrant", "StarTransaction", "XPTransaction", "Quiz")
    }


def test_parent_sees_passed_failed_and_retaken_attempts_with_server_rewards(api):
    admin = api.make_admin()
    quiz = make_quiz(api, admin, title="Farm animals", star_reward=7, xp_reward=11)
    full = api.get(f"/admin/quizzes/{quiz['id']}", admin["token"]).json()
    ctx = ready_child(api)
    child = ctx["child"]
    for answers in (wrong_answers(full), correct_answers(full), correct_answers(full)):
        attempt = start(api, child, quiz["id"])
        assert submit(api, child, attempt["attempt_id"], answers).status_code == 200

    response = _history(api, ctx)
    assert response.status_code == 200, response.text
    rows = response.json()
    assert len(rows) == 3
    # Newest first; only the first pass was paid, the retake and the failure earned nothing.
    assert [(r["passed"], r["stars_awarded"], r["xp_awarded"]) for r in rows] == [
        (True, 0, 0),
        (True, 7, 11),
        (False, 0, 0),
    ]
    first = rows[0]
    assert first["quiz_title"] == "Farm animals"
    assert (first["score_percent"], first["correct_count"], first["total_questions"]) == (100, 3, 3)
    assert first["submitted_at"]
    assert rows[2]["score_percent"] == 0


def test_history_exposes_no_questions_answers_or_review(api):
    admin = api.make_admin()
    quiz = make_quiz(api, admin)
    full = api.get(f"/admin/quizzes/{quiz['id']}", admin["token"]).json()
    ctx = ready_child(api)
    attempt = start(api, ctx["child"], quiz["id"])
    submit(api, ctx["child"], attempt["attempt_id"], correct_answers(full))
    response = _history(api, ctx)
    # Exactly the summary fields: nothing about the questions or what was chosen.
    assert set(response.json()[0]) == {
        "attempt_id",
        "quiz_id",
        "quiz_title",
        "score_percent",
        "correct_count",
        "total_questions",
        "passed",
        "stars_awarded",
        "xp_awarded",
        "submitted_at",
    }
    for private in ("is_correct", "explanation", "review", "selected", "Cow", "Cat", "milk"):
        assert private not in response.text


def test_open_attempts_are_not_history_and_a_new_child_has_none(api):
    admin = api.make_admin()
    quiz = make_quiz(api, admin)
    ctx = ready_child(api)
    assert _history(api, ctx).json() == []
    start(api, ctx["child"], quiz["id"])  # started, never submitted
    assert _history(api, ctx).json() == []


def test_limit_is_applied_and_validated(api):
    admin = api.make_admin()
    quiz = make_quiz(api, admin)
    full = api.get(f"/admin/quizzes/{quiz['id']}", admin["token"]).json()
    ctx = ready_child(api)
    for _ in range(3):
        attempt = start(api, ctx["child"], quiz["id"])
        submit(api, ctx["child"], attempt["attempt_id"], wrong_answers(full))
    assert len(_history(api, ctx, limit=2).json()) == 2
    assert _history(api, ctx, limit=0).status_code == 422


def test_attempt_dates_are_sent_as_utc_with_an_offset(api):
    """Without an offset the app reads the time as local and can show the wrong day."""
    admin = api.make_admin()
    quiz = make_quiz(api, admin)
    full = api.get(f"/admin/quizzes/{quiz['id']}", admin["token"]).json()
    ctx = ready_child(api)
    attempt = start(api, ctx["child"], quiz["id"])
    submit(api, ctx["child"], attempt["attempt_id"], correct_answers(full))
    before = datetime.now(timezone.utc)
    for response in (_history(api, ctx), api.get("/quizzes/history", ctx["child"]["token"])):
        submitted = datetime.fromisoformat(response.json()[0]["submitted_at"].replace("Z", "+00:00"))
        assert submitted.utcoffset() == timedelta(0)
        assert abs(before - submitted) < timedelta(minutes=5)


def test_offset_reaches_every_older_attempt_without_gaps(api):
    admin = api.make_admin()
    quiz = make_quiz(api, admin)
    full = api.get(f"/admin/quizzes/{quiz['id']}", admin["token"]).json()
    ctx = ready_child(api)
    for _ in range(5):
        attempt = start(api, ctx["child"], quiz["id"])
        submit(api, ctx["child"], attempt["attempt_id"], wrong_answers(full))
    everything = [row["attempt_id"] for row in _history(api, ctx).json()]
    assert len(everything) == 5
    pages = [_history(api, ctx, limit=2, offset=offset).json() for offset in (0, 2, 4, 6)]
    assert [len(page) for page in pages] == [2, 2, 1, 0]
    assert [row["attempt_id"] for page in pages for row in page] == everything
    assert _history(api, ctx, offset=-1).status_code == 422


def test_a_removed_family_member_loses_access(api):
    ctx = ready_child(api)
    assert _history(api, ctx).status_code == 200
    FamilyMember = get_model("FamilyMember")
    api.session.query(FamilyMember).filter(
        FamilyMember.family_id == ctx["child"]["family_id"]
    ).update({FamilyMember.is_active: False})
    api.session.commit()
    assert _history(api, ctx).status_code == 404


def test_another_familys_parent_cannot_read_a_childs_history(api):
    admin = api.make_admin()
    quiz = make_quiz(api, admin)
    full = api.get(f"/admin/quizzes/{quiz['id']}", admin["token"]).json()
    ctx = ready_child(api)
    other = ready_child(api)
    attempt = start(api, ctx["child"], quiz["id"])
    submit(api, ctx["child"], attempt["attempt_id"], correct_answers(full))
    path = f"/quizzes/children/{ctx['child']['id']}/history"
    denied = api.get(path, other["parent"]["token"])
    assert denied.status_code == 404  # indistinguishable from a missing child
    assert api.get(f"/quizzes/children/{uuid4()}/history", ctx["parent"]["token"]).status_code == 404


def test_only_parents_may_use_the_parent_endpoint(api):
    ctx = ready_child(api)
    other = ready_child(api)
    path = f"/quizzes/children/{ctx['child']['id']}/history"
    assert api.get(path, ctx["child"]["token"]).status_code == 403  # the child uses /quizzes/history
    assert api.get(path, other["child"]["token"]).status_code == 403
    assert api.get(path, api.make_admin()["token"]).status_code == 403
    assert api.get(path).status_code in (401, 403)


def test_viewing_history_writes_nothing_and_grants_nothing(api):
    admin = api.make_admin()
    quiz = make_quiz(api, admin, star_reward=5, xp_reward=5)
    full = api.get(f"/admin/quizzes/{quiz['id']}", admin["token"]).json()
    ctx = ready_child(api)
    attempt = start(api, ctx["child"], quiz["id"])
    submit(api, ctx["child"], attempt["attempt_id"], correct_answers(full))
    before = _counts(api)
    for _ in range(3):
        assert _history(api, ctx).status_code == 200
    assert _counts(api) == before
    # Writing verbs are not routed for this path.
    path = f"/quizzes/children/{ctx['child']['id']}/history"
    assert api.post(path, ctx["parent"]["token"], json={}).status_code in (404, 405)
    assert api.delete(path, ctx["parent"]["token"]).status_code in (404, 405)


def test_own_child_progress_and_achievements_stay_family_scoped(api):
    """The parent progress view reuses these endpoints: same-family parent allowed, other family 404."""
    ctx = ready_child(api)
    other = ready_child(api)
    child_id = ctx["child"]["id"]
    for suffix in ("", "/achievements"):
        path = f"/progress/children/{child_id}{suffix}"
        assert api.get(path, ctx["parent"]["token"]).status_code == 200
        assert api.get(path, other["parent"]["token"]).status_code == 404
