"""Quizzes: eligibility, attempts, server-side grading and the one-time reward.

Rules enforced here (never in the client):

* A child sees only published quizzes in their language (plus English) and age range.
* Correct answers leave the server only inside a *submitted* attempt's result.
* Scores are computed here from the stored options; the client sends option ids only.
* A reward is granted at most once per (child, quiz): ``quiz_reward_grants`` has a unique key on that
  pair and the ledger rows carry idempotency keys derived from it. The grant and its ledger rows are
  written in the same transaction as the submitted attempt.
* Stars/XP/pass mark are snapshotted on the attempt when it starts.
* Quiz content edits bump ``quizzes.revision``; an attempt started on an older revision cannot be
  submitted (409 ``quiz_changed``), so a child is never graded against different questions.
"""

from __future__ import annotations

from datetime import datetime, timezone
from uuid import UUID

from sqlalchemy import func
from sqlalchemy.dialects.postgresql import insert as pg_insert
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from app.core.exceptions import APIError
from app.db.base import get_model
from app.schemas.quiz import AttemptSubmit, QuizQuestionIn
from app.services.video_service import child_age, feed_languages
from app.utils import utc_naive


def _now() -> datetime:
	return utc_naive(datetime.now(timezone.utc))


def _not_found() -> APIError:
	return APIError(404, "quiz_not_found", "Quiz not found")


# -- eligibility ---------------------------------------------------------------------------------


def _languages(session: Session, child) -> list[str]:
	User = get_model("User")
	user = session.query(User).filter(User.id == child.user_id).one()
	return feed_languages(user.preferred_language)


def _eligible_filters(session: Session, child):
	Quiz = get_model("Quiz")
	age = child_age(child)
	if age is None:
		return None
	return [
		Quiz.is_published.is_(True),
		Quiz.language_code.in_(_languages(session, child)),
		Quiz.age_min <= age,
		Quiz.age_max >= age,
	]


def eligible_quiz(session: Session, child, quiz_id: UUID):
	Quiz = get_model("Quiz")
	filters = _eligible_filters(session, child)
	if filters is None:
		raise _not_found()
	quiz = session.query(Quiz).filter(Quiz.id == quiz_id, *filters).one_or_none()
	if quiz is None:
		raise _not_found()
	return quiz


def _question_counts(session: Session, quiz_ids) -> dict:
	QuizQuestion = get_model("QuizQuestion")
	rows = (
		session.query(QuizQuestion.quiz_id, func.count(QuizQuestion.id))
		.filter(QuizQuestion.quiz_id.in_(list(quiz_ids)))
		.group_by(QuizQuestion.quiz_id)
		.all()
	)
	return {quiz_id: int(count) for quiz_id, count in rows}


def list_quizzes(session: Session, child) -> list[dict]:
	Quiz = get_model("Quiz")
	QuizAttempt = get_model("QuizAttempt")
	QuizRewardGrant = get_model("QuizRewardGrant")
	filters = _eligible_filters(session, child)
	if filters is None:
		return []
	quizzes = session.query(Quiz).filter(*filters).order_by(Quiz.created_at.desc(), Quiz.id).all()
	if not quizzes:
		return []
	ids = [quiz.id for quiz in quizzes]
	counts = _question_counts(session, ids)
	submitted = {
		quiz_id: (int(attempts), best)
		for quiz_id, attempts, best in session.query(
			QuizAttempt.quiz_id, func.count(QuizAttempt.id), func.max(QuizAttempt.score_percent)
		)
		.filter(
			QuizAttempt.child_id == child.id,
			QuizAttempt.quiz_id.in_(ids),
			QuizAttempt.status == "submitted",
		)
		.group_by(QuizAttempt.quiz_id)
		.all()
	}
	passed = {
		quiz_id
		for (quiz_id,) in session.query(QuizAttempt.quiz_id)
		.filter(
			QuizAttempt.child_id == child.id,
			QuizAttempt.quiz_id.in_(ids),
			QuizAttempt.status == "submitted",
			QuizAttempt.passed.is_(True),
		)
		.distinct()
		.all()
	}
	open_ids = {
		quiz_id
		for (quiz_id,) in session.query(QuizAttempt.quiz_id).filter(
			QuizAttempt.child_id == child.id,
			QuizAttempt.quiz_id.in_(ids),
			QuizAttempt.status == "in_progress",
		)
	}
	granted = {
		quiz_id
		for (quiz_id,) in session.query(QuizRewardGrant.quiz_id).filter(
			QuizRewardGrant.child_id == child.id, QuizRewardGrant.quiz_id.in_(ids)
		)
	}
	items = []
	for quiz in quizzes:
		question_count = counts.get(quiz.id, 0)
		if question_count == 0:
			continue  # an empty quiz is never shown to children
		attempts, best = submitted.get(quiz.id, (0, None))
		if quiz.id in passed:
			state = "passed"
		elif attempts:
			state = "attempted"
		elif quiz.id in open_ids:
			state = "in_progress"
		else:
			state = "pending"
		items.append(
			{
				"id": quiz.id,
				"title": quiz.title,
				"description": quiz.description,
				"subject": quiz.subject,
				"difficulty": quiz.difficulty,
				"language_code": quiz.language_code,
				"age_min": quiz.age_min,
				"age_max": quiz.age_max,
				"question_count": question_count,
				"pass_percent": quiz.pass_percent,
				"star_reward": quiz.star_reward,
				"xp_reward": quiz.xp_reward,
				"allow_retry": quiz.allow_retry,
				"status": state,
				"attempts": attempts,
				"best_score_percent": best,
				"reward_claimed": quiz.id in granted,
				"can_start": quiz.allow_retry or attempts == 0,
			}
		)
	return items


