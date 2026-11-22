"""Structured mission instructions on daily_mission_variations (additive, nullable).

Adds four nullable columns. Nothing is dropped, rewritten or backfilled here: existing rows keep every
current value and every id, so assignments, snapshots, submissions and approvals are untouched.
Content is filled later by ``app.cli seed-daily-missions --backfill-structured`` or by an admin edit.

Dependencies: 0018_mission_video_requirements (the single head when this was written).
PostgreSQL: ADD COLUMN with no default and NULL allowed is a catalogue-only change (no table rewrite).
"""

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import postgresql

revision = "0019_mission_instruction_fields"
down_revision = "0018_mission_video_requirements"
branch_labels = None
depends_on = None

_TABLE = "daily_mission_variations"


def upgrade() -> None:
    op.add_column(_TABLE, sa.Column("learning_objective", sa.Text(), nullable=True))
    op.add_column(_TABLE, sa.Column("steps", postgresql.JSONB(), nullable=True))
    op.add_column(_TABLE, sa.Column("observation_guidance", sa.Text(), nullable=True))
    op.add_column(_TABLE, sa.Column("submission_requirements", sa.Text(), nullable=True))


def downgrade() -> None:
    op.drop_column(_TABLE, "submission_requirements")
    op.drop_column(_TABLE, "observation_guidance")
    op.drop_column(_TABLE, "steps")
    op.drop_column(_TABLE, "learning_objective")
