"""Quiz system: quizzes, questions, options, attempts, answers and one-time reward grants.

Additive only: five new tables, no change to any existing table. The reward guarantee is
``quiz_reward_grants UNIQUE (child_id, quiz_id)``; the ledger rows it produces carry idempotency
keys scoped to the same pair, so a retry can never pay twice.
"""

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import postgresql

revision = "0021_quiz_system"
down_revision = "0020_youtube_channel_discovery_runs"
branch_labels = None
depends_on = None

_UUID = postgresql.UUID(as_uuid=True)
_ID = dict(server_default=sa.text("gen_random_uuid()"), nullable=False)
_NOW = dict(server_default=sa.text("now()"), nullable=False)


def upgrade() -> None:
	op.create_table(
		"quizzes",
		sa.Column("id", _UUID, **_ID),
		sa.Column("title", sa.Text(), nullable=False),
		sa.Column("description", sa.Text(), nullable=True),
		sa.Column("subject", sa.Text(), nullable=False, server_default="general"),
		sa.Column("difficulty", sa.Text(), nullable=False, server_default="easy"),
		sa.Column("language_code", sa.Text(), nullable=False, server_default="en"),
		sa.Column("age_min", sa.Integer(), nullable=False, server_default="4"),
		sa.Column("age_max", sa.Integer(), nullable=False, server_default="15"),
		sa.Column("pass_percent", sa.Integer(), nullable=False, server_default="60"),
		sa.Column("star_reward", sa.Integer(), nullable=False, server_default="0"),
		sa.Column("xp_reward", sa.Integer(), nullable=False, server_default="0"),
		sa.Column("allow_retry", sa.Boolean(), nullable=False, server_default=sa.true()),
		sa.Column("is_published", sa.Boolean(), nullable=False, server_default=sa.false()),
		# Bumped on every content change; an attempt remembers the revision it started on.
		sa.Column("revision", sa.Integer(), nullable=False, server_default="1"),
		sa.Column("created_by", _UUID, nullable=True),
		sa.Column("created_at", sa.DateTime(), **_NOW),
		sa.Column("updated_at", sa.DateTime(), **_NOW),
		sa.PrimaryKeyConstraint("id", name="quizzes_pkey"),
		sa.ForeignKeyConstraint(["created_by"], ["users.id"], ondelete="SET NULL"),
		sa.CheckConstraint("difficulty IN ('easy','medium','hard')", name="quizzes_difficulty_check"),
		sa.CheckConstraint("pass_percent BETWEEN 1 AND 100", name="quizzes_pass_percent_check"),
		sa.CheckConstraint("star_reward >= 0 AND xp_reward >= 0", name="quizzes_reward_check"),
		sa.CheckConstraint("age_min >= 0 AND age_max >= age_min", name="quizzes_age_check"),
	)
	op.create_index("ix_quizzes_published_language", "quizzes", ["is_published", "language_code"])

	op.create_table(
		"quiz_questions",
		sa.Column("id", _UUID, **_ID),
		sa.Column("quiz_id", _UUID, nullable=False),
		sa.Column("position", sa.Integer(), nullable=False),
		sa.Column("prompt", sa.Text(), nullable=False),
		sa.Column("question_type", sa.Text(), nullable=False),
		sa.Column("explanation", sa.Text(), nullable=True),
		sa.PrimaryKeyConstraint("id", name="quiz_questions_pkey"),
		sa.ForeignKeyConstraint(["quiz_id"], ["quizzes.id"], ondelete="CASCADE"),
		sa.UniqueConstraint("quiz_id", "position", name="uq_quiz_questions_position"),
		sa.CheckConstraint("question_type IN ('single','multiple','true_false')", name="quiz_questions_type_check"),
	)

	op.create_table(
		"quiz_options",
		sa.Column("id", _UUID, **_ID),
		sa.Column("question_id", _UUID, nullable=False),
		sa.Column("position", sa.Integer(), nullable=False),
		sa.Column("text", sa.Text(), nullable=False),
		sa.Column("is_correct", sa.Boolean(), nullable=False, server_default=sa.false()),
		sa.PrimaryKeyConstraint("id", name="quiz_options_pkey"),
		sa.ForeignKeyConstraint(["question_id"], ["quiz_questions.id"], ondelete="CASCADE"),
		sa.UniqueConstraint("question_id", "position", name="uq_quiz_options_position"),
	)

	op.create_table(
		"quiz_attempts",
		sa.Column("id", _UUID, **_ID),
		sa.Column("quiz_id", _UUID, nullable=False),
		sa.Column("child_id", _UUID, nullable=False),
		sa.Column("status", sa.Text(), nullable=False, server_default="in_progress"),
		sa.Column("quiz_revision", sa.Integer(), nullable=False),
		# Snapshots taken when the attempt starts: later quiz edits never change this attempt.
		sa.Column("pass_percent", sa.Integer(), nullable=False),
		sa.Column("star_reward", sa.Integer(), nullable=False, server_default="0"),
		sa.Column("xp_reward", sa.Integer(), nullable=False, server_default="0"),
		sa.Column("started_at", sa.DateTime(), **_NOW),
		sa.Column("submitted_at", sa.DateTime(), nullable=True),
		sa.Column("total_questions", sa.Integer(), nullable=True),
		sa.Column("correct_count", sa.Integer(), nullable=True),
		sa.Column("score_percent", sa.Integer(), nullable=True),
		sa.Column("passed", sa.Boolean(), nullable=True),
		sa.Column("stars_awarded", sa.Integer(), nullable=False, server_default="0"),
		sa.Column("xp_awarded", sa.Integer(), nullable=False, server_default="0"),
		sa.PrimaryKeyConstraint("id", name="quiz_attempts_pkey"),
		sa.ForeignKeyConstraint(["quiz_id"], ["quizzes.id"], ondelete="CASCADE"),
		sa.ForeignKeyConstraint(["child_id"], ["child_profiles.id"], ondelete="CASCADE"),
		sa.CheckConstraint("status IN ('in_progress','submitted')", name="quiz_attempts_status_check"),
		sa.CheckConstraint("stars_awarded >= 0 AND xp_awarded >= 0", name="quiz_attempts_awarded_check"),
	)
	op.create_index("ix_quiz_attempts_child_quiz", "quiz_attempts", ["child_id", "quiz_id", "started_at"])
	# At most one open attempt per child and quiz: "start" is idempotent and cannot be raced.
	op.create_index(
		"uq_quiz_attempts_one_open",
		"quiz_attempts",
		["child_id", "quiz_id"],
		unique=True,
		postgresql_where=sa.text("status = 'in_progress'"),
	)

	op.create_table(
		"quiz_attempt_answers",
		sa.Column("id", _UUID, **_ID),
		sa.Column("attempt_id", _UUID, nullable=False),
		sa.Column("question_id", _UUID, nullable=False),
		sa.Column("selected_option_ids", postgresql.JSONB(), nullable=False, server_default=sa.text("'[]'::jsonb")),
		sa.Column("is_correct", sa.Boolean(), nullable=False),
		sa.PrimaryKeyConstraint("id", name="quiz_attempt_answers_pkey"),
		sa.ForeignKeyConstraint(["attempt_id"], ["quiz_attempts.id"], ondelete="CASCADE"),
		sa.ForeignKeyConstraint(["question_id"], ["quiz_questions.id"], ondelete="CASCADE"),
		sa.UniqueConstraint("attempt_id", "question_id", name="uq_quiz_attempt_answers_question"),
	)

	op.create_table(
		"quiz_reward_grants",
		sa.Column("id", _UUID, **_ID),
		sa.Column("child_id", _UUID, nullable=False),
		sa.Column("quiz_id", _UUID, nullable=False),
		sa.Column("attempt_id", _UUID, nullable=False),
		sa.Column("stars", sa.Integer(), nullable=False, server_default="0"),
		sa.Column("xp", sa.Integer(), nullable=False, server_default="0"),
		sa.Column("created_at", sa.DateTime(), **_NOW),
		sa.PrimaryKeyConstraint("id", name="quiz_reward_grants_pkey"),
		sa.ForeignKeyConstraint(["child_id"], ["child_profiles.id"], ondelete="CASCADE"),
		sa.ForeignKeyConstraint(["quiz_id"], ["quizzes.id"], ondelete="CASCADE"),
		sa.ForeignKeyConstraint(["attempt_id"], ["quiz_attempts.id"], ondelete="CASCADE"),
		# The one-time guarantee: a child can be granted a quiz's reward exactly once.
		sa.UniqueConstraint("child_id", "quiz_id", name="uq_quiz_reward_grants_child_quiz"),
		sa.CheckConstraint("stars >= 0 AND xp >= 0", name="quiz_reward_grants_amount_check"),
	)


def downgrade() -> None:
	op.drop_table("quiz_reward_grants")
	op.drop_table("quiz_attempt_answers")
	op.drop_index("uq_quiz_attempts_one_open", table_name="quiz_attempts")
	op.drop_index("ix_quiz_attempts_child_quiz", table_name="quiz_attempts")
	op.drop_table("quiz_attempts")
	op.drop_table("quiz_options")
	op.drop_table("quiz_questions")
	op.drop_index("ix_quizzes_published_language", table_name="quizzes")
	op.drop_table("quizzes")