def get_quiz_summary(session: Session, child, quiz_id: UUID) -> dict:
	quiz = eligible_quiz(session, child, quiz_id)
	for item in list_quizzes(session, child):
		if item["id"] == quiz.id:
			return item
	raise _not_found()


# -- attempts ------------------------------------------------------------------------------------


def _load_questions(session: Session, quiz_id: UUID):
	"""[(question, [options])] in display order."""
	QuizQuestion = get_model("QuizQuestion")
	QuizOption = get_model("QuizOption")
	questions = (
		session.query(QuizQuestion).filter(QuizQuestion.quiz_id == quiz_id).order_by(QuizQuestion.position).all()
	)
	options: dict = {}
	if questions:
		for option in (
			session.query(QuizOption)
			.filter(QuizOption.question_id.in_([question.id for question in questions]))
			.order_by(QuizOption.position)
		):
			options.setdefault(option.question_id, []).append(option)
	return [(question, options.get(question.id, [])) for question in questions]


def _started_payload(session: Session, quiz, attempt) -> dict:
	return {
		"attempt_id": attempt.id,
		"quiz_id": quiz.id,
		"title": quiz.title,
		"pass_percent": attempt.pass_percent,
		"star_reward": attempt.star_reward,
		"xp_reward": attempt.xp_reward,
		"started_at": attempt.started_at,
		"questions": [
			{
				"id": question.id,
				"position": question.position,
				"prompt": question.prompt,
				"question_type": question.question_type,
				"options": [{"id": option.id, "text": option.text} for option in options],
			}
			for question, options in _load_questions(session, quiz.id)
		],
	}


def start_attempt(session: Session, child, quiz_id: UUID) -> dict:
	"""Start (or resume) the child's open attempt on a quiz."""
	QuizAttempt = get_model("QuizAttempt")
	quiz = eligible_quiz(session, child, quiz_id)
	if not _load_questions(session, quiz.id):
		raise _not_found()
	open_attempt = (
		session.query(QuizAttempt)
		.filter(
			QuizAttempt.child_id == child.id,
			QuizAttempt.quiz_id == quiz.id,
			QuizAttempt.status == "in_progress",
		)
		.one_or_none()
	)
	if open_attempt is not None and open_attempt.quiz_revision != quiz.revision:
		# Started on content that has since changed: it can never be graded, so start fresh.
		session.delete(open_attempt)
		session.flush()
		open_attempt = None
	if open_attempt is None:
		if not quiz.allow_retry:
			taken = (
				session.query(QuizAttempt.id)
				.filter(
					QuizAttempt.child_id == child.id,
					QuizAttempt.quiz_id == quiz.id,
					QuizAttempt.status == "submitted",
				)
				.first()
			)
			if taken is not None:
				raise APIError(409, "retry_not_allowed", "This quiz can be taken only once")
		attempt = QuizAttempt(
			quiz_id=quiz.id,
			child_id=child.id,
			status="in_progress",
			quiz_revision=quiz.revision,
			pass_percent=quiz.pass_percent,
			star_reward=quiz.star_reward,
			xp_reward=quiz.xp_reward,
			started_at=_now(),
		)
		try:
			with session.begin_nested():
				session.add(attempt)
		except IntegrityError:
			# A concurrent start won the one-open-attempt index: resume that one.
			attempt = (
				session.query(QuizAttempt)
				.filter(
					QuizAttempt.child_id == child.id,
					QuizAttempt.quiz_id == quiz.id,
					QuizAttempt.status == "in_progress",
				)
				.one()
			)
		open_attempt = attempt
	session.commit()
	return _started_payload(session, quiz, open_attempt)


