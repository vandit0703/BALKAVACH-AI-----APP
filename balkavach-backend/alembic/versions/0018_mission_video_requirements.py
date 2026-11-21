"""Add mission video requirements and isolated verified watch sessions."""

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import postgresql

revision = "0018_mission_video_requirements"
down_revision = "0016_child_video_daily_allowance"
branch_labels = None
depends_on = None


def upgrade() -> None:
	op.add_column("tasks", sa.Column("required_video_seconds", sa.Integer(), nullable=True))
	op.create_check_constraint(
		"tasks_required_video_seconds_check",
		"tasks",
		"required_video_seconds IS NULL OR required_video_seconds BETWEEN 1 AND 86400",
	)
	op.create_table(
		"mission_video_watch_sessions",
		sa.Column("id", postgresql.UUID(as_uuid=True), nullable=False),
		sa.Column("client_session_id", sa.String(32), nullable=False),
		sa.Column("task_id", postgresql.UUID(as_uuid=True), nullable=False),
		sa.Column("child_id", postgresql.UUID(as_uuid=True), nullable=False),
		sa.Column("video_id", postgresql.UUID(as_uuid=True), nullable=False),
		sa.Column("started_at", sa.DateTime(timezone=True), nullable=False),
		sa.Column("last_heartbeat_at", sa.DateTime(timezone=True), nullable=False),
		sa.Column("ended_at", sa.DateTime(timezone=True), nullable=True),
		sa.Column("last_position_seconds", sa.Integer(), server_default="0", nullable=False),
		sa.Column("watched_seconds", sa.Integer(), server_default="0", nullable=False),
		sa.Column("last_sequence", sa.Integer(), server_default="-1", nullable=False),
		sa.Column("is_playing", sa.Boolean(), server_default=sa.false(), nullable=False),
		sa.Column("status", sa.String(16), nullable=False),
		sa.PrimaryKeyConstraint("id", name="mission_video_watch_sessions_pkey"),
		sa.UniqueConstraint("client_session_id", name="uq_mission_video_client_session"),
		sa.ForeignKeyConstraint(["task_id"], ["tasks.id"], ondelete="RESTRICT"),
		sa.ForeignKeyConstraint(["child_id"], ["child_profiles.id"], ondelete="RESTRICT"),
		sa.ForeignKeyConstraint(["video_id"], ["videos.id"], ondelete="RESTRICT"),
		sa.CheckConstraint("last_position_seconds >= 0", name="mission_video_position_check"),
		sa.CheckConstraint("watched_seconds >= 0", name="mission_video_watched_check"),
		sa.CheckConstraint("last_sequence >= -1", name="mission_video_sequence_check"),
		sa.CheckConstraint("status IN ('active', 'interrupted', 'completed')", name="mission_video_status_check"),
	)
	op.create_index(
		"uq_mission_video_one_active_per_child",
		"mission_video_watch_sessions",
		["child_id"],
		unique=True,
		postgresql_where=sa.text("status = 'active'"),
	)
	op.create_index(
		"ix_mission_video_progress",
		"mission_video_watch_sessions",
		["task_id", "child_id"],
	)


def downgrade() -> None:
	op.drop_index("ix_mission_video_progress", table_name="mission_video_watch_sessions")
	op.drop_index("uq_mission_video_one_active_per_child", table_name="mission_video_watch_sessions")
	op.drop_table("mission_video_watch_sessions")
	op.drop_constraint("tasks_required_video_seconds_check", "tasks", type_="check")
	op.drop_column("tasks", "required_video_seconds")