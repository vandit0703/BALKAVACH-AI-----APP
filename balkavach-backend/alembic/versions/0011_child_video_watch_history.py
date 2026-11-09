"""Add persistent per-child video watch history.

Playback entitlement sessions remain separate; this table records viewing
progress used by child feeds and parent history views.
"""

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import postgresql

revision = "0011_child_video_watch_history"
down_revision = "0010_youtube_trusted_channels"
branch_labels = None
depends_on = None


def upgrade() -> None:
	op.create_table(
		"child_video_watch_history",
		sa.Column("id", postgresql.UUID(as_uuid=True), server_default=sa.text("gen_random_uuid()"), nullable=False),
		sa.Column("child_id", postgresql.UUID(as_uuid=True), nullable=False),
		sa.Column("video_id", postgresql.UUID(as_uuid=True), nullable=False),
		sa.Column("youtube_video_id", sa.String(length=11), nullable=True),
		sa.Column("video_format", sa.String(length=10), nullable=False),
		sa.Column("started_at", sa.DateTime(timezone=True), server_default=sa.text("now()"), nullable=False),
		sa.Column("last_watched_at", sa.DateTime(timezone=True), server_default=sa.text("now()"), nullable=False),
		sa.Column("last_position_seconds", sa.Integer(), server_default=sa.text("0"), nullable=False),
		sa.Column("watch_duration_seconds", sa.Integer(), server_default=sa.text("0"), nullable=False),
		sa.Column("completion_percentage", sa.Integer(), server_default=sa.text("0"), nullable=False),
		sa.Column("is_completed", sa.Boolean(), server_default=sa.false(), nullable=False),
		sa.Column("parent_replay_authorized", sa.Boolean(), server_default=sa.false(), nullable=False),
		sa.Column("completed_at", sa.DateTime(timezone=True), nullable=True),
		sa.PrimaryKeyConstraint("id", name="child_video_watch_history_pkey"),
		sa.UniqueConstraint("child_id", "video_id", name="uq_child_video_watch_history_child_video"),
		sa.ForeignKeyConstraint(["child_id"], ["child_profiles.id"], ondelete="CASCADE", name="child_video_watch_history_child_id_fkey"),
		sa.ForeignKeyConstraint(["video_id"], ["videos.id"], ondelete="CASCADE", name="child_video_watch_history_video_id_fkey"),
		sa.CheckConstraint("video_format IN ('short', 'regular')", name="child_video_watch_history_format_check"),
		sa.CheckConstraint("last_position_seconds >= 0 AND watch_duration_seconds >= 0", name="child_video_watch_history_progress_check"),
		sa.CheckConstraint("completion_percentage BETWEEN 0 AND 100", name="child_video_watch_history_completion_check"),
	)
	op.create_index(
		"ix_child_video_watch_history_child_completed_last_watched",
		"child_video_watch_history",
		["child_id", "is_completed", "last_watched_at"],
	)


def downgrade() -> None:
	op.drop_index(
		"ix_child_video_watch_history_child_completed_last_watched",
		table_name="child_video_watch_history",
	)
	op.drop_table("child_video_watch_history")