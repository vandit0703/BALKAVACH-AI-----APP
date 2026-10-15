"""Refresh-token sessions for parents, children and admins.

Revision ID: 0002_auth_sessions
Revises: 0001_seed_progression
Create Date: 2026-10-13

Only a SHA-256 digest of each refresh token is stored. The previous digest is
kept so that re-use of an already-rotated token (a sign of theft) revokes the
whole session.
"""

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import postgresql

revision = "0002_auth_sessions"
down_revision = "0001_seed_progression"
branch_labels = None
depends_on = None


def upgrade() -> None:
	bind = op.get_bind()
	if not sa.inspect(bind).has_table("auth_sessions"):
		op.create_table(
			"auth_sessions",
			sa.Column("id", postgresql.UUID(as_uuid=True), server_default=sa.text("gen_random_uuid()"), nullable=False),
			sa.Column("user_id", postgresql.UUID(as_uuid=True), nullable=False),
			sa.Column("issued_by", postgresql.UUID(as_uuid=True), nullable=True),
			sa.Column("kind", sa.String(length=10), nullable=False),
			sa.Column("refresh_token_hash", sa.String(length=64), nullable=False),
			sa.Column("previous_token_hash", sa.String(length=64), nullable=True),
			sa.Column("device_label", sa.String(length=120), nullable=True),
			sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.text("now()"), nullable=False),
			sa.Column("last_used_at", sa.DateTime(timezone=True), nullable=True),
			sa.Column("expires_at", sa.DateTime(timezone=True), nullable=False),
			sa.Column("revoked_at", sa.DateTime(timezone=True), nullable=True),
			sa.PrimaryKeyConstraint("id", name="auth_sessions_pkey"),
			sa.ForeignKeyConstraint(["user_id"], ["users.id"], ondelete="CASCADE", name="auth_sessions_user_id_fkey"),
			sa.ForeignKeyConstraint(["issued_by"], ["users.id"], ondelete="SET NULL", name="auth_sessions_issued_by_fkey"),
			sa.UniqueConstraint("refresh_token_hash", name="auth_sessions_refresh_token_hash_key"),
			sa.CheckConstraint("kind IN ('parent', 'child', 'admin')", name="auth_sessions_kind_check"),
		)
	indexes = {index["name"] for index in sa.inspect(bind).get_indexes("auth_sessions")}
	if "ix_auth_sessions_user_id" not in indexes:
		op.create_index("ix_auth_sessions_user_id", "auth_sessions", ["user_id"])
	if "ix_auth_sessions_previous_token_hash" not in indexes:
		op.create_index("ix_auth_sessions_previous_token_hash", "auth_sessions", ["previous_token_hash"])


def downgrade() -> None:
	raise RuntimeError("Downgrade is disabled to prevent deleting authentication sessions or existing schema")
