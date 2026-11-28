"""Idempotent, transactional seeding for the curated quiz content pack."""

from __future__ import annotations

from datetime import datetime, timezone
from typing import Iterable

from pydantic import ValidationError
from sqlalchemy.orm import Session

from app.content.quizzes import QUIZ_PACK, quiz_uuid
from app.db.base import get_model
from app.schemas.quiz import QuizQuestionIn, QuizWrite
from app.services.quiz_service import replace_questions
from app.utils import utc_naive

_METADATA_FIELDS = (
	"title",
	"description",
	"subject",
	"difficulty",
	"language_code",
	"age_min",
	"age_max",
	"pass_percent",
	"star_reward",
	"xp_reward",
	"allow_retry",
)


def _now() -> datetime:
	return utc_naive(datetime.now(timezone.utc))


def validate_quiz_pack(pack: Iterable[dict] = QUIZ_PACK) -> tuple[list[tuple[str, QuizWrite]], list[str]]:
	"""Validate every quiz in ``pack`` against ``QuizWrite`` without touching the database."""
	valid: list[tuple[str, QuizWrite]] = []
	errors: list[str] = []
	seen_slugs: set[str] = set()

	for index, entry in enumerate(pack):
		if not isinstance(entry, dict):
			errors.append(f"entry[{index}]: must be a dict")
			continue
		raw_slug = entry.get("slug")
		slug = str(raw_slug).strip().lower() if isinstance(raw_slug, str) else ""
		if not slug:
			errors.append(f"entry[{index}]: missing non-empty slug")
			continue
		if slug in seen_slugs:
			errors.append(f"{slug}: duplicate slug")
			continue
		seen_slugs.add(slug)

		try:
			quiz = QuizWrite.model_validate(entry.get("quiz"))
		except ValidationError as exc:
			errors.append(f"{slug}: {exc.errors()[0]['msg']}")
			continue
		if not quiz.questions:
			errors.append(f"{slug}: quiz must contain at least one question")
			continue
		valid.append((slug, quiz))

	return valid, errors


def _metadata_matches(existing, desired: QuizWrite) -> bool:
	for field in _METADATA_FIELDS:
		if getattr(existing, field, None) != getattr(desired, field, None):
			return False
	return True


def _questions_match(session: Session, quiz_id, desired: list[QuizQuestionIn]) -> bool:
	QuizQuestion = get_model("QuizQuestion")
	QuizOption = get_model("QuizOption")
	questions = (
		session.query(QuizQuestion)
		.filter(QuizQuestion.quiz_id == quiz_id)
		.order_by(QuizQuestion.position)
		.all()
	)
	if len(questions) != len(desired):
		return False
	if not questions:
		return True
	options_by_q: dict = {}
	for opt in (
		session.query(QuizOption)
		.filter(QuizOption.question_id.in_([q.id for q in questions]))
		.order_by(QuizOption.position)
		.all()
	):
		options_by_q.setdefault(opt.question_id, []).append(opt)

	for q_row, q_want in zip(questions, desired):
		if q_row.prompt != q_want.prompt or q_row.question_type != q_want.question_type:
			return False
		if (q_row.explanation or None) != ((q_want.explanation or "").strip() or None):
			return False
		opts = options_by_q.get(q_row.id, [])
		if len(opts) != len(q_want.options):
			return False
		for o_row, o_want in zip(opts, q_want.options):
			if o_row.text != o_want.text or bool(o_row.is_correct) != bool(o_want.is_correct):
				return False
	return True


def seed_quizzes(
	session: Session | None,
	pack: Iterable[dict] = QUIZ_PACK,
	*,
	apply: bool = False,
	publish: bool = False,
) -> dict:
	"""Validate and optionally apply the quiz pack idempotently in one transaction.

	Never deletes manually authored quizzes, attempts, or reward grants.
	"""
	valid, errors = validate_quiz_pack(pack)
	if errors:
		if session is not None and apply:
			session.rollback()
		return {
			"created": 0,
			"updated": 0,
			"skipped": 0,
			"invalid": len(errors),
			"errors": errors,
		}

	if session is None:
		return {
			"created": len(valid),
			"updated": 0,
			"skipped": 0,
			"invalid": 0,
			"errors": [],
		}

	Quiz = get_model("Quiz")
	QuizAttempt = get_model("QuizAttempt")
	created = updated = skipped = 0
	now = _now()

	try:
		for slug, desired in valid:
			qid = quiz_uuid(slug)
			existing = session.query(Quiz).filter(Quiz.id == qid).one_or_none()
			if existing is None:
				if apply:
					row = Quiz(
						id=qid,
						**{field: getattr(desired, field) for field in _METADATA_FIELDS},
						is_published=publish,
						revision=1,
						created_at=now,
						updated_at=now,
					)
					session.add(row)
					session.flush()
					replace_questions(session, qid, desired.questions)
				created += 1
				continue

			meta_ok = _metadata_matches(existing, desired)
			questions_ok = _questions_match(session, qid, desired.questions)
			needs_publish = bool(publish and not existing.is_published)

			if meta_ok and questions_ok and not needs_publish:
				skipped += 1
				continue

			has_attempts = (
				session.query(QuizAttempt.id).filter(QuizAttempt.quiz_id == qid).first() is not None
			)
			if has_attempts and not questions_ok:
				# Preserve existing attempts and their snapshotted revision/answers.
				skipped += 1
				continue

			if apply:
				if not meta_ok:
					for field in _METADATA_FIELDS:
						setattr(existing, field, getattr(desired, field))
				if not questions_ok:
					replace_questions(session, qid, desired.questions)
					existing.revision = int(existing.revision or 1) + 1
				if needs_publish:
					existing.is_published = True
				existing.updated_at = now
			updated += 1

		if apply:
			session.commit()
		else:
			session.rollback()
	except Exception:
		session.rollback()
		raise

	return {
		"created": created,
		"updated": updated,
		"skipped": skipped,
		"invalid": 0,
		"errors": [],
	}
