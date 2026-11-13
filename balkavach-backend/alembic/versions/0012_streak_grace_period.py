"""Add grace-period and state tracking columns to child_streaks.

Extends child_streaks with four additive columns that drive the BalKavach
daily-streak grace-period state machine (Phase 2):
  - streak_state       – current FSM state (active / at_risk / broken / recovered)
  - grace_deadline     – UTC timestamp when the grace window closes (NULL when
                         active or permanently broken)
  - last_activity_at   – exact UTC timestamp of the last qualifying submission
  - streak_notified_state – last state for which a push notification was sent
"""

import os
import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import postgresql

revision = "0012_streak_grace_period"
down_revision = "0011_child_video_watch_history"
branch_labels = None
depends_on = None


def upgrade() -> None:
    if os.getenv("ALLOW_SCHEMA_MIGRATIONS", "true").lower() in ("false", "0"):
        raise RuntimeError("Schema migrations are disabled; set ALLOW_SCHEMA_MIGRATIONS=true")

    with op.batch_alter_table("child_streaks") as batch_op:
        batch_op.add_column(
            sa.Column(
                "streak_state",
                sa.String(length=16),
                server_default="active",
                nullable=False,
            )
        )
        batch_op.add_column(
            sa.Column(
                "grace_deadline",
                sa.DateTime(timezone=True),
                nullable=True,
            )
        )
        batch_op.add_column(
            sa.Column(
                "last_activity_at",
                sa.DateTime(timezone=True),
                nullable=True,
            )
        )
        batch_op.add_column(
            sa.Column(
                "streak_notified_state",
                sa.String(length=16),
                nullable=True,
            )
        )
        batch_op.create_check_constraint(
            "streak_state_check",
            "streak_state IN ('active', 'at_risk', 'broken', 'recovered')",
        )


def downgrade() -> None:
    with op.batch_alter_table("child_streaks") as batch_op:
        batch_op.drop_constraint("streak_state_check", type_="check")
        batch_op.drop_column("streak_notified_state")
        batch_op.drop_column("last_activity_at")
        batch_op.drop_column("grace_deadline")
        batch_op.drop_column("streak_state")
