"""Add explicit trusted YouTube channels and publication provenance.

Trusted channels are an admin-controlled signal, not a safety guarantee. New
videos still pass the normal metadata screening before automatic publication.
"""

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import postgresql

revision = "0010_youtube_trusted_channels"
down_revision = "0009_youtube_discovery_provenance"
branch_labels = None
depends_on = None


def upgrade() -> None:
	op.create_table(
		"youtube_trusted_channels",
		sa.Column("id", postgresql.UUID(as_uuid=True), server_default=sa.text("gen_random_uuid()"), nullable=False),
		sa.Column("channel_id", sa.String(length=64), nullable=False),
		sa.Column("channel_title", sa.String(length=200), nullable=True),
		sa.Column("age_min", sa.Integer(), nullable=False),
		sa.Column("age_max", sa.Integer(), nullable=False),
		sa.Column("language_code", sa.String(length=10), nullable=False),
		sa.Column("category_id", postgresql.UUID(as_uuid=True), nullable=True),
		sa.Column("rights_status", sa.String(length=20), nullable=False, server_default="unreviewed"),
		sa.Column("is_active", sa.Boolean(), nullable=False, server_default=sa.true()),
		sa.Column("created_by", postgresql.UUID(as_uuid=True), nullable=True),
		sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.text("now()"), nullable=False),
		sa.Column("updated_at", sa.DateTime(timezone=True), server_default=sa.text("now()"), nullable=False),
		sa.Column("notes", sa.Text(), nullable=True),
		sa.PrimaryKeyConstraint("id", name="youtube_trusted_channels_pkey"),
		sa.UniqueConstraint("channel_id", name="uq_youtube_trusted_channels_channel_id"),
		sa.ForeignKeyConstraint(["category_id"], ["video_categories.id"], ondelete="SET NULL", name="youtube_trusted_channels_category_id_fkey"),
		sa.ForeignKeyConstraint(["created_by"], ["users.id"], ondelete="SET NULL", name="youtube_trusted_channels_created_by_fkey"),
		sa.CheckConstraint("age_min >= 3 AND age_max <= 15 AND age_max >= age_min", name="youtube_trusted_channels_age_check"),
		sa.CheckConstraint("rights_status IN ('unreviewed', 'cleared', 'not_cleared')", name="youtube_trusted_channels_rights_check"),
		sa.CheckConstraint("channel_id ~ '^UC[A-Za-z0-9_-]{22}$'", name="youtube_trusted_channels_channel_id_check"),
	)
	op.create_index(
		"ix_youtube_trusted_channels_active",
		"youtube_trusted_channels",
		["is_active", "channel_id"],
	)
	op.add_column(
		"youtube_content_reviews",
		sa.Column("publication_source", sa.String(length=20), nullable=False, server_default="manual"),
	)
	op.add_column(
		"youtube_content_reviews",
		sa.Column("publication_reason", sa.Text(), nullable=True),
	)
	op.create_check_constraint(
		"youtube_content_reviews_publication_source_check",
		"youtube_content_reviews",
		"publication_source IN ('manual', 'automatic')",
	)


def downgrade() -> None:
	op.drop_constraint("youtube_content_reviews_publication_source_check", "youtube_content_reviews", type_="check")
	op.drop_column("youtube_content_reviews", "publication_reason")
	op.drop_column("youtube_content_reviews", "publication_source")
	op.drop_index("ix_youtube_trusted_channels_active", table_name="youtube_trusted_channels")
	op.drop_table("youtube_trusted_channels")
