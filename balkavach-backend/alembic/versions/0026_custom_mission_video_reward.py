"""Parent-configured video time per custom mission, and once-a-day video awards for repeating custom missions.

Additive only:
  - ``tasks.reward_video_seconds``: video seconds a parent configured for a custom mission (NULL = legacy row,
    which keeps the standard mission amount). Bounded by the largest daily cap a family can set (4 hours).
  - ``video_access_entitlements.repeat_reward_local_date``: the family-local day a repeating custom mission's
    video award belongs to (NULL for every other grant), with a partial unique index so one repeating mission
    can award video time to one child at most once per family-local day, even under concurrent approvals.
"""

import os

import sqlalchemy as sa
from alembic import op

revision = "0026_custom_mission_video_reward"
down_revision = "0025_auth_otp_challenges"
branch_labels = None
depends_on = None


def upgrade() -> None:
	if os.getenv("ALLOW_SCHEMA_MIGRATIONS", "true").lower() in ("false", "0"):
		raise RuntimeError("Schema migrations are disabled; set ALLOW_SCHEMA_MIGRATIONS=true")

	op.add_column("tasks", sa.Column("reward_video_seconds", sa.Integer(), nullable=True))
	op.create_check_constraint(
		"tasks_reward_video_seconds_check",
		"tasks",
		"reward_video_seconds IS NULL OR reward_video_seconds BETWEEN 0 AND 14400",
	)
	op.add_column(
		"video_access_entitlements",
		sa.Column("repeat_reward_local_date", sa.Date(), nullable=True),
	)
	op.create_index(
		"uq_video_entitlement_repeat_reward_day",
		"video_access_entitlements",
		["task_id", "child_id", "repeat_reward_local_date"],
		unique=True,
		postgresql_where=sa.text("repeat_reward_local_date IS NOT NULL"),
	)


def downgrade() -> None:
	op.drop_index("uq_video_entitlement_repeat_reward_day", table_name="video_access_entitlements")
	op.drop_column("video_access_entitlements", "repeat_reward_local_date")
	op.drop_constraint("tasks_reward_video_seconds_check", "tasks", type_="check")
	op.drop_column("tasks", "reward_video_seconds")
