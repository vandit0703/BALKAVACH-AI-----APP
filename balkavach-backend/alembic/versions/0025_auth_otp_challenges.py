"""Add purpose-specific one-time-code challenges for passwordless parent sign-in.

Registration verification keeps using ``parent_email_verifications`` (0023); this table is separate so a
sign-in code can never be confused with (or consumed as) a registration code.

Additive only. Downgrade drops just this table: its rows are short-lived codes (minutes), so nothing of
lasting value is lost, and no existing table is touched.
"""

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import postgresql

revision = "0025_auth_otp_challenges"
down_revision = "0024_panda_chat_access"
branch_labels = None
depends_on = None

TABLE = "auth_otp_challenges"


def upgrade() -> None:
	if sa.inspect(op.get_bind()).has_table(TABLE):
		return
	op.create_table(
		TABLE,
		sa.Column("id", postgresql.UUID(as_uuid=True), server_default=sa.text("gen_random_uuid()"), nullable=False),
		sa.Column("user_id", postgresql.UUID(as_uuid=True), nullable=False),
		sa.Column("purpose", sa.String(length=32), nullable=False),
		sa.Column("otp_hash", sa.String(length=255), nullable=False),
		sa.Column("expires_at", sa.DateTime(timezone=True), nullable=False),
		sa.Column("attempts", sa.Integer(), server_default=sa.text("0"), nullable=False),
		sa.Column("last_sent_at", sa.DateTime(timezone=True), nullable=False),
		sa.Column("consumed_at", sa.DateTime(timezone=True), nullable=True),
		sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.text("now()"), nullable=False),
		sa.PrimaryKeyConstraint("id", name="auth_otp_challenges_pkey"),
		sa.ForeignKeyConstraint(["user_id"], ["users.id"], ondelete="CASCADE", name="auth_otp_challenges_user_id_fkey"),
		sa.CheckConstraint("purpose IN ('login')", name="auth_otp_challenges_purpose_check"),
		sa.CheckConstraint("attempts >= 0", name="auth_otp_challenges_attempts_check"),
	)
	# At most one live (unconsumed) challenge per account and purpose; consumed rows are history.
	op.create_index(
		"auth_otp_challenges_active_key",
		TABLE,
		["user_id", "purpose"],
		unique=True,
		postgresql_where=sa.text("consumed_at IS NULL"),
	)
	# Cleanup scans by age.
	op.create_index("auth_otp_challenges_expires_at_idx", TABLE, ["expires_at"])


def downgrade() -> None:
	op.drop_index("auth_otp_challenges_expires_at_idx", table_name=TABLE)
	op.drop_index("auth_otp_challenges_active_key", table_name=TABLE)
	op.drop_table(TABLE)
