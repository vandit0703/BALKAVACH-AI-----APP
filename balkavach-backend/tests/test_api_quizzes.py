"""Quiz system: admin management, child attempts, server-side grading and one-time rewards.

HTTP tests use the ``api`` fixture (rolled-back PostgreSQL transaction; skipped without TEST_DATABASE_URL).
The schema-validation tests at the top need no database.
"""

from datetime import date, timedelta

import pytest
from pydantic import ValidationError

from app.db.base import get_model
from app.schemas.quiz import QuizQuestionIn, QuizWrite
from app.services.ledger_service import star_balance, xp_total


# -- payload validation (no database) --------------------------------------------------------


def _q(question_type="single", options=None, **extra):
    options = options or [{"text": "A", "is_correct": True}, {"text": "B"}]
    return {"prompt": "Pick one", "question_type": question_type, "options": options, **extra}


@pytest.mark.parametrize(
    "payload",
    [
        _q(options=[{"text": "A", "is_correct": True}, {"text": "B", "is_correct": True}]),  # single: two correct
        _q(options=[{"text": "A"}, {"text": "B"}]),  # single: none correct
        _q("true_false", [{"text": "T", "is_correct": True}, {"text": "F"}, {"text": "M"}]),  # three options
        _q("multiple", [{"text": "A"}, {"text": "B"}]),  # multiple: none correct
        _q("multiple", [{"text": "A", "is_correct": True}, {"text": "B", "is_correct": True}]),  # all correct
        _q(options=[{"text": "Same", "is_correct": True}, {"text": "same"}]),  # duplicate text
        _q(options=[{"text": "A", "is_correct": True}]),  # one option
        _q(options=[{"text": "  ", "is_correct": True}, {"text": "B"}]),  # blank
    ],
)
def test_invalid_question_shapes_are_rejected(payload):
    with pytest.raises(ValidationError):
        QuizQuestionIn.model_validate(payload)


def test_valid_question_shapes_are_accepted():
    QuizQuestionIn.model_validate(_q())
    QuizQuestionIn.model_validate(
        _q("multiple", [{"text": "A", "is_correct": True}, {"text": "B", "is_correct": True}, {"text": "C"}])
    )
    QuizQuestionIn.model_validate(_q("true_false", [{"text": "True", "is_correct": True}, {"text": "False"}]))


@pytest.mark.parametrize(
    "overrides",
    [
        {"pass_percent": 0},
        {"pass_percent": 101},
        {"star_reward": -1},
        {"xp_reward": -1},
        {"language_code": "fr"},
        {"difficulty": "extreme"},
        {"age_min": 9, "age_max": 8},
        {"title": "x"},
    ],
)
def test_invalid_quiz_settings_are_rejected(overrides):
    with pytest.raises(ValidationError):
        QuizWrite.model_validate({"title": "Animals", **overrides})


def test_rewards_default_to_zero():
    quiz = QuizWrite.model_validate({"title": "Animals"})
    assert (quiz.star_reward, quiz.xp_reward, quiz.pass_percent, quiz.allow_retry) == (0, 0, 60, True)


# -- helpers ---------------------------------------------------------------------------------

QUESTIONS = [
    {
        "prompt": "Which animal gives us milk?",
        "question_type": "single",
        "explanation": "Cows give milk.",
        "options": [{"text": "Cat"}, {"text": "Cow", "is_correct": True}, {"text": "Dog"}],
    },
    {
        "prompt": "Which are fruits?",
        "question_type": "multiple",
        "options": [
            {"text": "Apple", "is_correct": True},
            {"text": "Carrot"},
            {"text": "Mango", "is_correct": True},
        ],
    },
    {
        "prompt": "The sun is a star.",
        "question_type": "true_false",
        "options": [{"text": "True", "is_correct": True}, {"text": "False"}],
    },
]


def _put(api, path, token, json):
    return api.client.put(f"/api/v1{path}", headers=api.auth(token), json=json)


def _quiz_payload(**overrides):
    payload = {"title": "Animals and fruit", "subject": "science", "questions": QUESTIONS}
    payload.update(overrides)
    return payload


