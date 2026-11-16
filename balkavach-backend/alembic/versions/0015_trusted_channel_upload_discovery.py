"""Make trusted-channel overrides optional and persist upload scan progress."""

import sqlalchemy as sa
from alembic import op

revision = "0015_trusted_channel_upload_discovery"
down_revision = "0014_auth_security_controls"
branch_labels = None
depends_on = None


def upgrade() -> None:
	op.alter_column("youtube_trusted_channels", "age_min", existing_type=sa.Integer(), nullable=True)
	op.alter_column("youtube_trusted_channels", "age_max", existing_type=sa.Integer(), nullable=True)
	op.alter_column("youtube_trusted_channels", "language_code", existing_type=sa.String(length=10), nullable=True)
	op.add_column("youtube_trusted_channels", sa.Column("thumbnail_url", sa.String(length=1000), nullable=True))
	op.add_column("youtube_trusted_channels", sa.Column("uploads_scan_complete", sa.Boolean(), server_default=sa.false(), nullable=False))
	op.add_column("youtube_trusted_channels", sa.Column("uploads_page_token", sa.String(length=128), nullable=True))
	op.add_column("youtube_trusted_channels", sa.Column("uploads_latest_video_id", sa.String(length=11), nullable=True))


def downgrade() -> None:
	op.drop_column("youtube_trusted_channels", "uploads_latest_video_id")
	op.drop_column("youtube_trusted_channels", "uploads_page_token")
	op.drop_column("youtube_trusted_channels", "uploads_scan_complete")
	op.drop_column("youtube_trusted_channels", "thumbnail_url")
	op.execute("UPDATE youtube_trusted_channels SET age_min = 3 WHERE age_min IS NULL")
	op.execute("UPDATE youtube_trusted_channels SET age_max = 15 WHERE age_max IS NULL")
	op.execute("UPDATE youtube_trusted_channels SET language_code = 'en' WHERE language_code IS NULL")
	op.alter_column("youtube_trusted_channels", "language_code", existing_type=sa.String(length=10), nullable=False)
	op.alter_column("youtube_trusted_channels", "age_max", existing_type=sa.Integer(), nullable=False)
	op.alter_column("youtube_trusted_channels", "age_min", existing_type=sa.Integer(), nullable=False)