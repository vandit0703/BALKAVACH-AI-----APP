"""Version-controlled, curated quiz content pack for BALKAVACH.

Each entry has a stable ``slug`` (used to derive a deterministic UUID5 primary
key so repeated seed runs are idempotent without altering the database schema)
and a ``quiz`` dict validated by ``app.schemas.quiz.QuizWrite``.
"""

from __future__ import annotations

from uuid import UUID, uuid5

from app.content.quizzes.en_quizzes import EN_QUIZZES
from app.content.quizzes.gu_quizzes import GU_QUIZZES
from app.content.quizzes.hi_quizzes import HI_QUIZZES

# Fixed namespace for deterministic seeded quiz IDs.
QUIZ_SEED_NAMESPACE = UUID("7b2e6a8c-4f1d-4d9a-9c3e-2a8f5b1d0e42")

QUIZ_PACK: tuple[dict, ...] = (
	*EN_QUIZZES,
	*HI_QUIZZES,
	*GU_QUIZZES,
)


def quiz_uuid(slug: str) -> UUID:
	"""Return the deterministic UUID5 primary key for a seeded quiz slug."""
	return uuid5(QUIZ_SEED_NAMESPACE, slug.strip().lower())