def make_quiz(api, admin, publish=True, **overrides):
    response = api.post("/admin/quizzes", admin["token"], _quiz_payload(**overrides))
    assert response.status_code == 201, response.text
    quiz = response.json()
    if publish:
        published = api.patch(f"/admin/quizzes/{quiz['id']}/published", admin["token"], {"is_published": True})
        assert published.status_code == 200, published.text
        quiz = published.json()
    return quiz


def ready_child(api, language="en", age=8):
    """A family with one child old enough (age) and speaking ``language``."""
    ctx = api.family_with_child()
    child = ctx["child"]
    ChildProfile = get_model("ChildProfile")
    User = get_model("User")
    today = date.today()
    api.session.query(ChildProfile).filter(ChildProfile.id == child["id"]).update(
        {ChildProfile.date_of_birth: today.replace(year=today.year - age) - timedelta(days=30)}
    )
    api.session.query(User).filter(User.id == child["user_id"]).update({User.preferred_language: language})
    api.session.commit()
    return ctx


def correct_answers(quiz_detail):
    """The right answer for every question, from the admin view of the quiz."""
    return [
        {"question_id": q["id"], "option_ids": [o["id"] for o in q["options"] if o["is_correct"]]}
        for q in quiz_detail["questions"]
    ]


def wrong_answers(quiz_detail):
    return [
        {"question_id": q["id"], "option_ids": [next(o["id"] for o in q["options"] if not o["is_correct"])]}
        for q in quiz_detail["questions"]
    ]


def start(api, child, quiz_id):
    response = api.post(f"/quizzes/{quiz_id}/attempts", child["token"])
    assert response.status_code == 201, response.text
    return response.json()


def submit(api, child, attempt_id, answers):
    return api.post(f"/quizzes/attempts/{attempt_id}/submit", child["token"], {"answers": answers})


def ledger_rows(api, child_id, table):
    Model = get_model(table)
    return api.session.query(Model).filter(Model.child_id == child_id).all()


# -- admin management ------------------------------------------------------------------------


def test_admin_creates_edits_publishes_and_unpublishes(api):
    admin = api.make_admin()
    quiz = make_quiz(api, admin, publish=False)
    assert quiz["is_published"] is False and quiz["question_count"] == 3 and quiz["revision"] == 1
    assert quiz["star_reward"] == 0 and quiz["xp_reward"] == 0  # rewards default to zero
    published = api.patch(f"/admin/quizzes/{quiz['id']}/published", admin["token"], {"is_published": True})
    assert published.json()["is_published"] is True
    # A published quiz cannot be edited until it is unpublished.
    assert _put(api, f"/admin/quizzes/{quiz['id']}", admin["token"], _quiz_payload(title="New title")).status_code == 409
    api.patch(f"/admin/quizzes/{quiz['id']}/published", admin["token"], {"is_published": False})
    edited = _put(api, f"/admin/quizzes/{quiz['id']}", admin["token"], _quiz_payload(title="New title", star_reward=5))
    assert edited.status_code == 200, edited.text
    assert edited.json()["title"] == "New title" and edited.json()["revision"] == 2
    listing = api.get("/admin/quizzes", admin["token"]).json()
    assert [item["id"] for item in listing] == [quiz["id"]]


def test_cannot_publish_an_empty_quiz(api):
    admin = api.make_admin()
    quiz = make_quiz(api, admin, publish=False, questions=[])
    response = api.patch(f"/admin/quizzes/{quiz['id']}/published", admin["token"], {"is_published": True})
    assert response.status_code == 422 and response.json()["error"]["code"] == "quiz_incomplete"


def test_invalid_payload_is_rejected_by_the_api(api):
    admin = api.make_admin()
    bad = _quiz_payload(
        questions=[_q(options=[{"text": "A", "is_correct": True}, {"text": "B", "is_correct": True}])]
    )
    assert api.post("/admin/quizzes", admin["token"], bad).status_code == 422
    assert api.post("/admin/quizzes", admin["token"], _quiz_payload(pass_percent=0)).status_code == 422