def _owned_attempt(session: Session, child, attempt_id: UUID, *, lock: bool = False):
	QuizAttempt = get_model("QuizAttempt")
	query = session.query(QuizAttempt).filter(QuizAttempt.id == attempt_id, QuizAttempt.child_id == child.id)
	if lock:
		query = query.with_for_update()
	attempt = query.one_or_none()
	if attempt is None:
		raise APIError(404, "attempt_not_found", "Quiz attempt not found")
	return attempt


def _grade(questions, submitted: AttemptSubmit):
	"""[(question, options, selected_ids, is_correct)]; raises 422 on a malformed answer."""
	by_question: dict = {}
	for answer in submitted.answers:
		if answer.question_id in by_question:
			raise APIError(422, "invalid_answer", "A question was answered more than once")
		by_question[answer.question_id] = answer
	known = {question.id for question, _ in questions}
	if not set(by_question) <= known:
		raise APIError(422, "invalid_answer", "An answer refers to a question that is not in this quiz")
	graded = []
	for question, options in questions:
		answer = by_question.get(question.id)
		selected = list(dict.fromkeys(answer.option_ids)) if answer else []
		valid_ids = {option.id for option in options}
		if not set(selected) <= valid_ids:
			raise APIError(422, "invalid_answer", "An answer refers to an option that is not part of its question")
		if question.question_type != "multiple" and len(selected) > 1:
			raise APIError(422, "invalid_answer", "This question accepts one answer")
		correct_ids = {option.id for option in options if option.is_correct}
		graded.append((question, options, selected, bool(selected) and set(selected) == correct_ids))
	return graded


def _grant_reward(session: Session, child, quiz, attempt, now: datetime) -> tuple[int, int]:
	"""Pay the quiz reward once per (child, quiz). Returns what this call actually granted."""
	QuizRewardGrant = get_model("QuizRewardGrant")
	stars, xp = int(attempt.star_reward), int(attempt.xp_reward)
	grant_id = session.execute(
		pg_insert(QuizRewardGrant)
		.values(child_id=child.id, quiz_id=quiz.id, attempt_id=attempt.id, stars=stars, xp=xp, created_at=now)
		.on_conflict_do_nothing(constraint="uq_quiz_reward_grants_child_quiz")
		.returning(QuizRewardGrant.id)
	).scalar_one_or_none()
	if grant_id is None:
		return 0, 0  # already granted on an earlier attempt: retakes earn nothing
	key = f"quiz-passed:{child.id}:{quiz.id}"
	if stars > 0:
		StarTransaction = get_model("StarTransaction")
		session.add(
			StarTransaction(
				child_id=child.id,
				amount=stars,
				transaction_type="quiz_passed",
				idempotency_key=f"{key}:stars",
				description=f"Quiz passed: {quiz.title}",
			)
		)
	if xp > 0:
		XPTransaction = get_model("XPTransaction")
		session.add(
			XPTransaction(
				child_id=child.id,
				amount=xp,
				reason="quiz_passed",
				idempotency_key=f"{key}:xp",
			)
		)
		ChildProgress = get_model("ChildProgress")
		session.execute(
			pg_insert(ChildProgress)
			.values(child_id=child.id, total_xp=xp, garden_progress={}, updated_at=now)
			.on_conflict_do_update(
				index_elements=[ChildProgress.child_id],
				set_={"total_xp": ChildProgress.total_xp + xp, "updated_at": now},
			)
		)
		total_xp = session.query(ChildProgress.total_xp).filter(ChildProgress.child_id == child.id).scalar()
		Level = get_model("Level")
		level = (
			session.query(Level).filter(Level.minimum_xp <= total_xp).order_by(Level.minimum_xp.desc()).first()
		)
		if level:
			session.query(ChildProgress).filter(ChildProgress.child_id == child.id).update(
				{ChildProgress.current_level_id: level.id}
			)
			child.current_level_id = level.id
	if stars > 0 or xp > 0:
		# Quiz Stars/XP count towards total-based badges like any other earned reward (idempotent).
		from app.services.achievement_service import award_qualifying_badges

		session.flush()
		award_qualifying_badges(session, child, now)
	return stars, xp


