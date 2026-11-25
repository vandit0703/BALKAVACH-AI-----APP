"""Quiz endpoints: the child experience (``/quizzes``) and admin management (``/admin/quizzes``)."""

from datetime import datetime, timezone
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, Query, Response, status
from sqlalchemy import func
from sqlalchemy.orm import Session

from app.core.dependencies import require_admin_permission, require_child, require_parent
from app.core.exceptions import APIError
from app.db.base import get_model
from app.db.session import get_db
from app.schemas.quiz import (
	AdminQuizDetail,
	AdminQuizSummary,
	AttemptHistoryItem,
	AttemptResult,
	AttemptStarted,
	AttemptSubmit,
	ChildQuizSummary,
	PublishedUpdate,
	QuizWrite,
)
from app.services import quiz_service
from app.services.admin_service import record_audit
from app.utils import utc_naive

router = APIRouter(prefix="/quizzes", tags=["quizzes"])
admin_router = APIRouter(prefix="/admin/quizzes", tags=["admin quizzes"])


# -- child ---------------------------------------------------------------------------------------


@router.get("", response_model=list[ChildQuizSummary])
def list_my_quizzes(child=Depends(require_child), session: Session = Depends(get_db)):
	return quiz_service.list_quizzes(session, child)


# Literal paths are declared before "/{quiz_id}" so "history" is never read as an id.
@router.get("/history", response_model=list[AttemptHistoryItem])
def my_quiz_history(
	limit: int = Query(default=50, ge=1, le=100),
	child=Depends(require_child),
	session: Session = Depends(get_db),
):
	return quiz_service.attempt_history(session, child, limit)


@router.get("/children/{child_id}/history", response_model=list[AttemptHistoryItem])
def parent_child_quiz_history(
	child_id: UUID,
	limit: int = Query(default=50, ge=1, le=100),
	offset: int = Query(default=0, ge=0),
	parent=Depends(require_parent),
	session: Session = Depends(get_db),
):
	"""Read-only: a parent's view of one child's submitted quiz attempts (title, date, result, score, rewards).

	The child must belong to one of the parent's active families; anything else is a 404, exactly like the
	progress endpoints. Questions, answers and the review are never returned, and nothing is written."""
	ChildProfile = get_model("ChildProfile")
	FamilyMember = get_model("FamilyMember")
	child = session.query(ChildProfile).filter(ChildProfile.id == child_id, ChildProfile.is_active.is_(True)).one_or_none()
	member = None
	if child is not None:
		member = (
			session.query(FamilyMember.id)
			.filter(
				FamilyMember.family_id == child.family_id,
				FamilyMember.user_id == parent.id,
				FamilyMember.is_active.is_(True),
			)
			.first()
		)
	if child is None or member is None:
		raise HTTPException(status_code=404, detail="Child profile not found")
	return quiz_service.attempt_history_for(session, child.id, limit, offset)


@router.get("/attempts/{attempt_id}", response_model=AttemptResult)
def get_my_attempt_result(attempt_id: UUID, child=Depends(require_child), session: Session = Depends(get_db)):
	return quiz_service.build_result(session, child, attempt_id)


@router.post("/attempts/{attempt_id}/submit", response_model=AttemptResult)
def submit_my_attempt(
	attempt_id: UUID,
	body: AttemptSubmit,
	child=Depends(require_child),
	session: Session = Depends(get_db),
):
	return quiz_service.submit_attempt(session, child, attempt_id, body)


@router.get("/{quiz_id}", response_model=ChildQuizSummary)
def get_my_quiz(quiz_id: UUID, child=Depends(require_child), session: Session = Depends(get_db)):
	return quiz_service.get_quiz_summary(session, child, quiz_id)


@router.post("/{quiz_id}/attempts", response_model=AttemptStarted, status_code=status.HTTP_201_CREATED)
def start_my_attempt(quiz_id: UUID, child=Depends(require_child), session: Session = Depends(get_db)):
	return quiz_service.start_attempt(session, child, quiz_id)


# -- admin ---------------------------------------------------------------------------------------


def _quiz_or_404(session: Session, quiz_id: UUID):
	Quiz = get_model("Quiz")
	quiz = session.query(Quiz).filter(Quiz.id == quiz_id).one_or_none()
	if quiz is None:
		raise APIError(404, "quiz_not_found", "Quiz not found")
	return quiz


def _now() -> datetime:
	return utc_naive(datetime.now(timezone.utc))


