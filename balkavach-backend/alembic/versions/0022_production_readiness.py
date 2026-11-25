"""Production-readiness additive schema: child interests/requests, link codes, soft-delete, redemption snapshots."""

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import postgresql

revision = "0022_production_readiness"
down_revision = "0021_quiz_system"
branch_labels = None
depends_on = None

_UUID = postgresql.UUID(as_uuid=True)


def upgrade() -> None:
	op.add_column(
		"child_profiles",
		sa.Column("interests", postgresql.JSONB(), nullable=False, server_default=sa.text("'[]'::jsonb")),
	)
	op.add_column(
		"child_profiles",
		sa.Column("pending_interest_requests", postgresql.JSONB(), nullable=False, server_default=sa.text("'[]'::jsonb")),
	)
	op.add_column("child_profiles", sa.Column("interests_updated_at", sa.DateTime(), nullable=True))
	op.add_column("child_profiles", sa.Column("interests_updated_by", _UUID, nullable=True))
	op.create_foreign_key(
		"fk_child_profiles_interests_updated_by_users",
		"child_profiles",
		"users",
		["interests_updated_by"],
		["id"],
		ondelete="SET NULL",
	)
	op.add_column("child_profiles", sa.Column("deleted_at", sa.DateTime(), nullable=True))
	op.add_column("users", sa.Column("deleted_at", sa.DateTime(), nullable=True))
	op.add_column("redemption_requests", sa.Column("reward_title_snapshot", sa.Text(), nullable=True))
	op.add_column("redemption_requests", sa.Column("reward_description_snapshot", sa.Text(), nullable=True))
	op.add_column("redemption_requests", sa.Column("cancelled_at", sa.DateTime(), nullable=True))

	op.create_table(
		"child_link_codes",
		sa.Column("id", _UUID, server_default=sa.text("gen_random_uuid()"), nullable=False),
		sa.Column("family_id", _UUID, nullable=False),
		sa.Column("child_id", _UUID, nullable=False),
		sa.Column("created_by", _UUID, nullable=False),
		sa.Column("code_hash", sa.Text(), nullable=False),
		sa.Column("expires_at", sa.DateTime(), nullable=False),
		sa.Column("used_at", sa.DateTime(), nullable=True),
		sa.Column("is_revoked", sa.Boolean(), server_default=sa.false(), nullable=False),
		sa.Column("created_at", sa.DateTime(), server_default=sa.text("now()"), nullable=False),
		sa.PrimaryKeyConstraint("id", name="child_link_codes_pkey"),
		sa.ForeignKeyConstraint(["family_id"], ["families.id"], ondelete="CASCADE"),
		sa.ForeignKeyConstraint(["child_id"], ["child_profiles.id"], ondelete="CASCADE"),
		sa.ForeignKeyConstraint(["created_by"], ["users.id"], ondelete="CASCADE"),
		sa.UniqueConstraint("code_hash", name="uq_child_link_codes_hash"),
	)
	op.create_index("ix_child_link_codes_child_active", "child_link_codes", ["child_id", "is_revoked", "expires_at"])


def downgrade() -> None:
	op.drop_index("ix_child_link_codes_child_active", table_name="child_link_codes")
	op.drop_table("child_link_codes")
	op.drop_column("redemption_requests", "cancelled_at")
	op.drop_column("redemption_requests", "reward_description_snapshot")
	op.drop_column("redemption_requests", "reward_title_snapshot")
	op.drop_column("users", "deleted_at")
	op.drop_column("child_profiles", "deleted_at")
	op.drop_constraint("fk_child_profiles_interests_updated_by_users", "child_profiles", type_="foreignkey")
	op.drop_column("child_profiles", "interests_updated_by")
	op.drop_column("child_profiles", "interests_updated_at")
	op.drop_column("child_profiles", "pending_interest_requests")
	op.drop_column("child_profiles", "interests")
