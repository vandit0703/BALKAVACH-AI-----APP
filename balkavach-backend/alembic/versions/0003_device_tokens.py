"""Push-notification device tokens.

Revision ID: 0003_device_tokens
Revises: 0002_auth_sessions
Create Date: 2026-10-13

Tokens must be stored in the clear to be usable by FCM. They are never returned
by any API, are unique across users (a shared device re-registers to the current
user) and are deactivated when the provider reports them invalid.
"""

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import postgresql

revision = "0003_device_tokens"
down_revision = "0002_auth_sessions"
branch_labels = None
depends_on = None


def upgrade() -> None:
	bind = op.get_bind()
	if not sa.inspect(bind).has_table("device_tokens"):
		op.create_table(
			"device_tokens",
			sa.Column("id", postgresql.UUID(as_uuid=True), server_default=sa.text("gen_random_uuid()"), nullable=False),
			sa.Column("user_id", postgresql.UUID(as_uuid=True), nullable=False),
			sa.Column("token", sa.Text(), nullable=False),
			sa.Column("platform", sa.String(length=10), nullable=False),
			sa.Column("app_version", sa.String(length=40), nullable=True),
			sa.Column("is_active", sa.Boolean(), server_default=sa.text("true"), nullable=False),
			sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.text("now()"), nullable=False),
			sa.Column("last_seen_at", sa.DateTime(timezone=True), server_default=sa.text("now()"), nullable=False),
			sa.PrimaryKeyConstraint("id", name="device_tokens_pkey"),
			sa.ForeignKeyConstraint(["user_id"], ["users.id"], ondelete="CASCADE", name="device_tokens_user_id_fkey"),
			sa.UniqueConstraint("token", name="device_tokens_token_key"),
			sa.CheckConstraint("platform IN ('android', 'ios', 'web')", name="device_tokens_platform_check"),
		)
	indexes = {index["name"] for index in sa.inspect(bind).get_indexes("device_tokens")}
	if "ix_device_tokens_user_id" not in indexes:
		op.create_index("ix_device_tokens_user_id", "device_tokens", ["user_id"])


def downgrade() -> None:
	raise RuntimeError("Downgrade is disabled to prevent deleting device registrations or existing schema")
