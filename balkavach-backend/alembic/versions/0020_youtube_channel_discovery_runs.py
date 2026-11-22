"""Track per-channel YouTube discovery executions.

Manual "Discover More" and channel-specific discovery runs need durable,
queryable history so the admin UI can show real execution results and prevent
overlapping runs for the same channel. This does not change existing global or
trusted-channel discovery behaviour.
"""

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import postgresql

revision = "0020_youtube_channel_discovery_runs"
down_revision = "0019_mission_instruction_fields"
branch_labels = None
depends_on = None


def upgrade() -> None:
	op.create_table(
		"youtube_channel_discovery_runs",
		sa.Column(
			"id",
			postgresql.UUID(as_uuid=True),
			server_default=sa.text("gen_random_uuid()"),
			nullable=False,
		),
		sa.Column("channel_id", sa.String(length=64), nullable=False),
		sa.Column("triggered_by", postgresql.UUID(as_uuid=True), nullable=True),
		sa.Column("trigger", sa.String(length=30), nullable=False, server_default="manual"),
		sa.Column("status", sa.String(length=20), nullable=False, server_default="running"),
		sa.Column("started_at", sa.DateTime(timezone=True), server_default=sa.text("now()"), nullable=False),
		sa.Column("completed_at", sa.DateTime(timezone=True), nullable=True),
		sa.Column("scanned_videos", sa.Integer(), nullable=False, server_default="0"),
		sa.Column("new_videos", sa.Integer(), nullable=False, server_default="0"),
		sa.Column("duplicate_videos", sa.Integer(), nullable=False, server_default="0"),
		sa.Column("shorts_count", sa.Integer(), nullable=False, server_default="0"),
		sa.Column("long_videos_count", sa.Integer(), nullable=False, server_default="0"),
		sa.Column("auto_approved_count", sa.Integer(), nullable=False, server_default="0"),
		sa.Column("pending_review_count", sa.Integer(), nullable=False, server_default="0"),
		sa.Column("quarantined_count", sa.Integer(), nullable=False, server_default="0"),
		sa.Column("unavailable_count", sa.Integer(), nullable=False, server_default="0"),
		sa.Column("error_count", sa.Integer(), nullable=False, server_default="0"),
		sa.Column("error_message", sa.Text(), nullable=True),
		sa.ForeignKeyConstraint(
			["channel_id"],
			["youtube_trusted_channels.channel_id"],
			ondelete="CASCADE",
			name="youtube_channel_discovery_runs_channel_id_fkey",
		),
		sa.ForeignKeyConstraint(
			["triggered_by"],
			["users.id"],
			ondelete="SET NULL",
			name="youtube_channel_discovery_runs_triggered_by_fkey",
		),
		sa.PrimaryKeyConstraint("id", name="youtube_channel_discovery_runs_pkey"),
		sa.CheckConstraint(
			"status IN ('running', 'completed', 'failed')",
			name="youtube_channel_discovery_runs_status_check",
		),
		sa.CheckConstraint(
			"trigger IN ('manual', 'trust', 'scheduled')",
			name="youtube_channel_discovery_runs_trigger_check",
		),
		sa.CheckConstraint("channel_id ~ '^UC[A-Za-z0-9_-]{22}$'", name="youtube_channel_discovery_runs_channel_id_check"),
	)
	op.create_index(
		"ix_youtube_channel_discovery_runs_channel_started",
		"youtube_channel_discovery_runs",
		["channel_id", "started_at"],
	)
	op.create_index(
		"ix_youtube_channel_discovery_runs_status",
		"youtube_channel_discovery_runs",
		["status"],
	)


def downgrade() -> None:
	op.drop_index("ix_youtube_channel_discovery_runs_status", table_name="youtube_channel_discovery_runs")
	op.drop_index("ix_youtube_channel_discovery_runs_channel_started", table_name="youtube_channel_discovery_runs")
	op.drop_table("youtube_channel_discovery_runs")
