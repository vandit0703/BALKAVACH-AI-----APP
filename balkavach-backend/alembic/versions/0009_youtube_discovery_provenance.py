"""Store YouTube discovery topic and category provenance.

Revision ID: 0009_youtube_discovery_provenance
Revises: 0008_youtube_content_review
"""

import sqlalchemy as sa
from alembic import op

revision = "0009_youtube_discovery_provenance"
down_revision = "0008_youtube_content_review"
branch_labels = None
depends_on = None


def upgrade() -> None:
	op.add_column(
		"youtube_content_reviews",
		sa.Column("discovery_topic", sa.String(length=40), nullable=True),
	)
	op.add_column(
		"youtube_content_reviews",
		sa.Column("youtube_category_id", sa.String(length=20), nullable=True),
	)


def downgrade() -> None:
	op.drop_column("youtube_content_reviews", "youtube_category_id")
	op.drop_column("youtube_content_reviews", "discovery_topic")