def test_only_admins_with_content_permission_can_manage_quizzes(api):
    admin = api.make_admin()
    quiz = make_quiz(api, admin, publish=False)
    ctx = ready_child(api)
    for token in (ctx["parent"]["token"], ctx["child"]["token"]):
        assert api.get("/admin/quizzes", token).status_code == 403
        assert api.post("/admin/quizzes", token, _quiz_payload()).status_code == 403
        assert api.patch(f"/admin/quizzes/{quiz['id']}/published", token, {"is_published": True}).status_code == 403
        assert _put(api, f"/admin/quizzes/{quiz['id']}", token, _quiz_payload()).status_code == 403
        assert api.delete(f"/admin/quizzes/{quiz['id']}", token).status_code == 403
    assert api.get("/admin/quizzes").status_code in (401, 403)
    # content_manager holds content:write, so it may manage quizzes.
    manager = api.make_admin("content_manager")
    assert api.get("/admin/quizzes", manager["token"]).status_code == 200


def test_attempted_quiz_cannot_be_deleted(api):
    admin = api.make_admin()
    ctx = ready_child(api)
    quiz = make_quiz(api, admin)
    start(api, ctx["child"], quiz["id"])
    api.patch(f"/admin/quizzes/{quiz['id']}/published", admin["token"], {"is_published": False})
    assert api.delete(f"/admin/quizzes/{quiz['id']}", admin["token"]).status_code == 409
    draft = make_quiz(api, admin, publish=False, title="Draft")
    assert api.delete(f"/admin/quizzes/{draft['id']}", admin["token"]).status_code == 204


# -- child listing and eligibility -----------------------------------------------------------


def test_child_sees_only_published_age_and_language_eligible_quizzes(api):
    admin = api.make_admin()
    published = make_quiz(api, admin, title="Visible")
    make_quiz(api, admin, publish=False, title="Draft")
    make_quiz(api, admin, title="Hindi", language_code="hi")
    make_quiz(api, admin, title="Too old", age_min=12, age_max=15)
    ctx = ready_child(api, language="en", age=8)
    titles = [q["title"] for q in api.get("/quizzes", ctx["child"]["token"]).json()]
    assert titles == ["Visible"]
    item = api.get("/quizzes", ctx["child"]["token"]).json()[0]
    assert item["id"] == published["id"] and item["question_count"] == 3 and item["status"] == "pending"
    assert item["can_start"] is True and item["best_score_percent"] is None and item["reward_claimed"] is False
    # An ineligible quiz is a 404, never revealed.
    hidden = api.get("/admin/quizzes", admin["token"]).json()
    ids = {q["title"]: q["id"] for q in hidden}
    assert api.get(f"/quizzes/{ids['Draft']}", ctx["child"]["token"]).status_code == 404
    assert api.post(f"/quizzes/{ids['Too old']}/attempts", ctx["child"]["token"]).status_code == 404


def test_localised_listing_shows_own_language_plus_english(api):
    admin = api.make_admin()
    make_quiz(api, admin, title="English quiz")
    make_quiz(api, admin, title="हिंदी प्रश्नोत्तरी", language_code="hi")
    make_quiz(api, admin, title="ગુજરાતી ક્વિઝ", language_code="gu")
    hindi = ready_child(api, language="hi")
    gujarati = ready_child(api, language="gu")
    assert {q["title"] for q in api.get("/quizzes", hindi["child"]["token"]).json()} == {
        "English quiz",
        "हिंदी प्रश्नोत्तरी",
    }
    assert {q["title"] for q in api.get("/quizzes", gujarati["child"]["token"]).json()} == {
        "English quiz",
        "ગુજરાતી ક્વિઝ",
    }


def test_quiz_endpoints_require_a_child_session(api):
    admin = api.make_admin()
    quiz = make_quiz(api, admin)
    ctx = ready_child(api)
    assert api.get("/quizzes").status_code in (401, 403)
    assert api.get("/quizzes", ctx["parent"]["token"]).status_code == 403
    assert api.get("/quizzes", admin["token"]).status_code == 403
    assert api.post(f"/quizzes/{quiz['id']}/attempts", ctx["parent"]["token"]).status_code == 403


# -- attempts: no answer leakage, grading ----------------------------------------------------


def test_correct_answers_are_never_exposed_before_submission(api):
    admin = api.make_admin()
    quiz = make_quiz(api, admin)
    ctx = ready_child(api)
    token = ctx["child"]["token"]
    detail = api.get(f"/quizzes/{quiz['id']}", token)
    attempt = start(api, ctx["child"], quiz["id"])
    for body in (detail.text, str(attempt), api.get("/quizzes", token).text):
        assert "is_correct" not in body and "explanation" not in body and "Cows give milk" not in body
    # No result exists until the attempt is submitted.
    assert api.get(f"/quizzes/attempts/{attempt['attempt_id']}", token).status_code == 409


