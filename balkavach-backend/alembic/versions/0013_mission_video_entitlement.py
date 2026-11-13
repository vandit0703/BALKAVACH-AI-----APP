"""Add mission-earned video entitlement columns and constraints.

Extends video_access_entitlements with columns supporting Phase 3:
  - task_id       – foreign key referencing tasks.id (nullable)
  - submission_id – foreign key referencing task_submissions.id (nullable, unique for idempotency)
  - source_type   – discriminator ('star_redemption' vs 'mission_reward')
"""

import os
import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import postgresql

revision = "0013_mission_video_entitlement"
down_revision = "0012_streak_grace_period"
branch_labels = None
depends_on = None


def upgrade() -> None:
    if os.getenv("ALLOW_SCHEMA_MIGRATIONS", "true").lower() in ("false", "0"):
        raise RuntimeError("Schema migrations are disabled; set ALLOW_SCHEMA_MIGRATIONS=true")

    with op.batch_alter_table("video_access_entitlements") as batch_op:
        batch_op.add_column(
            sa.Column(
                "task_id",
                postgresql.UUID(as_uuid=True),
                sa.ForeignKey("tasks.id", ondelete="SET NULL"),
                nullable=True,
            )
        )
        batch_op.add_column(
            sa.Column(
                "submission_id",
                postgresql.UUID(as_uuid=True),
                sa.ForeignKey("task_submissions.id", ondelete="SET NULL"),
                nullable=True,
                unique=True,
            )
        )
        batch_op.add_column(
            sa.Column(
                "source_type",
                sa.String(length=32),
                server_default="star_redemption",
                nullable=False,
            )
        )
        batch_op.create_check_constraint(
            "source_type_check",
            "source_type IN ('star_redemption', 'mission_reward')",
        )
        batch_op.create_index(
            "ix_video_access_entitlements_child_source",
            ["child_id", "status", "source_type"],
        )


def downgrade() -> None:
    with op.batch_alter_table("video_access_entitlements") as batch_op:
        batch_op.drop_index("ix_video_access_entitlements_child_source")
        batch_op.drop_constraint("source_type_check", type_="check")
        batch_op.drop_column("source_type")
        batch_op.drop_column("submission_id")
        batch_op.drop_column("task_id")

