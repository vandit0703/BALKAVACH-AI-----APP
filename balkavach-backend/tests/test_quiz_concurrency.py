"""Quiz reward idempotency under real concurrency.

The ``api`` tests run inside one rolled-back transaction, which cannot race. These use separate committed
connections (disposable test database only) and clean up after themselves.
"""

from concurrent.futures import ThreadPoolExecutor
from datetime import date, datetime, timezone
from uuid import uuid4

import pytest
from sqlalchemy import func
from sqlalchemy.orm import sessionmaker

from app.db.base import get_model
from app.schemas.quiz import AttemptSubmit
from app.services import quiz_service
from app.services.ledger_service import star_balance, xp_total

THREADS = 8


@pytest.fixture
def world(isolated_test_engine):
    """A committed child and a published 1-question quiz paying 6 Stars / 9 XP. Removed afterwards."""
    factory = sessionmaker(bind=isolated_test_engine, expire_on_commit=False, autoflush=False)
    User, Family = get_model("User"), get_model("Family")
    Child, Quiz = get_model("ChildProfile"), get_model("Quiz")
    Question, Option = get_model("QuizQuestion"), get_model("QuizOption")
    with factory() as session:
        user = User(full_name="Concurrent Kid", role="child", preferred_language="en", email=f"{uuid4().hex}@example.com")
        session.add(user)
        session.flush()
        family = Family(family_name="Concurrency", created_by=user.id)
        session.add(family)
        session.flush()
        today = date.today()
        child = Child(
            user_id=user.id,
            family_id=family.id,
            display_name="Kid",
            date_of_birth=today.replace(year=today.year - 8),
        )
        session.add(child)
        quiz = Quiz(
            title="Race",
            subject="general",
            difficulty="easy",
            language_code="en",
            age_min=4,
            age_max=15,
            pass_percent=60,
            star_reward=6,
            xp_reward=9,
            allow_retry=True,
            is_published=True,
            revision=1,
        )
        session.add(quiz)
        session.flush()
        question = Question(quiz_id=quiz.id, position=1, prompt="1+1?", question_type="single")
        session.add(question)
        session.flush()
        right = Option(question_id=question.id, position=1, text="2", is_correct=True)
        session.add_all([right, Option(question_id=question.id, position=2, text="3", is_correct=False)])
        session.commit()
        ids = {
            "user": user.id,
            "family": family.id,
            "child": child.id,
            "quiz": quiz.id,
            "question": question.id,
            "right": right.id,
        }
    try:
        yield factory, ids
    finally:
        with factory() as session:
            session.query(Quiz).filter(Quiz.id == ids["quiz"]).delete()
            session.query(Family).filter(Family.id == ids["family"]).delete()
            session.query(User).filter(User.id == ids["user"]).delete()
            session.commit()


def _child(session, ids):
    return session.query(get_model("ChildProfile")).filter_by(id=ids["child"]).one()


def _answers(ids):
    return AttemptSubmit.model_validate(
        {"answers": [{"question_id": str(ids["question"]), "option_ids": [str(ids["right"])]}]}
    )


def _totals(factory, ids):
    with factory() as session:
        Star, Grant = get_model("StarTransaction"), get_model("QuizRewardGrant")
        return {
            "stars": star_balance(session, ids["child"]),
            "xp": xp_total(session, ids["child"]),
            "star_rows": session.query(func.count(Star.id)).filter(Star.child_id == ids["child"]).scalar(),
            "grants": session.query(func.count(Grant.id)).filter(Grant.child_id == ids["child"]).scalar(),
        }


def test_concurrent_starts_share_one_open_attempt(world):
    factory, ids = world

    def go(_):
        with factory() as session:
            return quiz_service.start_attempt(session, _child(session, ids), ids["quiz"])["attempt_id"]

    with ThreadPoolExecutor(THREADS) as pool:
        attempts = set(pool.map(go, range(THREADS)))
    assert len(attempts) == 1


def test_concurrent_submits_of_one_attempt_pay_once(world):
    factory, ids = world
    with factory() as session:
        attempt_id = quiz_service.start_attempt(session, _child(session, ids), ids["quiz"])["attempt_id"]

    def go(_):
        with factory() as session:
            return quiz_service.submit_attempt(session, _child(session, ids), attempt_id, _answers(ids))

    with ThreadPoolExecutor(THREADS) as pool:
        results = list(pool.map(go, range(THREADS)))
    assert all(result["passed"] for result in results)
    assert _totals(factory, ids) == {"stars": 6, "xp": 9, "star_rows": 1, "grants": 1}


def test_grant_race_between_different_attempts_pays_once(world):
    """The unique (child, quiz) key and the ledger idempotency keys hold even if two attempts race."""
    factory, ids = world
    Attempt = get_model("QuizAttempt")
    now = datetime.now(timezone.utc).replace(tzinfo=None)
    attempt_ids = []
    with factory() as session:
        for _ in range(THREADS):
            attempt = Attempt(
                quiz_id=ids["quiz"],
                child_id=ids["child"],
                status="submitted",
                quiz_revision=1,
                pass_percent=60,
                star_reward=6,
                xp_reward=9,
                started_at=now,
                submitted_at=now,
                total_questions=1,
                correct_count=1,
                score_percent=100,
                passed=True,
            )
            session.add(attempt)
            session.flush()
            attempt_ids.append(attempt.id)
        session.commit()

    def go(attempt_id):
        with factory() as session:
            child = _child(session, ids)
            quiz = session.query(get_model("Quiz")).filter_by(id=ids["quiz"]).one()
            attempt = session.query(Attempt).filter_by(id=attempt_id).one()
            granted = quiz_service._grant_reward(session, child, quiz, attempt, now)
            session.commit()
            return granted

    with ThreadPoolExecutor(THREADS) as pool:
        granted = list(pool.map(go, attempt_ids))
    assert sorted(granted) == [(0, 0)] * (THREADS - 1) + [(6, 9)]
    assert _totals(factory, ids) == {"stars": 6, "xp": 9, "star_rows": 1, "grants": 1}