def test_grading_single_multiple_and_true_false(api):
    admin = api.make_admin()
    quiz = make_quiz(api, admin)
    full = api.get(f"/admin/quizzes/{quiz['id']}", admin["token"]).json()
    ctx = ready_child(api)
    attempt = start(api, ctx["child"], quiz["id"])
    answers = correct_answers(full)
    # Multiple choice needs the exact set: dropping one right option makes that question wrong.
    answers[1]["option_ids"] = answers[1]["option_ids"][:1]
    result = submit(api, ctx["child"], attempt["attempt_id"], answers)
    assert result.status_code == 200, result.text
    body = result.json()
    assert (body["total_questions"], body["correct_count"], body["incorrect_count"]) == (3, 2, 1)
    assert body["score_percent"] == 66 and body["passed"] is True  # pass mark 60
    review = {item["position"]: item for item in body["review"]}
    assert review[1]["is_correct"] and review[1]["explanation"] == "Cows give milk."
    assert not review[2]["is_correct"] and len(review[2]["correct_option_ids"]) == 2
    assert review[3]["is_correct"]
    assert body["can_retry"] is True


def test_unanswered_and_wrong_answers_count_incorrect_and_fail(api):
    admin = api.make_admin()
    quiz = make_quiz(api, admin)
    full = api.get(f"/admin/quizzes/{quiz['id']}", admin["token"]).json()
    ctx = ready_child(api)
    attempt = start(api, ctx["child"], quiz["id"])
    body = submit(api, ctx["child"], attempt["attempt_id"], wrong_answers(full)[:2]).json()
    assert body["correct_count"] == 0 and body["score_percent"] == 0 and body["passed"] is False
    assert body["total_questions"] == 3  # the unanswered question still counts


def test_malformed_answers_are_rejected_and_the_attempt_stays_open(api):
    admin = api.make_admin()
    quiz = make_quiz(api, admin)
    full = api.get(f"/admin/quizzes/{quiz['id']}", admin["token"]).json()
    ctx = ready_child(api)
    attempt = start(api, ctx["child"], quiz["id"])
    q1, q2 = full["questions"][0], full["questions"][1]
    foreign = q2["options"][0]["id"]
    two_for_single = [o["id"] for o in q1["options"][:2]]
    bad_bodies = [
        [{"question_id": q1["id"], "option_ids": [foreign]}],  # option from another question
        [{"question_id": q1["id"], "option_ids": two_for_single}],  # two answers to a single-choice question
        [{"question_id": q1["id"], "option_ids": []}, {"question_id": q1["id"], "option_ids": []}],  # duplicate
        [{"question_id": "00000000-0000-0000-0000-000000000001", "option_ids": []}],  # unknown question
    ]
    for answers in bad_bodies:
        assert submit(api, ctx["child"], attempt["attempt_id"], answers).status_code == 422
    assert submit(api, ctx["child"], attempt["attempt_id"], correct_answers(full)).status_code == 200


def test_client_cannot_inject_a_score(api):
    admin = api.make_admin()
    quiz = make_quiz(api, admin, star_reward=5, xp_reward=5)
    full = api.get(f"/admin/quizzes/{quiz['id']}", admin["token"]).json()
    ctx = ready_child(api)
    attempt = start(api, ctx["child"], quiz["id"])
    body = {"answers": wrong_answers(full), "score_percent": 100, "passed": True, "stars": 999}
    result = api.post(f"/quizzes/attempts/{attempt['attempt_id']}/submit", ctx["child"]["token"], body).json()
    assert result["passed"] is False and result["stars_awarded"] == 0
    assert star_balance(api.session, ctx["child"]["id"]) == 0


# -- rewards ---------------------------------------------------------------------------------


def test_zero_reward_quiz_pays_nothing(api):
    admin = api.make_admin()
    quiz = make_quiz(api, admin)
    full = api.get(f"/admin/quizzes/{quiz['id']}", admin["token"]).json()
    ctx = ready_child(api)
    attempt = start(api, ctx["child"], quiz["id"])
    body = submit(api, ctx["child"], attempt["attempt_id"], correct_answers(full)).json()
    assert body["passed"] and body["stars_awarded"] == 0 and body["xp_awarded"] == 0
    assert ledger_rows(api, ctx["child"]["id"], "StarTransaction") == []
    assert ledger_rows(api, ctx["child"]["id"], "XPTransaction") == []


