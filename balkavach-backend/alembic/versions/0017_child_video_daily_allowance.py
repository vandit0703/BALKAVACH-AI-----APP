"""Track the daily free video allowance alongside per-child watch history."""

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import postgresql

revision = "0016_child_video_daily_allowance"
down_revision = ("0015_daily_mission_engine", "0015_trusted_channel_upload_discovery")
branch_labels = None
depends_on = None


def upgrade() -> None:
	op.create_table(
		"child_video_daily_usage",
		sa.Column("id", postgresql.UUID(as_uuid=True), server_default=sa.text("gen_random_uuid()"), nullable=False),
		sa.Column("child_id", postgresql.UUID(as_uuid=True), nullable=False),
		sa.Column("local_date", sa.Date(), nullable=False),
		sa.Column("free_watched_seconds", sa.Integer(), server_default="0", nullable=False),
		sa.Column("last_heartbeat_at", sa.DateTime(timezone=True), nullable=True),
		sa.Column("is_playing", sa.Boolean(), server_default=sa.false(), nullable=False),
		sa.PrimaryKeyConstraint("id", name="child_video_daily_usage_pkey"),
		sa.UniqueConstraint("child_id", "local_date", name="uq_child_video_daily_usage_child_date"),
		sa.ForeignKeyConstraint(["child_id"], ["child_profiles.id"], ondelete="CASCADE"),
		sa.CheckConstraint("free_watched_seconds >= 0", name="child_video_daily_usage_seconds_check"),
	)

def downgrade() -> None:
	op.drop_table("child_video_daily_usage")