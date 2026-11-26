"""Add parent email verification state and OTP storage."""

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import postgresql

revision = "0023_parent_email_verification"
down_revision = "0022_production_readiness"
branch_labels = None
depends_on = None


def upgrade() -> None:
	bind = op.get_bind()
	inspector = sa.inspect(bind)
	if "email_verified_at" not in {column["name"] for column in inspector.get_columns("users")}:
		op.add_column("users", sa.Column("email_verified_at", sa.DateTime(timezone=True), nullable=True))
	bind.execute(
		sa.text(
			"UPDATE users SET email_verified_at = now() "
			"WHERE role = 'parent' AND email IS NOT NULL AND email_verified_at IS NULL"
		)
	)
	if not inspector.has_table("parent_email_verifications"):
		op.create_table(
			"parent_email_verifications",
			sa.Column("id", postgresql.UUID(as_uuid=True), server_default=sa.text("gen_random_uuid()"), nullable=False),
			sa.Column("user_id", postgresql.UUID(as_uuid=True), nullable=False),
			sa.Column("otp_hash", sa.String(length=255), nullable=False),
			sa.Column("expires_at", sa.DateTime(timezone=True), nullable=False),
			sa.Column("attempts", sa.Integer(), server_default=sa.text("0"), nullable=False),
			sa.Column("last_sent_at", sa.DateTime(timezone=True), nullable=False),
			sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.text("now()"), nullable=False),
			sa.PrimaryKeyConstraint("id", name="parent_email_verifications_pkey"),
			sa.ForeignKeyConstraint(["user_id"], ["users.id"], ondelete="CASCADE", name="parent_email_verifications_user_id_fkey"),
			sa.UniqueConstraint("user_id", name="parent_email_verifications_user_id_key"),
			sa.CheckConstraint("attempts >= 0", name="parent_email_verifications_attempts_check"),
		)


def downgrade() -> None:
	raise RuntimeError("Downgrade is disabled to prevent deleting parent verification data")