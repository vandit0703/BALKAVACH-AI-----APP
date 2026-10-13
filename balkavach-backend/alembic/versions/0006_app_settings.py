"""Global application settings managed from the admin panel.

Revision ID: 0006_app_settings
Revises: 0005_preset_tasks
Create Date: 2026-10-13

A small key/value table. Only keys on the server-side allow-list can be written
(see ``app/services/app_settings_service.py``). The consent document versions
live here so the app no longer has to hard-code them.
"""

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import postgresql

revision = "0006_app_settings"
down_revision = "0005_preset_tasks"
branch_labels = None
depends_on = None


def upgrade() -> None:
	op.create_table(
		"app_settings",
		sa.Column("key", sa.String(length=80), nullable=False),
		sa.Column("value", postgresql.JSONB(), nullable=False),
		sa.Column("updated_by", postgresql.UUID(as_uuid=True), nullable=True),
		sa.Column("updated_at", sa.DateTime(timezone=True), server_default=sa.text("now()"), nullable=False),
		sa.PrimaryKeyConstraint("key", name="app_settings_pkey"),
		sa.ForeignKeyConstraint(["updated_by"], ["users.id"], ondelete="SET NULL", name="app_settings_updated_by_fkey"),
	)


def downgrade() -> None:
	op.drop_table("app_settings")
