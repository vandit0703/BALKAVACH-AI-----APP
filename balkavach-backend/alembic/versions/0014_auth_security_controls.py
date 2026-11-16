"""Add parent PIN and password reset token storage."""

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import postgresql


revision = "0014_auth_security_controls"
down_revision = "0013_mission_video_entitlement"
branch_labels = None
depends_on = None


def upgrade() -> None:
	bind = op.get_bind()
	inspector = sa.inspect(bind)
	if "parent_pin_hash" not in {column["name"] for column in inspector.get_columns("users")}:
		op.add_column("users", sa.Column("parent_pin_hash", sa.String(length=255), nullable=True))
	if not inspector.has_table("password_reset_tokens"):
		op.create_table(
		"password_reset_tokens",
		sa.Column("id", postgresql.UUID(as_uuid=True), server_default=sa.text("gen_random_uuid()"), nullable=False),
		sa.Column("user_id", postgresql.UUID(as_uuid=True), nullable=False),
		sa.Column("token_hash", sa.String(length=64), nullable=False),
		sa.Column("expires_at", sa.DateTime(timezone=True), nullable=False),
		sa.Column("used_at", sa.DateTime(timezone=True), nullable=True),
		sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.text("now()"), nullable=False),
		sa.PrimaryKeyConstraint("id", name="password_reset_tokens_pkey"),
		sa.ForeignKeyConstraint(["user_id"], ["users.id"], ondelete="CASCADE", name="password_reset_tokens_user_id_fkey"),
		sa.UniqueConstraint("token_hash", name="password_reset_tokens_token_hash_key"),
	)
	op.create_index("ix_password_reset_tokens_user_id", "password_reset_tokens", ["user_id"])


def downgrade() -> None:
	raise RuntimeError("Downgrade is disabled for authentication security data")