def test_reward_is_granted_once_on_first_pass_and_never_again(api):
    admin = api.make_admin()
    quiz = make_quiz(api, admin, star_reward=7, xp_reward=11)
    full = api.get(f"/admin/quizzes/{quiz['id']}", admin["token"]).json()
    ctx = ready_child(api)
    child = ctx["child"]
    session = api.session

    # A failed attempt pays nothing.
    failed = start(api, child, quiz["id"])
    fail_body = submit(api, child, failed["attempt_id"], wrong_answers(full)).json()
    assert fail_body["passed"] is False and (fail_body["stars_awarded"], fail_body["xp_awarded"]) == (0, 0)
    assert star_balance(session, child["id"]) == 0 and xp_total(session, child["id"]) == 0

    # The first passing attempt pays exactly once.
    first = start(api, child, quiz["id"])
    first_body = submit(api, child, first["attempt_id"], correct_answers(full)).json()
    assert (first_body["stars_awarded"], first_body["xp_awarded"]) == (7, 11)
    assert star_balance(session, child["id"]) == 7 and xp_total(session, child["id"]) == 11

    # Re-submitting the same attempt, reopening the result, and retaking all pay nothing more.
    again = submit(api, child, first["attempt_id"], correct_answers(full))
    assert again.status_code == 200 and again.json()["stars_awarded"] == 7  # the stored result, not a new grant
    api.get(f"/quizzes/attempts/{first['attempt_id']}", child["token"])
    retake = start(api, child, quiz["id"])
    retake_body = submit(api, child, retake["attempt_id"], correct_answers(full)).json()
    assert retake_body["passed"] and (retake_body["stars_awarded"], retake_body["xp_awarded"]) == (0, 0)
    assert star_balance(session, child["id"]) == 7 and xp_total(session, child["id"]) == 11
    assert len(ledger_rows(api, child["id"], "StarTransaction")) == 1
    assert len(ledger_rows(api, child["id"], "XPTransaction")) == 1
    assert len(session.query(get_model("QuizRewardGrant")).filter_by(child_id=child["id"]).all()) == 1

    summary = api.get("/quizzes", child["token"]).json()[0]
    assert summary["status"] == "passed" and summary["reward_claimed"] is True and summary["attempts"] == 3


def test_progress_and_level_follow_the_awarded_xp(api):
    admin = api.make_admin()
    quiz = make_quiz(api, admin, xp_reward=120)
    full = api.get(f"/admin/quizzes/{quiz['id']}", admin["token"]).json()
    ctx = ready_child(api)
    attempt = start(api, ctx["child"], quiz["id"])
    submit(api, ctx["child"], attempt["attempt_id"], correct_answers(full))
    progress = api.session.query(get_model("ChildProgress")).filter_by(child_id=ctx["child"]["id"]).one()
    assert progress.total_xp == 120 and progress.current_level_id is not None


def test_reward_values_are_frozen_when_the_attempt_starts(api):
    admin = api.make_admin()
    quiz = make_quiz(api, admin, star_reward=5)
    full = api.get(f"/admin/quizzes/{quiz['id']}", admin["token"]).json()
    ctx = ready_child(api)
    attempt = start(api, ctx["child"], quiz["id"])
    assert attempt["star_reward"] == 5
    # The admin raises the reward mid-attempt: unpublish, edit, republish.
    api.patch(f"/admin/quizzes/{quiz['id']}/published", admin["token"], {"is_published": False})
    during = submit(api, ctx["child"], attempt["attempt_id"], correct_answers(full))
    assert during.status_code == 409 and during.json()["error"]["code"] == "quiz_unavailable"
    edit = _put(api, f"/admin/quizzes/{quiz['id']}", admin["token"], _quiz_payload(star_reward=50))
    assert edit.status_code == 200
    api.patch(f"/admin/quizzes/{quiz['id']}/published", admin["token"], {"is_published": True})
    stale = submit(api, ctx["child"], attempt["attempt_id"], correct_answers(full))
    assert stale.status_code == 409 and stale.json()["error"]["code"] == "quiz_changed"
    assert star_balance(api.session, ctx["child"]["id"]) == 0
    # A fresh attempt starts on the new content and the new values.
    fresh = start(api, ctx["child"], quiz["id"])
    assert fresh["star_reward"] == 50 and fresh["attempt_id"] != attempt["attempt_id"]