def submit_attempt(session: Session, child, attempt_id: UUID, submitted: AttemptSubmit) -> dict:
	"""Grade an attempt on the server. Submitting twice returns the stored result and pays nothing."""
	Quiz = get_model("Quiz")
	QuizAttemptAnswer = get_model("QuizAttemptAnswer")
	attempt = _owned_attempt(session, child, attempt_id, lock=True)
	if attempt.status == "submitted":
		session.rollback()  # release the row lock; nothing changes
		return build_result(session, child, attempt_id)
	quiz = session.query(Quiz).filter(Quiz.id == attempt.quiz_id).one_or_none()
	if quiz is None or not quiz.is_published:
		session.rollback()
		raise APIError(409, "quiz_unavailable", "This quiz is no longer available")
	if quiz.revision != attempt.quiz_revision:
		session.rollback()
		raise APIError(409, "quiz_changed", "This quiz was updated. Please start it again")
	questions = _load_questions(session, quiz.id)
	graded = _grade(questions, submitted)
	total = len(graded)
	correct = sum(1 for *_, is_correct in graded if is_correct)
	score = (correct * 100) // total if total else 0
	passed = total > 0 and score >= attempt.pass_percent
	now = _now()
	try:
		for question, _options, selected, is_correct in graded:
			session.add(
				QuizAttemptAnswer(
					attempt_id=attempt.id,
					question_id=question.id,
					selected_option_ids=[str(option_id) for option_id in selected],
					is_correct=is_correct,
				)
			)
		stars = xp = 0
		attempt.status = "submitted"
		attempt.submitted_at = now
		attempt.total_questions = total
		attempt.correct_count = correct
		attempt.score_percent = score
		attempt.passed = passed
		session.flush()
		if passed:
			stars, xp = _grant_reward(session, child, quiz, attempt, now)
		attempt.stars_awarded = stars
		attempt.xp_awarded = xp
		session.commit()
	except Exception:
		session.rollback()
		raise
	return build_result(session, child, attempt_id)


def build_result(session: Session, child, attempt_id: UUID) -> dict:
	Quiz = get_model("Quiz")
	QuizAttemptAnswer = get_model("QuizAttemptAnswer")
	attempt = _owned_attempt(session, child, attempt_id)
	if attempt.status != "submitted":
		raise APIError(409, "attempt_not_submitted", "This attempt has not been submitted yet")
	quiz = session.query(Quiz).filter(Quiz.id == attempt.quiz_id).one()
	review = None
	if quiz.revision == attempt.quiz_revision:
		stored = {
			row.question_id: row
			for row in session.query(QuizAttemptAnswer).filter(QuizAttemptAnswer.attempt_id == attempt.id)
		}
		review = []
		for question, options in _load_questions(session, quiz.id):
			row = stored.get(question.id)
			selected = [UUID(value) for value in (row.selected_option_ids if row else [])]
			review.append(
				{
					"question_id": question.id,
					"position": question.position,
					"prompt": question.prompt,
					"question_type": question.question_type,
					"explanation": question.explanation,
					"selected_option_ids": selected,
					"correct_option_ids": [option.id for option in options if option.is_correct],
					"is_correct": bool(row.is_correct) if row else False,
					"options": [
						{"id": option.id, "text": option.text, "is_correct": option.is_correct} for option in options
					],
				}
			)
	return {
		"attempt_id": attempt.id,
		"quiz_id": quiz.id,
		"quiz_title": quiz.title,
		"status": attempt.status,
		"total_questions": attempt.total_questions,
		"correct_count": attempt.correct_count,
		"incorrect_count": attempt.total_questions - attempt.correct_count,
		"score_percent": attempt.score_percent,
		"passed": bool(attempt.passed),
		"pass_percent": attempt.pass_percent,
		"stars_awarded": attempt.stars_awarded,
		"xp_awarded": attempt.xp_awarded,
		"submitted_at": attempt.submitted_at,
		"can_retry": bool(quiz.is_published and quiz.allow_retry),
		"review": review,
	}


