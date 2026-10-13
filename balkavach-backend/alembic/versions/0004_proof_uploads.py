"""Uploaded mission proof photos.

Revision ID: 0004_proof_uploads
Revises: 0003_device_tokens
Create Date: 2026-10-13

Bytes live in the configured storage provider; this table is the authorisation
and integrity record (owner, family, type, size, SHA-256).
"""

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import postgresql

revision = "0004_proof_uploads"
down_revision = "0003_device_tokens"
branch_labels = None
depends_on = None


def upgrade() -> None:
	op.create_table(
		"proof_uploads",
		sa.Column("id", postgresql.UUID(as_uuid=True), server_default=sa.text("gen_random_uuid()"), nullable=False),
		sa.Column("family_id", postgresql.UUID(as_uuid=True), nullable=False),
		sa.Column("child_id", postgresql.UUID(as_uuid=True), nullable=False),
		sa.Column("uploaded_by", postgresql.UUID(as_uuid=True), nullable=False),
		sa.Column("content_type", sa.String(length=40), nullable=False),
		sa.Column("size_bytes", sa.Integer(), nullable=False),
		sa.Column("sha256", sa.String(length=64), nullable=False),
		sa.Column("storage_key", sa.String(length=255), nullable=False),
		sa.Column("submission_id", postgresql.UUID(as_uuid=True), nullable=True),
		sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.text("now()"), nullable=False),
		sa.PrimaryKeyConstraint("id", name="proof_uploads_pkey"),
		sa.ForeignKeyConstraint(["family_id"], ["families.id"], ondelete="CASCADE", name="proof_uploads_family_id_fkey"),
		sa.ForeignKeyConstraint(["child_id"], ["child_profiles.id"], ondelete="CASCADE", name="proof_uploads_child_id_fkey"),
		sa.ForeignKeyConstraint(["uploaded_by"], ["users.id"], ondelete="CASCADE", name="proof_uploads_uploaded_by_fkey"),
		sa.ForeignKeyConstraint(
			["submission_id"], ["task_submissions.id"], ondelete="SET NULL", name="proof_uploads_submission_id_fkey"
		),
		sa.UniqueConstraint("storage_key", name="proof_uploads_storage_key_key"),
		sa.CheckConstraint("size_bytes > 0", name="proof_uploads_size_check"),
	)
	op.create_index("ix_proof_uploads_child_id", "proof_uploads", ["child_id"])


def downgrade() -> None:
	op.drop_index("ix_proof_uploads_child_id", table_name="proof_uploads")
	op.drop_table("proof_uploads")
