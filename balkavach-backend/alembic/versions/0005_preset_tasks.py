"""Admin-managed library of preset missions.

Revision ID: 0005_preset_tasks
Revises: 0004_proof_uploads
Create Date: 2026-10-13

Parents browse these and create a normal family task from one. Reward values are
suggestions the parent can change; nothing is awarded from this table directly.
"""

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import postgresql

revision = "0005_preset_tasks"
down_revision = "0004_proof_uploads"
branch_labels = None
depends_on = None


def upgrade() -> None:
	bind = op.get_bind()
	if not sa.inspect(bind).has_table("preset_tasks"):
		op.create_table(
			"preset_tasks",
			sa.Column("id", postgresql.UUID(as_uuid=True), server_default=sa.text("gen_random_uuid()"), nullable=False),
			sa.Column("category_id", postgresql.UUID(as_uuid=True), nullable=True),
			sa.Column("title", sa.String(length=180), nullable=False),
			sa.Column("description", sa.Text(), nullable=True),
			sa.Column("language_code", sa.String(length=10), server_default=sa.text("'en'"), nullable=False),
			sa.Column("suggested_star_reward", sa.Integer(), server_default=sa.text("1"), nullable=False),
			sa.Column("suggested_xp_reward", sa.Integer(), server_default=sa.text("10"), nullable=False),
			sa.Column("age_min", sa.Integer(), server_default=sa.text("3"), nullable=False),
			sa.Column("age_max", sa.Integer(), server_default=sa.text("17"), nullable=False),
			sa.Column("is_active", sa.Boolean(), server_default=sa.text("true"), nullable=False),
			sa.Column("created_by", postgresql.UUID(as_uuid=True), nullable=True),
			sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.text("now()"), nullable=False),
			sa.Column("updated_at", sa.DateTime(timezone=True), server_default=sa.text("now()"), nullable=False),
			sa.PrimaryKeyConstraint("id", name="preset_tasks_pkey"),
			sa.ForeignKeyConstraint(["category_id"], ["task_categories.id"], ondelete="SET NULL", name="preset_tasks_category_id_fkey"),
			sa.ForeignKeyConstraint(["created_by"], ["users.id"], ondelete="SET NULL", name="preset_tasks_created_by_fkey"),
			sa.CheckConstraint("suggested_star_reward >= 0 AND suggested_xp_reward >= 0", name="preset_tasks_rewards_check"),
			sa.CheckConstraint("age_min >= 0 AND age_max >= age_min", name="preset_tasks_age_check"),
		)
	indexes = {index["name"] for index in sa.inspect(bind).get_indexes("preset_tasks")}
	if "ix_preset_tasks_category_id" not in indexes:
		op.create_index("ix_preset_tasks_category_id", "preset_tasks", ["category_id"])


def downgrade() -> None:
	raise RuntimeError("Downgrade is disabled to prevent deleting preset tasks or existing schema")