def attempt_history(session: Session, child, limit: int = 50) -> list[dict]:
	return attempt_history_for(session, child.id, limit)


def attempt_history_for(session: Session, child_id: UUID, limit: int = 50, offset: int = 0) -> list[dict]:
	"""Submitted attempts of one child, newest first. Summary fields only: no questions, answers or review."""
	Quiz = get_model("Quiz")
	QuizAttempt = get_model("QuizAttempt")
	rows = (
		session.query(QuizAttempt, Quiz.title)
		.join(Quiz, Quiz.id == QuizAttempt.quiz_id)
		.filter(QuizAttempt.child_id == child_id, QuizAttempt.status == "submitted")
		.order_by(QuizAttempt.submitted_at.desc(), QuizAttempt.id)
		.offset(offset)
		.limit(limit)
		.all()
	)
	return [
		{
			"attempt_id": attempt.id,
			"quiz_id": attempt.quiz_id,
			"quiz_title": title,
			"score_percent": attempt.score_percent,
			"correct_count": attempt.correct_count,
			"total_questions": attempt.total_questions,
			"passed": bool(attempt.passed),
			"stars_awarded": attempt.stars_awarded,
			"xp_awarded": attempt.xp_awarded,
			"submitted_at": attempt.submitted_at,
		}
		for attempt, title in rows
	]


# -- admin helpers -------------------------------------------------------------------------------


def replace_questions(session: Session, quiz_id: UUID, questions: list[QuizQuestionIn]) -> None:
	"""Replace a quiz's questions wholesale. Attempt scores survive; per-question answers go with them."""
	QuizQuestion = get_model("QuizQuestion")
	QuizOption = get_model("QuizOption")
	session.query(QuizQuestion).filter(QuizQuestion.quiz_id == quiz_id).delete(synchronize_session=False)
	session.flush()
	for position, question in enumerate(questions, start=1):
		row = QuizQuestion(
			quiz_id=quiz_id,
			position=position,
			prompt=question.prompt,
			question_type=question.question_type,
			explanation=(question.explanation or "").strip() or None,
		)
		session.add(row)
		session.flush()
		for option_position, option in enumerate(question.options, start=1):
			session.add(
				QuizOption(question_id=row.id, position=option_position, text=option.text, is_correct=option.is_correct)
			)
	session.flush()


def admin_detail(session: Session, quiz) -> dict:
	QuizAttempt = get_model("QuizAttempt")
	attempts = session.query(func.count(QuizAttempt.id)).filter(QuizAttempt.quiz_id == quiz.id).scalar()
	loaded = _load_questions(session, quiz.id)
	return {
		"id": quiz.id,
		"title": quiz.title,
		"description": quiz.description,
		"subject": quiz.subject,
		"difficulty": quiz.difficulty,
		"language_code": quiz.language_code,
		"age_min": quiz.age_min,
		"age_max": quiz.age_max,
		"pass_percent": quiz.pass_percent,
		"star_reward": quiz.star_reward,
		"xp_reward": quiz.xp_reward,
		"allow_retry": quiz.allow_retry,
		"is_published": quiz.is_published,
		"question_count": len(loaded),
		"attempt_count": int(attempts or 0),
		"revision": quiz.revision,
		"created_at": quiz.created_at,
		"updated_at": quiz.updated_at,
		"questions": [
			{
				"id": question.id,
				"position": question.position,
				"prompt": question.prompt,
				"question_type": question.question_type,
				"explanation": question.explanation,
				"options": [
					{"id": option.id, "position": option.position, "text": option.text, "is_correct": option.is_correct}
					for option in options
				],
			}
			for question, options in loaded
		],
	}