def test_start_resumes_the_open_attempt(api):
    admin = api.make_admin()
    quiz = make_quiz(api, admin)
    ctx = ready_child(api)
    first = start(api, ctx["child"], quiz["id"])
    second = start(api, ctx["child"], quiz["id"])
    assert first["attempt_id"] == second["attempt_id"]
    assert api.get("/quizzes", ctx["child"]["token"]).json()[0]["status"] == "in_progress"


def test_quiz_that_forbids_retry_allows_one_attempt(api):
    admin = api.make_admin()
    quiz = make_quiz(api, admin, allow_retry=False)
    full = api.get(f"/admin/quizzes/{quiz['id']}", admin["token"]).json()
    ctx = ready_child(api)
    attempt = start(api, ctx["child"], quiz["id"])
    result = submit(api, ctx["child"], attempt["attempt_id"], wrong_answers(full)).json()
    assert result["can_retry"] is False
    again = api.post(f"/quizzes/{quiz['id']}/attempts", ctx["child"]["token"])
    assert again.status_code == 409 and again.json()["error"]["code"] == "retry_not_allowed"
    assert api.get("/quizzes", ctx["child"]["token"]).json()[0]["can_start"] is False


# -- isolation, history ----------------------------------------------------------------------


def test_a_child_cannot_read_or_submit_another_childs_attempt(api):
    admin = api.make_admin()
    quiz = make_quiz(api, admin)
    full = api.get(f"/admin/quizzes/{quiz['id']}", admin["token"]).json()
    owner = ready_child(api)
    other = ready_child(api)
    attempt = start(api, owner["child"], quiz["id"])
    path = f"/quizzes/attempts/{attempt['attempt_id']}"
    assert api.get(path, other["child"]["token"]).status_code == 404
    assert submit(api, other["child"], attempt["attempt_id"], correct_answers(full)).status_code == 404
    assert api.get(path, owner["parent"]["token"]).status_code == 403
    submit(api, owner["child"], attempt["attempt_id"], correct_answers(full))
    assert api.get(path, other["child"]["token"]).status_code == 404
    assert api.get("/quizzes/history", other["child"]["token"]).json() == []


def test_history_lists_submitted_attempts_newest_first(api):
    admin = api.make_admin()
    quiz = make_quiz(api, admin, star_reward=3)
    full = api.get(f"/admin/quizzes/{quiz['id']}", admin["token"]).json()
    ctx = ready_child(api)
    first = start(api, ctx["child"], quiz["id"])
    submit(api, ctx["child"], first["attempt_id"], wrong_answers(full))
    second = start(api, ctx["child"], quiz["id"])
    submit(api, ctx["child"], second["attempt_id"], correct_answers(full))
    start(api, ctx["child"], quiz["id"])  # an open attempt is not history
    history = api.get("/quizzes/history", ctx["child"]["token"]).json()
    assert [(h["passed"], h["stars_awarded"]) for h in history] == [(True, 3), (False, 0)]
    assert history[0]["quiz_title"] == "Animals and fruit"
    summary = api.get("/quizzes", ctx["child"]["token"]).json()[0]
    assert summary["best_score_percent"] == 100 and summary["attempts"] == 2


def test_missions_are_untouched_by_quiz_rewards(api):
    """A quiz award never writes a mission-shaped ledger row."""
    admin = api.make_admin()
    quiz = make_quiz(api, admin, star_reward=4, xp_reward=4)
    full = api.get(f"/admin/quizzes/{quiz['id']}", admin["token"]).json()
    ctx = ready_child(api)
    attempt = start(api, ctx["child"], quiz["id"])
    submit(api, ctx["child"], attempt["attempt_id"], correct_answers(full))
    types = {row.transaction_type for row in ledger_rows(api, ctx["child"]["id"], "StarTransaction")}
    assert types == {"quiz_passed"}
    assert all(row.submission_id is None for row in ledger_rows(api, ctx["child"]["id"], "StarTransaction"))