_FIELDS = (
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


@admin_router.get("", response_model=list[AdminQuizSummary])
def admin_list_quizzes(
	limit: int = Query(default=100, ge=1, le=200),
	offset: int = Query(default=0, ge=0),
	admin=Depends(require_admin_permission("content:read")),
	session: Session = Depends(get_db),
):
	Quiz = get_model("Quiz")
	QuizQuestion = get_model("QuizQuestion")
	QuizAttempt = get_model("QuizAttempt")
	quizzes = session.query(Quiz).order_by(Quiz.created_at.desc(), Quiz.id).offset(offset).limit(limit).all()
	ids = [quiz.id for quiz in quizzes]
	questions = dict(
		session.query(QuizQuestion.quiz_id, func.count(QuizQuestion.id))
		.filter(QuizQuestion.quiz_id.in_(ids))
		.group_by(QuizQuestion.quiz_id)
		.all()
	)
	attempts = dict(
		session.query(QuizAttempt.quiz_id, func.count(QuizAttempt.id))
		.filter(QuizAttempt.quiz_id.in_(ids))
		.group_by(QuizAttempt.quiz_id)
		.all()
	)
	return [
		AdminQuizSummary(
			**{name: getattr(quiz, name) for name in AdminQuizSummary.model_fields if hasattr(quiz, name)},
			question_count=int(questions.get(quiz.id, 0)),
			attempt_count=int(attempts.get(quiz.id, 0)),
		)
		for quiz in quizzes
	]


@admin_router.get("/{quiz_id}", response_model=AdminQuizDetail)
def admin_get_quiz(
	quiz_id: UUID,
	admin=Depends(require_admin_permission("content:read")),
	session: Session = Depends(get_db),
):
	return quiz_service.admin_detail(session, _quiz_or_404(session, quiz_id))


@admin_router.post("", response_model=AdminQuizDetail, status_code=status.HTTP_201_CREATED)
def admin_create_quiz(
	body: QuizWrite,
	admin=Depends(require_admin_permission("content:write")),
	session: Session = Depends(get_db),
):
	Quiz = get_model("Quiz")
	now = _now()
	quiz = Quiz(
		**{name: getattr(body, name) for name in _FIELDS},
		is_published=False,
		revision=1,
		created_by=admin.id,
		created_at=now,
		updated_at=now,
	)
	try:
		session.add(quiz)
		session.flush()
		quiz_service.replace_questions(session, quiz.id, body.questions)
		record_audit(session, admin.id, "quiz.created", "quiz", quiz.id, {})
		session.commit()
	except Exception:
		session.rollback()
		raise
	return quiz_service.admin_detail(session, quiz)


@admin_router.put("/{quiz_id}", response_model=AdminQuizDetail)
def admin_update_quiz(
	quiz_id: UUID,
	body: QuizWrite,
	admin=Depends(require_admin_permission("content:write")),
	session: Session = Depends(get_db),
):
	"""Replace a quiz's settings and questions. Only an unpublished quiz can change, so a child never
	sees a quiz mid-edit; the revision bump invalidates any attempt started on the old content."""
	quiz = _quiz_or_404(session, quiz_id)
	if quiz.is_published:
		raise APIError(409, "unpublish_first", "Unpublish the quiz before editing it")
	try:
		for name in _FIELDS:
			setattr(quiz, name, getattr(body, name))
		quiz.revision = int(quiz.revision) + 1
		quiz.updated_at = _now()
		quiz_service.replace_questions(session, quiz.id, body.questions)
		record_audit(session, admin.id, "quiz.updated", "quiz", quiz.id, {"revision": quiz.revision})
		session.commit()
	except Exception:
		session.rollback()
		raise
	return quiz_service.admin_detail(session, quiz)


@admin_router.patch("/{quiz_id}/published", response_model=AdminQuizDetail)
def admin_set_quiz_published(
	quiz_id: UUID,
	body: PublishedUpdate,
	admin=Depends(require_admin_permission("content:write")),
	session: Session = Depends(get_db),
):
	QuizQuestion = get_model("QuizQuestion")
	quiz = _quiz_or_404(session, quiz_id)
	if body.is_published:
		count = session.query(func.count(QuizQuestion.id)).filter(QuizQuestion.quiz_id == quiz.id).scalar()
		if not count:
			raise APIError(422, "quiz_incomplete", "Add at least one question before publishing")
	try:
		quiz.is_published = body.is_published
		quiz.updated_at = _now()
		record_audit(
			session, admin.id, "quiz.published" if body.is_published else "quiz.unpublished", "quiz", quiz.id, {}
		)
		session.commit()
	except Exception:
		session.rollback()
		raise
	return quiz_service.admin_detail(session, quiz)


@admin_router.delete("/{quiz_id}", status_code=status.HTTP_204_NO_CONTENT)
def admin_delete_quiz(
	quiz_id: UUID,
	admin=Depends(require_admin_permission("content:write")),
	session: Session = Depends(get_db),
):
	"""Only a never-attempted draft can be deleted; anything with history is unpublished instead."""
	QuizAttempt = get_model("QuizAttempt")
	quiz = _quiz_or_404(session, quiz_id)
	if quiz.is_published:
		raise APIError(409, "unpublish_first", "Unpublish the quiz before deleting it")
	if session.query(QuizAttempt.id).filter(QuizAttempt.quiz_id == quiz.id).first():
		raise APIError(409, "quiz_has_history", "This quiz has attempts and is kept for history")
	try:
		record_audit(session, admin.id, "quiz.deleted", "quiz", quiz.id, {})
		session.delete(quiz)
		session.commit()
	except Exception:
		session.rollback()
		raise
	return Response(status_code=status.HTTP_204_NO_CONTENT)
