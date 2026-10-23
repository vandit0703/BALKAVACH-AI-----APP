"""Review state for YouTube-sourced videos, and parent content reports.

Revision ID: 0008_youtube_content_review
Revises: 0007_child_credentials
Create Date: 2026-10-23

Additive only: two new tables, no change to existing tables. A YouTube video is
still a row in ``videos`` (``video_source = 'youtube'``); its moderation state
lives in ``youtube_content_reviews``. The child feed shows a YouTube row only
while its review is ``approved`` and recently re-verified, so if this migration
is rolled back the feed simply stops showing YouTube videos (fails closed).

Rollback: ``alembic downgrade 0007_child_credentials`` drops both tables and the
review/report history they hold. Take a backup first if that history matters.
"""

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import postgresql

revision = "0008_youtube_content_review"
down_revision = "0007_child_credentials"
branch_labels = None
depends_on = None

REVIEW_STATUSES = ("discovered", "pending_review", "approved", "rejected", "quarantined", "revoked", "unavailable")
RIGHTS_STATUSES = ("unreviewed", "cleared", "not_cleared")
REPORT_REASONS = ("inappropriate", "scary", "violent", "misleading", "advertising", "other")
REPORT_STATUSES = ("open", "resolved", "dismissed")


def _in(column: str, values: tuple[str, ...]) -> str:
	return f"{column} IN ({', '.join(repr(value) for value in values)})"


def upgrade() -> None:
	inspector = sa.inspect(op.get_bind())
	for table in ("videos", "users"):
		if not inspector.has_table(table, schema="public"):
			raise RuntimeError(f"The existing {table} table must be provisioned before this migration")

	if not inspector.has_table("youtube_content_reviews", schema="public"):
		op.create_table(
			"youtube_content_reviews",
			sa.Column("id", postgresql.UUID(as_uuid=True), server_default=sa.text("gen_random_uuid()"), nullable=False),
			sa.Column("video_id", postgresql.UUID(as_uuid=True), nullable=False),
			sa.Column("youtube_video_id", sa.String(length=11), nullable=False),
			sa.Column("source_url", sa.Text(), nullable=False),
			sa.Column("channel_id", sa.String(length=64), nullable=True),
			sa.Column("channel_title", sa.String(length=200), nullable=True),
			sa.Column("source_published_at", sa.DateTime(timezone=True), nullable=True),
			sa.Column("made_for_kids", sa.Boolean(), nullable=True),
			sa.Column("status", sa.String(length=20), nullable=False, server_default="discovered"),
			sa.Column("screening_flags", postgresql.JSONB(), nullable=False, server_default=sa.text("'[]'::jsonb")),
			sa.Column("rights_status", sa.String(length=20), nullable=False, server_default="unreviewed"),
			sa.Column("discovered_by", postgresql.UUID(as_uuid=True), nullable=True),
			sa.Column("discovered_at", sa.DateTime(timezone=True), server_default=sa.text("now()"), nullable=False),
			sa.Column("reviewed_by", postgresql.UUID(as_uuid=True), nullable=True),
			sa.Column("reviewed_at", sa.DateTime(timezone=True), nullable=True),
			sa.Column("review_notes", sa.Text(), nullable=True),
			sa.Column("last_verified_at", sa.DateTime(timezone=True), nullable=True),
			sa.Column("revoked_reason", sa.Text(), nullable=True),
			sa.Column("revoked_at", sa.DateTime(timezone=True), nullable=True),
			sa.Column("updated_at", sa.DateTime(timezone=True), server_default=sa.text("now()"), nullable=False),
			sa.PrimaryKeyConstraint("id", name="youtube_content_reviews_pkey"),
			sa.ForeignKeyConstraint(["video_id"], ["videos.id"], ondelete="CASCADE", name="youtube_content_reviews_video_id_fkey"),
			sa.ForeignKeyConstraint(["discovered_by"], ["users.id"], ondelete="SET NULL", name="youtube_content_reviews_discovered_by_fkey"),
			sa.ForeignKeyConstraint(["reviewed_by"], ["users.id"], ondelete="SET NULL", name="youtube_content_reviews_reviewed_by_fkey"),
			sa.UniqueConstraint("video_id", name="uq_youtube_content_reviews_video_id"),
			sa.UniqueConstraint("youtube_video_id", name="uq_youtube_content_reviews_youtube_video_id"),
			sa.CheckConstraint(_in("status", REVIEW_STATUSES), name="youtube_content_reviews_status_check"),
			sa.CheckConstraint(_in("rights_status", RIGHTS_STATUSES), name="youtube_content_reviews_rights_status_check"),
			sa.CheckConstraint("youtube_video_id ~ '^[A-Za-z0-9_-]{11}$'", name="youtube_content_reviews_youtube_video_id_check"),
		)
		op.create_index("ix_youtube_content_reviews_status", "youtube_content_reviews", ["status", "last_verified_at"])

	if not inspector.has_table("content_reports", schema="public"):
		op.create_table(
			"content_reports",
			sa.Column("id", postgresql.UUID(as_uuid=True), server_default=sa.text("gen_random_uuid()"), nullable=False),
			sa.Column("video_id", postgresql.UUID(as_uuid=True), nullable=False),
			sa.Column("reported_by", postgresql.UUID(as_uuid=True), nullable=True),
			sa.Column("reason", sa.String(length=20), nullable=False),
			sa.Column("details", sa.Text(), nullable=True),
			sa.Column("status", sa.String(length=20), nullable=False, server_default="open"),
			sa.Column("resolved_by", postgresql.UUID(as_uuid=True), nullable=True),
			sa.Column("resolved_at", sa.DateTime(timezone=True), nullable=True),
			sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.text("now()"), nullable=False),
			sa.PrimaryKeyConstraint("id", name="content_reports_pkey"),
			sa.ForeignKeyConstraint(["video_id"], ["videos.id"], ondelete="CASCADE", name="content_reports_video_id_fkey"),
			sa.ForeignKeyConstraint(["reported_by"], ["users.id"], ondelete="SET NULL", name="content_reports_reported_by_fkey"),
			sa.ForeignKeyConstraint(["resolved_by"], ["users.id"], ondelete="SET NULL", name="content_reports_resolved_by_fkey"),
			sa.CheckConstraint(_in("reason", REPORT_REASONS), name="content_reports_reason_check"),
			sa.CheckConstraint(_in("status", REPORT_STATUSES), name="content_reports_status_check"),
		)
		op.create_index("ix_content_reports_status", "content_reports", ["status", "created_at"])


def downgrade() -> None:
	inspector = sa.inspect(op.get_bind())
	if inspector.has_table("content_reports", schema="public"):
		op.drop_index("ix_content_reports_status", table_name="content_reports")
		op.drop_table("content_reports")
	if inspector.has_table("youtube_content_reviews", schema="public"):
		op.drop_index("ix_youtube_content_reviews_status", table_name="youtube_content_reviews")
		op.drop_table("youtube_content_reviews")
